std             = "ngx_lua"
unused_args     = false
redefined       = false
max_line_length = 120

globals = {
  "_KONG",
  "kong",
  "ngx",
}

not_globals = {
  "string.len",
  "table.getn",
}

include_files = {
  "**/*.lua",
  "*.rockspec",
  ".luacheckrc",
}

files["spec/**/*.lua"] = {
  std = "ngx_lua+busted",
}
