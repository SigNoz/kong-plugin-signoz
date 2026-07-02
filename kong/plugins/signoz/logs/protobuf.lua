local otlp = require("kong.observability.otlp")

local floor = math.floor

local _M = {}

-- kong.observability.otlp.encode_logs() pb-encodes the batch as-is, so each
-- record must already be proto-shaped: body as an AnyValue message and
-- attributes as a KeyValue list. Kong's own pipeline does this in
-- prepare_logs(), but that transform assumes one batch-level trace_id;
-- our records carry per-request trace ids, so we transform here instead.

local function anyvalue(v)
  local t = type(v)
  if t == "string" then
    return { string_value = v }
  elseif t == "number" then
    if v == floor(v) then
      return { int_value = v }
    end
    return { double_value = v }
  elseif t == "boolean" then
    return { bool_value = v }
  end
  return { string_value = tostring(v) }
end

local function transform_attributes(map)
  local arr = {}
  if not map then return arr end
  local i = 0
  for k, v in pairs(map) do
    if v ~= nil then
      i = i + 1
      arr[i] = { key = k, value = anyvalue(v) }
    end
  end
  return arr
end

local function transform_record(rec)
  return {
    time_unix_nano          = rec.time_unix_nano,
    observed_time_unix_nano = rec.observed_time_unix_nano,
    severity_number         = rec.severity_number,
    severity_text           = rec.severity_text,
    body                    = { string_value = rec.body or "" },
    attributes              = transform_attributes(rec.attributes),
    trace_id                = rec.trace_id, -- raw bytes from the Kong span
    span_id                 = rec.span_id,
    flags                   = rec.trace_id and rec.flags or nil,
  }
end

---@param records             table
---@param resource_attributes table?
---@return string body
---@return string content_type
function _M.encode(records, resource_attributes)
  local log_records = {}
  for i, rec in ipairs(records) do
    log_records[i] = transform_record(rec)
  end
  return otlp.encode_logs(log_records, resource_attributes), "application/x-protobuf"
end

return _M
