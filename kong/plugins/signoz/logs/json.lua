local cjson = require("cjson.safe")
local meta  = require("kong.plugins.signoz.meta")

local fmt   = string.format
local byte  = string.byte
local gsub  = string.gsub
local floor = math.floor

local _M = {}

local function bytes_to_hex(s)
  if not s or s == "" then return "" end
  return (gsub(s, ".", function(c)
    return fmt("%02x", byte(c))
  end))
end

local function encode_attr(k, v)
  local vt = type(v)
  if vt == "string" then
    return { key = k, value = { stringValue = v } }
  elseif vt == "number" then
    if v == floor(v) then
      return { key = k, value = { intValue = fmt("%d", v) } }
    end
    return { key = k, value = { doubleValue = v } }
  elseif vt == "boolean" then
    return { key = k, value = { boolValue = v } }
  end
  return { key = k, value = { stringValue = tostring(v) } }
end

local function encode_attr_map(map)
  local arr = {}
  if not map then return arr end
  local i = 0
  for k, v in pairs(map) do
    if v ~= nil then
      i = i + 1
      arr[i] = encode_attr(k, v)
    end
  end
  return arr
end

local function encode_record(rec)
  return {
    timeUnixNano         = fmt("%d", rec.time_unix_nano or 0),
    observedTimeUnixNano = fmt("%d", rec.observed_time_unix_nano or 0),
    severityNumber       = rec.severity_number or 0,
    severityText         = rec.severity_text or "",
    body                 = { stringValue = rec.body or "" },
    attributes           = encode_attr_map(rec.attributes),
    traceId              = bytes_to_hex(rec.trace_id),
    spanId               = bytes_to_hex(rec.span_id),
    flags                = rec.flags or 0,
  }
end

---@param records             table
---@param resource_attributes table?
---@return string body
---@return string content_type
function _M.encode(records, resource_attributes)
  local log_records = {}
  for i, rec in ipairs(records) do
    log_records[i] = encode_record(rec)
  end

  local payload = {
    resourceLogs = {
      {
        resource  = { attributes = encode_attr_map(resource_attributes) },
        scopeLogs = {
          {
            scope = {
              name    = "kong-plugin-" .. meta.NAME,
              version = meta.VERSION,
            },
            logRecords = log_records,
          },
        },
      },
    },
  }

  return cjson.encode(payload), "application/json"
end

return _M
