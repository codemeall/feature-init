# Harness trigger eval

This runs every prompt in `evals/triggers.json` through a real agent CLI. Each prompt runs once in a temporary project where `feature-docs` is installed, and once in a project where it is not.

A skill load is taken from the CLI trace:

- a `Skill` tool call whose name is `feature-docs`
- a `Read` tool call whose path is that install's `SKILL.md`
- a Cursor `tool_call` that reads the same file, or a skill tool call named `feature-docs`

Reply text is ignored. The run writes `results.json` and `summary.md` with precision, recall, and one row per prompt.

Precision is true positives divided by prompts that loaded the skill only when it was installed. Recall is true positives divided by the should-trigger prompts. If the skill loads when it is not installed, the comparison is invalid and both rates stay unset.

The script does not invent a trace or a score. If the CLI or credentials are missing it prints `SKIP` and exits 0.

```bash
./evals/harness/run-harness-eval.sh --runner claude
./evals/harness/run-harness-eval.sh --runner cursor
```

`EVAL_TIMEOUT` is the per-prompt limit in seconds (default 180). This eval is not part of CI.

## Runner contract

A runner is an executable with four subcommands:

```text
probe
agent
run --cwd DIR --trace FILE --prompt TEXT
skill-loaded --trace FILE --skill NAME --skill-dir DIR
```

`probe` exits 0 when the CLI and credentials are present, and 3 when they are not. `agent` prints `claude`, `cursor`, `codex`, or `antigravity` so the harness can install that target. `run` writes the CLI's JSONL trace to `--trace` and exits non-zero on failure. `skill-loaded` exits 0 when the trace shows a load, 1 when the trace finished and the skill did not load, and 2 when the trace cannot be read. Exit 2 is not a negative.

Pass a path to use your own runner:

```bash
./evals/harness/run-harness-eval.sh --runner /path/to/runner
```
