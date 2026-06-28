# The runtime is placed on the nas01 Docker daemon. Tofu only *places* containers;
# Nyx judges health, so this layer stays deliberately dumb.
provider "docker" {
  host = var.docker_host
}
