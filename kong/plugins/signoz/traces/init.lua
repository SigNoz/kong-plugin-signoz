local kong = kong
local ngx  = ngx

local attributes = require("kong.plugins.signoz.attributes")

local _M = {}

local SPAN_STATUS_ERROR = 2

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

-- Mark the span errored on 5xx. Kong span tables carry a numeric status
-- field the OTLP encoder picks up; prefer the method when it exists.
local function set_error_status(span)
  if type(span.set_status) == "function" then
    local ok = pcall(span.set_status, span, SPAN_STATUS_ERROR)
    if ok then return end
  end
  span.status = SPAN_STATUS_ERROR
end

---@param message table  Output of kong.log.serialize().
function _M.decorate(message)
  local span = get_root_span()
  if not span then
    return
  end
  span.attributes = span.attributes or {}
  local a = span.attributes

  attributes.merge(a, attributes.identity(message))
  attributes.merge(a, attributes.measurements(message))
  attributes.merge(a, attributes.span_extras(message))

  local status = tonumber((message.response or {}).status) or 0
  if status >= 500 then
    set_error_status(span)
  end
end

return _M
