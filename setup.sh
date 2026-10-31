#!/usr/bin/env bash
# Install the status line and the session cost ledger into a Claude Code config dir.
# Usage: ./setup.sh [--force] [CONFIG_DIR]      (default: $CLAUDE_CONFIG_DIR, else ~/.claude)
# Copies statusline.sh and cost/*.sh, and merges settings.json (needs jq): sets statusLine and adds
# the SessionEnd hook. Existing files are saved as <name>.bak-<timestamp>. A different statusLine
# already in settings.json is kept unless --force.
set -euo pipefail

force=0
if [ "${1:-}" = "--force" ]; then force=1; shift; fi
kit="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
target="${1:-${CLAUDE_CONFIG_DIR:-$HOME/.claude}}"
ts="$(date +%Y%m%d%H%M%S)"

command -v jq >/dev/null 2>&1 || { echo "error: jq is required (brew install jq / apt install jq)" >&2; exit 1; }

mkdir -p "$target/cost/sessions"
target="$(cd "$target" && pwd)"

install_file() {
  local src="$1" dst="$2"
  if [ -f "$dst" ] && ! cmp -s "$src" "$dst"; then cp "$dst" "$dst.bak-$ts"; echo "backup: $dst.bak-$ts"; fi
  cp "$src" "$dst"
  chmod +x "$dst"
  echo "installed: $dst"
}

install_file "$kit/statusline.sh" "$target/statusline.sh"
install_file "$kit/cost/cost-log.sh" "$target/cost/cost-log.sh"
install_file "$kit/cost/cost-report.sh" "$target/cost/cost-report.sh"

settings="$target/settings.json"
[ -s "$settings" ] || echo '{}' > "$settings"
jq empty "$settings" 2>/dev/null || { echo "error: $settings is not valid JSON; fix it and rerun" >&2; exit 1; }

sl_cmd="bash \"$target/statusline.sh\""
hook_cmd="bash \"$target/cost/cost-log.sh\""

# Claude Code expands $CLAUDE_CONFIG_DIR, $HOME and ~ when it runs a command, so an existing
# `bash "$CLAUDE_CONFIG_DIR/statusline.sh"` may already run the file we install. `norm` reduces
# a command to the script path it runs, so such variants count as ours (no warning, no duplicate hook).
cfg="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
cfg="$(cd "$cfg" 2>/dev/null && pwd || printf '%s' "$cfg")"
# shellcheck disable=SC2016 # $names below are jq variables, not shell
norm='def norm:
  explode | map(select(. != 34 and . != 39)) | implode  # strip double and single quotes (34, 39)
  | gsub("\\$\\{?CLAUDE_CONFIG_DIR\\}?"; $cfg)
  | gsub("\\$\\{?HOME\\}?"; $home)
  | gsub("(?<p>^|\\s)~/"; "\(.p)\($home)/")
  | sub("^\\s*(bash|sh)\\s+"; "")
  | sub("\\s+$"; "")
  | gsub("/+"; "/");'
jqn() { jq --arg cfg "$cfg" --arg home "$HOME" "$@"; }

current_sl="$(jq -r '.statusLine.command // empty' "$settings")"
# shellcheck disable=SC2016 # jq program, not shell expansion
sl_state="$(jqn -r --arg path "$target/statusline.sh" "$norm"'
  (.statusLine.command // "") as $c
  | if $c == "" then "none" elif ($c | norm) == $path then "ours" else "other" end' "$settings")"
set_sl=1
case "$sl_state" in
  ours)
    set_sl=0
    echo "ok: statusLine already runs $target/statusline.sh"
    ;;
  other)
    if [ "$force" -eq 0 ]; then
      set_sl=0
      echo "kept: settings.json already has another statusLine ($current_sl); use --force to replace it"
    fi
    ;;
esac

tmp="$settings.tmp.$$"
trap 'rm -f "$tmp"' EXIT
# shellcheck disable=SC2016 # jq program, not shell expansion
jqn --arg sl "$sl_cmd" --arg hook "$hook_cmd" --arg hook_path "$target/cost/cost-log.sh" \
  --argjson set_sl "$set_sl" "$norm"'
  (if $set_sl == 1 then .statusLine = {type: "command", command: $sl} else . end)
  | .hooks.SessionEnd = (
      (.hooks.SessionEnd // [])
      | if any(.[]?; any(.hooks[]?; (.command // "" | norm) == $hook_path)) then .
        else . + [{hooks: [{type: "command", command: $hook, timeout: 10}]}] end
    )
' "$settings" > "$tmp"
if cmp -s "$tmp" "$settings"; then
  rm -f "$tmp"
  echo "unchanged: $settings"
else
  cp "$settings" "$settings.bak-$ts"
  mv "$tmp" "$settings"
  echo "updated: $settings (backup: $settings.bak-$ts)"
fi
trap - EXIT
echo
echo "Done. Restart Claude Code. Report: $target/cost/cost-report.sh [day|project|branch|name|session] [--since YYYY-MM-DD]"
