#!/usr/bin/env bash
# Step: clone the dotfiles and stow them. Needs git + stow (installed in step 10).

step_dotfiles() {
  local repo="${DOTFILES_REPO:-https://github.com/phillhood/.dotfiles.git}"
  local branch="${DOTFILES_BRANCH:-stow}"
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
