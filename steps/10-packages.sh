#!/usr/bin/env bash
# Step: install packages. Consumes lib/distro.sh (ensure_aur_helper, pkg_install)
# and packages/*.txt. Requires BOOTSTRAP_DIR to be set.

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
  local files=("$dir/core.txt" "$dir/cli.txt" "$dir/docker.txt" "$dir/k8s.txt")
  local f
  for f in "${files[@]}"; do
    [ -r "$f" ] || die "package file not found: $f"
  done
  local pkgs; mapfile -t pkgs < <(_read_packages "${files[@]}")
  info "installing ${#pkgs[@]} packages via the package manager"
  pkg_install "${pkgs[@]}"
}
