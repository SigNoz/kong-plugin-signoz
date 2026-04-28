local kong = kong

local _M = {
  is_kong_3_7_plus = false,
  is_kong_3_8_plus = false,
  hostname         = nil,
  node_id          = nil,
}

local detected = false

local function set_propagation_3_7(oc)
  oc.propagation = { default_format = "w3c" }
end

local function set_propagation_legacy(oc)
  oc.header_type = "w3c"
end

local function set_traces_endpoint_3_8(oc, url)
  oc.traces_endpoint = url
end

local function set_traces_endpoint_legacy(oc, url)
  oc.endpoint = url
end

local function set_logs_endpoint_3_8(oc, url)
  oc.logs_endpoint = url
end

local function set_logs_endpoint_noop(_, _) end

_M.set_propagation     = set_propagation_legacy
_M.set_traces_endpoint = set_traces_endpoint_legacy
_M.set_logs_endpoint   = set_logs_endpoint_noop

function _M.detect_once()
  if detected then
    return
  end

  local version_str = kong.version or "0.0"
  local major, minor = version_str:match("^(%d+)%.(%d+)")
  major = tonumber(major) or 0
  minor = tonumber(minor) or 0
  _M.is_kong_3_7_plus = (major > 3) or (major == 3 and minor >= 7)
  _M.is_kong_3_8_plus = (major > 3) or (major == 3 and minor >= 8)

  if _M.is_kong_3_7_plus then
    _M.set_propagation = set_propagation_3_7
  end
  if _M.is_kong_3_8_plus then
    _M.set_traces_endpoint = set_traces_endpoint_3_8
    _M.set_logs_endpoint   = set_logs_endpoint_3_8
  end

  local ok, v = pcall(kong.node.get_hostname)
  if ok then _M.hostname = v end
  ok, v = pcall(kong.node.get_id)
  if ok then _M.node_id = v end

  detected = true
end

return _M
