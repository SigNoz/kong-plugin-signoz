-- Framework-free unit tests, executed by the Kong image's own LuaJIT:
--   docker run --rm -v "$PWD:/w" kong:3.9 sh -c \
--     "/usr/local/openresty/luajit/bin/luajit /w/spec/unit/run.lua"
-- No busted, no C rocks — runs against the exact runtime Kong ships.

package.path  = "/w/?.lua;/w/?/init.lua;" .. package.path
package.cpath = "/usr/local/openresty/lualib/?.so;" .. package.cpath

-- ngx stub: enough surface for attributes.lua and logs record building.
_G.ngx = {
  var = {
    server_protocol = "HTTP/1.1",
    upstream_addr   = "10.1.1.1:80, 10.2.2.2:8080",
  },
  now = function() return 1700000000.5 end,
  req = { start_time = function() return 1700000000.0 end },
}

local passed, failed = 0, 0
local function check(name, fn)
  local ok, err = pcall(fn)
  if ok then
    passed = passed + 1
    print("ok    " .. name)
  else
    failed = failed + 1
    print("FAIL  " .. name .. " — " .. tostring(err))
  end
end

local function eq(got, want, what)
  if got ~= want then
    error(("%s: got %s, want %s"):format(what or "value", tostring(got), tostring(want)), 2)
  end
end

local attributes = require("kong.plugins.signoz.attributes")

local full_message = {
  request  = {
    method  = "GET",
    uri     = "/payments?page=2",
    url     = "https://gw.example.com/payments?page=2",
    size    = "421",
    headers = { ["user-agent"] = "m6-test/1.0" },
  },
  response  = { status = 200, size = 1234 },
  latencies = { kong = 2, proxy = 36, request = 38 },
  tries     = { { ip = "10.0.0.4", port = 80 }, { ip = "10.0.0.5", port = 80 } },
  service   = { name = "payments", id = "svc-1" },
  route     = { name = "payments-route", id = "rt-1", paths = { "/payments", "/pay" } },
  consumer  = { id = "cons-1", username = "acme-mobile" },
  client_ip = "203.0.113.7",
  upstream_status = "200",
}

check("identity: full message", function()
  local a = attributes.identity(full_message)
  eq(a["http.request.method"], "GET", "method")
  eq(a["url.path"], "/payments", "path strips query")
  eq(a["url.scheme"], "https", "scheme")
  eq(a["http.response.status_code"], 200, "status")
  eq(a["client.address"], "203.0.113.7", "client")
  eq(a["server.address"], "10.0.0.5", "server = last try ip")
  eq(a["kong.service.name"], "payments", "service name")
  eq(a["kong.service.id"], "svc-1", "service id")
  eq(a["kong.route.name"], "payments-route", "route name")
  eq(a["kong.route.id"], "rt-1", "route id")
  eq(a["kong.consumer.id"], "cons-1", "consumer id")
  eq(a["kong.consumer.username"], "acme-mobile", "consumer username")
end)

check("identity: empty message is safe", function()
  local a = attributes.identity({})
  eq(a["http.request.method"], "", "method")
  eq(a["http.response.status_code"], 0, "status")
  eq(a["kong.consumer.id"], nil, "no consumer")
  -- no tries → falls back to ngx.var.upstream_addr (last hop, port stripped)
  eq(a["server.address"], "10.2.2.2", "server from ngx.var fallback")
end)

check("measurements: latencies, sizes, tries, upstream status", function()
  local m = attributes.measurements(full_message)
  eq(m["kong.latency.gateway_ms"], 2, "gateway")
  eq(m["kong.latency.upstream_ms"], 36, "upstream")
  eq(m["kong.latency.total_ms"], 38, "total")
  eq(m["kong.request.size"], 421, "request size coerced to number")
  eq(m["kong.response.size"], 1234, "response size")
  eq(m["kong.balancer.tries"], 2, "tries")
  eq(m["kong.upstream.status"], "200", "upstream status")
end)

check("measurements: proxy=-1 (no upstream) is omitted", function()
  local m = attributes.measurements({ latencies = { kong = 1, proxy = -1, request = 1 } })
  eq(m["kong.latency.upstream_ms"], nil, "upstream omitted")
  eq(m["kong.latency.gateway_ms"], 1, "gateway kept")
end)

check("span_extras: route join, protocol, ua, no error.type on 2xx", function()
  local e = attributes.span_extras(full_message)
  eq(e["http.route"], "/payments,/pay", "paths joined")
  eq(e["network.protocol.version"], "1.1", "protocol")
  eq(e["user_agent.original"], "m6-test/1.0", "ua")
  eq(e["error.type"], nil, "no error.type on 200")
end)

check("span_extras: error.type on 5xx, ua as table", function()
  local e = attributes.span_extras({
    request  = { headers = { ["user-agent"] = { "first", "second" } } },
    response = { status = 503 },
  })
  eq(e["error.type"], "503", "error.type")
  eq(e["user_agent.original"], "first", "ua table takes first")
end)

check("merge overwrites destination keys", function()
  local dst = { a = 1, b = 1 }
  attributes.merge(dst, { b = 2, c = 3 })
  eq(dst.a, 1); eq(dst.b, 2); eq(dst.c, 3)
end)

-- logs record builder (encoder selection will fall back to JSON here:
-- kong.observability.otlp is not on package.path in this harness)
local logs = require("kong.plugins.signoz.logs")

check("build_record: body, severity, correlation, measurements", function()
  local rec = logs.build_record(full_message, { trace_id = "rawtid", span_id = "rawsid" })
  eq(rec.body, "GET /payments 200 38ms", "body")
  eq(rec.severity_number, 9, "severity number")
  eq(rec.severity_text, "INFO", "severity text")
  eq(rec.trace_id, "rawtid", "trace id")
  eq(rec.span_id, "rawsid", "span id")
  eq(rec.attributes["message.type"], "kong.access", "message.type")
  eq(rec.attributes["kong.latency.total_ms"], 38, "measurement present on log")
  eq(rec.attributes["kong.request.size"], 421, "size present on log")
  eq(rec.time_unix_nano, 1700000000.0 * 1e9, "start time ns")
end)

check("build_record: severity WARN on 4xx, ERROR on 5xx", function()
  local warn = logs.build_record({ response = { status = 404 } }, nil)
  eq(warn.severity_text, "WARN", "404")
  local err = logs.build_record({ response = { status = 502 } }, nil)
  eq(err.severity_text, "ERROR", "502")
  eq(err.trace_id, nil, "no span, no trace id")
end)

check("json encode: OTLP/HTTP-JSON envelope", function()
  local rec = logs.build_record(full_message, nil)
  local body, content_type = logs.encode({ rec }, { ["service.name"] = "kong" })
  eq(content_type, "application/json", "content type")
  assert(body:find('"resourceLogs"', 1, true), "resourceLogs envelope")
  assert(body:find('"stringValue":"GET \\/payments 200 38ms"', 1, true)
      or body:find('"stringValue":"GET /payments 200 38ms"', 1, true), "body value")
  assert(body:find('"key":"service.name"', 1, true), "resource attr")
end)

print(("\n%d passed, %d failed"):format(passed, failed))
if failed > 0 then os.exit(1) end
