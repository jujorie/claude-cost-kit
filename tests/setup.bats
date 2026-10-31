#!/usr/bin/env bats

load test_helper

setup() {
  common_setup
  SCRIPT="$REPO_ROOT/setup.sh"
  TARGET="$BATS_TEST_TMPDIR/target"
}

settings() { jq -r "$1" "$TARGET/settings.json"; }

@test "installs scripts executable into the target dir" {
  run bash "$SCRIPT" "$TARGET"
  [ "$status" -eq 0 ]
  for f in statusline.sh cost/cost-log.sh cost/cost-report.sh; do
    [ -x "$TARGET/$f" ]
  done
  cmp -s "$REPO_ROOT/statusline.sh" "$TARGET/statusline.sh"
  cmp -s "$REPO_ROOT/cost/cost-log.sh" "$TARGET/cost/cost-log.sh"
  cmp -s "$REPO_ROOT/cost/cost-report.sh" "$TARGET/cost/cost-report.sh"
  [ -d "$TARGET/cost/sessions" ]
}

@test "defaults to CLAUDE_CONFIG_DIR" {
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [ -x "$CLAUDE_CONFIG_DIR/statusline.sh" ]
  [ -f "$CLAUDE_CONFIG_DIR/settings.json" ]
}

@test "defaults to ~/.claude without CLAUDE_CONFIG_DIR" {
  unset CLAUDE_CONFIG_DIR
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [ -x "$HOME/.claude/statusline.sh" ]
}

@test "creates settings.json with statusLine and SessionEnd hook" {
  run bash "$SCRIPT" "$TARGET"
  [ "$status" -eq 0 ]
  [ "$(settings .statusLine.type)" = command ]
  [ "$(settings .statusLine.command)" = "bash \"$TARGET/statusline.sh\"" ]
  [ "$(settings '.hooks.SessionEnd | length')" = 1 ]
  [ "$(settings '.hooks.SessionEnd[0].hooks[0].command')" = "bash \"$TARGET/cost/cost-log.sh\"" ]
  [ "$(settings '.hooks.SessionEnd[0].hooks[0].timeout')" = 10 ]
}

@test "relative target is resolved to an absolute path" {
  cd "$BATS_TEST_TMPDIR"
  run bash "$SCRIPT" target
  [ "$status" -eq 0 ]
  [ "$(settings .statusLine.command)" = "bash \"$TARGET/statusline.sh\"" ]
}

@test "running twice is idempotent" {
  bash "$SCRIPT" "$TARGET"
  first="$(cat "$TARGET/settings.json")"
  run bash "$SCRIPT" "$TARGET"
  [ "$status" -eq 0 ]
  [ "$(cat "$TARGET/settings.json")" = "$first" ]
  [ "$(settings '.hooks.SessionEnd | length')" = 1 ]
  [[ "$output" != *"kept:"* ]]
}

@test "preserves unrelated settings and existing hooks" {
  mkdir -p "$TARGET"
  cat > "$TARGET/settings.json" <<'JSON'
{"model":"opus","hooks":{"SessionEnd":[{"hooks":[{"type":"command","command":"echo bye"}]}],"Stop":[{"hooks":[{"type":"command","command":"echo stop"}]}]}}
JSON
  run bash "$SCRIPT" "$TARGET"
  [ "$status" -eq 0 ]
  [ "$(settings .model)" = opus ]
  [ "$(settings '.hooks.Stop[0].hooks[0].command')" = "echo stop" ]
  [ "$(settings '.hooks.SessionEnd | length')" = 2 ]
  [ "$(settings '.hooks.SessionEnd[0].hooks[0].command')" = "echo bye" ]
}

@test "keeps a different statusLine without --force" {
  mkdir -p "$TARGET"
  echo '{"statusLine":{"type":"command","command":"my-line"}}' > "$TARGET/settings.json"
  run bash "$SCRIPT" "$TARGET"
  [ "$status" -eq 0 ]
  [[ "$output" == *"kept: settings.json already has another statusLine (my-line)"* ]]
  [ "$(settings .statusLine.command)" = my-line ]
  [ "$(settings '.hooks.SessionEnd | length')" = 1 ]
}

@test "--force replaces a different statusLine" {
  mkdir -p "$TARGET"
  echo '{"statusLine":{"type":"command","command":"my-line"}}' > "$TARGET/settings.json"
  run bash "$SCRIPT" --force "$TARGET"
  [ "$status" -eq 0 ]
  [ "$(settings .statusLine.command)" = "bash \"$TARGET/statusline.sh\"" ]
}

@test "empty settings.json is treated as {}" {
  mkdir -p "$TARGET"
  : > "$TARGET/settings.json"
  run bash "$SCRIPT" "$TARGET"
  [ "$status" -eq 0 ]
  [ "$(settings .statusLine.type)" = command ]
}

@test "invalid settings.json aborts without changing it" {
  mkdir -p "$TARGET"
  echo '{broken' > "$TARGET/settings.json"
  run bash "$SCRIPT" "$TARGET"
  [ "$status" -eq 1 ]
  [[ "$output" == *"is not valid JSON"* ]]
  [ "$(cat "$TARGET/settings.json")" = '{broken' ]
}

@test "backs up settings.json and changed scripts" {
  mkdir -p "$TARGET"
  echo '{"model":"opus"}' > "$TARGET/settings.json"
  echo 'old' > "$TARGET/statusline.sh"
  run bash "$SCRIPT" "$TARGET"
  [ "$status" -eq 0 ]
  set -- "$TARGET"/statusline.sh.bak-*
  [ -f "$1" ] && [ "$(cat "$1")" = old ]
  set -- "$TARGET"/settings.json.bak-*
  [ -f "$1" ] && [ "$(jq -r .model "$1")" = opus ]
}

@test "does not back up identical scripts" {
  bash "$SCRIPT" "$TARGET"
  rm -f "$TARGET"/*.bak-*
  run bash "$SCRIPT" "$TARGET"
  [ "$status" -eq 0 ]
  [ -z "$(ls "$TARGET"/statusline.sh.bak-* "$TARGET"/cost/*.bak-* 2>/dev/null)" ]
  [[ "$output" != *"backup: $TARGET/statusline.sh"* ]]
}

@test "leaves no temp files behind" {
  run bash "$SCRIPT" "$TARGET"
  [ -z "$(ls "$TARGET"/settings.json.tmp.* 2>/dev/null)" ]
}

@test "fails clearly when jq is missing" {
  fakebin="$BATS_TEST_TMPDIR/bin"
  mkdir -p "$fakebin"
  for c in dirname date; do ln -s "$(command -v "$c")" "$fakebin/$c"; done
  run env PATH="$fakebin" "$BASH" "$SCRIPT" "$TARGET"
  [ "$status" -eq 1 ]
  [[ "$output" == *"jq is required"* ]]
  [ ! -e "$TARGET" ]
}
