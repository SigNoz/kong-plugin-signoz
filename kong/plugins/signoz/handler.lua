local otel_handler = require "kong.plugins.opentelemetry.handler"

local SignozHandler = {
  VERSION  = "0.0.1",
  PRIORITY = 14,
}

local otel_conf_cache = setmetatable({}, { __mode = "k" })
local logs_unsupported_warned = false

-- Populated on first phase call from PDK values. Doing this lazily keeps
-- handler.lua free of Kong-core internal requires for version detection.
local detected = false
local is_kong_3_7_plus = false
local is_kong_3_8_plus = false
local logs_runtime_supported = false
local hostname = nil
local node_id = nil

local function detect_once()
  if detected then
    return
  end

  local version_str = kong.version or "0.0"
  local major, minor = version_str:match("^(%d+)%.(%d+)")
  major = tonumber(major) or 0
  minor = tonumber(minor) or 0
  is_kong_3_7_plus = (major > 3) or (major == 3 and minor >= 7)
  is_kong_3_8_plus = (major > 3) or (major == 3 and minor >= 8)
  logs_runtime_supported = is_kong_3_8_plus
    and type(otel_handler.configure) == "function"

  -- PDK: kong.node.get_hostname() / get_id(). Wrapped defensively in case a
  -- forked or minor variant lacks one of them.
  local ok, v = pcall(kong.node.get_hostname)
  if ok then hostname = v end
  ok, v = pcall(kong.node.get_id)
  if ok then node_id = v end

  detected = true
end

local function strip_trailing_slash(url)
  if url:sub(-1) == "/" then
    return url:sub(1, -2)
  end
  return url
end

local function traces_enabled(conf)
  return conf.traces and conf.traces.enabled
end

local function logs_enabled(conf)
  return conf.logs and conf.logs.enabled
end

local function warn_logs_unsupported_once()
  if not logs_unsupported_warned then
    kong.log.warn("signoz: logs require Kong >= 3.8; disabling log export")
    logs_unsupported_warned = true
  end
end

local function build_otel_conf(conf)
  local cached = otel_conf_cache[conf]
  if cached then
    return cached
  end

  local base = strip_trailing_slash(conf.ingestion.endpoint)

  local headers
  if conf.ingestion.key and conf.ingestion.key ~= "" then
    headers = { ["signoz-ingestion-key"] = conf.ingestion.key }
  end

  local resource_attributes = {
    ["service.name"] = conf.service_name or "kong",
  }
  if conf.deployment_environment then
    resource_attributes["deployment.environment"] = conf.deployment_environment
  end
  if hostname then
    resource_attributes["host.name"] = hostname
  end
  if node_id then
    resource_attributes["service.instance.id"] = node_id
  end

  local otel_conf = {
    headers             = headers,
    resource_attributes = resource_attributes,
    sampling_rate       = conf.traces and conf.traces.sampling_rate or 1.0,
    connect_timeout     = 1000,
    send_timeout        = 5000,
    read_timeout        = 5000,
    queue = {
      name                 = "signoz",
      max_batch_size       = 200,
      max_entries          = 10000,
      max_coalescing_delay = 3,
      max_retry_time       = 60,
      initial_retry_delay  = 0.01,
      max_retry_delay      = 60,
      concurrency_limit    = 1,
    },
  }

  if is_kong_3_7_plus then
    otel_conf.propagation = { default_format = "w3c" }
  else
    otel_conf.header_type = "w3c"
  end

  if traces_enabled(conf) then
    local traces_url = base .. "/v1/traces"
    if is_kong_3_8_plus then
      otel_conf.traces_endpoint = traces_url
    else
      otel_conf.endpoint = traces_url
    end
  end
  if logs_enabled(conf) and logs_runtime_supported then
    otel_conf.logs_endpoint = base .. "/v1/logs"
  end

  otel_conf_cache[conf] = otel_conf
  return otel_conf
end

function SignozHandler:configure(configs)
  detect_once()
  if not configs or not logs_runtime_supported then
    return
  end
  local mapped = {}
  for _, c in ipairs(configs) do
    if logs_enabled(c) then
      mapped[#mapped + 1] = build_otel_conf(c)
    end
  end
  if #mapped > 0 then
    otel_handler:configure(mapped)
  end
end

function SignozHandler:access(conf)
  detect_once()
  if not traces_enabled(conf) then
    return
  end
  otel_handler:access(build_otel_conf(conf))
end

function SignozHandler:header_filter(conf)
  detect_once()
  if not traces_enabled(conf) then
    return
  end
  otel_handler:header_filter(build_otel_conf(conf))
end

function SignozHandler:log(conf)
  detect_once()
  local do_traces = traces_enabled(conf)
  local do_logs   = logs_enabled(conf)

  if do_logs and not logs_runtime_supported then
    warn_logs_unsupported_once()
  end

  if not (do_traces or (do_logs and logs_runtime_supported)) then
    return
  end

  otel_handler:log(build_otel_conf(conf))
end

return SignozHandler
