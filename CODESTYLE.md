# Code style

Conventions for the shell scripts in this repo. They describe how the existing code is written; follow them for new code and changes.

## Target platform

- Scripts must run on macOS, Linux, WSL and Git Bash.
- Write for **bash 3.2** (the macOS system bash). Do not use associative arrays (`declare -A`), `mapfile`/`readarray`, `${var,,}`/`${var^^}`, `|&` or other bash 4+ features.
- Stick to POSIX options of `sed`, `date`, `cmp`, `column`, etc. BSD and GNU differ (for example `sed -i`); if a flag behaves differently, avoid it.
- Runtime dependencies: `bash`, `jq` and coreutils. `git` is optional (used only if present). Do not add new ones without a strong reason.

## File layout

1. Shebang: `#!/usr/bin/env bash`.
2. Header comment: what the script does, `Usage:` line, inputs/outputs and side effects. `cost-report.sh` prints lines 2–5 as `--help`, so keep the usage there.
3. `set -euo pipefail` (see [Error handling](#error-handling) for exceptions).
4. Constants and config paths.
5. Functions.
6. Entry point.

Scripts with more than trivial logic put it in `main()` and only run it when executed, so tests can `source` them:

```bash
main() {
  ...
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  main "$@"
fi
```

## Naming

- `UPPER_CASE` for constants and paths fixed at load time: `LEDGER`, `COST_DIR`, `FLAG`.
- `lower_case` for everything else: variables, function names (`install_file`, `usage`).
- Declare function variables with `local`. Several on one line is fine: `local input sid reason`.
- Script file names: `kebab-case.sh`.

## Config directory

Always resolve the Claude Code config dir as:

```bash
"${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
```

Never hardcode `~/.claude`. Tests depend on this to run in a temp dir.

## Quoting and expansion

- Quote every expansion: `"$var"`, `"$(cmd)"`, `"$@"`. The only exception is inside `[[ ]]` patterns, where quoting would turn off the pattern.
- Use `$(...)`, never backticks.
- Use `[ ]` for simple tests. `[[ ]]` is fine where you need pattern or regex matching.
- Use `printf '%s\n' "$data"` to output data. `echo` is only for fixed messages, since it mangles input with `-n`, `-e` or backslashes.
- Give defaults with `${1:-}` and required values with `${2:?message}` so `set -u` stays happy.

## JSON

- Use `jq` for all JSON reading and writing. Do not parse JSON with `grep`, `sed` or `awk`.
- Read optional fields with `// empty` (for shell checks) or `// ""` / `// 0` (for output defaults).
- Pass shell values into jq with `--arg` / `--argjson`, never by putting them inside the filter text. The one exception is a fixed key expression chosen from a closed `case` list (as in `cost-report.sh`).
- Check user files before changing them: `jq empty "$file"`.

## Untrusted input

Hook and status line input comes from Claude Code over stdin. Treat it as untrusted:

- Check values used in paths against an allowlist before using them:

  ```bash
  case "$sid" in
    ''|*[!A-Za-z0-9-]*) echo "cost-log: invalid session_id" >&2; return 0 ;;
  esac
  ```

- Allowlist enum-like values (see caveman modes in `statusline.sh`) and drop anything else.
- Limit how much you read from files you do not own (`head -c 64`) and ignore symlinks where it matters (`[ ! -L "$FLAG" ]`).

## Writing files

- **Atomic writes**: write to a temp file next to the target, then `mv`. Clean up on failure with `trap 'rm -f "$tmp"' EXIT`, and reset with `trap - EXIT` after the `mv`.
- **Backups**: before changing a user file, copy it to `<name>.bak-<timestamp>` (`date +%Y%m%d%H%M%S`). Only back up if the content actually changes (`cmp -s`).
- **Append-only ledger**: `sessions.jsonl` gets one compact JSON object per line (`jq -c ... >> "$LEDGER"`). Never rewrite it.
- **Idempotency**: running an installer or merge twice must leave the same result as running it once. Check before adding (see the `any(...)` check for hooks in `setup.sh`).
- Respect the user's existing config. Do not replace their settings unless asked to (`--force`).

## Error handling

- Errors and warnings go to **stderr**, starting with `error:` or the script name (`cost-log: ...`).
- Exit codes: `0` success, `1` runtime error, `2` bad usage.
- Fail early with a clear message when a dependency is missing:

  ```bash
  command -v jq >/dev/null 2>&1 || { echo "error: jq is required (brew install jq / apt install jq)" >&2; exit 1; }
  ```

- **Hooks never fail the session.** A Claude Code hook must exit 0 even on errors: report to stderr and `return 0`, and wrap the entry point as `main "$@" || true`.
- **The status line must always print something.** `statusline.sh` does not use `set -e`, so one bad field does not blank the whole line. Missing fields just drop their part.
- For commands that may fail and are optional, mark it: `git ... 2>/dev/null || true`.

## Output

- Messages for humans: short, lowercase start, one line per action (`installed: <path>`, `backup: <path>`, `kept: ...`).
- Tabular output: build TSV with jq `@tsv` and align with `column -t -s "$(printf '\t')"`.
- ANSI colors only in the status line, as named variables (`GREEN`, `RESET`), never inline escape codes.
- Comments explain *why* (constraints, Claude Code behavior), not what the next line does.

## Linting

All scripts must pass `shellcheck` with no warnings:

```sh
shellcheck setup.sh statusline.sh cost/*.sh
```

If you need to silence a rule, use `# shellcheck disable=SCxxxx` on the line, with a comment saying why.

## Tests

- Every script has a `tests/<script-name>.bats` file. Behavior changes come with tests.
- Use plain bats, without bats-assert/bats-support, so there are no extra dependencies.
- Call `common_setup` from `tests/test_helper.bash` in `setup()`. It gives each test its own `HOME` and `CLAUDE_CONFIG_DIR`. Tests must never touch the real `~/.claude`.
- Run scripts as `bash "$SCRIPT"` and feed stdin with `<<<`.
- Test names describe the behavior: `@test "resumed session counts only its last row"`.
- Cover the error paths (bad input, missing files, missing dependencies), not just the happy path.

```sh
bats tests/
```
