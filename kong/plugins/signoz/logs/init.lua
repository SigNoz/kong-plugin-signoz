local ngx = ngx

local fmt   = string.format
local floor = math.floor

local attributes = require("kong.plugins.signoz.attributes")

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

---@param message table  Output of kong.log.serialize().
---@param span    table|nil
---@return table
function _M.build_record(message, span)
  local lat = message.latencies or {}

  -- Same identity + measurement attributes as the root span, from the
  -- same serialize() message — the two signals cannot drift apart.
  local attrs = attributes.identity(message)
  attributes.merge(attrs, attributes.measurements(message))
  attrs["message.type"] = "kong.access"

  local method = attrs["http.request.method"]
  local path   = attrs["url.path"]
  local status = attrs["http.response.status_code"]
  local dur_ms = lat.request or 0

  local sev_num, sev_text = severity_from_status(status)

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
