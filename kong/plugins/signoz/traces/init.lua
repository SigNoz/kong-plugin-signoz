local kong = kong
local ngx  = ngx

local _M = {}

local get_root_span
do
  if kong.tracing and type(kong.tracing.get_active_span) == "function" then
    get_root_span = function()
      local ok, span = pcall(kong.tracing.get_active_span, kong.tracing)
      if ok and span then
        return span
      end
      return (ngx.ctx.KONG_SPANS or {})[1]
    end
  else
    get_root_span = function()
      return (ngx.ctx.KONG_SPANS or {})[1]
    end
  end
end

local function last_upstream_ip()
  local ua = ngx.var and ngx.var.upstream_addr
  if not ua or ua == "" then
    return nil
  end
  local last = ua:match("([^,]+)$") or ua
  last = last:match("^%s*(.-)%s*$") or last
  return last:match("^([^:]+)") or nil
end

function _M.decorate()
  local span = get_root_span()
  if not span then
    return
  end
  span.attributes = span.attributes or {}
  local a = span.attributes

  a["http.request.method"]       = kong.request.get_method()
  a["url.path"]                  = kong.request.get_path()
  a["url.scheme"]                = kong.request.get_scheme()
  a["http.response.status_code"] = kong.response.get_status()
  a["client.address"]            = kong.client.get_forwarded_ip()

  local server = last_upstream_ip()
  if server then a["server.address"] = server end

  local svc = kong.router.get_service()
  if svc and svc.name then a["kong.service.name"] = svc.name end

  local rt = kong.router.get_route()
  if rt and rt.name then a["kong.route.name"] = rt.name end

  local cons = kong.client.get_consumer()
  if cons then
    if cons.id       then a["kong.consumer.id"]       = cons.id end
    if cons.username then a["kong.consumer.username"] = cons.username end
  end
end

return _M
