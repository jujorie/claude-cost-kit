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
cp "$settings" "$settings.bak-$ts"

sl_cmd="bash \"$target/statusline.sh\""
hook_cmd="bash \"$target/cost/cost-log.sh\""

current_sl="$(jq -r '.statusLine.command // empty' "$settings")"
set_sl=1
if [ -n "$current_sl" ] && [ "$current_sl" != "$sl_cmd" ] && [ "$force" -eq 0 ]; then
  set_sl=0
  echo "kept: settings.json already has another statusLine ($current_sl); use --force to replace it"
fi

tmp="$settings.tmp.$$"
trap 'rm -f "$tmp"' EXIT
jq --arg sl "$sl_cmd" --arg hook "$hook_cmd" --argjson set_sl "$set_sl" '
  (if $set_sl == 1 then .statusLine = {type: "command", command: $sl} else . end)
  | .hooks.SessionEnd = (
      (.hooks.SessionEnd // [])
      | if any(.[]?; any(.hooks[]?; .command == $hook)) then .
        else . + [{hooks: [{type: "command", command: $hook, timeout: 10}]}] end
    )
' "$settings" > "$tmp"
mv "$tmp" "$settings"
trap - EXIT
echo "updated: $settings (backup: $settings.bak-$ts)"
echo
echo "Done. Restart Claude Code. Report: $target/cost/cost-report.sh [day|project|branch|name|session] [--since YYYY-MM-DD]"
