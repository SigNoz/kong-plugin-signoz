# kong-plugin-signoz

Kong Gateway plugin that emits OTLP traces and logs to [SigNoz](https://signoz.io).

Thin wrapper around Kong's bundled `opentelemetry` plugin. Users configure a single SigNoz ingestion endpoint and (optionally) an ingestion key; the plugin delegates to `kong.plugins.opentelemetry` in-process to do the actual span/log collection, queuing, and OTLP/HTTP POST.

**Research:** [`~/repo/integrations/research/kong/research.md`](../../integrations/research/kong/research.md)

## Requirements

- Kong Gateway **3.6 or newer** (traces). Verified on 3.6, 3.7, 3.8.
- Kong Gateway **3.8 or newer** (logs — gated at runtime; earlier versions silently disable log export).
- Kong's bundled `opentelemetry` plugin must be available (it is, on all OSS and Enterprise builds ≥ 3.0).
- Kong-level tracing must be enabled. Add to `kong.conf` or environment:

  ```
  KONG_TRACING_INSTRUMENTATIONS=all
  KONG_TRACING_SAMPLING_RATE=1.0
  ```

  Without this, Kong's internal tracer never populates `ngx.ctx.KONG_SPANS` and no spans are exported regardless of plugin config.

## Install

```sh
luarocks install kong-plugin-signoz
```

Then add `signoz` to Kong's loaded plugins. In `kong.conf`:

```ini
plugins = bundled,signoz
```

Or via environment variable:

```sh
export KONG_PLUGINS=bundled,signoz
```

Restart Kong.

## Configure

### SigNoz Cloud

```sh
curl -X POST http://localhost:8001/plugins \
  --data "name=signoz" \
  --data "config.ingestion.endpoint=https://ingest.us.signoz.cloud:443" \
  --data "config.ingestion.key=<your-ingestion-key>" \
  --data "config.service_name=kong" \
  --data "config.deployment_environment=production"
```

### Self-hosted SigNoz

```sh
curl -X POST http://localhost:8001/plugins \
  --data "name=signoz" \
  --data "config.ingestion.endpoint=http://signoz-otel-collector:4318" \
  --data "config.service_name=kong"
```

Self-hosted deployments do not require `ingestion.key`.

### Full config surface

| Field | Required | Default | Notes |
| --- | --- | --- | --- |
| `config.ingestion.endpoint` | yes | — | Base URL. `/v1/traces` and `/v1/logs` are appended. |
| `config.ingestion.key` | no | — | Emitted as `signoz-ingestion-key` header. Referenceable via Kong Vault. |
| `config.service_name` | no | `kong` | Maps to `service.name` resource attribute. |
| `config.deployment_environment` | no | — | Maps to `deployment.environment` resource attribute. |
| `config.traces.enabled` | no | `true` | Disable to turn off trace export. |
| `config.traces.sampling_rate` | no | `1.0` | 0–1 probability. |
| `config.logs.enabled` | no | `false` | Enable to export Kong access/worker logs via OTLP. Requires Kong ≥ 3.8. |
| `config.metrics.enabled` | no | `false` | Reserved. |

Plugin scope: global, per-service, per-route, per-consumer (standard Kong semantics).

## Logs

Set `config.logs.enabled=true` to export Kong's access logs and worker logs to SigNoz alongside traces. Log records automatically include `trace_id` when the request has an active trace (requires `config.traces.enabled=true` on the same request path).

```sh
curl -X POST http://localhost:8001/plugins \
  --data "name=signoz" \
  --data "config.ingestion.endpoint=https://ingest.us.signoz.cloud:443" \
  --data "config.ingestion.key=<your-ingestion-key>" \
  --data "config.traces.enabled=true" \
  --data "config.logs.enabled=true"
```

Logs require Kong Gateway ≥ 3.8 — earlier versions log a warning and skip log export without affecting traces.

Traces and logs are batched into separate internal queues named `signoz:traces` and `signoz:logs` respectively; both queues are flushed on worker shutdown.