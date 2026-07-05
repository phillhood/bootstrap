#!/usr/bin/env bash
# Step: enable docker service + add user to the docker group (idempotent).

step_docker() {
  if [ -d /run/systemd/system ]; then
    info "enabling docker.service"
    sudo systemctl enable --now docker.service
  else
    warn "systemd not running; skipping docker.service enable"
  fi
  if ! id -nG "$USER" | tr ' ' '\n' | grep -qx docker; then
    info "adding $USER to docker group (re-login required to take effect)"
    sudo usermod -aG docker "$USER"
  else
    info "$USER already in docker group"
  fi
}
