package.path = "./?.lua;./?/init.lua;" .. package.path

-- ngx stub: enough surface for attributes.lua
_G.ngx = _G.ngx or {}
_G.ngx.var = {
  server_protocol = "HTTP/1.1",
  upstream_addr   = "10.1.1.1:80, 10.2.2.2:8080",
}

local attributes = require("kong.plugins.signoz.attributes")

local function full_message()
  return {
    request  = {
      method  = "GET",
      uri     = "/payments?page=2",
      url     = "https://gw.example.com/payments?page=2",
      size    = "421",
      headers = { ["user-agent"] = "unit-test/1.0" },
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
end

describe("attributes.identity", function()
  it("maps a full serialize() message", function()
    local a = attributes.identity(full_message())
    assert.equals("GET", a["http.request.method"])
    assert.equals("/payments", a["url.path"])
    assert.equals("https", a["url.scheme"])
    assert.equals(200, a["http.response.status_code"])
    assert.equals("203.0.113.7", a["client.address"])
    assert.equals("10.0.0.5", a["server.address"])
    assert.equals("payments", a["kong.service.name"])
    assert.equals("svc-1", a["kong.service.id"])
    assert.equals("payments-route", a["kong.route.name"])
    assert.equals("rt-1", a["kong.route.id"])
    assert.equals("cons-1", a["kong.consumer.id"])
    assert.equals("acme-mobile", a["kong.consumer.username"])
  end)

  it("is safe on an empty message", function()
    local a = attributes.identity({})
    assert.equals("", a["http.request.method"])
    assert.equals(0, a["http.response.status_code"])
    assert.is_nil(a["kong.consumer.id"])
    -- no tries → last hop from ngx.var.upstream_addr, port stripped
    assert.equals("10.2.2.2", a["server.address"])
  end)
end)

describe("attributes.measurements", function()
  it("maps latencies, sizes, tries, upstream status", function()
    local m = attributes.measurements(full_message())
    assert.equals(2, m["kong.latency.gateway_ms"])
    assert.equals(36, m["kong.latency.upstream_ms"])
    assert.equals(38, m["kong.latency.total_ms"])
    assert.equals(421, m["kong.request.size"])
    assert.equals(1234, m["kong.response.size"])
    assert.equals(2, m["kong.balancer.tries"])
    assert.equals("200", m["kong.upstream.status"])
  end)

  it("omits upstream latency when proxy=-1 (no upstream)", function()
    local m = attributes.measurements({ latencies = { kong = 1, proxy = -1, request = 1 } })
    assert.is_nil(m["kong.latency.upstream_ms"])
    assert.equals(1, m["kong.latency.gateway_ms"])
  end)
end)

describe("attributes.span_extras", function()
  it("joins route paths, parses protocol and UA, no error.type on 2xx", function()
    local e = attributes.span_extras(full_message())
    assert.equals("/payments,/pay", e["http.route"])
    assert.equals("1.1", e["network.protocol.version"])
    assert.equals("unit-test/1.0", e["user_agent.original"])
    assert.is_nil(e["error.type"])
  end)

  it("sets error.type on 5xx and takes the first UA when repeated", function()
    local e = attributes.span_extras({
      request  = { headers = { ["user-agent"] = { "first", "second" } } },
      response = { status = 503 },
    })
    assert.equals("503", e["error.type"])
    assert.equals("first", e["user_agent.original"])
  end)
end)

describe("attributes.merge", function()
  it("overwrites destination keys", function()
    local dst = { a = 1, b = 1 }
    attributes.merge(dst, { b = 2, c = 3 })
    assert.same({ a = 1, b = 2, c = 3 }, dst)
  end)
end)
