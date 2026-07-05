#!/usr/bin/env bash
# Step: enable docker service + add user to the docker group (idempotent).

step_docker() {
  if [ -d /run/systemd/system ]; then
    info "enabling docker.service"
    sudo systemctl enable --now docker.service
  else
    warn "systemd not running; skipping docker.service enable"
  fi
  if ! id -nG "$(id -un)" | tr ' ' '\n' | grep -qx docker; then
    info "adding $(id -un) to docker group (re-login required to take effect)"
    sudo usermod -aG docker "$(id -un)"
  else
    info "$(id -un) already in docker group"
  fi
}
