#!/usr/bin/env bats

load test_helper

setup() {
  common_setup
  SCRIPT="$REPO_ROOT/cost/cost-report.sh"
  LEDGER="$CLAUDE_CONFIG_DIR/cost/sessions.jsonl"
  mkdir -p "$CLAUDE_CONFIG_DIR/cost"
}

row() { # ended session name project branch cost duration_ms
  jq -cn --arg e "$1" --arg s "$2" --arg n "$3" --arg p "$4" --arg b "$5" \
    --argjson c "$6" --argjson d "$7" \
    '{ended:$e, session:$s, name:$n, project:$p, branch:$b, cost_usd:$c, duration_ms:$d}' >> "$LEDGER"
}

sample_ledger() {
  row 2026-10-01T10:00:00+0000 aaaaaaaa1111 alpha /src/proj-a main 1.00 600000
  row 2026-10-01T12:00:00+0000 bbbbbbbb2222 ""    /src/proj-b dev  2.00 1200000
  row 2026-10-02T09:00:00+0000 cccccccc3333 gamma /src/proj-a dev  0.50 300000
}

# Print the whitespace-normalized line whose first column is $1.
line_for() {
  printf '%s\n' "$output" | awk -v k="$1" '$1 == k { $1 = $1; print }'
}

@test "no ledger: message and exit 0" {
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"no sessions logged yet"* ]]
}

@test "empty ledger: message and exit 0" {
  : > "$LEDGER"
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"no sessions logged yet"* ]]
}

@test "default groups by day with header and total" {
  sample_ledger
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$(line_for day)" = "day sessions usd min" ]
  [ "$(line_for 2026-10-01)" = "2026-10-01 2 3 30" ]
  [ "$(line_for 2026-10-02)" = "2026-10-02 1 0.5 5" ]
  [ "$(line_for TOTAL)" = "TOTAL 3 3.5 35" ]
}

@test "groups by project basename" {
  sample_ledger
  run bash "$SCRIPT" project
  [ "$status" -eq 0 ]
  [ "$(line_for project)" = "project sessions usd min" ]
  [ "$(line_for proj-a)" = "proj-a 2 1.5 15" ]
  [ "$(line_for proj-b)" = "proj-b 1 2 20" ]
}

@test "groups by project:branch" {
  sample_ledger
  run bash "$SCRIPT" branch
  [ "$(line_for proj-a:main)" = "proj-a:main 1 1 10" ]
  [ "$(line_for proj-a:dev)" = "proj-a:dev 1 0.5 5" ]
  [ "$(line_for proj-b:dev)" = "proj-b:dev 1 2 20" ]
}

@test "groups by name, unnamed as (sin nombre)" {
  sample_ledger
  run bash "$SCRIPT" name
  [ "$(line_for alpha)" = "alpha 1 1 10" ]
  [[ "$output" == *"(sin nombre)"* ]]
}

@test "groups by session with time, short id and name" {
  sample_ledger
  run bash "$SCRIPT" session
  [ "$status" -eq 0 ]
  [[ "$output" =~ 2026-10-01T10:00[[:space:]]+aaaaaaaa[[:space:]]+alpha ]]
  [[ "$output" != *aaaaaaaa1111* ]]
}

@test "resumed session counts only its last row" {
  row 2026-10-01T10:00:00+0000 same-session x /src/p main 1.00 60000
  row 2026-10-01T11:00:00+0000 same-session x /src/p main 4.00 240000
  run bash "$SCRIPT"
  [ "$(line_for TOTAL)" = "TOTAL 1 4 4" ]
}

@test "--since filters older sessions" {
  sample_ledger
  run bash "$SCRIPT" --since 2026-10-02
  [ "$status" -eq 0 ]
  [ -z "$(line_for 2026-10-01)" ]
  [ "$(line_for TOTAL)" = "TOTAL 1 0.5 5" ]
}

@test "--since after all sessions gives zero total" {
  sample_ledger
  run bash "$SCRIPT" --since 2030-01-01
  [ "$status" -eq 0 ]
  [ "$(line_for TOTAL)" = "TOTAL 0 0 0" ]
}

@test "--since works combined with a grouping" {
  sample_ledger
  run bash "$SCRIPT" project --since 2026-10-02
  [ "$(line_for proj-a)" = "proj-a 1 0.5 5" ]
  [ -z "$(line_for proj-b)" ]
}

@test "rounds cost to cents" {
  row 2026-10-01T10:00:00+0000 s1 "" /p main 1.006 0
  row 2026-10-01T10:00:00+0000 s2 "" /p main 0.001 0
  run bash "$SCRIPT"
  [ "$(line_for TOTAL)" = "TOTAL 2 1.01 0" ]
}

@test "--since without a date fails" {
  sample_ledger
  run bash "$SCRIPT" --since
  [ "$status" -ne 0 ]
  [[ "$output" == *"--since needs a date"* ]]
}

@test "unknown argument exits 2 with usage" {
  run bash "$SCRIPT" bogus
  [ "$status" -eq 2 ]
  [[ "$output" == *"unknown argument: bogus"* ]]
  [[ "$output" == *"Usage:"* ]]
}

@test "--help prints usage" {
  run bash "$SCRIPT" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage: cost-report.sh"* ]]
  [[ "$output" != *"#"* ]]
}

@test "sourcing does not run main" {
  sample_ledger
  run bash -c 'source "$1"; type -t main' _ "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$output" = function ]
}
