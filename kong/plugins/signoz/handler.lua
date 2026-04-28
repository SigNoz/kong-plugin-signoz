local kong = kong
local ngx  = ngx

local otel_handler  = require("kong.plugins.opentelemetry.handler")
local Queue         = require("kong.tools.queue")

local meta          = require("kong.plugins.signoz.meta")
local kong_compat   = require("kong.plugins.signoz.kong_compat")
local conf_builder  = require("kong.plugins.signoz.conf_builder")
local logs          = require("kong.plugins.signoz.logs")
local logs_exporter = require("kong.plugins.signoz.logs.exporter")
local traces        = require("kong.plugins.signoz.traces")

local SignozHandler = {
  VERSION  = meta.VERSION,
  PRIORITY = 14,
}

local runtime_unsupported_warned = false

local function traces_enabled(conf)
  return conf.traces and conf.traces.enabled
end

---@param conf SignozUserConf
---@param name string
---@return boolean
local function log_subtype_enabled(conf, name)
  local list = conf.logs and conf.logs.instrumentations
  if not list or #list == 0 then
    return false
  end
  for _, v in ipairs(list) do
    if v == "off" then
      return false
    end
    if v == "all" or v == name then
      return true
    end
  end
  return false
end

local function warn_runtime_unsupported_once()
  if not runtime_unsupported_warned then
    kong.log.warn("signoz: logs.instrumentations 'runtime' requires Kong >= 3.8; skipping")
    runtime_unsupported_warned = true
  end
end

---@param configs SignozUserConf[]
function SignozHandler:configure(configs)
  kong_compat.detect_once()
  if not configs or not kong_compat.is_kong_3_8_plus then
    return
  end
  local mapped = {}
  for _, c in ipairs(configs) do
    if log_subtype_enabled(c, "runtime") then
      mapped[#mapped + 1] = conf_builder.otel_conf(c)
    end
  end
  if #mapped > 0 then
    otel_handler:configure(mapped)
  end
end

---@param conf SignozUserConf
function SignozHandler:access(conf)
  kong_compat.detect_once()
  if not traces_enabled(conf) then
    return
  end
  otel_handler:access(conf_builder.otel_conf(conf))
end

---@param conf SignozUserConf
function SignozHandler:header_filter(conf)
  kong_compat.detect_once()
  if not traces_enabled(conf) then
    return
  end
  otel_handler:header_filter(conf_builder.otel_conf(conf))
end

---@param conf SignozUserConf
function SignozHandler:log(conf)
  kong_compat.detect_once()
  local do_traces       = traces_enabled(conf)
  local do_access_logs  = log_subtype_enabled(conf, "access")
  local do_runtime_logs = log_subtype_enabled(conf, "runtime")

  if do_runtime_logs and not kong_compat.is_kong_3_8_plus then
    warn_runtime_unsupported_once()
    do_runtime_logs = false
  end

  if do_traces then
    traces.decorate()
  end

  if do_traces or do_runtime_logs then
    otel_handler:log(conf_builder.otel_conf(conf))
  end

  if do_access_logs then
    local message = kong.log.serialize()
    local span    = (ngx.ctx.KONG_SPANS or {})[1]
    local record  = logs.build_record(message, span)
    local sc      = conf_builder.signoz_conf(conf)
    local ok, err = Queue.enqueue(sc.queue, logs_exporter.post, sc, record)
    if not ok then
      kong.log.err("signoz: failed to enqueue access log: ", err)
    end
  end
end

return SignozHandler
