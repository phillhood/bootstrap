#!/usr/bin/env bash
# Step: default rust toolchain (stable) + node LTS via fnm.

step_rust_node() {
  info "setting rust stable as the default toolchain"
  rustup default stable
  info "installing node LTS via fnm"
  export PATH="$HOME/.local/share/fnm:$PATH"
  eval "$(fnm env)"
  fnm install --lts
  fnm default lts-latest
}
