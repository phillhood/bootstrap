# Design: `bootstrap` — fresh-machine provisioner

**Date:** 2026-07-05
**Repo:** `phillhood/bootstrap` (new; built locally at `~/Dev/phillhood/bootstrap`, default branch `main`, not yet on GitHub)
**Related:** consumes `phillhood/.dotfiles` (the stow migration — see that repo's `docs/superpowers/specs/2026-07-05-stow-migration-design.md`).

## Goal

A plain, idempotent Bash provisioner that takes a bare Arch Linux machine to a fully
configured one: install packages, then clone + `make install` the dotfiles. This is the
"software deployment" half that GNU Stow deliberately does not do. It replaces the old
chezmoi bootstrap (`_setup/bootstrap` + `.chezmoiscripts/*` + `.chezmoidata/packages.yaml`),
whose logic is preserved in git history on the dotfiles `chezmoi` branch.

## Architecture: one-way dependency

```
bootstrap (this repo)          →  dotfiles (phillhood/.dotfiles)
  installs packages,              pure stow; `make install` symlinks configs.
  then clones + `make install`s   Depends on nothing.
  the dotfiles.
```

bootstrap depends on dotfiles (by URL); dotfiles never references bootstrap. No submodules.

## Non-goals

- Multi-distro support beyond a ready-to-extend dispatch point (Arch is the only implemented
  backend; non-Arch dies with a clear message).
- Managing dotfile *contents* — that's the dotfiles repo's job.
- A container smoke-test harness (deferred — see [Deferred](#deferred)).

## Repo structure

```
~/Dev/phillhood/bootstrap/
├── install.sh            # entrypoint: parse args, source lib, run steps in order, easter egg
├── lib/
│   ├── common.sh         # log helpers (info/warn/die), require-not-root, run_step
│   └── distro.sh         # detect $ID; pkg_install(); ensure_aur_helper(); die on non-arch
├── packages/
│   ├── core.txt          # zsh, stow
│   ├── cli.txt           # starship atuin fnm eza bat ripgrep fzf zoxide direnv jq uv rustup go tmux neovim fastfetch
│   ├── docker.txt        # docker docker-compose docker-buildx
│   └── k8s.txt           # kubectl kubectx k9s helm kubeseal argocd  (only with --k8s)
├── steps/                # each defines one step_* function, sourced by install.sh
│   ├── 10-packages.sh
│   ├── 20-dotfiles.sh
│   ├── 30-shell.sh
│   ├── 40-tmux.sh
│   ├── 50-rust-node.sh
│   └── 60-docker.sh
├── kek/
│   ├── run               # easter-egg finale (self-locating; ported butHesNotaRapper)
│   └── supaHotFire       # ascii art (read by kek/run)
├── README.md
└── .gitignore
```

Every file has one clear responsibility. `install.sh` is a thin orchestrator; each `steps/`
file is one provisioning concern that can be read and reasoned about in isolation.

## Components

### `install.sh` (orchestrator)
- `set -euo pipefail`.
- Parse args/env: `--k8s` flag OR `WITH_K8S=1` env → sets `WITH_K8S`. `--help` prints usage.
- Reads `DOTFILES_REPO` (default `https://github.com/phillhood/.dotfiles.git`) and
  `DOTFILES_BRANCH` (default `main`) from env — see [Dotfiles coordination](#dotfiles-coordination).
- Source `lib/common.sh`, `lib/distro.sh`, then every `steps/*.sh` (sorted).
- `require_not_root` (yay/makepkg must build as a normal user).
- `detect_distro` (dies on non-Arch before doing anything).
- Run steps in order via `run_step`: `step_packages` → `step_dotfiles` → `step_shell` →
  `step_tmux` → `step_rust_node` → `step_docker`.
- Finally run the easter egg (`kek/run || true`).

### `lib/common.sh`
- `info`/`warn`/`die` (stderr, prefixed).
- `require_not_root`: `[ "$(id -u)" -ne 0 ] || die "run as your normal user, not root"`.
- `run_step "<label>" step_fn`: prints a banner, calls the function.

### `lib/distro.sh`
- `detect_distro`: source `/etc/os-release`; set `DISTRO=$ID`; `case` — `arch` supported,
  else `die "unsupported distro: $DISTRO"`. This is the single extension point for Debian etc.
- `ensure_aur_helper` (Arch): if `yay` absent, `sudo pacman -S --needed --noconfirm base-devel git`,
  clone `https://aur.archlinux.org/yay-bin.git` to a tmpdir, `makepkg -si --noconfirm`, clean up.
- `pkg_install "$@"`: `case $DISTRO: arch) yay -S --needed --noconfirm "$@" ;; *) die ;;`.

### `steps/` (ported from `.chezmoiscripts/*`, chezmoi templating removed)
- **`10-packages.sh` / `step_packages`**: `ensure_aur_helper`; read package names from
  `packages/core.txt packages/cli.txt packages/docker.txt` (and `packages/k8s.txt` iff
  `WITH_K8S`), stripping `#`-comments and blanks; `pkg_install` the union.
- **`20-dotfiles.sh` / `step_dotfiles`**: if `~/.dotfiles` absent,
  `git clone --branch "$DOTFILES_BRANCH" "$DOTFILES_REPO" ~/.dotfiles`; then
  `make -C "$HOME/.dotfiles" install`. (Needs `git` + `stow` — both installed in step 10.)
- **`30-shell.sh` / `step_shell`**: if login shell ≠ `$(command -v zsh)`,
  `sudo chsh -s "$(command -v zsh)" "$USER"`.
- **`40-tmux.sh` / `step_tmux`**: if `~/.tmux/plugins/tpm` absent,
  `git clone --depth 1 https://github.com/tmux-plugins/tpm ~/.tmux/plugins/tpm`.
- **`50-rust-node.sh` / `step_rust_node`**: `rustup default stable`; then
  `export PATH="$HOME/.local/share/fnm:$PATH"; eval "$(fnm env)"; fnm install --lts; fnm default lts-latest`.
- **`60-docker.sh` / `step_docker`**: if `/run/systemd/system` exists,
  `sudo systemctl enable --now docker.service`; if `$USER` not in `docker` group,
  `sudo usermod -aG docker "$USER"` (warn: re-login required).

### `kek/`
`kek/run` is the ported `butHesNotaRapper`: self-locates via `BASH_SOURCE`, prints the "POW"
ASCII banner, then streams `kek/supaHotFire` line-by-line. Runs last, failure-tolerant.

## Package groups (three deliberate changes from the old `packages.yaml`)

- **core**: `zsh`, **`stow`** ← *added*; the dotfiles deploy (`make install`) requires stow,
  which the chezmoi-era list never needed.
- **cli**: `starship atuin fnm eza bat ripgrep fzf zoxide direnv jq uv rustup go tmux neovim fastfetch` (unchanged).
- **docker**: `docker docker-compose docker-buildx` (unchanged).
- **k8s**: `kubectl kubectx k9s helm kubeseal argocd` (unchanged; gated behind `--k8s`).
- **dropped**: `sops`, `age` — they existed only for chezmoi's encrypted-secrets workflow,
  which no longer exists. (Re-add a `packages/secrets.txt` if wanted as general tools.)

## Dotfiles coordination

`step_dotfiles` clones `phillhood/.dotfiles` at `$DOTFILES_BRANCH` (default `main`). The stow
layout currently lives on the **unpushed `stow` branch**. So on a fresh machine this step only
works once that layout is on the branch bootstrap clones. Resolution options (the user's call,
outside this repo): push `stow` and set `DOTFILES_BRANCH=stow`, or merge/reset `main` to the
stow layout and keep the default. The README documents this; `install.sh` exposes
`DOTFILES_REPO`/`DOTFILES_BRANCH` env overrides so no code change is needed to switch.

## Idempotency & safety

Every step is guarded so the whole script is safe to re-run:
- `pkg_install` uses `--needed` (skips installed).
- `ensure_aur_helper` skips if `yay` present.
- `step_dotfiles` clones only if `~/.dotfiles` absent; `make install` uses `stow --restow` (idempotent).
- `step_shell` chsh only if not already zsh; `step_tmux` clones only if tpm dir absent;
  `step_docker` usermod only if not already in the group; `rustup default`/`fnm` are idempotent.
- `set -euo pipefail`; refuses root; `sudo` prompts for password (works with a TTY — noted for
  `curl | bash` in the README).

## Fresh-machine usage (README)

```sh
# once the repo is on GitHub and the dotfiles stow layout is on DOTFILES_BRANCH:
curl -fsSL https://raw.githubusercontent.com/phillhood/bootstrap/main/install.sh | bash
# with k8s tools:
curl -fsSL https://raw.githubusercontent.com/phillhood/bootstrap/main/install.sh | WITH_K8S=1 bash
# or clone + run:
git clone https://github.com/phillhood/bootstrap.git && cd bootstrap && ./install.sh [--k8s]
```

Note: `curl | bash` fetches only `install.sh`; the `lib/`, `steps/`, `packages/`, `kek/` files
are resolved relative to the script. Since a piped script has no sibling files, `install.sh`
detects when it is running detached (no `lib/` next to it) and re-execs from a shallow clone of
the repo. The README documents the clone-first form as the primary path; `curl | bash` is the
convenience path.

## Testing / verification

No unit-test harness. Verification is behavioural, matching the dotfiles repo's convention:
- `bash -n` on `install.sh` and every `lib`/`steps` file (syntax).
- `shellcheck` if available (clean, or documented suppressions).
- Dry-run guards: each step's idempotency guard is individually checkable (e.g. run
  `step_shell` when already on zsh → no-op).
- Package-list parsing: the comment/blank-stripping produces the expected package set
  (core+cli+docker = N, +k8s = N+6).
- A real end-to-end run is only fully meaningful on a fresh Arch install / container (deferred).

## Deferred

- **Container smoke-test** (`smoke-test.sh`): runs the whole install in a clean Arch container
  and asserts idempotency + key binaries on PATH. The chezmoi-era version caught 2 real bugs, so
  it is valuable — but it is heavyweight (AUR builds inside the container are slow) and is a
  follow-up, not part of the initial build. Noted in the README as a TODO.
- **Debian/Ubuntu backend**: fill in the `case` arms in `lib/distro.sh` + add per-distro package
  name handling when a non-Arch machine actually needs provisioning.
