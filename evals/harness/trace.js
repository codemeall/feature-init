#!/usr/bin/env node
"use strict";

const fs = require("node:fs");
const path = require("node:path");

const PATH_KEYS = new Set(["path", "file_path", "filePath", "target_file", "uri"]);
const SKILL_INPUT_KEYS = ["command", "skill", "name", "skill_name", "skillName"];

function usage() {
  process.stderr.write(
    [
      "Usage:",
      "  trace.js skill-loaded --trace FILE --skill NAME --skill-dir DIR [--any-install]",
      "  trace.js score OBSERVATIONS.json",
      "  trace.js report --observations FILE --status STATUS --runner NAME --out DIR [--error TEXT]",
      "",
    ].join("\n"),
  );
}

function flag(argv, name) {
  const index = argv.indexOf(name);
  if (index === -1 || index + 1 >= argv.length) {
    process.stderr.write(`missing ${name}\n`);
    usage();
    process.exit(2);
  }
  return argv[index + 1];
}

function optionalFlag(argv, name) {
  const index = argv.indexOf(name);
  if (index === -1 || index + 1 >= argv.length) return "";
  return argv[index + 1];
}

function normalizeSkillName(value) {
  if (typeof value !== "string") return "";
  return value.replace(/^\//, "").trim();
}

function isSkillFile(skill, skillDir, value, anyInstall) {
  if (typeof value !== "string" || value === "") return false;
  const norm = value.replace(/\\/g, "/");
  const dir = skillDir.replace(/\\/g, "/").replace(/\/$/, "");
  return norm === `${dir}/SKILL.md` || (anyInstall && norm.endsWith(`/skills/${skill}/SKILL.md`));
}

function readTrace(file) {
  const text = fs.readFileSync(file, "utf8");
  const lines = text.split(/\r?\n/).filter((line) => line.trim() !== "");
  if (lines.length === 0) return { error: "trace is empty" };
  const events = [];
  for (const line of lines) {
    try {
      events.push(JSON.parse(line));
    } catch {
      events.length = 0;
      break;
    }
  }
  if (events.length === lines.length) return { events };
  try {
    const parsed = JSON.parse(text);
    return { events: Array.isArray(parsed) ? parsed : [parsed] };
  } catch {
    return { error: "trace is not JSON" };
  }
}

function scan(value, skill, skillDir, state) {
  if (Array.isArray(value)) {
    for (const item of value) scan(item, skill, skillDir, state);
    return;
  }
  if (!value || typeof value !== "object") return;

  if (value.type === "result" || value.type === "harness_stop") state.sawResult = true;

  if (value.type === "tool_use" && value.name === "Skill" && value.input && typeof value.input === "object") {
    for (const key of SKILL_INPUT_KEYS) {
      if (normalizeSkillName(value.input[key]) === skill) state.loaded = true;
    }
  }

  if (
    value.type === "tool_use" &&
    (value.name === "Read" || value.name === "ReadFile") &&
    value.input &&
    typeof value.input === "object"
  ) {
    for (const key of PATH_KEYS) {
      if (isSkillFile(skill, skillDir, value.input[key], state.anyInstall)) state.loaded = true;
    }
  }

  if (value.tool_call && typeof value.tool_call === "object") {
    for (const [toolName, call] of Object.entries(value.tool_call)) {
      if (!call || typeof call !== "object") continue;
      const args = call.args && typeof call.args === "object" ? call.args : {};
      if (toolName === "readToolCall") {
        for (const key of PATH_KEYS) {
          if (isSkillFile(skill, skillDir, args[key], state.anyInstall)) state.loaded = true;
        }
      }
      if (String(toolName).toLowerCase().includes("skill")) {
        for (const key of SKILL_INPUT_KEYS) {
          if (normalizeSkillName(args[key]) === skill) state.loaded = true;
        }
      }
    }
  }

  for (const child of Object.values(value)) scan(child, skill, skillDir, state);
}

function skillLoaded(argv) {
  const trace = flag(argv, "--trace");
  const skill = flag(argv, "--skill");
  const skillDir = flag(argv, "--skill-dir");
  const read = readTrace(trace);
  if (read.error) {
    process.stderr.write(`${read.error}\n`);
    process.exit(2);
  }
  const state = { loaded: false, sawResult: false, anyInstall: argv.includes("--any-install") };
  for (const event of read.events) scan(event, skill, skillDir, state);
  if (!state.sawResult) {
    process.stderr.write("trace has no result event\n");
    process.exit(2);
  }
  process.exit(state.loaded ? 0 : 1);
}

function readObservations(file) {
  if (!file || !fs.existsSync(file)) return [];
  const text = fs.readFileSync(file, "utf8").trim();
  if (text === "") return [];
  if (text.startsWith("[")) return JSON.parse(text);
  return text.split(/\n/).filter((line) => line.trim() !== "").map((line) => JSON.parse(line));
}

function scoreRows(rows) {
  let contaminated = 0;
  let truePositive = 0;
  let falseNegative = 0;
  let falsePositive = 0;
  let trueNegative = 0;
  for (const row of rows) {
    if (row.loaded_without_skill === true) {
      contaminated += 1;
      continue;
    }
    const loaded = row.loaded_with_skill === true;
    if (row.expected === "trigger" && loaded) truePositive += 1;
    else if (row.expected === "trigger") falseNegative += 1;
    else if (row.expected === "near_miss" && loaded) falsePositive += 1;
    else if (row.expected === "near_miss") trueNegative += 1;
    else {
      process.stderr.write(`unknown expected value: ${row.expected}\n`);
      process.exit(2);
    }
  }
  const predicted = truePositive + falsePositive;
  const relevant = truePositive + falseNegative;
  return {
    contaminated: contaminated > 0,
    contaminated_count: contaminated,
    true_positive: truePositive,
    false_negative: falseNegative,
    false_positive: falsePositive,
    true_negative: trueNegative,
    precision: contaminated > 0 || predicted === 0 ? null : truePositive / predicted,
    recall: contaminated > 0 || relevant === 0 ? null : truePositive / relevant,
  };
}

function outcome(row) {
  if (row.loaded_without_skill === true) return "contaminated";
  if (row.expected === "trigger" && row.loaded_with_skill === true) return "true_positive";
  if (row.expected === "trigger") return "false_negative";
  if (row.expected === "near_miss" && row.loaded_with_skill === true) return "false_positive";
  return "true_negative";
}

function formatRate(value) {
  if (value === null || value === undefined) return "not computed";
  return value.toFixed(4);
}

function hasBothClasses(rows) {
  let trigger = false;
  let nearMiss = false;
  for (const row of rows) {
    if (row.expected === "trigger") trigger = true;
    else if (row.expected === "near_miss") nearMiss = true;
  }
  return trigger && nearMiss;
}

function report(argv) {
  const observationsFile = flag(argv, "--observations");
  const requested = flag(argv, "--status");
  const runner = flag(argv, "--runner");
  const outDir = flag(argv, "--out");
  const error = optionalFlag(argv, "--error");
  const model = optionalFlag(argv, "--model") || null;
  const minScored = Number(optionalFlag(argv, "--min-scored") || "0.8");
  const maxPrompts = Number(optionalFlag(argv, "--max-prompts") || "0");
  const catalogSize = Number(optionalFlag(argv, "--catalog-size") || "0");
  const rows = readObservations(observationsFile).map((row) => ({ ...row, outcome: row.skipped ? "skipped" : outcome(row) }));
  const scoredRows = rows.filter((row) => !row.skipped);
  const skippedCount = rows.length - scoredRows.length;
  // A cap above the catalog is not a truncation. Omitting the catalog size
  // still treats a positive --max-prompts as a truncated smoke set.
  const truncated = maxPrompts > 0 && (catalogSize <= 0 || rows.length < catalogSize);
  // Zero scored rows stay incomplete even when --min-scored is 0.
  const enough = rows.length > 0 && scoredRows.length > 0 && scoredRows.length / rows.length >= minScored;
  const bothClasses = hasBothClasses(scoredRows);
  let preview = null;
  if (scoredRows.length > 0 && enough) preview = scoreRows(scoredRows);
  let status = requested;
  if (requested === "complete" && preview && preview.contaminated) status = "contaminated";
  else if (requested === "complete" && !enough) status = "incomplete";
  else if (requested === "complete" && !bothClasses) status = "incomplete";
  else if (requested === "complete" && truncated) status = "smoke";
  else if (requested === "complete" && skippedCount > 0) status = "partial";
  const claimRates = status === "complete" || status === "partial";
  const metrics = claimRates ? preview : {
    contaminated: status === "contaminated",
    contaminated_count: preview ? preview.contaminated_count : scoredRows.filter((row) => row.loaded_without_skill).length,
    true_positive: preview ? preview.true_positive : null,
    false_negative: preview ? preview.false_negative : null,
    false_positive: preview ? preview.false_positive : null,
    true_negative: preview ? preview.true_negative : null,
    precision: null,
    recall: null,
  };
  const usage = { input_tokens: 0, output_tokens: 0, cache_read_tokens: 0, runs_with_usage: 0, runs: 0 };
  for (const row of rows) {
    for (const u of [row.usage_with, row.usage_without]) {
      usage.runs += 1;
      if (!u || typeof u !== "object") continue;
      usage.runs_with_usage += 1;
      usage.input_tokens += Number(u.inputTokens ?? u.input_tokens ?? 0);
      usage.output_tokens += Number(u.outputTokens ?? u.output_tokens ?? 0);
      usage.cache_read_tokens += Number(u.cacheReadTokens ?? u.cache_read_input_tokens ?? 0);
    }
  }
  const body = {
    status,
    runner,
    model,
    skill: "feature-docs",
    error: error || null,
    prompts: rows.length,
    scored: scoredRows.length,
    skipped: skippedCount,
    min_scored: minScored,
    usage,
    true_positive: metrics.true_positive,
    false_positive: metrics.false_positive,
    false_negative: metrics.false_negative,
    true_negative: metrics.true_negative,
    contaminated_count: metrics.contaminated_count,
    precision: metrics.precision,
    recall: metrics.recall,
    results: rows,
  };
  fs.mkdirSync(outDir, { recursive: true });
  fs.writeFileSync(path.join(outDir, "results.json"), `${JSON.stringify(body, null, 2)}\n`);
  const lines = [
    "# Harness trigger eval",
    "",
    `Runner: ${runner}`,
    `Model: ${model || "CLI default"}`,
    `Status: ${status}`,
    error ? `Error: ${error}` : "",
    "",
    `Scored: ${scoredRows.length} of ${rows.length} prompts. Skipped: ${skippedCount}.`,
    `Usage: ${usage.input_tokens} input, ${usage.output_tokens} output, ${usage.cache_read_tokens} cache read tokens from ${usage.runs_with_usage} of ${usage.runs} runs. Early stopped runs report no usage. USD cost is not in the trace.`,
    "Skipped prompts (timeout, runner failure, unreadable trace) are left out of precision and recall.",
    `Status incomplete means fewer than ${Math.round(minScored * 100)}% of prompts were scored, a class has no scored row, or nothing scored, so no rates are claimed. Partial means some were skipped and both classes scored.`,
    "",
  ];
  if (status === "smoke") {
    lines.push("Smoke: --max-prompts truncated the prompt set. Precision and recall are not claimed.");
  } else {
    lines.push(`Precision: ${formatRate(body.precision)}`);
    lines.push(`Recall: ${formatRate(body.recall)}`);
  }
  lines.push(
    "",
    "Precision is true positives divided by every prompt that loaded the skill only in the with-skill run.",
    "Recall is true positives divided by the should-trigger prompts.",
    "A load is a Skill tool call or a read of the installed SKILL.md in the CLI trace.",
    "Reply text is ignored. A without-skill load makes the comparison invalid, so precision and recall stay unset.",
    "",
    "| Expected | With skill | Without skill | Outcome | Note | Prompt |",
    "| --- | --- | --- | --- | --- | --- |",
  );
  for (const row of rows) {
    const prompt = String(row.prompt).replace(/\|/g, "/");
    lines.push(
      row.skipped
        ? `| ${row.expected} | | | skipped | ${String(row.skip_reason).replace(/\|/g, "/")} | ${prompt} |`
        : `| ${row.expected} | ${row.loaded_with_skill ? "loaded" : "not loaded"} | ${row.loaded_without_skill ? "loaded" : "not loaded"} | ${row.outcome} | ${[row.early_stop_with, row.early_stop_without].filter(Boolean).join(", ")} | ${prompt} |`,
    );
  }
  if (rows.length === 0) lines.push("| | | | | | no completed prompts |");
  lines.push("");
  fs.writeFileSync(path.join(outDir, "summary.md"), `${lines.filter((line, index) => !(index === 5 && line === "")).join("\n")}\n`);
  process.stdout.write(`status ${status}\n`);
  process.stdout.write(`precision ${formatRate(body.precision)}\n`);
  process.stdout.write(`recall ${formatRate(body.recall)}\n`);
  process.stdout.write(`scored ${scoredRows.length} of ${rows.length}\n`);
  if (status === "contaminated") process.exit(2);
  if (status === "incomplete" && requested === "complete") process.exit(3);
}

function scoreCommand(file) {
  const rows = readObservations(file);
  process.stdout.write(`${JSON.stringify(scoreRows(rows))}\n`);
}

// Counts tool calls the agent started. Cursor emits tool_call started events.
// Claude emits tool_use blocks inside assistant messages.
function countToolCalls(value) {
  if (Array.isArray(value)) return value.reduce((sum, item) => sum + countToolCalls(item), 0);
  if (!value || typeof value !== "object") return 0;
  let count = 0;
  if (value.type === "tool_call" && value.subtype === "started") count += 1;
  if (value.type === "tool_use") count += 1;
  for (const child of Object.values(value)) count += countToolCalls(child);
  return count;
}

// Used by timeout.js to stop a run once the load decision is visible.
function earlyStopReason(events, skill, maxTools) {
  const state = { loaded: false, sawResult: false, anyInstall: true };
  let tools = 0;
  for (const event of events) {
    scan(event, skill, "", state);
    tools += countToolCalls(event);
  }
  if (state.loaded) return "skill_loaded";
  if (maxTools > 0 && tools >= maxTools) return "tool_limit";
  return "";
}

// Prints the harness stop reason and token usage recorded in a trace.
function meta(argv) {
  const read = readTrace(flag(argv, "--trace"));
  const out = { early_stop: null, usage: null };
  for (const event of read.events || []) {
    if (event && event.type === "harness_stop") out.early_stop = event.reason || "stopped";
    if (event && event.type === "result" && event.usage) out.usage = event.usage;
  }
  process.stdout.write(`${JSON.stringify(out)}\n`);
}

module.exports = { readTrace, earlyStopReason };

const command = process.argv[2];
const rest = process.argv.slice(3);
if (require.main !== module) {
  // Loaded as a library.
} else if (command === "skill-loaded") skillLoaded(rest);
else if (command === "meta") meta(rest);
else if (command === "score") scoreCommand(rest[0]);
else if (command === "report") report(rest);
else {
  usage();
  process.exit(2);
}
