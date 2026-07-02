# kong-plugin-signoz

Kong Gateway plugin that ships enriched OTLP traces and structured, trace-correlated request logs to [SigNoz](https://signoz.io) — configured with one endpoint and one ingestion key.

Built on Kong's bundled [OpenTelemetry plugin](https://developer.konghq.com/plugins/opentelemetry/): trace export is delegated to it, the request span is enriched for SigNoz before export, and one structured log record per request ships alongside. Supports Kong Gateway **3.6+** (open-source and Enterprise), OTLP over HTTP.

## What you get in SigNoz

- **Services view** — `kong` appears as a service with request rate, latency percentiles, and error rate.
- **Traces** — the gateway request span carries standard OTel HTTP attributes plus Kong context: matched service, route, consumer, retry count, and the latency split between Kong and the upstream.
- **Logs** — one record per request (`GET /payments 200 28ms`), severity-colored by status class, linked to its trace, with the full request context as queryable attributes.
- **"Is it Kong or the app?"** — every span and log records `kong.latency.gateway_ms` vs `kong.latency.upstream_ms`, so dashboards answer it out of the box.

Headers, query strings, and payloads are never captured.

## Install

The plugin's Lua sources need to be on every Kong node. Kong's [installation and distribution guide](https://developer.konghq.com/custom-plugins/installation-and-distribution/) covers each deployment shape in depth.

```sh
luarocks install kong-plugin-signoz
```

Load it — add `signoz` to the plugins list in `kong.conf` (or `KONG_PLUGINS`) on every node:

```ini
plugins = bundled,signoz
```

## Quickstart

### 1. Enable Kong's tracer

The plugin enriches and exports the spans Kong's own tracer creates, so the tracer must be on (see Kong's [tracing reference](https://developer.konghq.com/gateway/tracing/)):

```ini
tracing_instrumentations = all
tracing_sampling_rate    = 1.0
```

Restart Kong to pick up the plugin and tracer settings. If the tracer is off, the plugin warns at startup — request logs still flow; only traces are gated on it.

### 2. Get your ingestion endpoint and key

- **SigNoz Cloud:** both are under **Settings → Ingestion**. See [Ingestion Keys](https://signoz.io/docs/ingestion/signoz-cloud/keys/).
- **Self-hosted:** point the endpoint at your OTel collector's OTLP/HTTP port (default `4318`); no key required.

### 3. Enable the plugin

Globally, via the Admin API:

```sh
curl -X POST http://localhost:8001/plugins \
  --data "name=signoz" \
  --data "config.exporter.endpoint=https://ingest.<region>.signoz.cloud:443" \
  --data "config.exporter.key=<your-ingestion-key>" \
  --data "config.resource.service_name=kong" \
  --data "config.resource.deployment_environment=production"
```

Traces and request logs are both on by default. The plugin also scopes per service, route, or consumer with standard Kong [plugin precedence](https://developer.konghq.com/gateway/entities/plugin/).

### 4. Verify

Send a request through the gateway, then check SigNoz:

- **Services** shows `kong` with traffic.
- **Traces Explorer** shows gateway spans with `kong.service.name`, `kong.route.name`, and the latency split.
- **Logs Explorer** shows one record per request, one click away from its trace.

If nothing arrives within ~5 seconds, check Kong's error log for `[signoz]` entries and queue warnings.

## Configuration

```yaml
config:
  resource:
    service_name: kong               # service.name in SigNoz
    deployment_environment: production
  exporter:
    endpoint: https://ingest.<region>.signoz.cloud:443   # OTLP/HTTP; http(s) only
    key: <ingestion-key>             # encrypted; Kong Vault-referenceable
  traces:
    enabled: true
    sampling_rate: 1.0
  logs:
    enabled: true
```

Every field, default, and emitted attribute is documented in the [reference](docs/reference.md).

## What this plugin deliberately leaves to Kong

- **Metrics** — use Kong's native OTLP metrics (Gateway 3.13+).
- **Runtime/error logs** — use Kong's bundled OpenTelemetry plugin.

Enabling the bundled `opentelemetry` plugin alongside this one for the same scope double-exports spans; the plugin warns if it detects that.

## Development

`docs/examples/` has a docker-compose setup running Kong DB-less with the plugin source mounted. Tests: `busted spec/unit`, lint: `luacheck kong spec` (both run in CI).

## Support

Developed, tested, and maintained by SigNoz. Issues and questions: [GitHub issues](https://github.com/SigNoz/kong-plugin-signoz/issues) · [SigNoz docs](https://signoz.io/docs/).