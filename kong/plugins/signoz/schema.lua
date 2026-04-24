local typedefs = require "kong.db.schema.typedefs"

local PLUGIN_NAME = "signoz"

return {
  name = PLUGIN_NAME,
  fields = {
    { protocols = typedefs.protocols_http },
    { config = {
        type = "record",
        fields = {
          { ingestion = {
              type = "record",
              required = true,
              fields = {
                { endpoint = typedefs.url { required = true } },
                { key = {
                    type = "string",
                    required = false,
                    referenceable = true,
                    encrypted = true,
                } },
              },
          } },
          { service_name = { type = "string", default = "kong" } },
          { deployment_environment = { type = "string", required = false } },
          { traces = {
              type = "record",
              fields = {
                { enabled = { type = "boolean", default = true } },
                { sampling_rate = {
                    type = "number",
                    between = { 0, 1 },
                    default = 1.0,
                } },
              },
          } },
          { logs = {
              type = "record",
              fields = {
                { enabled = { type = "boolean", default = false } },
              },
          } },
          { metrics = {
              type = "record",
              fields = {
                { enabled = { type = "boolean", default = false } },
              },
          } },
        },
    } },
  },
}
