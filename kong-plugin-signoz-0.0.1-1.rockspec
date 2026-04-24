package = "kong-plugin-signoz"
version = "0.0.1-1"
source = {
   url = "git+https://github.com/SigNoz/kong-plugin-signoz.git",
   tag = "v0.0.1-1"
}
description = {
   summary = "Kong plugin that emits OTLP traces and logs to SigNoz.",
   homepage = "https://github.com/SigNoz/kong-plugin-signoz",
   license = "Apache-2.0"
}
dependencies = {
   "lua ~> 5.1"
}
build = {
   type = "builtin",
   modules = {
      ["kong.plugins.signoz.handler"] = "kong/plugins/signoz/handler.lua",
      ["kong.plugins.signoz.schema"] = "kong/plugins/signoz/schema.lua"
   }
}
