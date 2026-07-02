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

-- Gateway tracer state: without tracing_instrumentations, Kong never
-- creates spans and the traces path silently exports nothing.
local function gateway_tracer_off()
  local ti = kong.configuration and kong.configuration.tracing_instrumentations
  if ti == nil then
    return true
  end
  if type(ti) == "string" then
    return ti == "off" or ti == ""
  end
  if type(ti) == "table" then
    if #ti == 0 then
      return true
    end
    for _, v in ipairs(ti) do
      if v ~= "off" then
        return false
      end
    end
    return true
  end
  return false
end

-- Both this plugin and the bundled opentelemetry plugin run at priority 14
-- and export spans; running both on the same traffic double-exports.
local function bundled_otel_also_enabled()
  local ok, found = pcall(function()
    local db = kong.db
    if not (db and db.plugins and db.plugins.each) then
      return false
    end
    for plugin, err in db.plugins:each(1000) do
      if err then
        return false
      end
      if plugin.name == "opentelemetry" and plugin.enabled ~= false then
        return true
      end
    end
    return false
  end)
  return ok and found or false
end

---@param configs SignozUserConf[]
function SignozHandler:configure(configs)
  kong_compat.detect_once()
  if not configs then
    return
  end

  -- one worker's warning is enough
  local wid = ngx.worker and ngx.worker.id and ngx.worker.id()
  if wid ~= nil and wid ~= 0 then
    return
  end

  local any_traces = false
  for _, c in ipairs(configs) do
    if traces_enabled(c) then
      any_traces = true
      break
    end
  end

  if any_traces and gateway_tracer_off() then
    kong.log.warn(
      "signoz: traces.enabled=true but the gateway tracer is off — ",
      "no spans will be created or exported. Set tracing_instrumentations ",
      "(and tracing_sampling_rate) in kong.conf or via KONG_TRACING_INSTRUMENTATIONS. ",
      "Access logs are unaffected.")
  end

  if any_traces and bundled_otel_also_enabled() then
    kong.log.warn(
      "signoz: Kong's bundled opentelemetry plugin is also enabled — ",
      "both plugins export spans, so traces may be exported twice. ",
      "Disable one of them for the affected scope.")
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
