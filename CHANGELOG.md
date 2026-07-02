# Changelog

## 1.0.0 (unreleased)

First stable release. The plugin's scope is now fixed: enriched traces (delegated to Kong's bundled OpenTelemetry plugin) plus one structured, trace-correlated request log per request. Metrics and runtime-log forwarding are deliberately out of scope — use Kong's native plugins for those.

### Breaking

- `config.logs.instrumentations` (array: `off/all/access/runtime`) is replaced by `config.logs.enabled` (boolean, default `true`).
- Runtime/error log forwarding is removed. Use Kong's bundled `opentelemetry` plugin for that stream.
- `config.exporter.endpoint` accepts `http://`/`https://` URLs only; `grpc://`/`grpcs://` are rejected.

### Added

- Full request attribution on both span and log, built from one `kong.log.serialize()` snapshot: `http.route`, `network.protocol.version`, `user_agent.original`, `kong.request.size`, `kong.response.size`, `kong.latency.gateway_ms`/`upstream_ms`/`total_ms`, `kong.balancer.tries`, `kong.upstream.status`, `kong.service.id`, `kong.route.id`.
- Span status set to `ERROR` with `error.type` on 5xx responses.
- `service.version` (Kong version) resource attribute on the logs pipeline.
- Startup warning when `traces.enabled=true` but the gateway tracer (`tracing_instrumentations`) is off.
- Startup warning when Kong's bundled `opentelemetry` plugin is enabled alongside (double-export).
- Unit test suite (busted) and luacheck lint, both in CI.

### Fixed

- Protobuf log encoding on Kong 3.9+: records are now proto-shaped (AnyValue body, KeyValue attribute list, per-record trace IDs) before hitting `kong.observability.otlp.encode_logs`. Previously every log batch on 3.9 failed with `table expected at field 'body'`; Kong 3.6–3.8 were unaffected (JSON encoder path).

## 0.0.1

Initial release: trace delegation to the bundled OpenTelemetry plugin with root-span enrichment, per-request access-log records (`logs.instrumentations` DSL), optional runtime-log forwarding, LuaRocks packaging.
