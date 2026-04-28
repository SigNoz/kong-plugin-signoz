local PLUGIN_NAME = "signoz"

local validate do
  local validate_entity = require("spec.helpers").validate_plugin_config_schema
  local plugin_schema = require("kong.plugins." .. PLUGIN_NAME .. ".schema")

  function validate(data)
    return validate_entity(data, plugin_schema)
  end
end


describe(PLUGIN_NAME .. ": (schema)", function()

  it("accepts a cloud config with exporter.key", function()
    local ok, err = validate({
      exporter = {
        endpoint = "https://ingest.us.signoz.cloud:443",
        key = "test-key",
      },
    })
    assert.is_nil(err)
    assert.is_truthy(ok)
  end)

  it("accepts a self-hosted config without exporter.key", function()
    local ok, err = validate({
      exporter = {
        endpoint = "http://signoz-otel-collector:4318",
      },
    })
    assert.is_nil(err)
    assert.is_truthy(ok)
  end)

  it("rejects missing exporter.endpoint", function()
    local ok, err = validate({ exporter = { key = "test-key" } })
    assert.is_falsy(ok)
    assert.is_truthy(err)
  end)

  it("rejects missing exporter block entirely", function()
    local ok, err = validate({ resource = { service_name = "kong" } })
    assert.is_falsy(ok)
    assert.is_truthy(err)
  end)

  it("rejects sampling_rate out of range", function()
    local ok, err = validate({
      exporter = { endpoint = "http://localhost:4318" },
      traces = { sampling_rate = 2.0 },
    })
    assert.is_falsy(ok)
    assert.is_truthy(err)
  end)

  it("supplies sensible defaults across all groups", function()
    local ok, _, conf = validate({
      exporter = { endpoint = "http://localhost:4318" },
    })
    assert.is_truthy(ok)
    assert.equals("kong", conf.config.resource.service_name)
    assert.is_true(conf.config.traces.enabled)
    assert.equals(1.0, conf.config.traces.sampling_rate)
    assert.same({ "off" }, conf.config.logs.instrumentations)
    assert.same({ "off" }, conf.config.metrics.instrumentations)
    assert.equals(1000, conf.config.exporter.connect_timeout)
    assert.equals(5000, conf.config.exporter.send_timeout)
    assert.equals(5000, conf.config.exporter.read_timeout)
    assert.equals(200, conf.config.exporter.queue.max_batch_size)
    assert.equals(10000, conf.config.exporter.queue.max_entries)
  end)

  it("accepts logs.instrumentations=[access, runtime]", function()
    local ok, err = validate({
      exporter = { endpoint = "http://localhost:4318" },
      logs = { instrumentations = { "access", "runtime" } },
    })
    assert.is_nil(err)
    assert.is_truthy(ok)
  end)

  it("rejects unknown logs.instrumentations sub-type", function()
    local ok, err = validate({
      exporter = { endpoint = "http://localhost:4318" },
      logs = { instrumentations = { "access", "bogus" } },
    })
    assert.is_falsy(ok)
    assert.is_truthy(err)
  end)

  it("accepts user-tuned exporter.queue + timeouts", function()
    local ok, err = validate({
      exporter = {
        endpoint = "http://localhost:4318",
        connect_timeout = 500,
        send_timeout    = 2500,
        read_timeout    = 2500,
        queue = {
          max_batch_size       = 50,
          max_coalescing_delay = 1,
        },
      },
    })
    assert.is_nil(err)
    assert.is_truthy(ok)
  end)

end)
