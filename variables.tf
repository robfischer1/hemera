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
# Retention — bounds the storage footprint on nas01 (the plan's open risk).
# ---------------------------------------------------------------------------
variable "metrics_retention" {
  type        = string
  description = "Prometheus TSDB retention window."
  default     = "15d"
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
