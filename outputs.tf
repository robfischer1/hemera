# The blessed star output (Smaller Hammers roster shape) — hephaestus's
# pg_state reader turns this into the fleet-contract stars{} row, which is
# how hemera joins the roster (its absence was the Braid B3 drift item).
# Non-MCP star: verb_prefix null; the backend addresses ride `extras`
# (the Pontus registry_addr precedent).
output "star" {
  value = {
    name        = "hemera"
    verb_prefix = null
    address     = "hemera-otelcol:4318"
    topics      = []
    db          = "none"
    extras = {
      grafana_addr    = "hemera-grafana:3000"
      loki_addr       = "hemera-loki:3100"
      prometheus_addr = "hemera-prometheus:9090"
      tempo_addr      = "hemera-tempo:3200"
    }
  }
}
