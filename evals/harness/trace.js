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

  if (value.type === "result") state.sawResult = true;

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

function report(argv) {
  const observationsFile = flag(argv, "--observations");
  const requested = flag(argv, "--status");
  const runner = flag(argv, "--runner");
  const outDir = flag(argv, "--out");
  const error = optionalFlag(argv, "--error");
  const rows = readObservations(observationsFile).map((row) => ({ ...row, outcome: outcome(row) }));
  const scored = requested === "complete" ? scoreRows(rows) : null;
  let status = requested;
  if (requested === "complete" && scored.contaminated) status = "contaminated";
  const metrics = status === "complete" ? scored : {
    contaminated: status === "contaminated",
    contaminated_count: scored ? scored.contaminated_count : rows.filter((row) => row.loaded_without_skill).length,
    true_positive: scored ? scored.true_positive : null,
    false_negative: scored ? scored.false_negative : null,
    false_positive: scored ? scored.false_positive : null,
    true_negative: scored ? scored.true_negative : null,
    precision: null,
    recall: null,
  };
  const body = {
    status,
    runner,
    skill: "feature-docs",
    error: error || null,
    prompts: rows.length,
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
    `Status: ${status}`,
    error ? `Error: ${error}` : "",
    "",
    `Precision: ${formatRate(body.precision)}`,
    `Recall: ${formatRate(body.recall)}`,
    "",
    "Precision is true positives divided by every prompt that loaded the skill only in the with-skill run.",
    "Recall is true positives divided by the should-trigger prompts.",
    "A load is a Skill tool call or a read of the installed SKILL.md in the CLI trace.",
    "Reply text is ignored. A without-skill load makes the comparison invalid, so precision and recall stay unset.",
    "",
    "| Expected | With skill | Without skill | Outcome | Prompt |",
    "| --- | --- | --- | --- | --- |",
  ];
  for (const row of rows) {
    const prompt = String(row.prompt).replace(/\|/g, "/");
    lines.push(
      `| ${row.expected} | ${row.loaded_with_skill ? "loaded" : "not loaded"} | ${row.loaded_without_skill ? "loaded" : "not loaded"} | ${row.outcome} | ${prompt} |`,
    );
  }
  if (rows.length === 0) lines.push("| | | | | no completed prompts |");
  lines.push("");
  fs.writeFileSync(path.join(outDir, "summary.md"), `${lines.filter((line, index) => !(index === 4 && line === "")).join("\n")}\n`);
  process.stdout.write(`status ${status}\n`);
  process.stdout.write(`precision ${formatRate(body.precision)}\n`);
  process.stdout.write(`recall ${formatRate(body.recall)}\n`);
  if (status === "contaminated") process.exit(2);
}

function scoreCommand(file) {
  const rows = readObservations(file);
  process.stdout.write(`${JSON.stringify(scoreRows(rows))}\n`);
}

const command = process.argv[2];
const rest = process.argv.slice(3);
if (command === "skill-loaded") skillLoaded(rest);
else if (command === "score") scoreCommand(rest[0]);
else if (command === "report") report(rest);
else {
  usage();
  process.exit(2);
}
