# The Nyx telemetry seam (Hemera F4)

> The query contract Nyx's membership-standing engine binds to. This is the
> decision the Nyx plan's telemetry-enrichment feature reconciles against.

## Decision — direct backend queries (no wrapper, v1)

Nyx reads fleet telemetry by querying **Hemera's backends directly over
`hemera-net`** — there is no thin Hemera API in v1. The backends already expose
stable, well-documented HTTP query surfaces; wrapping them would add a service to
own, version, and keep live for no contract gain. If a future need appears
(aggregation Nyx shouldn't recompute, auth, rate-limiting), a wrapper is added
then — the seam below is the boundary it would implement.

| Signal | Backend | Surface | Reachable at |
| :--- | :--- | :--- | :--- |
| metrics | Prometheus | HTTP API (`/api/v1/query`, `/api/v1/query_range`) — PromQL | `http://hemera-prometheus:9090` |
| logs | Loki | HTTP API (`/loki/api/v1/query_range`) — LogQL | `http://hemera-loki:3100` |
| traces | Tempo | HTTP API (`/api/search`, `/api/traces/{id}`) | `http://hemera-tempo:3200` |

Nyx joins `hemera-net` (read-only consumer) to reach them. The backends publish no
host ports — this is an east-west, in-cluster contract.

## What Nyx's rubric reads (per star)

The standing engine assigns Green/Yellow/Red. Hemera supplies the *behavioral*
inputs (heartbeat liveness stays Pontus's — Hemera enriches, never double-counts
liveness). Metrics are labelled by the OTel `service.name` each star sets, which
remote-write surfaces as the `service_name` label.

| Rubric input | Query (PromQL, `$star` = the star's `service.name`) |
| :--- | :--- |
| recent error rate | `sum(rate(otelcol_exporter_send_failed_spans_total{service_name="$star"}[5m]))` — or the star's own RED-method error counter once instrumented |
| request latency (p95) | `histogram_quantile(0.95, sum by (le) (rate(http_server_duration_milliseconds_bucket{service_name="$star"}[5m])))` |
| signal liveness | `max(timestamp(up) - up) ` / freshness of the star's last-seen metric — "is telemetry still arriving?" |
| log error volume | LogQL: `sum(count_over_time({service_name="$star"} \|= "error" [5m]))` |

These metric names are the OTel semantic-convention defaults; the exact names
firm up as each star wires its `observability.py`. The **contract** is stable: Nyx
queries Hemera's backends by `service_name` for error/latency/freshness; the
specific PromQL is Nyx's to own.

## Boundary

- Hemera **exposes** the query surfaces; **Nyx decides** standing. No standing
  logic lives here.
- Liveness is Pontus's heartbeats; Hemera is metric/trace/log **enrichment**.
- The seam is direct-query. A wrapper, if ever added, implements exactly this
  table — Nyx's calling contract would not change.
