# Code Review: Hemera (Constellation Observability Plane)
**Review Date:** 2026-07-09  
**Reviewer:** Gemini  
**Target Repository:** `/home/rob/Forge/Outputs/hemera`  

---

## 1. Executive Summary

Hemera is a substrate star implementation of the constellation's observability plane. It uses OpenTofu (`Nereus` runtime) and the `kreuzwerker/docker` provider to provision an isolated, upstream-only observability stack: OpenTelemetry Collector, Prometheus, Loki, Tempo, and Grafana (LGTM).

### High-Level Posture
* **Architecture:** **Excellent**. High consistency, strict containment (no host ports, east-west internal networking), and clean GitOps provisioning using OpenTofu `upload` blocks.
* **Security:** **Strong**. Fronted by SSO through a loopback-bound host-port connection to Caddy, relying on Grafana's `auth.proxy` with tailnet authentication.
* **Resilience:** **Moderate-High**. While container restarts are delegated to Docker (`restart = unless-stopped`), the lack of container-level memory limits and dynamic Docker networking presents specific operational failure modes (subnet mismatch and OOM-killer vulnerability).

---

## 2. Tech Stack & Architecture

```mermaid
graph TD
    subgraph Fleet Networks (mnemosyne-net / pantheon)
        Stars[Constellation Stars] -->|OTLP/gRPC & HTTP| OTel[hemera-otelcol:4317/4318]
    end

    subgraph Private Network (hemera-net)
        OTel -->|Remote Write| Prom[hemera-prometheus:9090]
        OTel -->|OTLP/HTTP| Loki[hemera-loki:3100]
        OTel -->|OTLP/gRPC| Tempo[hemera-tempo:4317]
        
        Prom -->|Query| Grafana[hemera-grafana:3000]
        Loki -->|Query| Grafana
        Tempo -->|Query| Grafana
    end

    subgraph Host Network (nas01)
        Caddy[Caddy / tsidp SSO] -->|127.0.0.1:31093| Grafana
    end
```

### Stack Components
* **Orchestration:** OpenTofu `pg` backend (schema `hemera`) with `kreuzwerker/docker` provider.
* **Telemetry Collector:** `otel/opentelemetry-collector-contrib:0.114.0`
* **Metrics Store:** `prom/prometheus:v3.0.1` (with `--web.enable-remote-write-receiver` enabled).
* **Log Store:** `grafana/loki:3.3.0` (filesystem-backed).
* **Trace Store:** `grafana/tempo:2.6.1` (filesystem-backed).
* **Visualization:** `grafana/grafana:11.4.0` (SSO via auth proxy headers).

---

## 3. Critical Findings

### 3.1. Dynamic Docker Subnet Mismatch Risk (Critical)
* **Location:** [main.tf](file:///home/rob/Forge/Outputs/hemera/main.tf#L25-L27) & [main.tf](file:///home/rob/Forge/Outputs/hemera/main.tf#L194)
* **Context:** In `main.tf`, Grafana is configured with:
  ```terraform
  "GF_AUTH_PROXY_WHITELIST=192.168.32.0/20"
  ```
  This restricts auth proxy requests (reverse proxied via Caddy through the local loopback host port) to the dynamic `hemera-net` gateway interface.
* **Vulnerability:** The `docker_network.hemera` resource is declared without an explicit subnet block. Docker allocates bridge networks dynamically (typically `172.17.0.0/16`, `172.18.0.0/16`, etc., depending on existing bridges). If Docker allocates any subnet outside the `192.168.32.0/20` CIDR block, Grafana will reject the `X-WEBAUTH-USER` headers sent by the gateway, effectively locking the operator out of Grafana.
* **Fix:** Hardcode the IPAM subnet in the network declaration:
  ```terraform
  resource "docker_network" "hemera" {
    name = "hemera-net"
    ipam_config {
      subnet = "192.168.32.0/20"
    }
  }
  ```

### 3.2. Unbounded Memory Limits & OTel Collector OOM Risk (High)
* **Location:** [main.tf](file:///home/rob/Forge/Outputs/hemera/main.tf#L38-L69) & [otel-collector.yaml](file:///home/rob/Forge/Outputs/hemera/config/otel-collector.yaml#L14-L17)
* **Context:** The OTel Collector uses a `memory_limiter` processor with `limit_percentage = 80`.
* **Vulnerability:** In OTel Collector, percentages are resolved against the container cgroups memory limit. Since the `docker_container.otelcol` resource in `main.tf` has no `memory` limit configured, the collector reads the host's physical RAM (e.g., 64GB on `nas01`) as its boundary. The processor will allow the collector to consume up to ~51GB before dropping spans. Under heavy telemetry spikes, the collector will trigger the host Linux kernel OOM killer or exhaust host resources, impacting other substrate stars.
* **Fix:** Apply a hard memory limit to the container in `main.tf` so cgroups restricts it and the OTel processor can accurately gauge its limits:
  ```terraform
  resource "docker_container" "otelcol" {
    ...
    memory = 2048 # 2GB
  }
  ```

### 3.3. Invalid Per-Star Telemetry Query in Nyx Seam Contract (Medium)
* **Location:** [nyx-telemetry-seam.md](file:///home/rob/Forge/Outputs/hemera/docs/nyx-telemetry-seam.md#L33)
* **Context:** The seam document describes the rubric query for checking recent error rate of a specific `$star` as:
  ```promql
  sum(rate(otelcol_exporter_send_failed_spans_total{service_name="$star"}[5m]))
  ```
* **Vulnerability:** `otelcol_exporter_send_failed_spans_total` is a self-observability metric emitted by the OTel Collector itself (scraped from `:8888`). The collector's internal metrics track global export failures to Tempo; they do **not** carry resource attributes (like `service.name` / `service_name`) of the individual payload stars. As a result, this query will evaluate to `no data` when queried with a specific `service_name`, leading Nyx to report zero errors even when a star is completely failing to export traces.
* **Fix:** Nyx must inspect individual star metrics (e.g. `http_server_duration_milliseconds_count` or client-side instrumentation errors) or check the collector's global health without filtering by star name.

### 3.4. Grafana Dashboard Volume Pollution & GitOps Drift (Medium)
* **Location:** [main.tf](file:///home/rob/Forge/Outputs/hemera/main.tf#L214-L225)
* **Context:** OpenTofu `upload` blocks place dashboards (`fleet-overview.json`, `claude-usage.json`) directly into `/var/lib/grafana/dashboards/`.
* **Vulnerability:** `/var/lib/grafana` is mounted as a persistent volume `hemera_grafana-data` (intended for the SQLite DB, plug-ins, etc.). Placing declarative dashboards on a persistent volume mixes static code with mutable runtime state. If a dashboard is deleted or renamed in Git, the old file will persist in the Docker volume indefinitely, causing GitOps drift.
* **Fix:** Move the declarative dashboards into the read-only container layer (e.g. `/etc/grafana/dashboards/`) which is not mounted to the volume. Recreating the container will then guarantee cleanup of stale dashboards. Update `config/grafana/dashboards.yaml` to point to `/etc/grafana/dashboards`.

---

## 4. Refactoring Recommendations

### 4.1. Remove Default Break-Glass Credentials
* **Location:** [variables.tf](file:///home/rob/Forge/Outputs/hemera/variables.tf#L70-L75)
* **Problem:** `grafana_admin_password` defaults to `"admin"`. If the deployment wrapper fails to override it from the Secrets Manager (BWS), the local break-glass admin console will remain open to default credentials.
* **Recommendation:** Remove the `default = "admin"` block. Force OpenTofu to demand the password at apply time if it is not provided.

### 4.2. Upgrade to Native OTLP for Prometheus Exporter
* **Location:** [otel-collector.yaml](file:///home/rob/Forge/Outputs/hemera/config/otel-collector.yaml#L23-L28)
* **Problem:** The collector utilizes the `prometheusremotewrite` exporter, which is deprecated.
* **Recommendation:** Since Prometheus `v3.0.1` natively supports OTLP ingest, update the OTel Collector pipeline to use the standard `otlphttp` exporter target pointing to the Prometheus OTLP receiver (e.g., `http://hemera-prometheus:9090/api/v1/otlp/v1/metrics`). This removes the need for `--web.enable-remote-write-receiver`.

### 4.3. Implement Cryptographic Digest Pinning
* **Location:** [variables.tf](file:///home/rob/Forge/Outputs/hemera/variables.tf#L11-L40)
* **Problem:** Upstream images are pinned by tag only (e.g. `prom/prometheus:v3.0.1`). Tags are mutable and can be replaced or hijacked on the registry.
* **Recommendation:** Pin the exact container digest hash (`image:tag@sha256:...`) for all third-party dependencies in `variables.tf` to ensure cryptographic integrity.
