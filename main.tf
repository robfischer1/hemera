# Hemera — the constellation observability plane (kreuzwerker/docker, via Nereus).
#
# One substrate star running the upstream OTel Collector + LGTM backends + Grafana.
# All images are upstream (no custom build); each service's config is injected with
# `upload` blocks (file content baked into the container at apply — no bind mount,
# no host path on nas01, no image rebuild).
#
# Topology (the no-host-ports invariant holds):
#   - the collector joins mnemosyne-net + pantheon so every star ships OTLP to it
#     east-west at http://hemera-otelcol:4318 (the otel_endpoint target);
#   - the backends + grafana sit on the private hemera-net (internal only);
#   - grafana is fronted by Caddy/tsidp SSO at deploy (the plan's exposure item),
#     not a raw host port.
#
# Health is deliberately NOT asserted here — providers.tf: "Tofu only places
# containers; Nyx judges health." `restart = unless-stopped` covers crash-loops
# while a dependency comes up.

locals {
  # External nets (owned elsewhere — attached by name, never declared here).
  ext_nets = ["mnemosyne-net", "pantheon"]
}

# Private east-west net for collector <-> backends <-> grafana.
resource "docker_network" "hemera" {
  name = "hemera-net"
}

# ---------------------------------------------------------------------------
# OTel Collector — the single OTLP ingest point (4317 gRPC / 4318 HTTP).
# Every star's otel_endpoint resolves here. Fans each signal to its backend.
# ---------------------------------------------------------------------------
resource "docker_image" "otelcol" {
  name         = var.otelcol_image
  keep_locally = true
}

resource "docker_container" "otelcol" {
  name    = "hemera-otelcol"
  image   = docker_image.otelcol.image_id
  restart = "unless-stopped"

  upload {
    content = file("${path.module}/config/otel-collector.yaml")
    file    = "/etc/otelcol-contrib/config.yaml"
  }

  # Aether DB scrape credential — the hemera_monitor role (pg_monitor). Sourced at
  # apply from bws (pantheon: AETHER_MONITOR_PASSWORD); never committed. The
  # postgresql receiver reads it via ${env:AETHER_MONITOR_PASSWORD}.
  env = ["AETHER_MONITOR_PASSWORD=${var.aether_monitor_password}"]

  # Host filesystem (read-only) for the hostmetrics receiver — nas01 disk / IO /
  # memory. root_path=/hostfs in the collector config points here, so an
  # approaching disk-full alerts before it grinds Aether to a halt.
  volumes {
    host_path      = "/"
    container_path = "/hostfs"
    read_only      = true
  }

  # Private net + the two fleet nets stars dial east-west.
  networks_advanced { name = docker_network.hemera.name }
  dynamic "networks_advanced" {
    for_each = local.ext_nets
    content { name = networks_advanced.value }
  }

  # Tailnet-bound OTLP ingest (gRPC + HTTP) for off-fleet emitters — the
  # per-host Anvil otelcol agents forwarding Claude Code usage telemetry
  # (DS-38). Bound to the tailnet IP, never 0.0.0.0; the in-container
  # receiver already listens on 0.0.0.0, so publishing is sufficient.
  ports {
    internal = 4317
    external = 4317
    ip       = var.otlp_tailnet_ip
  }
  ports {
    internal = 4318
    external = 4318
    ip       = var.otlp_tailnet_ip
  }
}

# ---------------------------------------------------------------------------
# Prometheus — metrics store. Remote-write receiver on; the collector pushes.
# ---------------------------------------------------------------------------
resource "docker_image" "prometheus" {
  name         = var.prometheus_image
  keep_locally = true
}

resource "docker_container" "prometheus" {
  name    = "hemera-prometheus"
  image   = docker_image.prometheus.image_id
  restart = "unless-stopped"

  command = [
    "--config.file=/etc/prometheus/prometheus.yml",
    "--storage.tsdb.path=/prometheus",
    "--storage.tsdb.retention.time=${var.metrics_retention}",
    "--web.enable-remote-write-receiver",
    "--web.enable-lifecycle",
  ]

  upload {
    content = file("${path.module}/config/prometheus.yml")
    file    = "/etc/prometheus/prometheus.yml"
  }

  # Aether SPOF alert rules (rule_files in prometheus.yml points here).
  upload {
    content = file("${path.module}/config/prometheus/rules/aether.yml")
    file    = "/etc/prometheus/rules/aether.yml"
  }

  volumes {
    volume_name    = "hemera_prometheus-data"
    container_path = "/prometheus"
  }

  networks_advanced { name = docker_network.hemera.name }
}

# ---------------------------------------------------------------------------
# Loki — log store (single-binary, filesystem). OTLP-native ingest (/otlp).
# ---------------------------------------------------------------------------
resource "docker_image" "loki" {
  name         = var.loki_image
  keep_locally = true
}

resource "docker_container" "loki" {
  name    = "hemera-loki"
  image   = docker_image.loki.image_id
  restart = "unless-stopped"

  command = ["-config.file=/etc/loki/local-config.yaml"]

  upload {
    content = file("${path.module}/config/loki-config.yaml")
    file    = "/etc/loki/local-config.yaml"
  }

  volumes {
    volume_name    = "hemera_loki-data"
    container_path = "/loki"
  }

  networks_advanced { name = docker_network.hemera.name }
}

# ---------------------------------------------------------------------------
# promtail — docker-log collection for the signed-state spine (Braid B3).
# Docker service discovery over the socket (read-only) keeps ONLY the
# ouranos-* containers; lines push to Loki, and the derived REFUSED counter
# is scraped by the collector (config/otel-collector.yaml) and alerted in
# rules/signed-state.yml. Log streaming rides the Docker API — no
# /var/lib/docker/containers mount needed.
# ---------------------------------------------------------------------------
resource "docker_image" "promtail" {
  name         = var.promtail_image
  keep_locally = true
}

resource "docker_container" "promtail" {
  name    = "hemera-promtail"
  image   = docker_image.promtail.image_id
  restart = "unless-stopped"

  command = ["-config.file=/etc/promtail/config.yaml"]

  upload {
    content = file("${path.module}/config/promtail.yaml")
    file    = "/etc/promtail/config.yaml"
  }

  volumes {
    host_path      = "/var/run/docker.sock"
    container_path = "/var/run/docker.sock"
    read_only      = true
  }

  # positions survive restarts — a named volume like its siblings.
  volumes {
    volume_name    = "hemera_promtail-positions"
    container_path = "/positions"
  }

  networks_advanced { name = docker_network.hemera.name }
}

# ---------------------------------------------------------------------------
# Tempo — trace store (local backend). OTLP receiver on 4317/4318.
# ---------------------------------------------------------------------------
resource "docker_image" "tempo" {
  name         = var.tempo_image
  keep_locally = true
}

resource "docker_container" "tempo" {
  name    = "hemera-tempo"
  image   = docker_image.tempo.image_id
  restart = "unless-stopped"

  command = ["-config.file=/etc/tempo.yaml"]

  upload {
    content = file("${path.module}/config/tempo.yaml")
    file    = "/etc/tempo.yaml"
  }

  volumes {
    volume_name    = "hemera_tempo-data"
    container_path = "/var/tempo"
  }

  networks_advanced { name = docker_network.hemera.name }
}

# ---------------------------------------------------------------------------
# Grafana — the operator surface. Datasources + dashboards provisioned-as-code.
# Reached via Caddy/tsidp SSO at deploy (no host port — the invariant).
# ---------------------------------------------------------------------------
resource "docker_image" "grafana" {
  name         = var.grafana_image
  keep_locally = true
}

resource "docker_container" "grafana" {
  name    = "hemera-grafana"
  image   = docker_image.grafana.image_id
  restart = "unless-stopped"

  env = [
    "GF_SECURITY_ADMIN_PASSWORD=${var.grafana_admin_password}", # break-glass local admin
    "GF_USERS_DEFAULT_THEME=dark",
    "GF_SERVER_DOMAIN=${var.grafana_domain}",
    "GF_SERVER_ROOT_URL=https://${var.grafana_domain}/",
    # auth.proxy — trust the X-WEBAUTH-USER header Caddy maps from the tsauth
    # Remote-User shim (same pattern Forgejo uses). Auto-create the user; the
    # single tailnet identity (rob) becomes an Org Admin. The security boundary
    # is the 127.0.0.1 host-port binding + Caddy's forward_auth — Grafana is not
    # on mnemosyne-net, so no other star can reach :3000 to spoof the header.
    "GF_AUTH_PROXY_ENABLED=true",
    "GF_AUTH_PROXY_HEADER_NAME=X-WEBAUTH-USER",
    "GF_AUTH_PROXY_HEADER_PROPERTY=username",
    "GF_AUTH_PROXY_AUTO_SIGN_UP=true",
    "GF_AUTH_PROXY_ENABLE_LOGIN_TOKEN=true",
    # Defense-in-depth: only trust the X-WEBAUTH-USER header from the hemera-net
    # subnet — the host-net Caddy reaches :3000 via the loopback host port, so the
    # docker-proxy source is the hemera-net gateway. Nothing outside this net can
    # spoof the header (Grafana is off mnemosyne-net; the host port is loopback-only).
    "GF_AUTH_PROXY_WHITELIST=192.168.32.0/20",
    "GF_USERS_AUTO_ASSIGN_ORG_ROLE=Admin",
  ]

  # Loopback host port for the host-networked Caddy to reach (no tailnet exposure).
  ports {
    internal = 3000
    external = var.grafana_host_port
    ip       = "127.0.0.1"
  }

  upload {
    content = file("${path.module}/config/grafana/datasources.yaml")
    file    = "/etc/grafana/provisioning/datasources/datasources.yaml"
  }
  upload {
    content = file("${path.module}/config/grafana/dashboards.yaml")
    file    = "/etc/grafana/provisioning/dashboards/dashboards.yaml"
  }
  upload {
    content = file("${path.module}/config/grafana/dashboards/fleet-overview.json")
    file    = "/var/lib/grafana/dashboards/fleet-overview.json"
  }
  upload {
    content = file("${path.module}/config/grafana/dashboards/aether.json")
    file    = "/var/lib/grafana/dashboards/aether.json"
  }
  upload {
    content = file("${path.module}/config/grafana/dashboards/claude-usage.json")
    file    = "/var/lib/grafana/dashboards/claude-usage.json"
  }
  upload {
    content = file("${path.module}/config/grafana/dashboards/forgejo-ci.json")
    file    = "/var/lib/grafana/dashboards/forgejo-ci.json"
  }

  volumes {
    volume_name    = "hemera_grafana-data"
    container_path = "/var/lib/grafana"
  }

  # hemera-net only — reaches the datasources; Caddy reaches it via the loopback
  # host port above, NOT the docker net, so it stays off mnemosyne-net.
  networks_advanced { name = docker_network.hemera.name }
}
