# Configuration

The plugin schema is grouped into three clusters:

- **`resource`** — how this Kong identifies itself in SigNoz.
- **`exporter`** — where data ships and how the HTTP transport behaves.
- **`traces`** / **`logs`** — what to capture per signal.

For e.g:

```yaml
config:
    resource:
        service_name: kong
        deployment_environment: dev
    exporter:
        endpoint: https://ingest.us.staging.signoz.cloud:443
        key: TjJpmy7lHzHGpwdAjsx0B4CaDP1PF8s06ucO
    traces:
        enabled: true
        sampling_rate: 1.0
    logs:
        instrumentations: [access, runtime]
```

## `config.resource` — service identity

| Field | Required | Default | Notes |
| --- | --- | --- | --- |
| `resource.service_name` | no | `kong` | Maps to OTel `service.name` resource attribute. |
| `resource.deployment_environment` | no | — | Maps to `deployment.environment` resource attribute. |

`host.name` and `service.instance.id` are populated automatically from Kong's node metadata.

## `config.exporter` — destination and transport

| Field | Required | Default | Notes |
| --- | --- | --- | --- |
| `exporter.endpoint` | yes | — | Base URL of the SigNoz OTLP/HTTP ingestion endpoint. `/v1/traces` and `/v1/logs` are appended internally. |
| `exporter.key` | no | — | Sent as the `signoz-ingestion-key` header. Required for SigNoz Cloud, ignored for self-hosted. Referenceable via [Kong Vault](https://developer.konghq.com/gateway/secrets-management/). |
| `exporter.connect_timeout` | no | `1000` | OTLP-POST connect timeout (ms). |
| `exporter.send_timeout` | no | `5000` | OTLP-POST send timeout (ms). |
| `exporter.read_timeout` | no | `5000` | OTLP-POST read timeout (ms). |

### `exporter.queue` — batching and retry

Records are batched per worker and flushed by a background timer.

| Field | Default | Notes |
| --- | --- | --- |
| `queue.max_batch_size` | `200` | Max records per HTTP POST. |
| `queue.max_entries` | `10000` | Queue capacity per worker. Records past this are dropped and warned. |
| `queue.max_coalescing_delay` | `3` | Max seconds to hold records before flushing a partial batch. |
| `queue.max_retry_time` | `60` | Total seconds the retry loop runs before giving up. |
| `queue.initial_retry_delay` | `0.01` | Seconds before first retry. |
| `queue.max_retry_delay` | `60` | Cap on exponential backoff between retries (seconds). |

## `config.traces` — trace export

| Field | Default | Notes |
| --- | --- | --- |
| `traces.enabled` | `true` | When `true`, delegates trace export to Kong's bundled [OpenTelemetry plugin](https://developer.konghq.com/plugins/opentelemetry/). |
| `traces.sampling_rate` | `1.0` | 0–1 probability. Applied per request before export. |

Kong's gateway-level tracer must be on (`tracing_instrumentations`, `tracing_sampling_rate` in `kong.conf`) for any spans to be created in the first place. See Kong's [tracing reference](https://developer.konghq.com/gateway/tracing/) for valid values, and [Getting started](../README.md#2-enable-kongs-tracer) for the minimum config.

Before each root span is encoded, the plugin enriches it with stable OTel HTTP semconv:

- `http.request.method`, `url.path`, `url.scheme`, `http.response.status_code`
- `client.address`, `server.address`

…and Kong-customer attribution:

- `kong.service.name`, `kong.route.name`
- `kong.consumer.id`, `kong.consumer.username` (when authenticated)

Legacy attributes that Kong's tracer already sets coexist non-destructively.

## `config.logs` — per-request OTLP log records

| Field | Default | Notes |
| --- | --- | --- |
| `logs.instrumentations` | `[off]` | Comma-separated list (curl) or YAML array. Values: `off`, `all`, `access`, `runtime`. |

The DSL mirrors Kong's gateway-level [`tracing_instrumentations`](https://developer.konghq.com/gateway/tracing/) — `[off]` ships nothing, `[all]` ships every supported sub-type, otherwise list sub-types by name.

### `access` — one structured log record per request

Equivalent in audience to Kong's [HTTP Log](https://developer.konghq.com/plugins/http-log/) or [File Log](https://developer.konghq.com/plugins/file-log/) plugin output, but shipped over OTLP and correlated with traces.

Each record:

- **Body**: compact summary, e.g. `"GET /payments 200 28ms"`.
- **Severity**: `INFO` for 2xx/3xx, `WARN` for 4xx, `ERROR` for 5xx.
- **Trace correlation**: `trace_id` / `span_id` populated when a trace is active for the request.
- **Attributes**: descriptive identity only — method, path, scheme, status, route, service, consumer, client IP, last upstream IP.

Excluded by design: latencies and body sizes (those belong on traces or metrics), retry counts, request/response headers (PII + cardinality), querystrings.

### `runtime` — Kong's internal logs

Forwards Kong's own runtime logs (warnings, errors, debug output the gateway writes via `kong.log`) over OTLP. Useful when you want gateway operator logs alongside your application telemetry.

### Encoding

Records batch into an internal queue named `signoz:logs_access` (for `access`) and `signoz:logs` (for `runtime`), then flush via background timer. The wire encoder is selected automatically per Kong version: protobuf when `kong.observability.otlp.encode_logs` is available (Kong 3.9+), OTLP/HTTP-JSON otherwise.

## Plugin scope

Standard Kong semantics — global, per-service, per-route, per-consumer, or any combination. Kong's [plugin precedence rules](https://developer.konghq.com/gateway/entities/plugin/#plugin-precedence) decide which configuration wins when the plugin is enabled at multiple levels.

## Versioning and compatibility

The plugin delegates to `kong.plugins.opentelemetry.*` modules that are not part of Kong's PDK stability contract. Each release is tested against currently-supported Kong minor versions. Upgrading Kong may require upgrading the plugin.
