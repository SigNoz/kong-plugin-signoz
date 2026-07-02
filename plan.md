# kong-plugin-signoz v1.0.0 — build plan

Rebuild of the plugin to its final shape. Shape derivation, stakeholder analysis, and the full attribution spec live in `~/repo/integrations/research/kong/observability-perspectives.md`; partnership positioning in `~/repo/integrations/research/kong/comparison.md`.

**Identity:** a SigNoz destination integration built on Kong's OpenTelemetry plugin. Two signals: enriched traces (delegated export) + full-context structured request logs (own OTLP pipeline). Nothing general-purpose.

## Final shape

| Decision | Value |
| --- | --- |
| Form | Lua plugin, LuaRocks, Kong **3.6+** (OSS + Enterprise), priority 14 |
| Traces | Delegate export to bundled `opentelemetry` plugin; enrich root span pre-drain |
| Logs | One **full transaction record** per request from `kong.log.serialize()`; trace-correlated; OTLP/HTTP via `kong.tools.queue` |
| Not shipped | Metrics (→ Kong native 3.13+), runtime-log forwarding (→ bundled plugin), header/query/payload capture (privacy) |
| Encoding | Capability-detected: Kong's protobuf encoder when present, self-contained OTLP/HTTP-JSON otherwise; both paths tested |
| Version | 0.0.1 → **1.0.0**, CHANGELOG, CI matrix per Kong minor |

### Config schema (v1.0.0)

```yaml
config:
  exporter:
    endpoint:            # required, base URL; /v1/traces, /v1/logs appended
    key:                 # optional → signoz-ingestion-key header; encrypted, referenceable
    connect_timeout: 1000
    send_timeout: 5000
    read_timeout: 5000
    queue: { ... }       # unchanged defaults
  resource:
    service_name: kong
    deployment_environment:   # optional
  traces:
    enabled: true
    sampling_rate: 1.0
  logs:
    enabled: true        # boolean — REPLACES instrumentations array; default ON
```

Removed from 0.0.1: `logs.instrumentations` array (`off/all/access/runtime`) and the entire runtime-forwarding path.

### Attribution spec (implementation target)

**Resource (all signals):** `service.name`, `deployment.environment`, `host.name`, `service.instance.id`, `service.version` (Kong version).

**Root span — add to existing set:**

| Attribute | Source |
| --- | --- |
| `http.route` (matched route pattern, low-cardinality) | `kong.router.get_route().paths` |
| `network.protocol.version` | `ngx.req.http_version()` |
| `user_agent.original` | request header via serialize |
| `http.request.body.size` / `http.response.body.size` | `serialize().request.size` / `.response.size` |
| `kong.latency.gateway_ms` / `kong.latency.upstream_ms` / `kong.latency.total_ms` | `serialize().latencies.kong` / `.proxy` / `.request` |
| `kong.balancer.tries` | `#serialize().tries` |
| `kong.upstream.status` (when ≠ client status) | serialize |
| span status → ERROR + `error.type` on 5xx | derived |

(Existing kept: `http.request.method`, `url.path`, `url.scheme`, `http.response.status_code`, `client.address`, `server.address`, `kong.service.name/.id`, `kong.route.name/.id`, `kong.consumer.id/.username`.)

**Log record — identity set (existing) + measurements:** `kong.latency.gateway_ms/upstream_ms/total_ms`, `http.request.body.size`, `http.response.body.size`, `kong.balancer.tries`, `kong.upstream.status`. Body/severity/trace-correlation unchanged.

## Work breakdown

- **M1 — Schema v1.0.0.** `schema.lua`: `logs = { enabled boolean, default true }`; drop `instrumentations`. Update `spec/signoz/01-schema_spec.lua`.
- **M2 — Strip runtime path.** `handler.lua` (`configure()` runtime mapping, `log_subtype_enabled`, runtime warn), `conf_builder.lua` (`runtime_logs_enabled`, logs-endpoint wiring), `kong_compat.lua` (`set_logs_endpoint`).
- **M3 — Enrichment expansion.** `traces/init.lua`: new span attributes + span error status. `logs/init.lua`: measurement attributes on the record. Shared attribute builder so span and log stay consistent.
- **M4 — Guards.**
  - Tracer-off: in `configure()`/`init_worker`, warn when `traces.enabled` and `kong.configuration.tracing_instrumentations == "off"`.
  - Double-enable: warn when the bundled `opentelemetry` plugin is also active (investigate detection: `configure()` sees only own configs — likely via `kong.db.plugins` lookup on traditional / declarative config scan on DB-less; if unreliable, ship as documented caution instead).
- **M5 — Encoder + transport hardening.** Verify JSON path byte-for-byte against protobuf path on 3.9; confirm absence of `kong.observability.otlp` never errors; queue names unchanged.
- **M6 — Tests + CI.** Busted specs (schema, conf_builder, record builder, attribute mapping). Integration harness: docker-compose matrix **3.6.1 / 3.7.1 / 3.8.0 / 3.9.x** → assert spans + logs land (mock OTLP sink or SigNoz staging). GitHub Actions matrix on PR.
- **M7 — Docs.** README + `docs/reference.md` rewritten to v1.0.0 schema with full attribute tables; Hub-format page (Overview → How it works → Config → Compatibility → Changelog); CHANGELOG.md.
- **M8 — Demo environment + media capture.** See below.
- **M9 — Release.** rockspec 1.0.0, `luarocks upload`, GitHub release + tag, update the partnership doc with final asset embeds.

## M8 — Demo & media plan (screenshots / videos from SigNoz)

**Setup** (extends `docs/examples/`): Kong 3.9 DB-less + plugin, upstreams that make the views look real — httpbin-style endpoints with variable delay (`/delay/*`) and status mix (`/status/200|404|500`); 2–3 services/routes with names that read well (`payments`, `orders`, `auth`); key-auth consumers (`acme-mobile`, `acme-web`) so consumer attribution shows; a traffic generator loop with weighted endpoints (mostly 200s, some 4xx/5xx, occasional slow upstream) against SigNoz Cloud staging.

**Asset list** (destination in parentheses):

| # | Asset | Shows |
| --- | --- | --- |
| 1 | Screenshot — Services view | `kong` as a service: RPS, p99, error rate (listing, comparison doc, signoz.io docs) |
| 2 | Screenshot — Trace detail, attributes panel open | enriched span: `kong.latency.*` split, `kong.service.name`, `kong.consumer.username` (listing, comparison doc) |
| 3 | Screenshot — Logs Explorer | colored severity lines, `GET /payments 200 28ms` bodies (listing, docs) |
| 4 | GIF/short video — log → trace click-through | the correlation differentiator, in motion (comparison doc, README, outreach) |
| 5 | Screenshot — Kong dashboard | gateway-vs-upstream latency panel, top routes, top consumers, error rate (docs, outreach) |
| 6 | Video 60–90 s — zero-to-observability | `luarocks install` → enable plugin → traffic → data in SigNoz (listing, outreach, README) |
| 7 | Screenshot — alert rule | alert on `kong.latency.gateway_ms` threshold (docs) |

Capture after M3 lands (assets must show the *new* attribute set — capturing before enrichment would show the thin 0.0.1 spans).

## Out of scope for v1.0.0

Metrics of any kind · runtime-log forwarding · header/query/payload capture (opt-in later) · `custom_attributes_by_lua` · Konnect certification track · DD→OTel metric mapping (dashboard/collector work, other repos).

## Open items

- Double-enable detection mechanism (M4) — code vs docs-only.
- `http.route` source: route `paths[]` may hold regex/multiple paths — pick first path or join; verify cardinality behavior.
- Span error status: confirm Kong span table honors a `status` field through the bundled encoder on 3.6–3.9.
- Mutual-customer reference disclosure (partnership, not code).
