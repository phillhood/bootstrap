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
./install.sh
```

One-liner (convenience — `install.sh` clones itself and re-execs):

```sh
curl -fsSL https://raw.githubusercontent.com/phillhood/bootstrap/main/install.sh | bash
```

Run as your normal user (not root); it uses `sudo` where needed.

## What it does

1. Install `yay` + packages (`packages/*.txt`): zsh, stow, and the CLI/docker/Kubernetes toolchain.
2. Clone `phillhood/.dotfiles` → `~/.dotfiles` and `make install` (stow symlinks).
3. Apply non-stowed `canonical/` configs — merges `canonical/.claude/settings.json` into the live
   `~/.claude/settings.json` (deep-merge via `jq`, so plugin-generated keys are preserved).
4. Set the login shell to zsh.
5. Install the tmux plugin manager (tpm).
6. Default Rust toolchain (stable) + Node LTS (via fnm).
7. Enable docker + add you to the `docker` group.

## Configuration

| Env | Default | Purpose |
| --- | --- | --- |
| `DOTFILES_REPO` | `https://github.com/phillhood/.dotfiles.git` | dotfiles repo to clone |
| `DOTFILES_BRANCH` | `stow` | branch to clone |

## Extending to other distros

`lib/distro.sh` is the single dispatch point — `detect_distro` and `pkg_install` have a `case`
with an `arch` arm and a `die` default. Add a `debian`/`ubuntu` arm (and per-distro package
handling) there to support another distro.

## TODO

- Container smoke-test: run the full install in a clean Arch container and assert idempotency +
  key binaries on PATH. The chezmoi-era version caught real bugs; port it here.
