local typedefs = require("kong.db.schema.typedefs")

local PLUGIN_NAME = "signoz"

return {
  name = PLUGIN_NAME,
  fields = {
    { protocols = typedefs.protocols_http },
    { config = {
        type = "record",
        fields = {
          { resource = {
              type = "record",
              fields = {
                { service_name = { type = "string", default = "kong" } },
                { deployment_environment = { type = "string", required = false } },
              },
          } },

          { exporter = {
              type = "record",
              required = true,
              fields = {
                { endpoint = typedefs.url { required = true } },
                { key = {
                    type          = "string",
                    required      = false,
                    referenceable = true,
                    encrypted     = true,
                } },
                { connect_timeout = typedefs.timeout { default = 1000 } },
                { send_timeout    = typedefs.timeout { default = 5000 } },
                { read_timeout    = typedefs.timeout { default = 5000 } },
                { queue = {
                    type   = "record",
                    fields = {
                      { max_batch_size = {
                          type    = "integer",
                          between = { 1, 1000000 },
                          default = 200,
                      } },
                      { max_entries = {
                          type    = "integer",
                          between = { 1, 1000000 },
                          default = 10000,
                      } },
                      { max_coalescing_delay = {
                          type    = "number",
                          between = { 0, 3600 },
                          default = 3,
                      } },
                      { max_retry_time = {
                          type    = "number",
                          default = 60,
                      } },
                      { initial_retry_delay = {
                          type    = "number",
                          between = { 0.001, 1000000 },
                          default = 0.01,
                      } },
                      { max_retry_delay = {
                          type    = "number",
                          between = { 0.001, 1000000 },
                          default = 60,
                      } },
                    },
                } },
              },
          } },

          { traces = {
              type = "record",
              fields = {
                { enabled = { type = "boolean", default = true } },
                { sampling_rate = {
                    type    = "number",
                    between = { 0, 1 },
                    default = 1.0,
                } },
              },
          } },
          { logs = {
              type = "record",
              fields = {
                { instrumentations = {
                    type    = "array",
                    default = { "off" },
                    elements = {
                      type   = "string",
                      one_of = { "off", "all", "access", "runtime" },
                    },
                } },
              },
          } },
        },
    } },
  },
}
