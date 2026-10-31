#!/usr/bin/env bash
# Summarize Claude Code session costs from ~/.claude/cost/sessions.jsonl.
# Usage: cost-report.sh [day|project|branch|name|session] [--since YYYY-MM-DD]
# A resumed session can appear several times; only its last row counts.
# Costs are Claude Code's USD estimates (API list price), not an invoice.
set -euo pipefail

LEDGER="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/cost/sessions.jsonl"

usage() { sed -n '2,5p' "$0" | sed 's/^# \{0,1\}//'; }

main() {
  local by="day" since="" key
  while [ $# -gt 0 ]; do
    case "$1" in
      day|project|branch|name|session) by="$1"; shift ;;
      --since) since="${2:?--since needs a date}"; shift 2 ;;
      -h|--help) usage; return 0 ;;
      *) echo "error: unknown argument: $1" >&2; usage >&2; return 2 ;;
    esac
  done

  if [ ! -s "$LEDGER" ]; then
    echo "no sessions logged yet ($LEDGER)" >&2
    return 0
  fi

  case "$by" in
    day)     key='.ended[0:10]' ;;
    project) key='(.project | split("/") | last)' ;;
    branch)  key='((.project | split("/") | last) + ":" + .branch)' ;;
    name)    key='(if .name == "" then "(sin nombre)" else .name end)' ;;
    session) key='(.ended[0:16] + " " + .session[0:8] + " " + .name)' ;;
  esac

  jq -rs --arg since "$since" "
    map(select(.ended[0:10] >= \$since))
    | group_by(.session) | map(last)
    | group_by($key)
    | map({k: (.[0] | $key), n: length,
           cost: (map(.cost_usd) | add),
           mins: ((map(.duration_ms) | add) / 60000)})
    | sort_by(.k)
    | ([\"$by\", \"sessions\", \"usd\", \"min\"] | @tsv),
      (.[] | [.k, .n, (.cost * 100 | round / 100), (.mins | round)] | @tsv),
      ([\"TOTAL\", (map(.n) | add // 0), ((map(.cost) | add // 0) * 100 | round / 100), (map(.mins) | add // 0 | round)] | @tsv)
  " "$LEDGER" | column -t -s "$(printf '\t')"
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  main "$@"
fi
