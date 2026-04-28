package = "kong-plugin-signoz"
version = "0.0.1-1"
source = {
   url = "git+https://github.com/SigNoz/kong-plugin-signoz.git",
   tag = "v0.0.1-1"
}
description = {
   summary = "Kong plugin that emits OTLP traces and logs to SigNoz.",
   homepage = "https://github.com/SigNoz/kong-plugin-signoz",
   license = "Apache 2.0"
}
dependencies = {
   "lua >= 5.1",
   "lua-cjson",
   "lua-resty-http >= 0.11"
}
build = {
   type = "builtin",
   modules = {
      ["kong.plugins.signoz.handler"] = "kong/plugins/signoz/handler.lua",
      ["kong.plugins.signoz.schema"] = "kong/plugins/signoz/schema.lua",
      ["kong.plugins.signoz.meta"] = "kong/plugins/signoz/meta.lua",
      ["kong.plugins.signoz.kong_compat"] = "kong/plugins/signoz/kong_compat.lua",
      ["kong.plugins.signoz.conf_builder"] = "kong/plugins/signoz/conf_builder.lua",
      ["kong.plugins.signoz.logs"] = "kong/plugins/signoz/logs/init.lua",
      ["kong.plugins.signoz.logs.protobuf"] = "kong/plugins/signoz/logs/protobuf.lua",
      ["kong.plugins.signoz.logs.json"] = "kong/plugins/signoz/logs/json.lua",
      ["kong.plugins.signoz.logs.exporter"] = "kong/plugins/signoz/logs/exporter.lua",
      ["kong.plugins.signoz.traces"] = "kong/plugins/signoz/traces/init.lua"
   }
}
