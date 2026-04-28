# kong-plugin-signoz

Kong Gateway plugin that ships OTLP traces and logs from Kong to [SigNoz](https://signoz.io).

Supports Kong Gateway **3.6+** (open-source and Enterprise). Delegates trace export to Kong's bundled [OpenTelemetry plugin](https://developer.konghq.com/plugins/opentelemetry/) and synthesises one structured OTLP log record per request alongside.

## Install

```sh
luarocks install kong-plugin-signoz
```

Add `signoz` to the loaded plugins (`kong.conf` or env):

```ini
plugins = bundled,signoz
```

Restart Kong, then enable the plugin against your gateway, service, route, or consumer.

## Getting Started

Install the plugin, enable Kong's tracer, and ship the first request to SigNoz.

## 1. Install the plugin

On every Kong node:

```sh
luarocks install kong-plugin-signoz
```

Add `signoz` to the loaded plugins in `kong.conf` (or via the `KONG_PLUGINS` environment variable):

```ini
plugins = bundled,signoz
```

## 2. Enable Kong's tracer

The plugin enriches Kong's root request span before export. Kong's tracer must be on for that span to exist. Set in `kong.conf` or via environment (see Kong's [tracing reference](https://developer.konghq.com/gateway/tracing/) for the full list of values):

```ini
tracing_instrumentations = all
tracing_sampling_rate    = 1.0
```

Without these, `ngx.ctx.KONG_SPANS` stays empty and no spans are exported. Logs still ship; only the trace path is gated on the tracer being on.

Restart Kong to pick up both the new plugin and the tracer settings.

## 3. Get your ingestion endpoint and key

**SigNoz Cloud:** find both under **Settings > Ingestion**. See [Ingestion Keys](https://signoz.io/docs/ingestion/signoz-cloud/keys/).

**Self-hosted:** point `exporter.endpoint` at your OTel collector's OTLP/HTTP port (default `4318`). No key required.

## 4. Enable the plugin

Globally on the gateway (Cloud example):

```sh
curl -X POST http://localhost:8001/plugins \
  --data "name=signoz" \
  --data "config.exporter.endpoint=https://ingest.<region>.signoz.cloud:443" \
  --data "config.exporter.key=<your-ingestion-key>" \
  --data "config.resource.service_name=kong" \
  --data "config.resource.deployment_environment=production" \
  --data "config.logs.instrumentations=access"
```

Self-hosted equivalent:

```sh
curl -X POST http://localhost:8001/plugins \
  --data "name=signoz" \
  --data "config.exporter.endpoint=http://signoz-otel-collector:4318" \
  --data "config.resource.service_name=kong" \
  --data "config.logs.instrumentations=access"
```

The plugin can also be scoped per-service, per-route, or per-consumer using the standard Kong [Admin API](https://developer.konghq.com/admin-api/). See Kong's [Plugin entity](https://developer.konghq.com/gateway/entities/plugin/) docs for scoping syntax.

## 5. Verify

Send a request through Kong:

```sh
curl -i http://localhost:8000/<your-route>
```

In SigNoz:

- **Services** view shows `kong` with traffic.
- **Traces Explorer** lists spans named `kong` with attributes `kong.service.name`, `kong.route.name`, and HTTP semconv fields.
- **Logs Explorer** lists one record per request with body shaped `"<METHOD> <path> <status> <duration>ms"` and severity coloured by status class.

If nothing arrives within ~5 seconds, check Kong's error log for `[signoz]` entries — exporter HTTP errors and queue drops are logged there.

## What's next

- [Reference](docs/reference.md) for understanding every field, default, and behaviour.
- [Ingestion overview](https://signoz.io/docs/ingestion/signoz-cloud/overview/) for checking out endpoints by region, auth headers
