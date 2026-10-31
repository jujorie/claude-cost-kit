# Shared setup for the bats suites. Each test gets an isolated HOME and
# CLAUDE_CONFIG_DIR under $BATS_TEST_TMPDIR so nothing touches ~/.claude.

common_setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  export HOME="$BATS_TEST_TMPDIR/home"
  export CLAUDE_CONFIG_DIR="$BATS_TEST_TMPDIR/claude"
  mkdir -p "$HOME" "$CLAUDE_CONFIG_DIR"
}

