local http = require("resty.http")
local logs = require("kong.plugins.signoz.logs")

local fmt = string.format

local _M = {}

local function strip_trailing_slash(url)
  if url:sub(-1) == "/" then
    return url:sub(1, -2)
  end
  return url
end

---@param signoz_conf SignozExporterConf
---@param batch       table
---@return boolean|nil ok
---@return string|nil  err
function _M.post(signoz_conf, batch)
  local body, content_type = logs.encode(batch, signoz_conf.resource_attributes)
  if not body then
    return nil, "encode failed"
  end

  local url = strip_trailing_slash(signoz_conf.ingestion_endpoint) .. logs.endpoint_path()

  local headers = { ["Content-Type"] = content_type }
  if signoz_conf.headers then
    for k, v in pairs(signoz_conf.headers) do
      headers[k] = v
    end
  end

  local httpc = http.new()
  httpc:set_timeouts(
    signoz_conf.connect_timeout,
    signoz_conf.send_timeout,
    signoz_conf.read_timeout
  )

  local res, err = httpc:request_uri(url, {
    method  = "POST",
    headers = headers,
    body    = body,
  })

  if not res then
    return nil, "request failed: " .. tostring(err)
  end
  if res.status >= 300 then
    return nil, fmt("HTTP %d: %s", res.status, res.body or "")
  end

  return true
end

return _M
