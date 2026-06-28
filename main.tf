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

  # Private net + the two fleet nets stars dial east-west.
  networks_advanced { name = docker_network.hemera.name }
  dynamic "networks_advanced" {
    for_each = local.ext_nets
    content { name = networks_advanced.value }
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
    "GF_SECURITY_ADMIN_PASSWORD=${var.grafana_admin_password}",
    "GF_USERS_DEFAULT_THEME=dark",
    # Behind SSO at deploy; serve under the eventual reverse-proxy host cleanly.
    "GF_SERVER_ROOT_URL=%(protocol)s://%(domain)s/",
  ]

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

  volumes {
    volume_name    = "hemera_grafana-data"
    container_path = "/var/lib/grafana"
  }

  # hemera-net to reach the datasources; mnemosyne-net so the SSO front can dial it.
  networks_advanced { name = docker_network.hemera.name }
  networks_advanced { name = "mnemosyne-net" }
}
