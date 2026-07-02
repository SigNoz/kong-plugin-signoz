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

local function traces_enabled(conf)
  return conf.traces and conf.traces.enabled
end

local function logs_enabled(conf)
  return conf.logs and conf.logs.enabled
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
  local do_traces = traces_enabled(conf)
  local do_logs   = logs_enabled(conf)

  if not do_traces and not do_logs then
    return
  end

  -- One serialize() feeds both signals so span and log attributes match.
  local message = kong.log.serialize()

  if do_traces then
    traces.decorate(message)
    otel_handler:log(conf_builder.otel_conf(conf))
  end

  if do_logs then
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
