local kong_compat = require("kong.plugins.signoz.kong_compat")
local meta        = require("kong.plugins.signoz.meta")

local _M = {}

local otel_conf_cache   = setmetatable({}, { __mode = "k" })
local signoz_conf_cache = setmetatable({}, { __mode = "k" })

---@class SignozUserConf
---@field resource { service_name: string, deployment_environment: string|nil }
---@field exporter SignozExporterUserConf
---@field traces   { enabled: boolean, sampling_rate: number }
---@field logs     { instrumentations: string[] }
---@field metrics  { instrumentations: string[] }

---@class SignozExporterUserConf
---@field endpoint        string
---@field key             string|nil
---@field connect_timeout number
---@field send_timeout    number
---@field read_timeout    number
---@field queue           table

---@class SignozExporterConf
---@field ingestion_endpoint  string
---@field headers             table<string,string>|nil
---@field resource_attributes table<string,string>
---@field connect_timeout     number
---@field send_timeout        number
---@field read_timeout        number
---@field queue               table

local function strip_trailing_slash(url)
  if url:sub(-1) == "/" then
    return url:sub(1, -2)
  end
  return url
end

local function traces_enabled(conf)
  return conf.traces and conf.traces.enabled
end

local function runtime_logs_enabled(conf)
  local list = conf.logs and conf.logs.instrumentations
  if not list then return false end
  for _, v in ipairs(list) do
    if v == "off" then return false end
    if v == "all" or v == "runtime" then return true end
  end
  return false
end

---@param conf SignozUserConf
---@return table<string,string>
local function build_resource_attributes(conf)
  local r = conf.resource or {}
  local attrs = {
    ["service.name"] = r.service_name or "kong",
  }
  if r.deployment_environment then
    attrs["deployment.environment"] = r.deployment_environment
  end
  if kong_compat.hostname then
    attrs["host.name"] = kong_compat.hostname
  end
  if kong_compat.node_id then
    attrs["service.instance.id"] = kong_compat.node_id
  end
  return attrs
end

local function ingestion_headers(conf)
  local key = conf.exporter and conf.exporter.key
  if key and key ~= "" then
    return { ["signoz-ingestion-key"] = key }
  end
  return nil
end

---@param conf SignozUserConf
---@param queue_name string
---@return table
local function build_queue(conf, queue_name)
  local q = conf.exporter.queue
  return {
    name                 = queue_name,
    max_batch_size       = q.max_batch_size,
    max_entries          = q.max_entries,
    max_coalescing_delay = q.max_coalescing_delay,
    max_retry_time       = q.max_retry_time,
    initial_retry_delay  = q.initial_retry_delay,
    max_retry_delay      = q.max_retry_delay,
    concurrency_limit    = 1,
  }
end

---@param conf SignozUserConf
---@return SignozExporterConf
function _M.signoz_conf(conf)
  local cached = signoz_conf_cache[conf]
  if cached then
    return cached
  end

  local sc = {
    ingestion_endpoint  = conf.exporter.endpoint,
    headers             = ingestion_headers(conf),
    resource_attributes = build_resource_attributes(conf),
    connect_timeout     = conf.exporter.connect_timeout,
    send_timeout        = conf.exporter.send_timeout,
    read_timeout        = conf.exporter.read_timeout,
    queue               = build_queue(conf, meta.NAME .. ":logs_access"),
  }
  signoz_conf_cache[conf] = sc
  return sc
end

---@param conf SignozUserConf
---@return table
function _M.otel_conf(conf)
  local cached = otel_conf_cache[conf]
  if cached then
    return cached
  end

  local base = strip_trailing_slash(conf.exporter.endpoint)

  local oc = {
    headers             = ingestion_headers(conf),
    resource_attributes = build_resource_attributes(conf),
    sampling_rate       = conf.traces and conf.traces.sampling_rate or 1.0,
    connect_timeout     = conf.exporter.connect_timeout,
    send_timeout        = conf.exporter.send_timeout,
    read_timeout        = conf.exporter.read_timeout,
    queue               = build_queue(conf, meta.NAME),
  }

  kong_compat.set_propagation(oc)

  if traces_enabled(conf) then
    kong_compat.set_traces_endpoint(oc, base .. "/v1/traces")
  end

  if runtime_logs_enabled(conf) then
    kong_compat.set_logs_endpoint(oc, base .. "/v1/logs")
  end

  otel_conf_cache[conf] = oc
  return oc
end

return _M
