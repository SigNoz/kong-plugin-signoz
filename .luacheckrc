std = "ngx_lua"
max_line_length = false
self = false  -- Kong handler methods use the colon form without touching self

globals = {
  "kong",
}

files["spec/**/*_spec.lua"] = {
  std = "+busted",
  globals = { "kong", "ngx" },
}
