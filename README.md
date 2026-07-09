# Hemera

**The constellation observability plane** — the OTel collector every star ships
traces/metrics/logs to, the LGTM backends that store each signal, and the Grafana
that renders them. One substrate star on nas01.

A Forge **substrate star**: its runtime is declared as `kreuzwerker/docker`
resources (`main.tf`), deployed through **Nereus** (OpenTofu) as a standalone root
sharing the Nereus PG state backend — never hand-composed. All images are
**upstream** (no custom build); each service's config is injected via Tofu `upload`
blocks. Health is judged by **Nyx**, so this layer stays dumb (`restart=unless-stopped`).

## The stack

| Service | Image | Role | Reached at (on the docker net) |
| :-- | :-- | :-- | :-- |
| `hemera-otelcol` | otel/opentelemetry-collector-contrib | OTLP ingest → fans each signal | `:4317` gRPC / `:4318` HTTP |
| `hemera-prometheus` | prom/prometheus | metrics store (remote-write receiver) | `:9090` |
| `hemera-loki` | grafana/loki | log store (OTLP-native) | `:3100` |
| `hemera-tempo` | grafana/tempo | trace store | `:3200` (query) / `:4317` (ingest) |
| `hemera-grafana` | grafana/grafana | operator dashboards | `:3000` (via SSO front) |

Image tags are pinned in `variables.tf` (e.g. `otelcol_image`, `prometheus_image`)
and bumped by Renovate fleet-wide — no custom builds live in this repo.

**The `otel_endpoint` target.** Every star's `Settings.otel_endpoint` resolves to
`http://hemera-otelcol:4318` once repointed (the existing-star migration plan — not
here). The collector joins `mnemosyne-net` + `pantheon` so stars reach it east-west.

**Off-fleet OTLP ingest.** The collector also binds `:4317`/`:4318` on the nas01
tailnet IP (`otlp_tailnet_ip`, `main.tf`) for per-host Anvil otelcol agents
forwarding Claude Code usage telemetry — never `0.0.0.0`, tailnet-floor standing
only.

**No host ports** (the constellation invariant): OTLP is east-west; Grafana is
fronted by Caddy/tsidp SSO at deploy — a loopback-only host port
(`grafana_host_port`, default `31093`) plus `auth.proxy` header trust scoped to the
`hemera-net` subnet (`GF_AUTH_PROXY_WHITELIST` in `main.tf`).

## Layout

| Path | Role |
| :-- | :-- |
| `star.toml` | the star manifest (identity, charter, seams) |
| `main.tf` | the LGTM stack as docker resources |
| `backend.tf` | shared Nereus PG state (schema `hemera`) |
| `providers.tf` / `versions.tf` | docker provider config + Tofu/provider version pins |
| `variables.tf` | image pins (renovate-bumped), retention, grafana secret |
| `config/otel-collector.yaml` | receivers → per-signal exporters |
| `config/prometheus.yml` · `loki-config.yaml` · `tempo.yaml` | backend configs |
| `config/grafana/` | datasources + dashboards provisioned-as-code |
| `docs/nyx-telemetry-seam.md` | the F4 query contract Nyx binds to |
| `.forgejo/workflows/admit.yml` | the fail-closed admission gate (below) |

## Deploy

The parent runs the live apply on nas01 (never from a worktree — shared state):

```bash
export PG_CONN_STR="postgres://forge:<pw>@100.93.64.106:5432/tofu?sslmode=disable"
export TF_VAR_docker_host="unix:///var/run/docker.sock"   # when applying on nas01
export TF_VAR_grafana_admin_password="<from bws>"
tofu init -backend-config="conn_str=$PG_CONN_STR"
tofu plan
tofu apply
```

The external nets (`mnemosyne-net`, `pantheon`) must already exist on the daemon.

## CI — the admission gate

`.forgejo/workflows/admit.yml` runs on every PR (`runs-on: nas01`). It is
fail-closed: any step exiting non-zero blocks merge. Sequence:

1. checkout, then install `uv`, `conftest`, `cosign`, `syft`, `oras` (versions
   pinned once in `.forgejo/versions.env`, shared with the signer so cosign can
   never version-drift v2/v3);
2. `oras`-pull + `cosign verify --key cosign.pub` the pinned governance policy
   bundle named in `star.toml`'s `[governance]` block;
3. supply-chain attestation (image cosign verify + syft SBOM) if `star.toml`
   declares an `image.ref` — Hemera has none, so this stays a no-op;
4. build `admission-input.json` via `constellation.gate` (run through
   `uv run --no-project --with constellation` — this repo has no Python project
   env);
5. `conftest test admission-input.json` against the pulled policy.

This repo has no application build/test/lint step of its own — `tofu validate`
and `tofu plan` are the closest analog, run manually before a deploy; there's no
`justfile`/`Makefile` wrapping them.

## Regenerating from template

This repo is Copier-managed (`.copier-answers.yml`, template `tofu-repo-template`).
Run `copier update` to pull template changes as a 3-way merge against local edits.
`AGENTS.md`/`CLAUDE.md`/`.claude/` are furnace-provisioned locally and gitignored
— they are not part of this repo's committed tree.

## Consumers

- **The operator** — Grafana fleet overview (`Constellation` folder), the 3am view.
- **Nyx** — reads the backends directly over `hemera-net` to enrich membership
  standing (see `docs/nyx-telemetry-seam.md`). Liveness stays Pontus's heartbeats;
  Hemera is metric/trace/log enrichment.
