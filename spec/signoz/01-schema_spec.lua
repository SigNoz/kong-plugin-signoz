local PLUGIN_NAME = "signoz"

local validate do
  local validate_entity = require("spec.helpers").validate_plugin_config_schema
  local plugin_schema = require("kong.plugins." .. PLUGIN_NAME .. ".schema")

  function validate(data)
    return validate_entity(data, plugin_schema)
  end
end


describe(PLUGIN_NAME .. ": (schema)", function()

  it("accepts a cloud config with ingestion.key", function()
    local ok, err = validate({
      ingestion = {
        endpoint = "https://ingest.us.signoz.cloud:443",
        key = "test-key",
      },
    })
    assert.is_nil(err)
    assert.is_truthy(ok)
  end)

  it("accepts a self-hosted config without ingestion.key", function()
    local ok, err = validate({
      ingestion = {
        endpoint = "http://ingest.us.signoz.cloud:443",
      },
    })
    assert.is_nil(err)
    assert.is_truthy(ok)
  end)

  it("rejects missing ingestion.endpoint", function()
    local ok, err = validate({
      ingestion = {
        key = "test-key",
      },
    })
    assert.is_falsy(ok)
    assert.is_truthy(err)
  end)

  it("rejects missing ingestion block entirely", function()
    local ok, err = validate({
      service_name = "kong",
    })
    assert.is_falsy(ok)
    assert.is_truthy(err)
  end)

  it("rejects sampling_rate out of range", function()
    local ok, err = validate({
      ingestion = {
        endpoint = "http://localhost:4318",
      },
      traces = { sampling_rate = 2.0 },
    })
    assert.is_falsy(ok)
    assert.is_truthy(err)
  end)

  it("defaults service_name to 'kong'", function()
    local ok, _, conf = validate({
      ingestion = {
        endpoint = "http://localhost:4318",
      },
    })
    assert.is_truthy(ok)
    assert.equals("kong", conf.config.service_name)
  end)

  it("accepts logs.enabled=true with an endpoint", function()
    local ok, err = validate({
      ingestion = {
        endpoint = "http://localhost:4318",
      },
      logs = { enabled = true },
    })
    assert.is_nil(err)
    assert.is_truthy(ok)
  end)

  it("accepts traces+logs together", function()
    local ok, err = validate({
      ingestion = {
        endpoint = "http://localhost:4318",
        key = "test-key",
      },
      traces = { enabled = true, sampling_rate = 0.5 },
      logs   = { enabled = true },
    })
    assert.is_nil(err)
    assert.is_truthy(ok)
  end)

end)
