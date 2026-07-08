variable "docker_host" {
  type        = string
  description = "Docker daemon endpoint Tofu provisions against (the nas01 host)."
  default     = "ssh://rob@nas01"
}

# ---------------------------------------------------------------------------
# Image pins — upstream only (no custom build). Renovate bumps these (see
# renovate.json); each is a single image:tag so the digest is reproducible.
# ---------------------------------------------------------------------------
variable "otelcol_image" {
  type        = string
  description = "OpenTelemetry Collector (contrib distro — has the loki/prometheusremotewrite exporters)."
  # NB: 0.116.0 ships a broken image (core + contrib both fail `exec /otelcol*`).
  default = "otel/opentelemetry-collector-contrib:0.114.0"
}

variable "prometheus_image" {
  type        = string
  description = "Prometheus — metrics store + remote-write receiver."
  default     = "prom/prometheus:v3.0.1"
}

variable "loki_image" {
  type        = string
  description = "Loki — log store (single-binary, filesystem)."
  default     = "grafana/loki:3.3.0"
}

variable "tempo_image" {
  type        = string
  description = "Tempo — trace store (local backend)."
  default     = "grafana/tempo:2.6.1"
}

variable "grafana_image" {
  type        = string
  description = "Grafana — the operator dashboard surface."
  default     = "grafana/grafana:11.4.0"
}

# ---------------------------------------------------------------------------
# Retention — long window per the usage-telemetry charter (DS-38: rate-limit
# windows + context% + session cost OVER TIME). The original 15d bound guarded
# the nas01 storage footprint; measured 2026-07-02 the risk is moot: 5.3MiB of
# TSDB for 14d of full-fleet volume against 340G free on /srv (~140MiB/yr).
# ---------------------------------------------------------------------------
variable "metrics_retention" {
  type        = string
  description = "Prometheus TSDB retention window."
  default     = "730d"
}

# ---------------------------------------------------------------------------
# OTLP ingest for off-fleet emitters — the tailnet-bound door per-host Anvil
# otelcol agents ship to (Claude Code usage telemetry, DS-38). Tailnet-floor
# standing, same as hades 8101 / corpus PG 5432: only tailnet members reach
# it. East-west fleet traffic keeps the docker-net endpoint (hemera-otelcol).
# ---------------------------------------------------------------------------
variable "otlp_tailnet_ip" {
  type        = string
  description = "nas01 tailnet IP the OTLP host ports bind to (never 0.0.0.0)."
  default     = "100.93.64.106"
}

# ---------------------------------------------------------------------------
# Grafana admin password. Greenfield default; at deploy, override via
# TF_VAR_grafana_admin_password sourced from bws (pantheon project).
# ---------------------------------------------------------------------------
variable "grafana_admin_password" {
  type        = string
  description = "Grafana admin password (break-glass local admin). Override at apply from bws; never commit a real value."
  sensitive   = true
  default     = "admin"
}

# ---------------------------------------------------------------------------
# Aether DB scrape credential — the hemera_monitor role (pg_monitor) the OTel
# postgresql receiver authenticates as. Override at apply from bws (pantheon:
# AETHER_MONITOR_PASSWORD); never commit a real value. Empty default => the
# receiver fails auth (safe: no plaintext fallback).
# ---------------------------------------------------------------------------
variable "aether_monitor_password" {
  type        = string
  description = "Password for the hemera_monitor role on Aether (postgres-postgres-1), read by the collector's postgresql receiver."
  sensitive   = true
  default     = ""
}

# ---------------------------------------------------------------------------
# Grafana SSO front — fronted by Caddy (host-net) on a loopback host port, with
# the tsauth Remote-User shim mapped to Grafana's auth.proxy X-WEBAUTH-USER.
# ---------------------------------------------------------------------------
variable "grafana_domain" {
  type        = string
  description = "External FQDN Caddy serves Grafana on (ACME cert auto-provisioned)."
  default     = "grafana.notusmi.com"
}

variable "grafana_host_port" {
  type        = number
  description = "Loopback host port (127.0.0.1) Caddy reverse-proxies to. tantalus=31091, charon=31092."
  default     = 31093
}
