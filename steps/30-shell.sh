#!/usr/bin/env bash
# Step: set the login shell to zsh (idempotent).

step_shell() {
  local zsh_path current
  zsh_path="$(command -v zsh)" || die "zsh not installed"
  current="$(getent passwd "$(id -un)" | cut -d: -f7)"
  if [ "$current" != "$zsh_path" ]; then
    info "setting default shell to zsh ($zsh_path)"
    sudo chsh -s "$zsh_path" "$(id -un)"
  else
    info "default shell already zsh"
  fi
}
