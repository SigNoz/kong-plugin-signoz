package.path = "./?.lua;./?/init.lua;" .. package.path

-- ngx stub: enough surface for the record builder
_G.ngx = _G.ngx or {}
_G.ngx.var = _G.ngx.var or {}
_G.ngx.now = function() return 1700000000.5 end
_G.ngx.req = { start_time = function() return 1700000000.0 end }

-- The JSON encoder needs cjson; stub it only when absent so the module
-- loads everywhere (CI installs lua-cjson and exercises the real one).
local has_cjson = pcall(require, "cjson.safe")
if not has_cjson then
  package.preload["cjson.safe"] = function()
    return { encode = function() return "{}" end }
  end
end

local logs = require("kong.plugins.signoz.logs")

local function full_message()
  return {
    request   = { method = "GET", uri = "/payments?page=2",
                  url = "https://gw.example.com/payments?page=2", size = "421" },
    response  = { status = 200, size = 1234 },
    latencies = { kong = 2, proxy = 36, request = 38 },
    service   = { name = "payments", id = "svc-1" },
    route     = { name = "payments-route", id = "rt-1" },
    client_ip = "203.0.113.7",
  }
end

describe("logs.build_record", function()
  it("builds body, severity, correlation and measurements", function()
    local rec = logs.build_record(full_message(), { trace_id = "rawtid", span_id = "rawsid" })
    assert.equals("GET /payments 200 38ms", rec.body)
    assert.equals(9, rec.severity_number)
    assert.equals("INFO", rec.severity_text)
    assert.equals("rawtid", rec.trace_id)
    assert.equals("rawsid", rec.span_id)
    assert.equals("kong.access", rec.attributes["message.type"])
    assert.equals(38, rec.attributes["kong.latency.total_ms"])
    assert.equals(421, rec.attributes["kong.request.size"])
    assert.equals(1700000000.0 * 1e9, rec.time_unix_nano)
  end)

  it("maps severity WARN on 4xx and ERROR on 5xx", function()
    assert.equals("WARN", logs.build_record({ response = { status = 404 } }, nil).severity_text)
    local rec = logs.build_record({ response = { status = 502 } }, nil)
    assert.equals("ERROR", rec.severity_text)
    assert.is_nil(rec.trace_id)
  end)
end)

describe("logs.encode (OTLP/HTTP-JSON)", function()
  it("produces the resourceLogs envelope", function()
    if not has_cjson then
      pending("lua-cjson not installed in this environment")
      return
    end
    local rec = logs.build_record(full_message(), nil)
    local body, content_type = logs.encode({ rec }, { ["service.name"] = "kong" })
    assert.equals("application/json", content_type)
    assert.truthy(body:find('"resourceLogs"', 1, true))
    assert.truthy(body:find('"key":"service.name"', 1, true))
    assert.truthy(body:find("GET", 1, true))
  end)
end)
