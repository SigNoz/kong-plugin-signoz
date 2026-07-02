# Reference

Complete configuration surface and emitted telemetry for `kong-plugin-signoz` v1.x.

## Configuration

```yaml
config:
  resource:
    service_name: kong
    deployment_environment: production
  exporter:
    endpoint: <otlp-http-base-url>     # required
    key: <ingestion-key>
  traces:
    enabled: true
    sampling_rate: 1.0
  logs:
    enabled: true
```

### `config.resource` — service identity

| Field | Required | Default | Notes |
| --- | --- | --- | --- |
| `resource.service_name` | no | `kong` | `service.name` resource attribute. |
| `resource.deployment_environment` | no | — | `deployment.environment` resource attribute. |

`host.name`, `service.instance.id`, and `service.version` (the Kong version) are populated automatically from node metadata.

### `config.exporter` — destination and transport

| Field | Required | Default | Notes |
| --- | --- | --- | --- |
| `exporter.endpoint` | yes | — | Base URL of the SigNoz OTLP/HTTP endpoint; `/v1/traces` and `/v1/logs` are appended internally. **`http://` or `https://` only** — `grpc://`/`grpcs://` are rejected at validation. |

> **`https://` endpoints need a CA trust store.** Kong verifies outbound TLS against `lua_ssl_trusted_certificate`, which many container setups leave unset — every export then fails with `unable to get local issuer certificate` in the queue warnings. Set `lua_ssl_trusted_certificate = system` and `lua_ssl_verify_depth = 3` in `kong.conf` (or `KONG_LUA_SSL_TRUSTED_CERTIFICATE=system`, `KONG_LUA_SSL_VERIFY_DEPTH=3`).
| `exporter.key` | no | — | Sent as the `signoz-ingestion-key` header. Required for SigNoz Cloud, omit for self-hosted. Encrypted; referenceable via [Kong Vault](https://developer.konghq.com/gateway/secrets-management/). |
| `exporter.connect_timeout` | no | `1000` | OTLP POST connect timeout (ms). |
| `exporter.send_timeout` | no | `5000` | OTLP POST send timeout (ms). |
| `exporter.read_timeout` | no | `5000` | OTLP POST read timeout (ms). |

### `config.exporter.queue` — batching and retry

Log records batch per worker and flush on a background timer.

| Field | Default | Notes |
| --- | --- | --- |
| `queue.max_batch_size` | `200` | Max records per HTTP POST. |
| `queue.max_entries` | `10000` | Queue capacity per worker; overflow drops with a warning. |
| `queue.max_coalescing_delay` | `3` | Max seconds to hold a partial batch. |
| `queue.max_retry_time` | `60` | Total seconds the retry loop runs. |
| `queue.initial_retry_delay` | `0.01` | Seconds before first retry. |
| `queue.max_retry_delay` | `60` | Cap on exponential backoff (seconds). |

### `config.traces`

| Field | Default | Notes |
| --- | --- | --- |
| `traces.enabled` | `true` | Delegates trace export to Kong's bundled [OpenTelemetry plugin](https://developer.konghq.com/plugins/opentelemetry/), after enriching the request span (see below). |
| `traces.sampling_rate` | `1.0` | 0–1 probability, applied per request before export. |

Kong's gateway tracer must be on for spans to exist at all (`tracing_instrumentations`, `tracing_sampling_rate` — see Kong's [tracing reference](https://developer.konghq.com/gateway/tracing/)). If it is off while `traces.enabled=true`, the plugin logs a warning at configuration time; request logs are unaffected.

### `config.logs`

| Field | Default | Notes |
| --- | --- | --- |
| `logs.enabled` | `true` | One structured, trace-correlated OTLP log record per request. |

## Emitted telemetry

Both signals are built from the same `kong.log.serialize()` snapshot, so span and log attributes always agree.

### Resource attributes (all signals)

| Attribute | Source |
| --- | --- |
| `service.name` | `resource.service_name` (default `kong`) |
| `deployment.environment` | `resource.deployment_environment` (when set) |
| `host.name` | Kong node hostname |
| `service.instance.id` | Kong node ID |
| `service.version` | Kong version |

### Request span

The plugin decorates the root span Kong's tracer creates. Legacy attributes set by Kong's tracer coexist non-destructively. On 5xx responses the span status is set to `ERROR`.

| Attribute | Notes |
| --- | --- |
| `http.request.method` | |
| `http.route` | Matched route path template(s), comma-joined — low-cardinality |
| `url.path` | Actual request path, query stripped |
| `url.scheme` | |
| `http.response.status_code` | |
| `network.protocol.version` | e.g. `1.1`, `2` |
| `user_agent.original` | |
| `client.address` | Forwarded client IP |
| `server.address` | Last upstream target IP |
| `kong.service.name` / `kong.service.id` | Matched Kong service |
| `kong.route.name` / `kong.route.id` | Matched Kong route |
| `kong.consumer.id` / `kong.consumer.username` | When authenticated |
| `kong.latency.gateway_ms` | Time spent inside Kong |
| `kong.latency.upstream_ms` | Time waiting on the upstream (omitted when no upstream was reached) |
| `kong.latency.total_ms` | Total request duration |
| `kong.request.size` / `kong.response.size` | Total bytes (headers + body — Kong's own accounting) |
| `kong.balancer.tries` | Number of balancer attempts |
| `kong.upstream.status` | Status returned by the upstream (may differ from the client-facing status) |
| `error.type` | Status code as string, 5xx only |

### Request log record

| Field | Value |
| --- | --- |
| Body | `"<METHOD> <path> <status> <duration>ms"` — e.g. `GET /payments 200 28ms` |
| Severity | `INFO` 2xx/3xx · `WARN` 4xx · `ERROR` 5xx |
| `trace_id` / `span_id` | From the request's span, when tracing is active |
| Attributes | The same identity and measurement set as the span (method, path, scheme, status, addresses, `kong.service/route/consumer.*`, latency split, sizes, tries, upstream status) plus `message.type=kong.access` |

**Never captured** (by design): request/response headers, query strings, payloads.

### Encoding and transport

OTLP over HTTP only. Log records encode with Kong's protobuf OTLP encoder where available (`kong.observability.otlp`, Kong 3.9+) and a self-contained OTLP/HTTP-JSON encoder otherwise; SigNoz accepts both. Traces always encode through the bundled plugin's own pipeline.

## Startup warnings

| Warning | Cause | Effect |
| --- | --- | --- |
| `gateway tracer is off` | `traces.enabled=true` with `tracing_instrumentations=off` | No spans exist to export; logs still ship |
| `bundled opentelemetry plugin is also enabled` | Both plugins active for the same traffic | Spans export twice — disable one |

Warnings are emitted once (worker 0) at configuration time.

## Plugin scope

Standard Kong semantics — global, per-service, per-route, per-consumer; [plugin precedence](https://developer.konghq.com/gateway/entities/plugin/#plugin-precedence) decides which config wins. Priority 14 (same as the bundled OpenTelemetry plugin).

## Versioning and compatibility

Kong Gateway **3.6+**, open-source and Enterprise. The plugin delegates to `kong.plugins.opentelemetry.*` modules that sit outside Kong's PDK stability contract; each release is tested against supported Kong minors (3.6–3.9 at the time of writing). Upgrading Kong may require upgrading the plugin — see [CHANGELOG](../CHANGELOG.md).
