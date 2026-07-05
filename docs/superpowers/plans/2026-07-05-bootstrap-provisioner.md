# Bootstrap Provisioner Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build `phillhood/bootstrap` — an idempotent Bash provisioner that takes a bare Arch machine to fully configured: install packages, then clone + `make install` the dotfiles.

**Architecture:** A thin `install.sh` orchestrator sources a small `lib/` (logging + distro/package dispatch) and numbered `steps/*.sh` (one provisioning concern each), driven by package lists in `packages/*.txt`. Arch is the only implemented backend, behind a single `case` in `lib/distro.sh`. One-way dependency: bootstrap clones + stows the dotfiles; the dotfiles repo never references bootstrap.

**Tech Stack:** Bash 5, GNU coreutils, git, sudo, pacman/yay (Arch), GNU Make (to call the dotfiles' `make install`).

## Global Constraints

- Repo: `~/Dev/phillhood/bootstrap`. Implement on branch **`build-bootstrap`** (off `main`, which holds the spec commit); merge to `main` when complete. Never commit implementation directly to `main`.
- Commit messages: simple, lowercase, no `Co-Authored-By` / "Generated with Claude Code" trailer.
- Every script starts with `#!/usr/bin/env bash`. `install.sh` uses `set -euo pipefail`. `lib/` and `steps/` files are **sourced** (define functions; no top-level side effects beyond function defs).
- **SAFETY — do NOT run the provisioning steps against this machine.** `step_packages/step_dotfiles/step_shell/step_tmux/step_rust_node/step_docker` and a full `install.sh` run mutate the system and are meant for a *fresh* machine. Verify by `bash -n`, `shellcheck` (if installed), sourcing + `declare -F` (function exists), and pure-logic checks only. `install.sh --help` is safe (exits before any step). Real end-to-end is deferred to a fresh Arch container.
- Package groups (verbatim): core = `zsh stow`; cli = `starship atuin fnm eza bat ripgrep fzf zoxide direnv jq uv rustup go tmux neovim fastfetch`; docker = `docker docker-compose docker-buildx`; k8s = `kubectl kubectx k9s helm kubeseal argocd`. Package counts: base (core+cli+docker) = **21**; with k8s = **27**.
- k8s installs only when `WITH_K8S=1` (set by `--k8s` or env).
- Dotfiles clone defaults: `DOTFILES_REPO=https://github.com/phillhood/.dotfiles.git`, `DOTFILES_BRANCH=main`, both env-overridable.
- `shellcheck` verification is conditional: if `shellcheck` is installed it must be clean (or carry an inline `# shellcheck disable=` with reason); if not installed, note that and rely on `bash -n`.

---

### Task 1: Shared library (`lib/`) + `.gitignore`

**Files:**
- Create: `lib/common.sh`, `lib/distro.sh`, `.gitignore`

**Interfaces:**
- Produces (consumed by all later tasks):
  - `info MSG`, `warn MSG`, `die MSG` (die exits 1) — logging to stderr.
  - `require_not_root` — dies if EUID 0.
  - `run_step LABEL FN [ARGS...]` — prints banner, runs `FN`.
  - `detect_distro` — sets global `DISTRO` from `/etc/os-release` `$ID`; dies on non-arch.
  - `ensure_aur_helper` — installs `yay` if absent (Arch).
  - `pkg_install PKG...` — installs via yay `--needed --noconfirm` (Arch).

- [ ] **Step 1: Create `lib/common.sh`**

```bash
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
```

- [ ] **Step 2: Create `lib/distro.sh`**

```bash
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
```

- [ ] **Step 3: Create `.gitignore`**

```gitignore
# superpowers SDD scratch
.superpowers/
```

- [ ] **Step 4: Verify syntax + behaviour (no system mutation)**

Run:
```bash
cd ~/Dev/phillhood/bootstrap
bash -n lib/common.sh && bash -n lib/distro.sh && echo "syntax ok"
command -v shellcheck >/dev/null && shellcheck lib/common.sh lib/distro.sh && echo "shellcheck clean" || echo "shellcheck not installed (bash -n only)"
# Behaviour: source, stub yay, check dispatch + detect (this machine is arch)
bash -c '
  set -euo pipefail
  source lib/common.sh; source lib/distro.sh
  yay() { echo "yay $*"; }          # stub — do NOT hit the real package manager
  DISTRO=arch
  out="$(pkg_install foo bar)"
  [ "$out" = "yay -S --needed --noconfirm foo bar" ] && echo "pkg_install dispatch ok" || { echo "BAD: $out"; exit 1; }
  detect_distro; [ "$DISTRO" = arch ] && echo "detect_distro=arch ok" || { echo "BAD DISTRO=$DISTRO"; exit 1; }
  declare -F info require_not_root run_step ensure_aur_helper >/dev/null && echo "functions defined ok"
'
```
Expected: `syntax ok`; shellcheck line; `pkg_install dispatch ok`; `detect_distro=arch ok`; `functions defined ok`.

- [ ] **Step 5: Commit**

```bash
cd ~/Dev/phillhood/bootstrap
git add lib/common.sh lib/distro.sh .gitignore
git commit -m "add shared lib (logging + distro dispatch) and gitignore"
```

---

### Task 2: Package lists + packages step

**Files:**
- Create: `packages/core.txt`, `packages/cli.txt`, `packages/docker.txt`, `packages/k8s.txt`, `steps/10-packages.sh`

**Interfaces:**
- Consumes: `ensure_aur_helper`, `pkg_install`, `info`, `die` (Task 1); globals `BOOTSTRAP_DIR` (repo root) and `WITH_K8S` (0/1), set by `install.sh` (Task 5).
- Produces: `step_packages` (installs the package union); helper `_read_packages FILE...` (prints package names, one per line, comments/blanks stripped).

- [ ] **Step 1: Create the four package files**

`packages/core.txt`:
```
# Foundational (shell + the dotfiles symlink manager)
zsh
stow
```

`packages/cli.txt`:
```
# CLI tooling
starship
atuin
fnm
eza
bat
ripgrep
fzf
zoxide
direnv
jq
uv
rustup
go
tmux
neovim
fastfetch
```

`packages/docker.txt`:
```
# Container tooling
docker
docker-compose
docker-buildx
```

`packages/k8s.txt`:
```
# Kubernetes tooling (installed only with --k8s / WITH_K8S=1)
kubectl
kubectx
k9s
helm
kubeseal
argocd
```

- [ ] **Step 2: Create `steps/10-packages.sh`**

```bash
#!/usr/bin/env bash
# Step: install packages. Consumes lib/distro.sh (ensure_aur_helper, pkg_install)
# and packages/*.txt. Honors WITH_K8S. Requires BOOTSTRAP_DIR to be set.

# Print package names from the given files, stripping #-comments and blank lines.
_read_packages() {
  local f line
  for f in "$@"; do
    [ -r "$f" ] || die "package file not found: $f"
    while IFS= read -r line || [ -n "$line" ]; do
      line="${line%%#*}"                 # drop comments
      line="${line//[[:space:]]/}"       # drop all whitespace
      [ -n "$line" ] && printf '%s\n' "$line"
    done < "$f"
  done
}

step_packages() {
  ensure_aur_helper
  local dir="$BOOTSTRAP_DIR/packages"
  local files=("$dir/core.txt" "$dir/cli.txt" "$dir/docker.txt")
  [ "${WITH_K8S:-0}" = 1 ] && files+=("$dir/k8s.txt")
  local pkgs; mapfile -t pkgs < <(_read_packages "${files[@]}")
  info "installing ${#pkgs[@]} packages via the package manager"
  pkg_install "${pkgs[@]}"
}
```

- [ ] **Step 3: Verify syntax + parsing counts (no install)**

Run:
```bash
cd ~/Dev/phillhood/bootstrap
bash -n steps/10-packages.sh && echo "syntax ok"
command -v shellcheck >/dev/null && shellcheck steps/10-packages.sh && echo "shellcheck clean" || echo "shellcheck skipped"
bash -c '
  set -euo pipefail
  source lib/common.sh; source lib/distro.sh; source steps/10-packages.sh
  BOOTSTRAP_DIR="$PWD"
  mapfile -t base < <(_read_packages packages/core.txt packages/cli.txt packages/docker.txt)
  mapfile -t all  < <(_read_packages packages/core.txt packages/cli.txt packages/docker.txt packages/k8s.txt)
  echo "base=${#base[@]} (expect 21), with-k8s=${#all[@]} (expect 27)"
  [ "${#base[@]}" -eq 21 ] && [ "${#all[@]}" -eq 27 ] && echo "counts ok" || { echo "BAD counts"; exit 1; }
  printf "%s\n" "${base[@]}" | grep -qx stow && echo "stow present ok" || { echo "stow MISSING"; exit 1; }
  printf "%s\n" "${all[@]}" | grep -qiE "sops|age" && { echo "sops/age SHOULD be absent"; exit 1; } || echo "sops/age absent ok"
'
```
Expected: `syntax ok`; shellcheck line; `base=21 … with-k8s=27`; `counts ok`; `stow present ok`; `sops/age absent ok`.

- [ ] **Step 4: Commit**

```bash
cd ~/Dev/phillhood/bootstrap
git add packages steps/10-packages.sh
git commit -m "add package lists and package-install step"
```

---

### Task 3: Post-package steps (dotfiles, shell, tmux, rust/node, docker)

**Files:**
- Create: `steps/20-dotfiles.sh`, `steps/30-shell.sh`, `steps/40-tmux.sh`, `steps/50-rust-node.sh`, `steps/60-docker.sh`

**Interfaces:**
- Consumes: `info`, `warn`, `die` (Task 1); env `DOTFILES_REPO`, `DOTFILES_BRANCH` (Task 5).
- Produces: `step_dotfiles`, `step_shell`, `step_tmux`, `step_rust_node`, `step_docker` — each a guarded, idempotent function.

- [ ] **Step 1: Create `steps/20-dotfiles.sh`**

```bash
#!/usr/bin/env bash
# Step: clone the dotfiles and stow them. Needs git + stow (installed in step 10).

step_dotfiles() {
  local repo="${DOTFILES_REPO:-https://github.com/phillhood/.dotfiles.git}"
  local branch="${DOTFILES_BRANCH:-main}"
  local dest="$HOME/.dotfiles"
  if [ ! -d "$dest/.git" ]; then
    info "cloning dotfiles ($repo @ $branch)"
    git clone --branch "$branch" "$repo" "$dest"
  else
    info "dotfiles already present at $dest (skipping clone)"
  fi
  info "stowing dotfiles (make install)"
  make -C "$dest" install
}
```

- [ ] **Step 2: Create `steps/30-shell.sh`**

```bash
#!/usr/bin/env bash
# Step: set the login shell to zsh (idempotent).

step_shell() {
  local zsh_path current
  zsh_path="$(command -v zsh)" || die "zsh not installed"
  current="$(getent passwd "$USER" | cut -d: -f7)"
  if [ "$current" != "$zsh_path" ]; then
    info "setting default shell to zsh ($zsh_path)"
    sudo chsh -s "$zsh_path" "$USER"
  else
    info "default shell already zsh"
  fi
}
```

- [ ] **Step 3: Create `steps/40-tmux.sh`**

```bash
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
```

- [ ] **Step 4: Create `steps/50-rust-node.sh`**

```bash
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
```

- [ ] **Step 5: Create `steps/60-docker.sh`**

```bash
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
```

- [ ] **Step 6: Verify syntax + functions defined (do NOT execute the steps)**

Run:
```bash
cd ~/Dev/phillhood/bootstrap
for f in steps/20-dotfiles.sh steps/30-shell.sh steps/40-tmux.sh steps/50-rust-node.sh steps/60-docker.sh; do bash -n "$f" || exit 1; done; echo "syntax ok"
command -v shellcheck >/dev/null && shellcheck steps/2*.sh steps/3*.sh steps/4*.sh steps/5*.sh steps/6*.sh && echo "shellcheck clean" || echo "shellcheck skipped"
bash -c '
  set -euo pipefail
  source lib/common.sh; source lib/distro.sh
  for f in steps/20-dotfiles.sh steps/30-shell.sh steps/40-tmux.sh steps/50-rust-node.sh steps/60-docker.sh; do source "$f"; done
  declare -F step_dotfiles step_shell step_tmux step_rust_node step_docker >/dev/null && echo "all 5 step functions defined ok" || { echo "MISSING function"; exit 1; }
'
```
Expected: `syntax ok`; shellcheck line; `all 5 step functions defined ok`. (Functions are defined but never called — no system mutation.)

- [ ] **Step 7: Commit**

```bash
cd ~/Dev/phillhood/bootstrap
git add steps/20-dotfiles.sh steps/30-shell.sh steps/40-tmux.sh steps/50-rust-node.sh steps/60-docker.sh
git commit -m "add dotfiles, shell, tmux, rust/node, docker steps"
```

---

### Task 4: Easter egg (`kek/`)

**Files:**
- Create: `kek/run`, `kek/supaHotFire`

**Interfaces:**
- Produces: an executable `kek/run` that prints the finale; called last by `install.sh` (Task 5).

- [ ] **Step 1: Copy the ASCII art verbatim from git history**

The art is large; pull it from the dotfiles repo's `chezmoi` branch rather than retyping:
```bash
cd ~/Dev/phillhood/bootstrap
mkdir -p kek
git -C "$HOME/.dotfiles" show chezmoi:_setup/_kek/supaHotFire > kek/supaHotFire
wc -l kek/supaHotFire   # expect a non-trivial ascii-art file (~80+ lines)
```

- [ ] **Step 2: Create `kek/run`**

```bash
#!/usr/bin/env bash
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo -e "\nSetup complete - time to spit some bars...\n"
sleep 1
echo -e "boom.."
sleep 1
echo -e "\tbam.."
sleep 1
echo -e "\t\tbop.."
sleep 2
echo -e "\t\t\tbada-bap.."
sleep 0.6
echo -e "\t\t\t\t    boop.."
sleep 0.9
echo -e "\n"
echo -e "\t\t\t\t ██████   ██████   ██     ██"
echo -e "\t\t\t\t ██  ██  ██    ██  ██     ██"
echo -e "\t\t\t\t ██████  ██    ██  ██  █  ██"
echo -e "\t\t\t\t ██      ██    ██  ██ ███ ██"
echo -e "\t\t\t\t ██       ██████    ███ ███ "
echo -e "\n"
sleep 0.5
while IFS= read -r line; do
  printf "%s\n" "$line"
  sleep 0.005
done < "$here/supaHotFire"
echo -e "\n"
echo -e "\tThis system has been blessed by SupaHotFire.\n"
echo -e "\n\n"
```

- [ ] **Step 3: Make executable + verify**

```bash
cd ~/Dev/phillhood/bootstrap
chmod +x kek/run
bash -n kek/run && echo "syntax ok"
test -s kek/supaHotFire && echo "art present ($(wc -l < kek/supaHotFire) lines)" || echo "ART MISSING"
diff <(git -C "$HOME/.dotfiles" show chezmoi:_setup/_kek/supaHotFire) kek/supaHotFire && echo "art matches source" || echo "ART DIFFERS"
```
Expected: `syntax ok`; `art present (N lines)`; `art matches source`. (Running `kek/run` is safe — it only prints and sleeps ~7s — but not required for the gate.)

- [ ] **Step 4: Commit**

```bash
cd ~/Dev/phillhood/bootstrap
git add kek/run kek/supaHotFire
git commit -m "add easter egg finale"
```

---

### Task 5: Orchestrator (`install.sh`)

**Files:**
- Create: `install.sh`

**Interfaces:**
- Consumes: everything from Tasks 1–4 (`lib/*`, `steps/*`, `kek/run`).
- Produces: the executable entrypoint. Sets/exports `BOOTSTRAP_DIR` (repo root) and `WITH_K8S` for the steps. Reads `DOTFILES_REPO`/`DOTFILES_BRANCH` from env (defaults applied in `step_dotfiles`).

- [ ] **Step 1: Create `install.sh`**

```bash
#!/usr/bin/env bash
set -euo pipefail

# Fresh-machine provisioner for Arch Linux. Installs packages, then clones and
# stows the dotfiles. Safe to re-run.
#
# Usage: ./install.sh [--k8s]
# Env: WITH_K8S=1, DOTFILES_REPO=<url>, DOTFILES_BRANCH=<name>

usage() {
  cat <<'EOF'
Usage: install.sh [--k8s] [--help]
  --k8s        also install Kubernetes tooling (kubectl, k9s, helm, ...)
  --help       show this help
Env:
  WITH_K8S=1              same as --k8s
  DOTFILES_REPO=<url>     dotfiles repo to clone (default: phillhood/.dotfiles)
  DOTFILES_BRANCH=<name>  branch to clone (default: main)
EOF
}

WITH_K8S="${WITH_K8S:-0}"
while [ "$#" -gt 0 ]; do
  case "$1" in
    --k8s) WITH_K8S=1 ;;
    -h|--help) usage; exit 0 ;;
    *) printf 'unknown argument: %s\n' "$1" >&2; usage; exit 1 ;;
  esac
  shift
done
export WITH_K8S

# Locate self. If running detached (curl | bash) there are no sibling files, so
# clone the repo and re-exec from it. WITH_K8S/DOTFILES_* propagate via the env.
SOURCE="${BASH_SOURCE[0]:-}"
BOOTSTRAP_DIR=""
if [ -n "$SOURCE" ] && [ -f "$SOURCE" ]; then
  BOOTSTRAP_DIR="$(cd "$(dirname "$SOURCE")" && pwd)"
fi
if [ -z "$BOOTSTRAP_DIR" ] || [ ! -d "$BOOTSTRAP_DIR/lib" ]; then
  echo "==> fetching bootstrap repo (running detached)" >&2
  command -v git >/dev/null 2>&1 || sudo pacman -Sy --needed --noconfirm git
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
```

- [ ] **Step 2: Make executable + verify (help/arg paths only — never a full run)**

Run:
```bash
cd ~/Dev/phillhood/bootstrap
chmod +x install.sh
bash -n install.sh && echo "syntax ok"
command -v shellcheck >/dev/null && shellcheck -x install.sh && echo "shellcheck clean" || echo "shellcheck skipped"
./install.sh --help | head -1                      # safe: exits before any step
./install.sh --k8s --help >/dev/null && echo "help exits 0 ok"
./install.sh --bogus 2>&1 | grep -q "unknown argument" && echo "bad-arg rejected ok"
# Confirm the step order the orchestrator will run (static check, no execution):
grep -c 'run_step' install.sh   # expect 6
```
Expected: `syntax ok`; shellcheck line; the usage first line; `help exits 0 ok`; `bad-arg rejected ok`; `6`.

> Do NOT run `./install.sh` without `--help` — it would provision this machine.

- [ ] **Step 3: Commit**

```bash
cd ~/Dev/phillhood/bootstrap
git add install.sh
git commit -m "add install.sh orchestrator"
```

---

### Task 6: README

**Files:**
- Create: `README.md`

**Interfaces:** none (documentation).

- [ ] **Step 1: Create `README.md`**

````markdown
# bootstrap

Fresh-machine provisioner for Arch Linux. Installs packages, then clones and stows
[phillhood/.dotfiles](https://github.com/phillhood/.dotfiles). Idempotent — safe to re-run.

One-way dependency: this repo provisions the machine and deploys the dotfiles; the dotfiles
repo does only symlink management and knows nothing about this one.

## Usage

Clone-first (primary):

```sh
git clone https://github.com/phillhood/bootstrap.git
cd bootstrap
./install.sh            # base install
./install.sh --k8s      # + Kubernetes tooling
```

One-liner (convenience — `install.sh` clones itself and re-execs):

```sh
curl -fsSL https://raw.githubusercontent.com/phillhood/bootstrap/main/install.sh | bash
curl -fsSL https://raw.githubusercontent.com/phillhood/bootstrap/main/install.sh | WITH_K8S=1 bash
```

Run as your normal user (not root); it uses `sudo` where needed.

## What it does

1. Install `yay` + packages (`packages/*.txt`): zsh, stow, and the CLI/docker toolchain (+k8s with `--k8s`).
2. Clone `phillhood/.dotfiles` → `~/.dotfiles` and `make install` (stow symlinks).
3. Set the login shell to zsh.
4. Install the tmux plugin manager (tpm).
5. Default Rust toolchain (stable) + Node LTS (via fnm).
6. Enable docker + add you to the `docker` group.

## Configuration

| Env | Default | Purpose |
| --- | --- | --- |
| `WITH_K8S` | `0` | `1` (or `--k8s`) also installs Kubernetes tooling |
| `DOTFILES_REPO` | `https://github.com/phillhood/.dotfiles.git` | dotfiles repo to clone |
| `DOTFILES_BRANCH` | `main` | branch to clone |

**Dotfiles branch:** the stow layout currently lives on the dotfiles `stow` branch. Until it is
on `main`, run with `DOTFILES_BRANCH=stow` (or push/merge the stow layout to `main`).

## Extending to other distros

`lib/distro.sh` is the single dispatch point — `detect_distro` and `pkg_install` have a `case`
with an `arch` arm and a `die` default. Add a `debian`/`ubuntu` arm (and per-distro package
handling) there to support another distro.

## TODO

- Container smoke-test: run the full install in a clean Arch container and assert idempotency +
  key binaries on PATH. The chezmoi-era version caught real bugs; port it here.
````

- [ ] **Step 2: Verify**

```bash
cd ~/Dev/phillhood/bootstrap
test -s README.md && echo "README present"
grep -q 'DOTFILES_BRANCH' README.md && grep -q 'no sibling' README.md 2>/dev/null; grep -q 'clones itself' README.md && echo "curl re-exec documented"
grep -q 'WITH_K8S' README.md && echo "k8s documented"
```
Expected: `README present`; `curl re-exec documented`; `k8s documented`.

- [ ] **Step 3: Commit**

```bash
cd ~/Dev/phillhood/bootstrap
git add README.md
git commit -m "add readme"
```

---

## Self-Review

**Spec coverage** (against `docs/superpowers/specs/2026-07-05-bootstrap-provisioner-design.md`):
- `install.sh` orchestrator (args, source, run steps, re-exec-when-detached, easter egg) → Task 5. ✓
- `lib/common.sh` (info/warn/die, require_not_root, run_step) → Task 1. ✓
- `lib/distro.sh` (detect_distro, ensure_aur_helper, pkg_install; die on non-arch) → Task 1. ✓
- `packages/{core,cli,docker,k8s}.txt` with +stow, −sops/age → Task 2. ✓
- `steps/10-packages.sh` (WITH_K8S conditional, comment/blank stripping) → Task 2. ✓
- `steps/20..60` ported from `.chezmoiscripts/*`, guards intact → Task 3. ✓
- `kek/run` + `kek/supaHotFire` → Task 4. ✓
- Dotfiles coordination (`DOTFILES_REPO`/`DOTFILES_BRANCH`, stow-branch note) → Task 3 (env) + Task 5 (defaults) + Task 6 (README note). ✓
- Idempotency + safety (set -euo pipefail, not-root, --needed guards) → Tasks 1–5. ✓
- Fresh-machine usage / `curl|bash` re-exec → Task 5 + Task 6. ✓
- Deferred smoke-test noted → Task 6 README TODO. ✓

**Placeholder scan:** none — every step has full file contents and concrete verification with expected output.

**Type/name consistency:** function names are consistent across tasks — `info/warn/die/require_not_root/run_step` (Task 1) used in Tasks 2/3/5; `detect_distro/DISTRO/ensure_aur_helper/pkg_install` (Task 1) used in Task 2/5; `step_packages` (Task 2) + `step_dotfiles/step_shell/step_tmux/step_rust_node/step_docker` (Task 3) all called by `install.sh` (Task 5) in that order; globals `BOOTSTRAP_DIR`/`WITH_K8S` set in Task 5, consumed in Task 2. Package counts (21 / 27) consistent between Global Constraints and Task 2's verification.
