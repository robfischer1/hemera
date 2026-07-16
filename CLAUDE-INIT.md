Codebase orientation for AI sessions. Posture and governance live in AGENTS.md
(furnace-compiled); this file is the repo-specific map, read on demand.

## Overview

Hemera is a Forge **substrate star**: the constellation's observability plane.
It is not an application with source code — it is an OpenTofu (Terraform-fork)
root module that places five upstream Docker containers on the nas01 daemon: an
OTel Collector (single OTLP ingest point), Prometheus (metrics), Loki (logs),
Tempo (traces), and Grafana (dashboards). No custom images, no build step — every
`docker_image` resource in `main.tf` pulls an upstream tag pinned in `variables.tf`.

Role in the fleet: every other star's `Settings.otel_endpoint` points at
`http://hemera-otelcol:4318`. Hemera fans each signal to its backend and exposes
query surfaces; it asserts no health/standing logic itself (`providers.tf`: "Tofu
only places containers; Nyx judges health"). Nyx queries Hemera's backends
directly over `hemera-net` — see `docs/nyx-telemetry-seam.md` for the exact
PromQL/LogQL contract Nyx's membership-standing engine binds to.

## Architecture / module map

This is IaC, not application code — there is no `src/`. The "modules" are Tofu
resource blocks in `main.tf`, one per service, each following the same shape:
`docker_image` (pull, `keep_locally = true`) → `docker_container` (config via
`upload` blocks baking file content into the container at apply — no bind mounts,
no host paths, no rebuild) → `networks_advanced`.

| Path | Responsibility |
| :-- | :-- |
| `star.toml` | Star manifest: identity (`name`, `cluster`), charter, interface (`sync = ["otlp"]`), observability (`exports = ["metrics"]`), and the `[governance]` policy-bundle pin (tag + digest) the admission gate verifies |
| `main.tf` | All five `docker_container` resources + the private `hemera-net` docker network + the `ext_nets` local (`mnemosyne-net`, `pantheon`) attached by name, never declared |
| `backend.tf` | Tofu `pg` backend, `schema_name = "hemera"` — shared fleet Postgres state DB, distinct schema per star |
| `providers.tf` | `docker` provider, `host = var.docker_host` |
| `variables.tf` | Every tunable: image tags (`otelcol_image`, `prometheus_image`, `loki_image`, `tempo_image`, `grafana_image`), `metrics_retention` (730d), `otlp_tailnet_ip`, `grafana_admin_password` (sensitive), `grafana_domain`, `grafana_host_port` |
| `versions.tf` | `required_version >= 1.8.0`, `kreuzwerker/docker ~> 3.0` |
| `config/otel-collector.yaml` | Collector pipelines: `otlp` receiver (4317/4318) → `memory_limiter`+`batch` → per-signal exporters (`prometheusremotewrite`, `otlphttp/loki`, `otlp/tempo`); own telemetry on `:8888` |
| `config/prometheus.yml`, `loki-config.yaml`, `tempo.yaml` | Backend-native configs, uploaded verbatim into each container |
| `config/grafana/datasources.yaml`, `dashboards.yaml` | Grafana provisioning-as-code |
| `config/grafana/dashboards/*.json` | `fleet-overview.json`, `claude-usage.json` — dashboard JSON baked in at apply |
| `docs/nyx-telemetry-seam.md` | The Nyx query contract (F4): which backend, which HTTP surface, which query language, per signal — the seam a future Hemera wrapper (if ever built) would implement unchanged |
| `.forgejo/workflows/admit.yml` | PR admission gate (see below) |
| `.forgejo/versions.env` | Single source of truth for CI tool versions (`COSIGN_VERSION`, `CONFTEST_VERSION`, `SYFT_VERSION`, `ORAS_VERSION`) |
| `cosign.pub` | Fleet cosign public key, used to verify the governance policy bundle and any signed image |
| `.copier-answers.yml` | Copier template lineage (`tofu-repo-template`) + the answers this repo was generated from |
| `.furnace/pin.toml` | `kit = "code-repo-sdd"`, `provider = "claude"` — furnace's pour metadata for this repo |
| `.specify/` | Spec-Kit scaffold (workflows, templates, `memory/constitution.md`) for AI-driven feature work in this repo |

## Entry points

There is no CLI, no MCP server, no library API here. The two operational entry
points are:

- **`main.tf`** — the Tofu apply is the deployment entry point (`tofu plan` /
  `tofu apply`, run from nas01 against the shared PG backend — never from an
  agent worktree, per `star.toml`'s `entrypoint = "main.tf"`).
- **`.forgejo/workflows/admit.yml`** — the CI entry point, triggered on
  `pull_request`, `runs-on: nas01`.

## Build / Test / Run

No build. No test suite. No local "run" beyond `tofu plan`/`tofu apply` against
the real nas01 Docker daemon and the shared fleet PG state — there is nothing to
execute in a worktree; deploys are single-apply against shared state, done by the
parent context only. Secrets come from **Calypso** (Infisical) via the nas01
machine identity — both TF_VARs below are **mandatory**; an apply without
`TF_VAR_aether_monitor_password` recreates `hemera-otelcol` with an empty
postgresql-receiver password and the collector crashloops on config validation.

```bash
# Deploy (nas01 only, from ~/hemera — never from a worktree; state is shared fleet-wide)
# one-time: init the pg backend (conn_str never committed)
tofu init -backend-config="conn_str=$PG_CONN_STR"

# every plan/apply — machine-identity login, then run with both secrets mapped
set -a; . ~/.config/infisical/nas01.env; set +a
export INFISICAL_TOKEN="$(infisical login --method=universal-auth \
  --client-id="$INFISICAL_UNIVERSAL_AUTH_CLIENT_ID" \
  --client-secret="$INFISICAL_UNIVERSAL_AUTH_CLIENT_SECRET" \
  --domain="$INFISICAL_API_URL" --silent --plain)"
infisical run --projectId "$INFISICAL_WORKSPACE_ID" --env prod --recursive --path / --silent -- \
  bash -c 'export TF_VAR_aether_monitor_password="$AETHER_MONITOR_PASSWORD" \
                  TF_VAR_grafana_admin_password="$HEMERA_GRAFANA_ADMIN_PASSWORD" \
                  TF_VAR_docker_host="unix:///var/run/docker.sock"; \
           tofu apply'
```

Calypso prod holds `AETHER_MONITOR_PASSWORD` under `/misc` and
`HEMERA_GRAFANA_ADMIN_PASSWORD` under `/hemera` (hence `--recursive --path /`);
on nas01 `tofu` lives at `~/.local/bin/tofu`, off the non-interactive PATH.

CI (`admit.yml`) runs on every PR: installs `uv`/`conftest`/`cosign`/`syft`/`oras`,
pulls+verifies the pinned governance bundle from `star.toml`'s `[governance]`
block via `cosign verify --key cosign.pub`, builds `admission-input.json` via
`uv run --no-project --with constellation python -m constellation.gate`, then
`conftest test admission-input.json -p policy`. There is no Python project env in
this repo (`--no-project` is deliberate) — do not add one for tooling that can run
via `uv run --no-project`.

## Conventions and gotchas

- **This is IaC, not an app.** Don't look for source files, tests, or a package
  manifest — `pyproject.toml`/`package.json` don't exist here and shouldn't.
- **Upstream images only.** Never add a `docker build`/`Dockerfile` here; the
  charter is "all images are upstream." Version bumps go through `variables.tf`
  defaults (Renovate-managed fleet-wide).
- **Config via `upload` blocks, not volumes.** Editing collector/backend behavior
  means editing the YAML under `config/` — the file content is baked into the
  container at `tofu apply`, not bind-mounted. A running container won't pick up
  a `config/` edit without a re-apply.
- **No health assertions in Tofu.** `providers.tf` and `main.tf` both call this
  out explicitly: Tofu places containers, `restart = unless-stopped` covers
  crash loops, and Nyx (a separate star) is the health judge. Don't add
  Terraform health-check logic here — it's an intentional non-goal.
- **No host ports except two deliberate exceptions.** (1) The OTel Collector
  binds `4317`/`4318` on the nas01 **tailnet IP** (`var.otlp_tailnet_ip`), never
  `0.0.0.0` — for off-fleet emitters (per-host Anvil otelcol agents). (2) Grafana
  binds `3000` on `127.0.0.1` only, for the host-net Caddy to reverse-proxy. Every
  other container is `hemera-net`-only. If you're adding a new port, ask why it
  isn't east-west first.
- **Grafana auth is header-trust, not a login form.** `GF_AUTH_PROXY_*` env vars
  trust `X-WEBAUTH-USER` from Caddy's tsauth Remote-User shim, whitelisted to the
  `hemera-net` subnet (`192.168.32.0/20`) — Grafana itself is deliberately off
  `mnemosyne-net` so nothing else on the fleet can spoof the header.
  `grafana_admin_password` is a break-glass local-admin fallback only; the real
  value comes from Calypso at apply (`HEMERA_GRAFANA_ADMIN_PASSWORD` →
  `TF_VAR_grafana_admin_password`), never committed.
- **State is shared, not per-repo.** `backend.tf` points at the fleet PG backend
  with `schema_name = "hemera"` — this is one schema in a shared `tofu` database
  on nas01, not an isolated backend. Never run `tofu apply` from an ephemeral
  worktree; it would race the parent's state.
- **`AGENTS.md`/`CLAUDE.md`/`.claude/` are gitignored.** They're
  furnace-provisioned locally at pour time and are not part of the committed
  tree — don't expect to find them in a fresh clone or a CI checkout.
- **`renovate.json` is not in this repo.** `variables.tf` comments reference
  Renovate bumping image tags; that config lives fleet-wide, not per-star — don't
  go looking for it here.
- **Retention is deliberately long.** `metrics_retention` defaults to `730d`
  (2 years) — a 2026-07-02 measurement found 14d of full-fleet metrics costs
  ~5.3MiB against 340G free, so the storage-footprint concern that motivated a
  shorter window no longer holds (see the comment above `variable
  "metrics_retention"` in `variables.tf`).

## Related repos

- **rob/infra** — the constellation IaC home (platform + services deploy lanes);
  Hemera shares its PG state backend (the `tofu` DB) as a standalone root but is
  not in the services catalog — it deploys manually, never generated into it.
- **constellation** (`forgejo.notusmi.com/rob/constellation.git`) — supplies the
  `StarManifest` schema `star.toml` conforms to and the `constellation.gate` /
  `constellation.gate` policy-input builder the admission CI step runs.
- **furnace** — owns the `oci://forgejo.notusmi.com/furnace/policy` governance
  bundle this repo's `[governance]` block pins, and pours `.furnace/pin.toml` +
  the gitignored `AGENTS.md`/`CLAUDE.md`.
- **Nyx** — the sole documented consumer of Hemera's query surfaces (see
  `docs/nyx-telemetry-seam.md`); reads Prometheus/Loki/Tempo directly over
  `hemera-net`, never through a Hemera-owned API.
- **tofu-repo-template** (Copier source, `.copier-answers.yml`) — the template
  this repo was generated from; `copier update` pulls template changes forward.
