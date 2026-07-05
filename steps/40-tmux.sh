#!/usr/bin/env bash
# Step: install the tmux plugin manager (tpm), idempotent.

step_tmux() {
  local tpm="$HOME/.tmux/plugins/tpm"
  if [ ! -d "$tpm" ]; then
    info "cloning tpm to $tpm"
    git clone --depth 1 https://github.com/tmux-plugins/tpm "$tpm"
  else
    info "tpm already installed"
  fi
}
