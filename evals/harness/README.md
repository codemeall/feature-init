# Harness trigger eval

This runs every prompt in `evals/triggers.json` through a real agent CLI. Each prompt runs once in a temporary project where `feature-docs` is installed, and once in a project where it is not.

A load is taken from the CLI trace, and only from the skill under test:

- a `Skill` tool call whose name is `feature-docs`
- a `Read` tool call whose path is that install's `SKILL.md`
- a Cursor `tool_call` that reads the same file, or a skill tool call named `feature-docs`

The with-skill arm matches the selected install. The without-skill arm matches any install of `feature-docs`, so a control agent that opens that `SKILL.md` invalidates the comparison.

These traces do not count as a load:

- reply text
- a path that only contains the string `feature-docs` (including a temp directory name)
- a read of a different skill's `SKILL.md`
- a directory listing, glob, or search that names the file and does not read it

The run writes `results.json` and `summary.md` with precision, recall, and one row per prompt.

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
- `--timeout SECS` (env `EVAL_TIMEOUT`). A timeout, a runner failure, or an unreadable trace marks that prompt as skipped with a reason. The run continues. A skipped control arm skips the with-skill arm for that same prompt.
- `--stop-after-tools N` (env `HARNESS_STOP_AFTER_TOOLS`, default 4, 0 disables). See Early stop.
- `--max-prompts N` (env `HARNESS_MAX_PROMPTS`) runs only N prompts, alternating should-trigger and near-miss, for a cheap smoke run. When that cap truncates the catalog, the status is `smoke` and precision and recall are not claimed.
- `--min-scored F` (env `HARNESS_MIN_SCORED`, default 0.8). If fewer than this fraction of prompts were scored, the status is `incomplete`, precision and recall stay unset, and the script exits 1. `0` still requires at least one scored row.

## Status

- `complete`: every prompt scored, with at least one scored row in each class (should-trigger and should-not-trigger).
- `partial`: some prompts were skipped, at least `--min-scored` of them scored, and both classes have a scored row. Rates use scored prompts only.
- `smoke`: `--max-prompts` truncated the prompt set, and the scored rows would otherwise have been eligible for rates. No rates are claimed.
- `incomplete`: too few prompts scored, one class has no scored row, nothing scored, or the run stopped on an error. No rates.
- `contaminated`: the skill loaded in a without-skill run. No rates.

The summary shows scored and skipped counts, each skip reason, and token usage summed from the CLI `result` events. The CLIs do not report USD cost in the trace, so cost has to be read from the provider dashboard.

## Isolation

Each arm gets its own fresh, empty git workspace in a temporary root outside the repository. The control arm runs first, and its workspace is removed before `feature-docs` is installed for the other arm, so the two workspaces are never on disk together. A skipped control arm skips the with-skill arm for that prompt. Temp directories are named `harness-eval.*`, `harness-cursor-home.*`, and `harness-claude.*`. Those names, and the workspace README, do not contain the skill name. Prompts are held in memory, so no eval file (`triggers.json`, a prompt list, or the harness scripts) sits in or next to the workspace. The with-skill workspace gets only `feature-docs`, installed at project scope.

The Cursor runner always starts the CLI with an empty temporary `HOME`, so global plugins, skills, rules, and chats under the real `~/.cursor` are not visible. Login is carried over in one of two ways:

- `CURSOR_API_KEY` in the environment, if set. Nothing is copied.
- Otherwise only `${XDG_CONFIG_HOME:-~/.config}/cursor/auth.json` is copied into the temporary `HOME` with mode 0600.

The runner records that directory beside the trace. On a normal exit the wrapper deletes its own temp directory and that marker. On timeout and early stop, the supervisor deletes the recorded directory after the process group is dead, which still runs when the agent ignores SIGTERM and keeps writing plugin caches. A kill -9 of the harness process itself can still leave the directory, because the supervisor is gone too.

## Token refresh

`CURSOR_API_KEY` is the preferred way to run evals. With the auth.json copy, a refreshed token is not written back, so run `cursor-agent status` after the first real run to confirm the login still works.

The Claude runner already used a temporary `HOME` and `CLAUDE_CONFIG_DIR` that receive only the credentials file.

This is not a sandbox. The agent runs as your user and could still read any absolute path it guesses, such as the repository clone. Keep the clone outside the temporary directory if you want it harder to stumble on, and read the without-skill control: a load there marks the run contaminated.

## Early stop

By default a run ends as soon as the trace shows a `feature-docs` load (a Skill call or a read of that skill's `SKILL.md`), or after the agent has started 4 tool calls without one. The with-skill arm counts a read of the selected installation only. The without-skill arm counts a read of any installation of `feature-docs`. A listing of a skill directory, or a read of a different skill, does not count and does not stop the run with `skill_loaded`. That is the same rule the scorer uses. The supervisor stops the whole process group and appends a `{"type":"harness_stop"}` line, so the partial trace still scores. The reason is kept per run as `early_stop_with` and `early_stop_without`.

Tradeoff: this cuts cost and time a lot, because the agent never goes on to do the task. A skill loaded only after the Nth tool call is counted as not loaded, which can lower recall. A near-miss prompt whose real load would happen after tool N is scored as not loaded, which can inflate precision. Results at different `--stop-after-tools` values are not comparable. Raise `--stop-after-tools`, or set it to 0, to measure late loads. Early stopped runs have no `result` event, so they report no token usage.

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
Reads must match the selected installation. For the without-skill control, the harness passes `--any-install` so a read of `feature-docs/SKILL.md` from any install also invalidates the comparison. Writes, searches, directory listings, and reads of a different skill never count as loads.

Pass a path to use your own runner:

```bash
./evals/harness/run-harness-eval.sh --runner /path/to/runner
```
