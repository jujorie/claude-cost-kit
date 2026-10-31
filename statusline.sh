#!/usr/bin/env bash
# Custom status line: [caveman mode] + model + dir + context + session cost.
# The caveman badge only shows when the caveman plugin wrote its flag file.
# BADGE = naranja
# ctx    = verde
# coste  = amarillo

input=$(cat)

model=$(echo "$input" | jq -r '.model.display_name')
cwd=$(echo "$input" | jq -r '.workspace.current_dir')
dir=$(basename "$cwd")

FLAG="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/.caveman-active"

# Get caveman mode
if [ -f "$FLAG" ] && [ ! -L "$FLAG" ]; then
  MODE=$(head -c 64 "$FLAG" 2>/dev/null | tr -d '\n\r' | tr '[:upper:]' '[:lower:]')
  MODE=$(printf '%s' "$MODE" | tr -cd 'a-z0-9-')

  case "$MODE" in
    off|lite|full|ultra|wenyan-lite|wenyan|wenyan-full|wenyan-ultra|commit|review|compress) ;;
    *) MODE="" ;;
  esac
fi

# Build caveman badge (empty without the flag file)
BADGE=""
if [ -f "$FLAG" ] && [ ! -L "$FLAG" ]; then
  if [ -z "$MODE" ] || [ "$MODE" = "full" ]; then
    BADGE='[CAVEMAN] '
  else
    SUFFIX=$(printf '%s' "$MODE" | tr '[:lower:]' '[:upper:]')
    BADGE="[CAVEMAN:$SUFFIX] "
  fi
fi

used=$(echo "$input" | jq -r '.context_window.used_percentage // empty')

ctx_part=""
[ -n "$used" ] && ctx_part=" | ctx:$(printf '%.0f' "$used")%"

# Session cost (estimated USD, from Claude Code)
cost=$(echo "$input" | jq -r '.cost.total_cost_usd // empty')
cost_part=""
[ -n "$cost" ] && cost_part=" | \$$(printf '%.2f' "$cost")"

# Snapshot for ~/.claude/cost/cost-log.sh (SessionEnd hook)
sid=$(echo "$input" | jq -r '.session_id // empty')
case "$sid" in
  ''|*[!A-Za-z0-9-]*) ;;
  *)
    snap_dir="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/cost/sessions"
    mkdir -p "$snap_dir"
    printf '%s\n' "$input" > "$snap_dir/$sid.json.tmp" && mv "$snap_dir/$sid.json.tmp" "$snap_dir/$sid.json"
    ;;
esac

# ANSI colors
ORANGE='\033[38;5;208m'
GREEN='\033[32m'
YELLOW='\033[33m'
RESET='\033[0m'

printf "${ORANGE}%s${RESET}%s | %s${GREEN}%s${RESET}${YELLOW}%s${RESET}\n" \
  "$BADGE" "$model" "$dir" "$ctx_part" "$cost_part"
