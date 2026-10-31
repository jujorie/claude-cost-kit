#!/usr/bin/env bash
# SessionEnd hook: append the session's cost to ~/.claude/cost/sessions.jsonl.
# Cost comes from the snapshot ~/.claude/statusline.sh writes on each refresh
# (cost/sessions/<session_id>.json); hooks do not receive the cost themselves.
# Reads the hook JSON on stdin. Never fails the session: errors go to stderr, exit 0.
set -euo pipefail

COST_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/cost"
LEDGER="$COST_DIR/sessions.jsonl"

main() {
  local input sid reason snap dir branch
  input=$(cat)
  sid=$(printf '%s' "$input" | jq -r '.session_id // empty')
  reason=$(printf '%s' "$input" | jq -r '.reason // empty')

  case "$sid" in
    ''|*[!A-Za-z0-9-]*) echo "cost-log: invalid session_id" >&2; return 0 ;;
  esac

  snap="$COST_DIR/sessions/$sid.json"
  if [ ! -f "$snap" ]; then
    echo "cost-log: no snapshot for $sid" >&2
    return 0
  fi

  dir=$(jq -r '.workspace.project_dir // .cwd // empty' "$snap")
  branch=""
  if [ -n "$dir" ] && [ -d "$dir" ]; then
    branch=$(git -C "$dir" rev-parse --abbrev-ref HEAD 2>/dev/null || true)
  fi

  jq -c \
    --arg ended "$(date '+%Y-%m-%dT%H:%M:%S%z')" \
    --arg reason "$reason" \
    --arg branch "$branch" \
    '{
      ended: $ended,
      session: .session_id,
      name: (.session_name // ""),
      project: (.workspace.project_dir // .cwd // ""),
      branch: $branch,
      model: (.model.id // ""),
      cost_usd: (.cost.total_cost_usd // 0),
      duration_ms: (.cost.total_duration_ms // 0),
      api_duration_ms: (.cost.total_api_duration_ms // 0),
      lines_added: (.cost.total_lines_added // 0),
      lines_removed: (.cost.total_lines_removed // 0),
      reason: $reason
    }' "$snap" >> "$LEDGER"
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  main "$@" || true
fi
