rockspec_format = "3.0"
package = "kong-plugin-signoz"
version = "0.0.1-1"
supported_platforms = { "linux", "macosx" }
source = {
   url = "git+https://github.com/SigNoz/kong-plugin-signoz.git",
   tag = "v0.0.1"
}
description = {
   summary    = "Kong plugin that emits OTLP traces and logs to SigNoz.",
   homepage   = "https://github.com/SigNoz/kong-plugin-signoz",
   license    = "Apache 2.0",
   maintainer = "SigNoz Marketplaces <marketplaces@signoz.io>",
   issues_url = "https://github.com/SigNoz/kong-plugin-signoz/issues",
   labels     = { "kong", "kong-plugin", "observability", "opentelemetry", "otlp", "signoz", "tracing", "logging" }
}
dependencies = {}
build = {
   type = "builtin",
   modules = {
      ["kong.plugins.signoz.handler"]         = "kong/plugins/signoz/handler.lua",
      ["kong.plugins.signoz.schema"]          = "kong/plugins/signoz/schema.lua",
      ["kong.plugins.signoz.meta"]            = "kong/plugins/signoz/meta.lua",
      ["kong.plugins.signoz.kong_compat"]     = "kong/plugins/signoz/kong_compat.lua",
      ["kong.plugins.signoz.conf_builder"]    = "kong/plugins/signoz/conf_builder.lua",
      ["kong.plugins.signoz.logs"]            = "kong/plugins/signoz/logs/init.lua",
      ["kong.plugins.signoz.logs.protobuf"]   = "kong/plugins/signoz/logs/protobuf.lua",
      ["kong.plugins.signoz.logs.json"]       = "kong/plugins/signoz/logs/json.lua",
      ["kong.plugins.signoz.logs.exporter"]   = "kong/plugins/signoz/logs/exporter.lua",
      ["kong.plugins.signoz.traces"]          = "kong/plugins/signoz/traces/init.lua"
   }
}
