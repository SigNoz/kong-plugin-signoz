local otlp = require("kong.observability.otlp")

local _M = {}

---@param records             table
---@param resource_attributes table?
---@return string body
---@return string content_type
function _M.encode(records, resource_attributes)
  return otlp.encode_logs(records, resource_attributes), "application/x-protobuf"
end

return _M
