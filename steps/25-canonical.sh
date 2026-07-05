#!/usr/bin/env bash
# Step: apply non-stowed "canonical" configs from the dotfiles repo.
# These are files a tool/plugin rewrites at runtime, so they aren't stowed (a symlink
# would just churn/break). Instead we MERGE our canonical values into the live file,
# preserving whatever the tool generated. Runs after step_dotfiles (needs ~/.dotfiles)
# and needs jq (installed in step_packages).

step_canonical() {
  local base="$HOME/.dotfiles/canonical"
  [ -d "$base" ] || { info "no canonical/ dir in dotfiles; skipping"; return 0; }

  # ~/.claude/settings.json: deep-merge our prefs ON TOP of the live file, so a
  # freshly-installed plugin's generated keys (e.g. GSD hooks) survive.
  local pref="$base/.claude/settings.json"
  if [ -f "$pref" ]; then
    command -v jq >/dev/null 2>&1 || die "jq is required to merge settings.json"
    local dest="$HOME/.claude/settings.json"
    mkdir -p "$(dirname "$dest")"
    [ -f "$dest" ] || echo '{}' > "$dest"
    info "merging canonical prefs into $dest"
    # jq '*' deep-merges objects; canonical (.[1]) wins on overlapping keys. Note it
    # REPLACES arrays (e.g. permissions.allow) rather than concatenating them.
    local tmp; tmp="$(mktemp)"
    if jq -s '.[0] * .[1]' "$dest" "$pref" > "$tmp"; then
      mv "$tmp" "$dest"
    else
      rm -f "$tmp"; die "failed to merge $pref into $dest (invalid JSON?)"
    fi
  fi
}
