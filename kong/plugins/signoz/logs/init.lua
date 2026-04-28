local ngx = ngx

local fmt   = string.format
local floor = math.floor

local _M = {}

local encoder
do
  local ok, otlp = pcall(require, "kong.observability.otlp")
  if ok and type(otlp.encode_logs) == "function" then
    encoder = require("kong.plugins.signoz.logs.protobuf")
  else
    encoder = require("kong.plugins.signoz.logs.json")
  end
end

local function severity_from_status(status)
  status = tonumber(status) or 0
  if status >= 500 then return 17, "ERROR"
  elseif status >= 400 then return 13, "WARN"
  else return 9, "INFO"
  end
end

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

---@param message table  Output of kong.log.serialize().
---@param span    table|nil
---@return table
function _M.build_record(message, span)
  local req     = message.request   or {}
  local res     = message.response  or {}
  local lat     = message.latencies or {}
  local svc     = message.service   or {}
  local rt      = message.route     or {}
  local cons    = message.consumer
  local tries   = message.tries     or {}

  local method  = req.method or ""
  local path    = strip_query(req.uri)
  local status  = tonumber(res.status) or 0
  local dur_ms  = lat.request or 0

  local sev_num, sev_text = severity_from_status(status)

  local attrs = {
    ["message.type"]              = "kong.access",
    ["http.request.method"]       = method,
    ["url.path"]                  = path,
    ["url.scheme"]                = scheme_from_url(req.url),
    ["http.response.status_code"] = status,
    ["client.address"]            = message.client_ip,
  }
  if svc.name then attrs["kong.service.name"] = svc.name end
  if rt.name  then attrs["kong.route.name"]   = rt.name  end
  if cons then
    attrs["kong.consumer.id"]       = cons.id
    attrs["kong.consumer.username"] = cons.username
  end
  if #tries > 0 then
    local last = tries[#tries]
    if last and last.ip then
      attrs["server.address"] = last.ip
    end
  end

  local trace_id, span_id
  if span then
    trace_id = span.trace_id
    span_id  = span.span_id
  end

  local now_ns   = floor(ngx.now() * 1e9)
  local start_ns = floor((ngx.req.start_time() or ngx.now()) * 1e9)

  return {
    time_unix_nano          = start_ns,
    observed_time_unix_nano = now_ns,
    severity_number         = sev_num,
    severity_text           = sev_text,
    body                    = fmt("%s %s %d %dms", method, path, status, dur_ms),
    attributes              = attrs,
    trace_id                = trace_id,
    span_id                 = span_id,
    flags                   = 1,
  }
end

---@param records             table
---@param resource_attributes table?
---@return string body
---@return string content_type
function _M.encode(records, resource_attributes)
  return encoder.encode(records, resource_attributes)
end

function _M.endpoint_path()
  return "/v1/logs"
end

return _M
