---
title: "The signed-state ops surface (Golden Braid B3)"
status: ready
---
# B3 — Design Plan

> Binding: decided or [OPEN].

**Summary.** Four additive pieces on the live stack: (1) `hemera-promtail`
(docker_sd over the socket ro, keep `ouranos-.*`, label by container name,
metrics stage derives `promtail_custom_refresher_refused_total` from REFUSED
lines, pushes Loki native); (2) the collector gains a `prometheus` receiver
scraping `ouranos-opa:8181` + `hemera-promtail:9080` into the existing
metrics pipeline (the collector rides pantheon — prometheus itself cannot);
(3) `rules/signed-state.yml` alert on counter increase + the provisioned
`signed-state.json` dashboard (uids hemera-prometheus/hemera-loki);
(4) `outputs.tf` blessed star shape → roster. Apply from nas01 `~/hemera`
(pg schema `hemera`, conn cached). RR verified: main.tf upload/network
pattern L38-88; datasource uids; rules dir precedent (aether.yml);
`local.ext_nets` carries pantheon.

| Decision | Resolution | Prov |
| :-- | :-- | :-- |
| Log collector | promtail docker_sd (name-stable across recreates) | Claude · filelog-by-container-id rejected (id churns) |
| Refusal metric | promtail metrics stage (no new exporter service) | Claude |
| OPA scrape home | the collector's prometheus receiver | Claude (network-correct) |
| die_lag | dropped from B3 — B4 polls die_standing directly | Default (plan-sanctioned variant) |
