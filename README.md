# claude-cost-kit

Status line with session cost, plus a ledger of the cost of every session.

- `statusline.sh`: shows `[CAVEMAN] model | dir | ctx:NN% | $cost` (the badge only if the caveman plugin is on). On each refresh it saves the status line input to `cost/sessions/<session_id>.json`: it is the only place Claude Code exposes `cost.total_cost_usd`.
- `cost/cost-log.sh`: `SessionEnd` hook, appends one row per session to `cost/sessions.jsonl`.
- `cost/cost-report.sh [day|project|branch|name|session] [--since YYYY-MM-DD]`: adds the costs up. Costs are Claude Code's estimates at API list price, not an invoice.

Install (needs `jq`; macOS, Linux, WSL, Git Bash):

    unzip claude-cost-kit.zip && cd claude-cost-kit
    ./setup.sh                 # into ~/.claude (or $CLAUDE_CONFIG_DIR)
    ./setup.sh /other/dir      # into another config dir
    ./setup.sh --force         # also replace a different statusLine

It backs up every file and settings.json it changes (`*.bak-<timestamp>`), and running it again is safe.
Restart Claude Code afterwards.

## Tests

Unit tests use [bats](https://github.com/bats-core/bats-core) (`brew install bats-core`) and run in a temporary `CLAUDE_CONFIG_DIR`, so they never touch `~/.claude`:

    bats tests/

## License

[MIT](LICENSE)
