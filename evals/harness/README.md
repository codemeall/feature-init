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

The Cursor runner prefers `cursor-agent`. A generic `agent` command is used only when its help identifies it as Cursor.

`EVAL_TIMEOUT` (or `--timeout`) is the per-run limit in seconds (default 180). This eval is not part of CI.

## Options

```bash
./evals/harness/run-harness-eval.sh --runner cursor --model grok-4.7-high \
  --timeout 180 --stop-after-tools 4 --max-prompts 0 --min-scored 0.8
```

- `--model NAME` (env `HARNESS_MODEL`) is passed to the CLI as `--model`. Both runners support it. The model is written to `results.json` and `summary.md`.
- `--timeout SECS` (env `EVAL_TIMEOUT`). A timeout, a runner failure, or an unreadable trace marks that prompt as skipped with a reason. The run continues.
- `--stop-after-tools N` (env `HARNESS_STOP_AFTER_TOOLS`, default 4, 0 disables). See Early stop.
- `--max-prompts N` (env `HARNESS_MAX_PROMPTS`) runs only N prompts, alternating should-trigger and near-miss, for a cheap smoke run.
- `--min-scored F` (env `HARNESS_MIN_SCORED`, default 0.8). If fewer than this fraction of prompts were scored, the status is `incomplete`, precision and recall stay unset, and the script exits 1.

## Status

- `complete`: every prompt scored.
- `partial`: some prompts were skipped, but at least `--min-scored` of them scored. Rates use scored prompts only.
- `incomplete`: too few prompts scored, or the run stopped on an error. No rates.
- `contaminated`: the skill loaded in a without-skill run. No rates.

The summary shows scored and skipped counts, each skip reason, and token usage summed from the CLI `result` events. The CLIs do not report USD cost in the trace, so cost has to be read from the provider dashboard.

## Isolation

Each run (with and without the skill) gets its own fresh, empty git workspace in a temporary root outside the repository. Prompts are held in memory, so no eval file (`triggers.json`, a prompt list, or the harness scripts) sits in or next to the workspace. The with-skill workspace gets only `feature-docs`, installed at project scope.

The Cursor runner always starts the CLI with an empty temporary `HOME`, so global plugins, skills, rules, and chats under the real `~/.cursor` are not visible. Login is carried over in one of two ways:

- `CURSOR_API_KEY` in the environment, if set. Nothing is copied.
- Otherwise only `${XDG_CONFIG_HOME:-~/.config}/cursor/auth.json` is copied into the temporary `HOME` with mode 0600. It is removed with that `HOME` when the run ends, including on timeout.

The Claude runner already used a temporary `HOME` and `CLAUDE_CONFIG_DIR` that receive only the credentials file.

This is not a sandbox. The agent runs as your user and could still read any absolute path it guesses, such as the repository clone. Keep the clone outside the temporary directory if you want it harder to stumble on, and read the without-skill control: a load there marks the run contaminated.

## Early stop

By default a run ends as soon as the trace shows a `feature-docs` load (a Skill call or a read of a `feature-docs/SKILL.md`), or after the agent has started 4 tool calls without one. The supervisor stops the whole process group and appends a `{"type":"harness_stop"}` line, so the partial trace still scores. The reason is kept per run as `early_stop_with` and `early_stop_without`.

Tradeoff: this cuts cost and time a lot, because the agent never goes on to do the task. A skill loaded only after the Nth tool call is counted as not loaded, which can lower recall. Raise `--stop-after-tools`, or set it to 0, to measure late loads. Early stopped runs have no `result` event, so they report no token usage.
The timeout supervisor stops the runner and its child processes together, allows one second for cleanup, then kills any remaining processes. Node is required on both macOS and Linux. Relative `--out` paths are resolved from the directory where the harness was started.

## Runner contract

A runner is an executable with four subcommands:

```text
probe
agent
run --cwd DIR --trace FILE --prompt TEXT
skill-loaded --trace FILE --skill NAME --skill-dir DIR [--any-install]
```

`probe` exits 0 when the CLI and credentials are present, and 3 when they are not. `agent` prints `claude`, `cursor`, `codex`, or `antigravity` so the harness can install that target. `run` writes the CLI's JSONL trace to `--trace` and exits non-zero on failure. `skill-loaded` exits 0 when the trace shows a load, 1 when the trace finished and the skill did not load, and 2 when the trace cannot be read. Exit 2 is not a negative.
Reads must match the selected installation. For the without-skill control, the harness passes `--any-install` so reads from a global or another project installation also invalidate the comparison. Writes and searches never count as loads.

Pass a path to use your own runner:

```bash
./evals/harness/run-harness-eval.sh --runner /path/to/runner
```
