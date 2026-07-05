#!/usr/bin/env bash
# Shared helpers for the bootstrap provisioner. Sourced by install.sh.

info() { printf '\033[1;34m==>\033[0m %s\n' "$*" >&2; }
warn() { printf '\033[1;33mwarn:\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31merror:\033[0m %s\n' "$*" >&2; exit 1; }

# yay/makepkg refuse to build as root; the whole run must be a normal user + sudo.
require_not_root() {
  [ "$(id -u)" -ne 0 ] || die "run as your normal user (not root); sudo is used where needed"
}

# run_step "<label>" step_function [args...]
run_step() {
  local label="$1"; shift
  info "$label"
  "$@"
}
