std             = "ngx_lua"
unused_args     = false
redefined       = false
max_line_length = false

globals = {
  "_KONG",
  "kong",
  "ngx.IS_CLI",
}

not_globals = {
  "string.len",
  "table.getn",
}

ignore = {
  "6.", -- whitespace warnings
}

include_files = {
  "**/*.lua",
  "*.rockspec",
  ".busted",
  ".luacheckrc",
}

files["spec/**/*.lua"] = {
  std = "ngx_lua+busted",
}
