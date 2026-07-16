# Feature Specification: The signed-state ops surface (Golden Braid B3)

**Status**: Draft | **Input**: The Golden Braid master-plan §B3 (Head)

## User Scenarios & Testing

### User Story 1 - The 3am REFUSED reaches an operator (Priority: P1)
A die refusal anywhere in the standing consumers (the ouranos refreshers)
raises a Prometheus alert and is queryable in Loki — the fail-closed design's
deliberate signal stops dying in docker logs.

**Acceptance**: a REFUSED log line increments a counter within one scrape
interval; the alert fires on any increase; the raw lines answer a Loki query.

### User Story 2 - The spine has one pane of glass (Priority: P1)
A "Signed State" Grafana dashboard shows refresher outcomes (laid/noop/
REFUSED), the refusal counter, and PDP request rate + latency.

### User Story 3 - Hemera joins the roster (Priority: P2)
Hemera publishes the blessed `output "star"` so the fleet projection carries
it — closing its roster absence, and (by being a fleet change) triggering the
first project_fleet-integrated fleet-die publish (the D9 live proof).

## Requirements
- **FR-001**: container-log collection for `ouranos-*` (docker service
  discovery — survives container recreates), pushed to Loki with a `container`
  label.
- **FR-002**: a `refresher_refused_total`-class counter derived from REFUSED
  lines; a Prometheus alert on any increase (the aether.yml precedent —
  delivery/contact-points remain the standing follow-up).
- **FR-003**: PDP metrics scraped (`ouranos-opa:8181/metrics`) via the
  collector (network-correct: the collector already rides pantheon).
- **FR-004**: the signed-state dashboard provisioned like its siblings.
- **FR-005**: `outputs.tf` with the blessed star shape (`verb_prefix: null`,
  extras carry the backend addresses — the Pontus non-MCP precedent).
- **FR-006**: zero new credentials; docker.sock mounted read-only for
  discovery only.

## Success Criteria
- **SC-001**: refresher log lines queryable in Loki (live).
- **SC-002**: a synthetic/observed REFUSED increments the counter; the alert
  rule loads (rule visible in Prometheus /rules).
- **SC-003**: OPA metrics present in Prometheus (live).
- **SC-004**: the next fleet projection carries `hemera` in stars{} AND
  publishes the fleet die from inside project_fleet (D9 SC-004 closed).

## Assumptions
- die_lag is NOT emitted here — B4 reads `data.die_standing` directly (the
  poll variant the Braid plan allowed), so the B3→B4 edge dissolves.
- Deny-rate metrics wait on OPA decision logging (the Braid's surfaced open;
  a D3-spine config drill) — latency/request-rate land now.
