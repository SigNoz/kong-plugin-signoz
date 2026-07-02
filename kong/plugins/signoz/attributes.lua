-- Shared attribute builders for the root span and the access-log record.
-- Both signals source from one kong.log.serialize() message so they never drift.
local ngx = ngx

local _M = {}

local function strip_query(uri)
  if not uri or uri == "" then return "" end
  local q = uri:find("?", 1, true)
  if q then return uri:sub(1, q - 1) end
  return uri
end

local function scheme_from_url(url)
  if not url or url == "" then return "" end
  return url:match("^(%w+)://") or ""
end

-- Last upstream IP: prefer the balancer tries list, fall back to ngx.var.
local function server_address(message)
  local tries = message.tries or {}
  local last  = tries[#tries]
  if last and last.ip then
    return last.ip
  end
  local ua = ngx.var and ngx.var.upstream_addr
  if not ua or ua == "" then
    return nil
  end
  local addr = ua:match("([^,]+)$") or ua
  addr = addr:match("^%s*(.-)%s*$") or addr
  return addr:match("^([^:]+)") or nil
end

---@param dst table
---@param src table
function _M.merge(dst, src)
  for k, v in pairs(src) do
    dst[k] = v
  end
end

-- Descriptive identity: who called what, and what happened.
---@param message table  Output of kong.log.serialize().
---@return table
function _M.identity(message)
  local req  = message.request  or {}
  local res  = message.response or {}
  local svc  = message.service  or {}
  local rt   = message.route    or {}
  local cons = message.consumer

  local attrs = {
    ["http.request.method"]       = req.method or "",
    ["url.path"]                  = strip_query(req.uri),
    ["url.scheme"]                = scheme_from_url(req.url),
    ["http.response.status_code"] = tonumber(res.status) or 0,
    ["client.address"]            = message.client_ip,
  }

  local server = server_address(message)
  if server then attrs["server.address"] = server end

  if svc.name then attrs["kong.service.name"] = svc.name end
  if svc.id   then attrs["kong.service.id"]   = svc.id   end
  if rt.name  then attrs["kong.route.name"]   = rt.name  end
  if rt.id    then attrs["kong.route.id"]     = rt.id    end

  if cons then
    attrs["kong.consumer.id"]       = cons.id
    attrs["kong.consumer.username"] = cons.username
  end

  return attrs
end

-- Measurements: where the time went, how big it was, how hard Kong tried.
-- Note: request/response sizes are Kong's totals (headers + body), hence the
-- kong.* namespace rather than OTel's body-only http.*.body.size.
---@param message table  Output of kong.log.serialize().
---@return table
function _M.measurements(message)
  local req   = message.request  or {}
  local res   = message.response or {}
  local lat   = message.latencies or {}
  local tries = message.tries or {}

  local attrs = {}

  if lat.kong    then attrs["kong.latency.gateway_ms"]  = lat.kong    end
  if lat.proxy and lat.proxy >= 0 then
    attrs["kong.latency.upstream_ms"] = lat.proxy
  end
  if lat.request then attrs["kong.latency.total_ms"]    = lat.request end

  local req_size = tonumber(req.size)
  local res_size = tonumber(res.size)
  if req_size then attrs["kong.request.size"]  = req_size end
  if res_size then attrs["kong.response.size"] = res_size end

  if #tries > 0 then
    attrs["kong.balancer.tries"] = #tries
  end

  if message.upstream_status and message.upstream_status ~= "" then
    attrs["kong.upstream.status"] = tostring(message.upstream_status)
  end

  return attrs
end

-- Span-only extras: route template, protocol, user agent, error type.
---@param message table  Output of kong.log.serialize().
---@return table
function _M.span_extras(message)
  local req = message.request  or {}
  local res = message.response or {}
  local rt  = message.route    or {}

  local attrs = {}

  local paths = rt.paths
  if type(paths) == "table" and #paths > 0 then
    attrs["http.route"] = table.concat(paths, ",")
  end

  local proto = ngx.var and ngx.var.server_protocol
  if proto then
    local version = proto:match("^HTTP/([%d%.]+)$")
    if version then attrs["network.protocol.version"] = version end
  end

  local headers = req.headers
  if type(headers) == "table" and headers["user-agent"] then
    local ua = headers["user-agent"]
    attrs["user_agent.original"] = type(ua) == "table" and ua[1] or ua
  end

  local status = tonumber(res.status) or 0
  if status >= 500 then
    attrs["error.type"] = tostring(status)
  end

  return attrs
end

return _M
