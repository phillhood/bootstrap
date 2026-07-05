#!/usr/bin/env bash
set -euo pipefail

# Fresh-machine provisioner for Arch Linux. Installs packages, then clones and
# stows the dotfiles. Safe to re-run.
#
# Usage: ./install.sh
# Env: DOTFILES_REPO=<url>, DOTFILES_BRANCH=<name>

usage() {
  cat <<'EOF'
Usage: install.sh [--help]
  --help       show this help
Env:
  DOTFILES_REPO=<url>     dotfiles repo to clone (default: phillhood/.dotfiles)
  DOTFILES_BRANCH=<name>  branch to clone (default: stow)
EOF
}

case "${1:-}" in
  "") ;;
  -h|--help) usage; exit 0 ;;
  *) printf 'unknown argument: %s\n' "$1" >&2; usage; exit 1 ;;
esac

# Locate self. If running detached (curl | bash) there are no sibling files, so
# clone the repo and re-exec from it. DOTFILES_* propagate via the env.
SOURCE="${BASH_SOURCE[0]:-}"
BOOTSTRAP_DIR=""
if [ -n "$SOURCE" ] && [ -f "$SOURCE" ]; then
  BOOTSTRAP_DIR="$(cd "$(dirname "$SOURCE")" && pwd)"
fi
if [ -z "$BOOTSTRAP_DIR" ] || [ ! -d "$BOOTSTRAP_DIR/lib" ]; then
  if [ -n "${BOOTSTRAP_REEXEC:-}" ]; then
    echo "error: re-exec failed — lib/ not found in the cloned repo" >&2; exit 1
  fi
  export BOOTSTRAP_REEXEC=1
  echo "==> fetching bootstrap repo (running detached)" >&2
  command -v git >/dev/null 2>&1 || sudo pacman -S --needed --noconfirm git
  BOOTSTRAP_DIR="${BOOTSTRAP_REPO_DIR:-$HOME/Dev/phillhood/bootstrap}"
  if [ ! -d "$BOOTSTRAP_DIR/.git" ]; then
    git clone --depth 1 "${BOOTSTRAP_REPO:-https://github.com/phillhood/bootstrap.git}" "$BOOTSTRAP_DIR"
  fi
  exec bash "$BOOTSTRAP_DIR/install.sh"
fi
export BOOTSTRAP_DIR

# shellcheck source=lib/common.sh
. "$BOOTSTRAP_DIR/lib/common.sh"
# shellcheck source=lib/distro.sh
. "$BOOTSTRAP_DIR/lib/distro.sh"
for f in "$BOOTSTRAP_DIR"/steps/*.sh; do
  # shellcheck source=/dev/null
  . "$f"
done

require_not_root
detect_distro
run_step "Packages"       step_packages
run_step "Dotfiles"       step_dotfiles
run_step "Default shell"  step_shell
run_step "tmux plugins"   step_tmux
run_step "Rust + Node"    step_rust_node
run_step "Docker"         step_docker

[ -x "$BOOTSTRAP_DIR/kek/run" ] && "$BOOTSTRAP_DIR/kek/run" || true

info "bootstrap complete"
