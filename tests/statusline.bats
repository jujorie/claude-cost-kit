#!/usr/bin/env bats

load test_helper

setup() {
  common_setup
  SCRIPT="$REPO_ROOT/statusline.sh"
  FLAG="$CLAUDE_CONFIG_DIR/.caveman-active"
  INPUT='{"session_id":"abc-123","model":{"display_name":"Opus"},"workspace":{"current_dir":"/tmp/work/myproj"},"context_window":{"used_percentage":42.6},"cost":{"total_cost_usd":1.234}}'
}

render() {
  run bash -c '"$1" <<< "$2" | sed $'"'"'s/\033\\[[0-9;]*m//g'"'"'' _ "$SCRIPT" "$1"
}

@test "shows model, dir, context and cost" {
  render "$INPUT"
  [ "$status" -eq 0 ]
  [ "$output" = 'Opus | myproj | ctx:43% | $1.23' ]
}

@test "omits context and cost when missing" {
  render '{"model":{"display_name":"Sonnet"},"workspace":{"current_dir":"/a/b"}}'
  [ "$status" -eq 0 ]
  [ "$output" = 'Sonnet | b' ]
}

@test "output is colored" {
  run bash -c '"$1" <<< "$2"' _ "$SCRIPT" "$INPUT"
  [[ "$output" == *$'\033[32m'* ]]
  [[ "$output" == *$'\033[33m'* ]]
}

@test "no badge without flag file" {
  render "$INPUT"
  [[ "$output" != *CAVEMAN* ]]
}

@test "badge [CAVEMAN] for full mode" {
  echo full > "$FLAG"
  render "$INPUT"
  [ "$output" = '[CAVEMAN] Opus | myproj | ctx:43% | $1.23' ]
}

@test "badge [CAVEMAN] for empty flag file" {
  : > "$FLAG"
  render "$INPUT"
  [[ "$output" == '[CAVEMAN] Opus'* ]]
}

@test "badge shows non-default mode in uppercase" {
  printf 'Ultra\n' > "$FLAG"
  render "$INPUT"
  [[ "$output" == '[CAVEMAN:ULTRA] Opus'* ]]
}

@test "badge for wenyan-lite mode" {
  echo wenyan-lite > "$FLAG"
  render "$INPUT"
  [[ "$output" == '[CAVEMAN:WENYAN-LITE] Opus'* ]]
}

@test "unknown mode falls back to plain badge" {
  echo 'rm -rf /' > "$FLAG"
  render "$INPUT"
  [[ "$output" == '[CAVEMAN] Opus'* ]]
}

@test "symlinked flag file is ignored" {
  echo ultra > "$BATS_TEST_TMPDIR/real-flag"
  ln -s "$BATS_TEST_TMPDIR/real-flag" "$FLAG"
  render "$INPUT"
  [[ "$output" != *CAVEMAN* ]]
}

@test "writes session snapshot with the full input" {
  render "$INPUT"
  snap="$CLAUDE_CONFIG_DIR/cost/sessions/abc-123.json"
  [ -f "$snap" ]
  [ "$(cat "$snap")" = "$INPUT" ]
  [ ! -e "$snap.tmp" ]
}

@test "overwrites snapshot on refresh" {
  render "$INPUT"
  render "${INPUT/1.234/2.5}"
  [ "$(jq -r .cost.total_cost_usd "$CLAUDE_CONFIG_DIR/cost/sessions/abc-123.json")" = "2.5" ]
}

@test "no snapshot for unsafe session_id" {
  render '{"session_id":"../evil","model":{"display_name":"Opus"},"workspace":{"current_dir":"/x"}}'
  [ "$status" -eq 0 ]
  [ -z "$(ls -A "$CLAUDE_CONFIG_DIR/cost/sessions" 2>/dev/null)" ]
  [ ! -e "$CLAUDE_CONFIG_DIR/cost/evil.json" ]
}

@test "no snapshot without session_id" {
  render '{"model":{"display_name":"Opus"},"workspace":{"current_dir":"/x"}}'
  [ ! -d "$CLAUDE_CONFIG_DIR/cost/sessions" ]
}
