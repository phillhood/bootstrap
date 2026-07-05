#!/usr/bin/env bash
# Distro detection + package-manager dispatch. Sourced after common.sh.
# Arch is the only implemented backend; adding another distro is one case arm here.

# Sets global DISTRO from /etc/os-release $ID. Dies on unsupported distros.
detect_distro() {
  [ -r /etc/os-release ] || die "/etc/os-release not found; cannot detect distro"
  # shellcheck disable=SC1091  # /etc/os-release is data, not a tracked source file
  DISTRO="$(. /etc/os-release && printf '%s' "$ID")"
  case "$DISTRO" in
    arch) : ;;
    *) die "unsupported distro: '$DISTRO' (only arch is implemented)" ;;
  esac
}

# Ensure an AUR helper (yay) exists. Arch-only. Idempotent.
ensure_aur_helper() {
  command -v yay >/dev/null 2>&1 && return 0
  info "installing build prerequisites (base-devel, git)"
  sudo pacman -S --needed --noconfirm base-devel git
  info "installing yay (AUR helper)"
  local tmp; tmp="$(mktemp -d)"
  git clone --depth 1 https://aur.archlinux.org/yay-bin.git "$tmp/yay-bin"
  ( cd "$tmp/yay-bin" && makepkg -si --noconfirm )
  rm -rf "$tmp"
}

# Install packages via the distro's manager. Idempotent (--needed).
pkg_install() {
  [ "$#" -gt 0 ] || return 0
  case "$DISTRO" in
    arch) yay -S --needed --noconfirm "$@" ;;
    *) die "pkg_install: unsupported distro: ${DISTRO:-unset}" ;;
  esac
}
