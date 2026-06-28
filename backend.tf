# State lives in the shared Nereus PG backend (the `tofu` DB on nas01 — the
# protected boundary per Constellation Deployment — Canonical). Hemera gets its
# own schema so its state is distinct from the fleet root, one engine, one DB.
#
# conn_str is supplied at init (never committed):
#   tofu init -backend-config="conn_str=$PG_CONN_STR"
# (PG_CONN_STR = postgres://forge:<pw>@100.93.64.106:5432/tofu?sslmode=disable)
terraform {
  backend "pg" {
    schema_name = "hemera"
  }
}
