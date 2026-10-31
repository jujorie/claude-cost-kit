# Contributing

Thanks for helping improve claude-cost-kit. This guide covers how to set up, make a change, and get it merged.

## Prerequisites

| Tool | Why | Install |
|---|---|---|
| `bash` 3.2+ | runtime | preinstalled on macOS/Linux |
| `jq` | runtime, JSON handling | `brew install jq` / `apt install jq` |
| `bats` | tests | `brew install bats-core` / `apt install bats` |
| `shellcheck` | lint | `brew install shellcheck` / `apt install shellcheck` |
| `git` | optional at runtime (branch in the ledger), needed for one test | |

## Project layout

```
statusline.sh          status line; saves a cost snapshot per session
cost/cost-log.sh       SessionEnd hook; appends a row to cost/sessions.jsonl
cost/cost-report.sh    sums the ledger by day/project/branch/name/session
setup.sh               installs everything into a Claude Code config dir
tests/*.bats           one bats suite per script
CODESTYLE.md           shell conventions
```

## Development workflow

1. Create a branch from `main`: `git switch -c fix/short-description`.
2. Make the change, following [CODESTYLE.md](CODESTYLE.md).
3. Add or update tests in `tests/<script>.bats` for any behavior change.
4. Run the checks:

   ```sh
   shellcheck setup.sh statusline.sh cost/*.sh
   bats tests/
   ```

5. Commit and open a pull request.

### Trying it without touching your real config

The tests already use a temporary `CLAUDE_CONFIG_DIR`. To try the scripts by hand, install them into a throwaway dir:

```sh
./setup.sh /tmp/claude-test
CLAUDE_CONFIG_DIR=/tmp/claude-test bash statusline.sh <<< '{"session_id":"t1","model":{"display_name":"Opus"},"workspace":{"current_dir":"'"$PWD"'"},"cost":{"total_cost_usd":0.42}}'
CLAUDE_CONFIG_DIR=/tmp/claude-test bash cost/cost-log.sh <<< '{"session_id":"t1","reason":"exit"}'
CLAUDE_CONFIG_DIR=/tmp/claude-test bash cost/cost-report.sh
```

To try it inside Claude Code, run `./setup.sh` against a separate config dir and start Claude Code with `CLAUDE_CONFIG_DIR` pointing at it.

## Guidelines for changes

- **Keep dependencies minimal.** Only `bash`, `jq` and coreutils. Ask in an issue before adding anything new.
- **Stay portable.** Must work on macOS (bash 3.2, BSD tools), Linux, WSL and Git Bash.
- **Never break the user's session.** Hooks exit 0 on errors, and the status line always prints a line.
- **Respect existing config.** `setup.sh` must stay idempotent, back up whatever it changes, and not replace user settings without `--force`.
- **Don't break the ledger format.** `sessions.jsonl` is append-only, and users keep their history. New fields are fine. Renaming or removing fields needs a migration plan in the PR.
- **Update the README** when you change usage, flags or output.

## Commit messages

Use [Conventional Commits](https://www.conventionalcommits.org/):

```
feat(report): add --until filter
fix(statusline): handle missing context_window
test(setup): cover --force with existing hooks
docs: explain CLAUDE_CONFIG_DIR
```

Keep the subject under ~50 characters, in the imperative mood. Use the body to explain *why* when it isn't obvious.

## Pull requests

Before opening a PR, check that:

- [ ] `shellcheck` passes with no warnings
- [ ] `bats tests/` passes
- [ ] New behavior has tests, including error paths
- [ ] README updated if usage or output changed
- [ ] The PR describes what changed, why, and how you tested it (OS + bash version help)

Keep PRs focused: one fix or feature per PR.

## Reporting bugs

Open an issue with:

- OS, `bash --version`, `jq --version` and Claude Code version
- What you ran and what you expected
- The actual output or error
- If relevant, a status line snapshot from `cost/sessions/<id>.json` or a ledger row, **with paths and session names redacted**

## Security

The scripts read JSON from Claude Code and write into your config dir. If you find a way to make them write outside that dir, run arbitrary commands, or corrupt user settings, report it privately to the maintainer instead of opening a public issue.

## License

By contributing, you agree that your contributions are licensed under the [MIT License](LICENSE).
