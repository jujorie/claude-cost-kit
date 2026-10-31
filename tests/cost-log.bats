#!/usr/bin/env bats

load test_helper

setup() {
  common_setup
  SCRIPT="$REPO_ROOT/cost/cost-log.sh"
  SNAPS="$CLAUDE_CONFIG_DIR/cost/sessions"
  LEDGER="$CLAUDE_CONFIG_DIR/cost/sessions.jsonl"
  mkdir -p "$SNAPS"
}

write_snapshot() { # sid json
  printf '%s\n' "$2" > "$SNAPS/$1.json"
}

@test "appends one ledger row from the snapshot" {
  write_snapshot s1 '{"session_id":"s1","session_name":"demo","workspace":{"project_dir":"/nope/proj"},"model":{"id":"claude-opus-5-5"},"cost":{"total_cost_usd":1.5,"total_duration_ms":120000,"total_api_duration_ms":60000,"total_lines_added":10,"total_lines_removed":3}}'
  run bash "$SCRIPT" <<< '{"session_id":"s1","reason":"exit"}'
  [ "$status" -eq 0 ]
  [ "$(wc -l < "$LEDGER" | tr -d ' ')" -eq 1 ]
  row="$(cat "$LEDGER")"
  [ "$(jq -r .session <<< "$row")" = s1 ]
  [ "$(jq -r .name <<< "$row")" = demo ]
  [ "$(jq -r .project <<< "$row")" = /nope/proj ]
  [ "$(jq -r .branch <<< "$row")" = "" ]
  [ "$(jq -r .model <<< "$row")" = claude-opus-5-5 ]
  [ "$(jq -r .cost_usd <<< "$row")" = 1.5 ]
  [ "$(jq -r .duration_ms <<< "$row")" = 120000 ]
  [ "$(jq -r .api_duration_ms <<< "$row")" = 60000 ]
  [ "$(jq -r .lines_added <<< "$row")" = 10 ]
  [ "$(jq -r .lines_removed <<< "$row")" = 3 ]
  [ "$(jq -r .reason <<< "$row")" = exit ]
  [[ "$(jq -r .ended <<< "$row")" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}[+-][0-9]{4}$ ]]
}

@test "records git branch of the project dir" {
  proj="$BATS_TEST_TMPDIR/proj"
  git init -q -b feature-x "$proj"
  git -C "$proj" -c user.name=t -c user.email=t@t commit -q --allow-empty -m init
  write_snapshot s2 "{\"session_id\":\"s2\",\"workspace\":{\"project_dir\":\"$proj\"}}"
  run bash "$SCRIPT" <<< '{"session_id":"s2"}'
  [ "$status" -eq 0 ]
  [ "$(jq -r .branch "$LEDGER")" = feature-x ]
}

@test "falls back to cwd when project_dir missing" {
  write_snapshot s3 '{"session_id":"s3","cwd":"/some/cwd"}'
  run bash "$SCRIPT" <<< '{"session_id":"s3"}'
  [ "$(jq -r .project "$LEDGER")" = /some/cwd ]
}

@test "uses defaults for missing fields" {
  write_snapshot s4 '{"session_id":"s4"}'
  run bash "$SCRIPT" <<< '{"session_id":"s4"}'
  [ "$status" -eq 0 ]
  row="$(cat "$LEDGER")"
  [ "$(jq -r .name <<< "$row")" = "" ]
  [ "$(jq -r .project <<< "$row")" = "" ]
  [ "$(jq -r .model <<< "$row")" = "" ]
  [ "$(jq -r .cost_usd <<< "$row")" = 0 ]
  [ "$(jq -r .duration_ms <<< "$row")" = 0 ]
  [ "$(jq -r .reason <<< "$row")" = "" ]
}

@test "appends instead of overwriting" {
  write_snapshot a '{"session_id":"a"}'
  write_snapshot b '{"session_id":"b"}'
  bash "$SCRIPT" <<< '{"session_id":"a"}'
  bash "$SCRIPT" <<< '{"session_id":"b"}'
  [ "$(jq -sr 'map(.session) | join(",")' "$LEDGER")" = "a,b" ]
}

@test "missing snapshot: warns, exits 0, no ledger" {
  run bash "$SCRIPT" <<< '{"session_id":"ghost"}'
  [ "$status" -eq 0 ]
  [[ "$output" == *"no snapshot for ghost"* ]]
  [ ! -e "$LEDGER" ]
}

@test "unsafe session_id: warns, exits 0" {
  run bash "$SCRIPT" <<< '{"session_id":"../../etc/passwd"}'
  [ "$status" -eq 0 ]
  [[ "$output" == *"invalid session_id"* ]]
  [ ! -e "$LEDGER" ]
}

@test "missing session_id: warns, exits 0" {
  run bash "$SCRIPT" <<< '{}'
  [ "$status" -eq 0 ]
  [[ "$output" == *"invalid session_id"* ]]
}

@test "invalid JSON input never fails the session" {
  run bash "$SCRIPT" <<< 'not json'
  [ "$status" -eq 0 ]
  [ ! -e "$LEDGER" ]
}

@test "corrupt snapshot never fails the session" {
  printf 'garbage' > "$SNAPS/bad.json"
  run bash "$SCRIPT" <<< '{"session_id":"bad"}'
  [ "$status" -eq 0 ]
}
