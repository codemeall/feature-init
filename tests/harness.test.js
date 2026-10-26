"use strict";

const assert = require("node:assert/strict");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const { spawnSync } = require("node:child_process");
const { test } = require("node:test");
const { earlyStopReason, readTrace } = require("../evals/harness/trace.js");

const root = path.resolve(__dirname, "..");
const harness = path.join(root, "evals/harness");
function workspace(t) {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "harness-regression-"));
  t.after(() => fs.rmSync(dir, { recursive: true, force: true }));
  return dir;
}
function loaded(file, skillDir, flags = []) {
  return spawnSync(process.execPath, [path.join(harness, "trace.js"), "skill-loaded",
    "--trace", file, "--skill", "feature-docs", "--skill-dir", skillDir, ...flags], { encoding: "utf8" });
}

test("Cursor loads require a read of the selected installation", (t) => {
  const dir = workspace(t);
  const skillDir = path.join(dir, ".cursor/skills/feature-docs");
  const file = path.join(dir, "trace.jsonl");
  for (const [tool, target, status] of [
    ["readToolCall", path.join(skillDir, "SKILL.md"), 0],
    ["writeToolCall", path.join(skillDir, "SKILL.md"), 1],
    ["searchToolCall", path.join(skillDir, "SKILL.md"), 1],
    ["readToolCall", "/another/project/.cursor/skills/feature-docs/SKILL.md", 1],
  ]) {
    fs.writeFileSync(file, JSON.stringify({ type: "tool_call", tool_call: {
      [tool]: { args: { path: target } },
    } }) + '\n{"type":"result","subtype":"success"}\n');
    const result = loaded(file, skillDir);
    assert.equal(result.status, status, `${tool} ${target}: ${result.stderr}`);
    assert.equal(loaded(file, skillDir, ["--any-install"]).status, tool === "readToolCall" ? 0 : 1);
  }
});

test("Claude reads from a different installation do not count", (t) => {
  const dir = workspace(t);
  const file = path.join(dir, "trace.jsonl");
  fs.writeFileSync(file, JSON.stringify({ type: "tool_use", name: "Read", input: {
    path: "/another/project/.claude/skills/feature-docs/SKILL.md",
  } }) + '\n{"type":"result","subtype":"success"}\n');
  assert.equal(loaded(file, path.join(dir, "selected-install")).status, 1);
  assert.equal(loaded(file, path.join(dir, "selected-install"), ["--any-install"]).status, 0);
});

test("timeout without GNU timeout stops descendants and runs wrapper cleanup", async (t) => {
  const dir = workspace(t);
  const bin = path.join(dir, "bin");
  fs.mkdirSync(bin);
  for (const [name, target] of [["bash", "/bin/bash"], ["node", process.execPath],
    ["sleep", "/bin/sleep"], ["dirname", "/usr/bin/dirname"]]) {
    fs.symlinkSync(target, path.join(bin, name));
  }
  const marker = path.join(dir, "survived");
  const cleanup = path.join(dir, "cleaned");
  const child = path.join(dir, "child.js");
  const wrapper = path.join(dir, "wrapper.sh");
  fs.writeFileSync(child, 'process.on("SIGTERM", () => {}); setTimeout(() => { require("node:fs").writeFileSync(process.argv[2], "survived"); }, 3500);\n');
  fs.writeFileSync(wrapper, 'trap \'printf cleaned > "$CLEANUP"; exit 143\' TERM\n"$TEST_NODE" "$1" "$2" &\nwait\n');
  const result = spawnSync("/bin/bash", ["-c",
    'source "$1"; run_with_timeout 1 bash "$2" "$3" "$4"', "test",
    path.join(harness, "lib.sh"), wrapper, child, marker], {
    env: { ...process.env, PATH: bin, TEST_NODE: process.execPath, CLEANUP: cleanup },
    stdio: "ignore", timeout: 8000,
  });
  assert.equal(result.status, 124, String(result.error || "timeout exit code"));
  await new Promise((resolve) => setTimeout(resolve, 3600));
  assert.equal(fs.existsSync(marker), false, "descendant continued running after timeout");
  assert.equal(fs.existsSync(cleanup), true, "wrapper cleanup was skipped");
});

test("timeout preserves ordinary command exit codes", () => {
  for (const status of [0, 7]) {
    const result = spawnSync("/bin/bash", ["-c", 'source "$1"; run_with_timeout 5 bash -c "$2"',
      "test", path.join(harness, "lib.sh"), `exit ${status}`]);
    assert.equal(result.status, status);
  }
});

test("normal runner exit stops a background child in the process group", async (t) => {
  const dir = workspace(t);
  const bin = path.join(dir, "bin");
  fs.mkdirSync(bin);
  for (const [name, target] of [["bash", "/bin/bash"], ["node", process.execPath],
    ["sleep", "/bin/sleep"], ["dirname", "/usr/bin/dirname"]]) {
    fs.symlinkSync(target, path.join(bin, name));
  }
  const pidFile = path.join(dir, "child.pid");
  let childPid = 0;
  t.after(() => {
    if (!Number.isInteger(childPid) || childPid <= 0) return;
    try {
      process.kill(childPid, "SIGKILL");
    } catch {
      // The child has already exited.
    }
  });
  const runner = path.join(dir, "runner.sh");
  fs.writeFileSync(runner, [
    "#!/bin/bash",
    "\"$TEST_NODE\" -e 'require(\"node:fs\").writeFileSync(process.argv[1], String(process.pid)); setInterval(() => {}, 1000);' \"$1\" </dev/null >/dev/null 2>&1 &",
    "for ((i=0; i<40; i++)); do",
    "  [[ -s \"$1\" ]] && break",
    "  sleep 0.05",
    "done",
    "[[ -s \"$1\" ]] || exit 1",
    "exit 0",
    "",
  ].join("\n"));
  const result = spawnSync("/bin/bash", ["-c",
    "source \"$1\"; run_with_timeout 15 bash \"$2\" \"$3\"", "test",
    path.join(harness, "lib.sh"), runner, pidFile], {
    env: { ...process.env, PATH: bin, TEST_NODE: process.execPath },
    stdio: "ignore",
    timeout: 8000,
  });
  if (fs.existsSync(pidFile)) childPid = Number(fs.readFileSync(pidFile, "utf8"));
  assert.equal(result.status, 0, String(result.error || "runner did not exit normally"));
  const pid = childPid;
  assert.equal(Number.isInteger(pid) && pid > 0, true, "background child did not start");
  let gone = false;
  for (let attempt = 0; attempt < 20; attempt += 1) {
    try {
      process.kill(pid, 0);
    } catch (error) {
      if (error.code === "ESRCH") {
        gone = true;
        break;
      }
      throw error;
    }
    await new Promise((resolve) => setTimeout(resolve, 100));
  }
  assert.equal(gone, true, `background child ${pid} still running after a normal exit`);
});

for (const runner of ["claude", "cursor"]) {
  test(`${runner} timeout removes temporary credentials even if the CLI ignores TERM`, (t) => {
    const dir = workspace(t);
    const bin = path.join(dir, "bin");
    fs.mkdirSync(bin);
    const record = path.join(dir, "credential-dir");
    if (runner === "cursor") fs.writeFileSync(path.join(bin, "agent"), "#!/bin/bash\nexit 99\n", { mode: 0o755 });
    fs.writeFileSync(path.join(bin, runner === "claude" ? "claude" : "cursor-agent"), `#!/usr/bin/env node
const fs = require("node:fs");
fs.writeFileSync(process.env.CLEANUP_RECORD, ${runner === "claude" ? "process.env.CLAUDE_CONFIG_DIR" : "process.env.HOME"});
process.on("SIGTERM", () => {});
setInterval(() => {}, 1000);
`, { mode: 0o755 });
    const result = spawnSync("/bin/bash", ["-c", 'source "$1"; run_with_timeout 3 bash "$2" run --cwd "$3" --trace "$4" --prompt test',
      "test", path.join(harness, "lib.sh"), path.join(harness, "runners", `${runner}.sh`), dir, path.join(dir, "trace.jsonl")], {
      encoding: "utf8", timeout: 10000,
      env: { ...process.env, PATH: `${bin}${path.delimiter}${process.env.PATH}`,
        CLEANUP_RECORD: record, ANTHROPIC_API_KEY: "fixture-only", CURSOR_API_KEY: "fixture-only" },
    });
    assert.equal(result.status, 124, result.stderr);
    const stderrFile = path.join(dir, "trace.jsonl.stderr");
    assert.equal(fs.existsSync(record), true, `stub CLI did not start: ${fs.existsSync(stderrFile) ? fs.readFileSync(stderrFile, "utf8") : result.stderr}`);
    const credentialDir = fs.readFileSync(record, "utf8");
    assert.equal(fs.existsSync(credentialDir), false, "temporary credentials survived timeout");
  });
}

test("Cursor rejects unrelated programs named agent", (t) => {
  const dir = workspace(t);
  for (const [name, target] of [["node", process.execPath], ["dirname", "/usr/bin/dirname"]]) {
    fs.symlinkSync(target, path.join(dir, name));
  }
  const file = path.join(dir, "agent");
  for (const [banner, status] of [["Grok Build TUI", 3], ["Start the Cursor Agent", 0]]) {
    fs.writeFileSync(file, `#!/bin/bash\nprintf '%s\\n' '${banner}'\n`, { mode: 0o755 });
    const result = spawnSync("/bin/bash", [path.join(harness, "runners/cursor.sh"), "probe"], {
      encoding: "utf8", env: { ...process.env, PATH: dir, CURSOR_API_KEY: "fixture-only" },
    });
    assert.equal(result.status, status, result.stdout + result.stderr);
  }
});

for (const contaminated of [false, true]) {
test(`relative output paths work through the Claude runner (contaminated=${contaminated})`, (t) => {
  const dir = workspace(t);
  const temporaryRoot = path.join(dir, "workspaces");
  const temporaryAlias = path.join(dir, "workspace-alias");
  fs.mkdirSync(temporaryRoot);
  fs.symlinkSync(temporaryRoot, temporaryAlias);
  const bin = path.join(dir, "bin");
  fs.mkdirSync(bin);
  fs.writeFileSync(path.join(bin, "claude"), `#!/usr/bin/env node
const fs = require("node:fs"), path = require("node:path");
const file = path.join(process.cwd(), ".claude/skills/feature-docs/SKILL.md");
if (fs.existsSync(file)) console.log(JSON.stringify({type:"tool_use",name:"Read",input:{path:file}}));
else if (process.env.FIXTURE_GLOBAL_SKILL === "1") console.log(JSON.stringify({type:"tool_use",name:"Read",input:{path:"/host/.claude/skills/feature-docs/SKILL.md"}}));
console.log(JSON.stringify({type:"result",subtype:"success"}));
`, { mode: 0o755 });
  const result = spawnSync("/bin/bash", [path.join(harness, "run-harness-eval.sh"),
    "--runner", "claude", "--out", "relative results"], {
    cwd: dir, encoding: "utf8", timeout: 60000,
    env: { ...process.env, TMPDIR: temporaryAlias, PATH: `${bin}${path.delimiter}${process.env.PATH}`,
      ANTHROPIC_API_KEY: "fixture-only-no-network", FIXTURE_GLOBAL_SKILL: contaminated ? "1" : "0" },
  });
  assert.equal(result.status, contaminated ? 2 : 0, result.stderr);
  const report = JSON.parse(fs.readFileSync(path.join(dir, "relative results/results.json"), "utf8"));
  assert.equal(report.status, contaminated ? "contaminated" : "complete");
  if (contaminated) {
    assert.equal(report.precision, null);
    assert.equal(report.recall, null);
    assert.equal(report.contaminated_count, 24);
  } else {
    assert.equal(report.recall, 1);
    assert.equal(report.false_negative, 0);
    assert.equal(report.precision, 0.5);
  }
  assert.equal(report.prompts, 24);
  assert.equal(fs.readdirSync(path.join(dir, "relative results/traces")).filter((f) => f.endsWith(".jsonl")).length, 48);
});
}

// Fake Cursor CLI used by the isolation, model, skip, and early stop tests.
// It never touches the network. FAKE_MODE picks the behavior.
const FAKE_CURSOR = `#!/usr/bin/env node
const fs = require("node:fs"), path = require("node:path");
const args = process.argv.slice(2);
if (args[0] === "status") { console.log("Logged in"); process.exit(0); }
const ws = args[args.indexOf("--workspace") + 1];
const home = process.env.HOME;
const auth = path.join(home, ".config/cursor/auth.json");
const probe = {
  home, cwd: process.cwd(), workspace: ws,
  model: args.includes("--model") ? args[args.indexOf("--model") + 1] : null,
  plugins: fs.existsSync(path.join(home, ".cursor/plugins")),
  auth_mode: fs.existsSync(auth) ? (fs.statSync(auth).mode & 0o777).toString(8) : null,
  auth_entries: fs.existsSync(path.join(home, ".config/cursor")) ? fs.readdirSync(path.join(home, ".config/cursor")) : [],
  home_entries: fs.readdirSync(home).sort(),
  cwd_entries: fs.readdirSync(process.cwd()).sort(),
  readme: fs.readFileSync(path.join(ws, "README.md"), "utf8"),
};
if (process.env.PROBE_LOG) fs.appendFileSync(process.env.PROBE_LOG, JSON.stringify(probe) + "\\n");
const skill = path.join(ws, ".cursor/skills/feature-docs/SKILL.md");
const say = (o) => process.stdout.write(JSON.stringify(o) + "\\n");
const mode = process.env.FAKE_MODE || "normal";
const counter = process.env.FAKE_COUNTER;
let n = 0;
if (counter) { n = fs.existsSync(counter) ? Number(fs.readFileSync(counter, "utf8")) : 0; fs.writeFileSync(counter, String(n + 1)); }
if (mode === "hang-first" && n === 0) setInterval(() => {}, 1000);
else if (mode === "load-then-hang") {
  if (fs.existsSync(skill)) say({type:"tool_call",subtype:"started",tool_call:{readToolCall:{args:{path:skill}}}});
  else for (let i = 0; i < 10; i++) say({type:"tool_call",subtype:"started",tool_call:{lsToolCall:{args:{path:ws}}}});
  setInterval(() => {}, 1000);
} else if (mode === "busy-then-hang") {
  for (let i = 0; i < 10; i++) say({type:"tool_call",subtype:"started",tool_call:{lsToolCall:{args:{path:ws}}}});
  setInterval(() => {}, 1000);
} else if (mode === "foreign-then-tools") {
  say({type:"tool_call",subtype:"started",tool_call:{readToolCall:{args:{path:"/other/project/.cursor/skills/feature-docs/SKILL.md"}}}});
  for (let i = 0; i < 6; i++) say({type:"tool_call",subtype:"started",tool_call:{lsToolCall:{args:{path:ws}}}});
  setInterval(() => {}, 1000);
} else if (mode === "sibling-search") {
  const parent = path.dirname(ws);
  let found = "";
  for (const name of fs.readdirSync(parent)) {
    const candidate = path.join(parent, name, ".cursor", "skills", "feature-docs", "SKILL.md");
    if (fs.existsSync(candidate)) found = candidate;
  }
  say({type:"tool_call",subtype:"started",tool_call:{readToolCall:{args:{path:found || path.join(ws, "README.md")}}}});
  say({type:"result",subtype:"success",usage:{inputTokens:1,outputTokens:1}});
} else if (mode === "other-skill") {
  say({type:"tool_call",subtype:"started",tool_call:{readToolCall:{args:{path:path.join(home, ".cursor/plugins/cache/example/writing-for-agents/SKILL.md")}}}});
  say({type:"tool_call",subtype:"started",tool_call:{globToolCall:{args:{targetDirectory:path.join(home, ".cursor"), globPattern:"**/*"}}}});
  say({type:"tool_call",subtype:"started",tool_call:{skillToolCall:{args:{name:"writing-for-agents"}}}});
  say({type:"result",subtype:"success",usage:{inputTokens:1,outputTokens:1}});
} else {
  if (fs.existsSync(skill)) say({type:"tool_call",subtype:"started",tool_call:{readToolCall:{args:{path:skill}}}});
  say({type:"result",subtype:"success",usage:{inputTokens:10,outputTokens:2}});
}
`;

function fakeCursorEnv(t, extra = {}) {
  const dir = workspace(t);
  const bin = path.join(dir, "bin");
  const realHome = path.join(dir, "real-home");
  fs.mkdirSync(bin);
  fs.mkdirSync(path.join(realHome, ".cursor/plugins/evil"), { recursive: true });
  fs.mkdirSync(path.join(realHome, ".cursor/skills-cursor"), { recursive: true });
  fs.mkdirSync(path.join(realHome, ".config/cursor"), { recursive: true });
  fs.writeFileSync(path.join(realHome, ".config/cursor/auth.json"), '{"accessToken":"fixture"}', { mode: 0o600 });
  fs.writeFileSync(path.join(realHome, ".config/cursor/other.json"), "{}");
  fs.writeFileSync(path.join(bin, "cursor-agent"), FAKE_CURSOR, { mode: 0o755 });
  const env = { ...process.env, PATH: `${bin}${path.delimiter}${process.env.PATH}`, HOME: realHome,
    PROBE_LOG: path.join(dir, "probe.jsonl"), FAKE_COUNTER: path.join(dir, "counter") };
  delete env.CURSOR_API_KEY;
  delete env.XDG_CONFIG_HOME;
  delete env.HARNESS_MODEL;
  Object.assign(env, extra);
  return { dir, realHome, env };
}

function assertHomesRemoved(probeLog) {
  const text = fs.readFileSync(probeLog, "utf8").trim();
  assert.notEqual(text, "", "probe log was empty");
  for (const line of text.split("\n")) {
    const probe = JSON.parse(line);
    assert.equal(fs.existsSync(probe.home), false, `temporary HOME survived: ${probe.home}`);
    assert.equal(fs.existsSync(path.join(probe.home, ".config/cursor/auth.json")), false, `auth copy survived: ${probe.home}`);
  }
}

function runHarness(dir, env, args, timeout = 60000) {
  return spawnSync("/bin/bash", [path.join(harness, "run-harness-eval.sh"), "--runner", "cursor", "--out", path.join(dir, "out"), ...args],
    { cwd: dir, encoding: "utf8", timeout, env });
}

function reportEval(t, rows, args = []) {
  const dir = workspace(t);
  const observations = path.join(dir, "observations.json");
  fs.writeFileSync(observations, JSON.stringify(rows));
  const result = spawnSync(process.execPath, [path.join(harness, "trace.js"), "report",
    "--observations", observations, "--status", "complete", "--runner", "fixture", "--out", dir, ...args],
    { encoding: "utf8" });
  const body = JSON.parse(fs.readFileSync(path.join(dir, "results.json"), "utf8"));
  const summary = fs.readFileSync(path.join(dir, "summary.md"), "utf8");
  return { result, body, summary };
}

test("Cursor runs use an isolated HOME, an empty workspace, only the auth file, and the chosen model", (t) => {
  const { dir, realHome, env } = fakeCursorEnv(t);
  const result = runHarness(dir, env, ["--model", "fixture-model", "--max-prompts", "2"]);
  assert.equal(result.status, 0, result.stderr);
  const probes = fs.readFileSync(env.PROBE_LOG, "utf8").trim().split("\n").map((l) => JSON.parse(l));
  assert.equal(probes.length, 4);
  const workspaces = new Set();
  for (const p of probes) {
    assert.notEqual(p.home, realHome);
    assert.equal(p.plugins, false);
    assert.equal(p.model, "fixture-model");
    assert.equal(p.auth_mode, "600");
    assert.deepEqual(p.auth_entries, ["auth.json"]);
    assert.ok(!p.cwd.startsWith(root) && !p.workspace.startsWith(root), p.cwd);
    assert.ok(!p.workspace.startsWith(dir), "workspace must not sit beside the eval output");
    for (const name of ["triggers.json", "prompts.jsonl", "run-harness-eval.sh", "trace.js"]) {
      assert.ok(!p.cwd_entries.includes(name), name);
    }
    assert.ok(!fs.existsSync(p.home), "temporary HOME and auth copy were not removed");
    workspaces.add(p.workspace);
  }
  assert.equal(workspaces.size, 4, "each run needs a fresh workspace");
  const report = JSON.parse(fs.readFileSync(path.join(dir, "out/results.json"), "utf8"));
  assert.equal(report.model, "fixture-model");
  assert.equal(report.prompts, 2);
  assert.equal(report.scored, 2);
  assert.equal(report.skipped, 0);
  assert.equal(report.status, "smoke");
  assert.equal(report.precision, null);
  assert.equal(report.recall, null);
  const summary = fs.readFileSync(path.join(dir, "out/summary.md"), "utf8");
  assert.match(summary, /Model: fixture-model/);
  assert.match(summary, /Smoke:/);
  assert.doesNotMatch(summary, /^Precision: [0-9]/m);
  assert.doesNotMatch(summary, /^Recall: [0-9]/m);
  assert.deepEqual(report.results.map((r) => r.expected), ["trigger", "near_miss"]);
});

test("HARNESS_MODEL is the model fallback", (t) => {
  const { dir, env } = fakeCursorEnv(t, { HARNESS_MODEL: "env-model" });
  const result = runHarness(dir, env, ["--max-prompts", "2"]);
  assert.equal(result.status, 0, result.stderr);
  const p = JSON.parse(fs.readFileSync(env.PROBE_LOG, "utf8").split("\n")[0]);
  assert.equal(p.model, "env-model");
});

test("a timeout is a skip with a reason, not an aborted run, and too few scored prompts is incomplete", (t) => {
  const { dir, env } = fakeCursorEnv(t, { FAKE_MODE: "hang-first" });
  const result = runHarness(dir, env, ["--timeout", "2", "--max-prompts", "2"]);
  const report = JSON.parse(fs.readFileSync(path.join(dir, "out/results.json"), "utf8"));
  assert.equal(report.prompts, 2);
  assert.equal(report.scored, 1);
  assert.equal(report.skipped, 1);
  assert.equal(report.status, "incomplete");
  assert.equal(report.precision, null);
  assert.equal(report.recall, null);
  const skipped = report.results.find((r) => r.skipped);
  assert.match(skipped.skip_reason, /timeout/);
  assert.equal(result.status, 1, result.stderr);
  assert.match(fs.readFileSync(path.join(dir, "out/summary.md"), "utf8"), /Scored: 1 of 2/);
  assertHomesRemoved(env.PROBE_LOG);
});

test("early stop ends a run at the first skill load, and after N tool calls without one", (t) => {
  for (const [mode, loaded] of [["load-then-hang", true], ["busy-then-hang", false]]) {
    const { dir, env } = fakeCursorEnv(t, { FAKE_MODE: mode });
    const started = Date.now();
    const result = runHarness(dir, env, ["--timeout", "60", "--max-prompts", "2", "--stop-after-tools", "4"]);
    assert.ok(Date.now() - started < 30000, "early stop did not end the run");
    const report = JSON.parse(fs.readFileSync(path.join(dir, "out/results.json"), "utf8"));
    assert.equal(report.skipped, 0, JSON.stringify(report.results));
    assert.equal(report.stop_after_tools, 4);
    assert.match(fs.readFileSync(path.join(dir, "out/summary.md"), "utf8"), /Stop after tools: 4/);
    const trigger = report.results.find((r) => r.expected === "trigger");
    assert.equal(trigger.loaded_with_skill, loaded, mode);
    assert.equal(trigger.loaded_without_skill, false);
    assert.equal(trigger.early_stop_with, loaded ? "skill_loaded" : "tool_limit");
    assert.equal(result.status, 0, result.stderr);
    assertHomesRemoved(env.PROBE_LOG);
  }
});

test("max-prompts truncation is a smoke run and does not claim rates", (t) => {
  const rows = [
    { expected: "trigger", loaded_with_skill: true, loaded_without_skill: false, prompt: "trigger prompt" },
    { expected: "near_miss", loaded_with_skill: false, loaded_without_skill: false, prompt: "near miss prompt" },
  ];
  const { result, body, summary } = reportEval(t, rows, ["--max-prompts", "2", "--catalog-size", "24", "--min-scored", "0.8"]);
  assert.equal(result.status, 0, result.stderr);
  assert.equal(body.status, "smoke");
  assert.equal(body.precision, null);
  assert.equal(body.recall, null);
  assert.match(summary, /Smoke:/);
  assert.doesNotMatch(summary, /^Precision: [0-9]/m);
  assert.doesNotMatch(summary, /^Recall: [0-9]/m);
});

test("a scored set with only one class is incomplete", (t) => {
  const rows = [
    { expected: "trigger", loaded_with_skill: true, loaded_without_skill: false, prompt: "one" },
    { expected: "trigger", loaded_with_skill: false, loaded_without_skill: false, prompt: "two" },
  ];
  const { result, body } = reportEval(t, rows, ["--min-scored", "0"]);
  assert.equal(body.status, "incomplete");
  assert.equal(body.precision, null);
  assert.equal(body.recall, null);
  assert.equal(result.status, 3, result.stderr);
});

test("min-scored 0 with zero scored rows is incomplete, not partial", (t) => {
  const rows = [
    { expected: "trigger", skipped: true, skip_reason: "timeout", prompt: "one" },
    { expected: "near_miss", skipped: true, skip_reason: "timeout", prompt: "two" },
  ];
  const { result, body, summary } = reportEval(t, rows, ["--min-scored", "0"]);
  assert.equal(body.status, "incomplete");
  assert.notEqual(body.status, "partial");
  assert.equal(body.precision, null);
  assert.equal(body.recall, null);
  assert.equal(body.scored, 0);
  assert.equal(result.status, 3, result.stderr);
  assert.match(summary, /Precision: not computed/);
});

test("results record the stop-after-tools value that was used", (t) => {
  const rows = [
    { expected: "trigger", loaded_with_skill: true, loaded_without_skill: false, prompt: "one" },
    { expected: "near_miss", loaded_with_skill: false, loaded_without_skill: false, prompt: "two" },
  ];
  const { result, body, summary } = reportEval(t, rows, ["--stop-after-tools", "4", "--min-scored", "0"]);
  assert.equal(result.status, 0, result.stderr);
  assert.equal(body.status, "complete");
  assert.equal(body.stop_after_tools, 4);
  assert.match(summary, /Stop after tools: 4/);
});

test("a read of a different installation does not end the with-skill run early", () => {
  const selected = "/tmp/ws/.cursor/skills/feature-docs";
  const events = [
    { type: "tool_call", subtype: "started", tool_call: { readToolCall: { args: { path: "/other/project/.cursor/skills/feature-docs/SKILL.md" } } } },
  ];
  for (let i = 0; i < 4; i += 1) {
    events.push({ type: "tool_call", subtype: "started", tool_call: { lsToolCall: { args: { path: "/tmp/ws" } } } });
  }
  assert.equal(earlyStopReason(events, "feature-docs", 4, { anyInstall: false, skillDir: selected }), "tool_limit");
  assert.equal(earlyStopReason(events, "feature-docs", 4, { anyInstall: true, skillDir: selected }), "skill_loaded");
  const selectedRead = [{ type: "tool_call", subtype: "started", tool_call: { readToolCall: { args: { path: `${selected}/SKILL.md` } } } }];
  assert.equal(earlyStopReason(selectedRead, "feature-docs", 4, { anyInstall: false, skillDir: selected }), "skill_loaded");
});

test("harness early stop uses the same install the scorer uses", (t) => {
  const { dir, env } = fakeCursorEnv(t, { FAKE_MODE: "foreign-then-tools" });
  const result = runHarness(dir, env, ["--timeout", "60", "--max-prompts", "1", "--stop-after-tools", "4"]);
  const report = JSON.parse(fs.readFileSync(path.join(dir, "out/results.json"), "utf8"));
  const trigger = report.results.find((r) => r.expected === "trigger");
  assert.equal(trigger.loaded_with_skill, false);
  assert.equal(trigger.early_stop_with, "tool_limit");
  assert.equal(trigger.loaded_without_skill, true);
  assert.equal(trigger.early_stop_without, "skill_loaded");
  assert.equal(report.stop_after_tools, 4);
  assert.equal(result.status, 2, result.stderr);
});

test("detector ignores temp paths, other skills, and directory listings", () => {
  const skillDir = "/tmp/feature-docs-harness.example/ws.ctrl/.cursor/skills/feature-docs";
  const installed = "/tmp/feature-docs-harness.example/ws.treat/.cursor/skills/feature-docs";
  const cases = [
    ["cursor-control-search.jsonl", 1],
    ["cursor-other-skill.jsonl", 1],
    ["cursor-skill-listing.jsonl", 1],
    ["cursor-sibling-skill-read.jsonl", 0],
  ];
  for (const [name, status] of cases) {
    const file = path.join(harness, "testdata", name);
    const result = loaded(file, skillDir, ["--any-install"]);
    assert.equal(result.status, status, `${name}: ${result.stderr}`);
    const events = readTrace(file).events;
    const reason = earlyStopReason(events, "feature-docs", 6, { anyInstall: true, skillDir });
    assert.equal(reason === "skill_loaded", status === 0, name);
  }
  const sibling = path.join(harness, "testdata/cursor-sibling-skill-read.jsonl");
  assert.equal(loaded(sibling, skillDir).status, 1, "a sibling install is not the selected install");
  assert.equal(loaded(sibling, installed).status, 0, "a read of the selected SKILL.md is a load");
});

test("a control run cannot see the skill installed for the other arm", (t) => {
  const { dir, env } = fakeCursorEnv(t, { FAKE_MODE: "sibling-search" });
  const result = runHarness(dir, env, ["--timeout", "30", "--max-prompts", "2", "--stop-after-tools", "4"]);
  const report = JSON.parse(fs.readFileSync(path.join(dir, "out/results.json"), "utf8"));
  assert.equal(report.status, "smoke", result.stderr);
  assert.equal(result.status, 0, result.stderr);
  const probes = fs.readFileSync(env.PROBE_LOG, "utf8").trim().split("\n").map((line) => JSON.parse(line));
  assert.equal(probes.length, 4);
  for (const probe of probes) {
    assert.equal(probe.cwd.includes("feature-docs"), false, probe.cwd);
    assert.equal(probe.home.includes("feature-docs"), false, probe.home);
    assert.equal(probe.readme.includes("feature-docs"), false, probe.readme);
  }
  for (const row of report.results) {
    assert.equal(row.loaded_with_skill, true, row.prompt);
    assert.equal(row.loaded_without_skill, false, row.prompt);
  }
});

test("reading another skill does not contaminate the control arm", (t) => {
  const { dir, env } = fakeCursorEnv(t, { FAKE_MODE: "other-skill" });
  const result = runHarness(dir, env, ["--timeout", "30", "--max-prompts", "2", "--stop-after-tools", "4"]);
  const report = JSON.parse(fs.readFileSync(path.join(dir, "out/results.json"), "utf8"));
  assert.equal(report.status, "smoke", result.stderr);
  assert.notEqual(report.status, "contaminated");
  assert.equal(result.status, 0, result.stderr);
  for (const row of report.results) {
    assert.equal(row.loaded_with_skill, false, row.prompt);
    assert.equal(row.loaded_without_skill, false, row.prompt);
    assert.notEqual(row.early_stop_with, "skill_loaded");
    assert.notEqual(row.early_stop_without, "skill_loaded");
  }
});

for (const runner of ["claude", "cursor"]) {
  test(`${runner} removes the temp home when the agent keeps writing until kill`, (t) => {
    const dir = workspace(t);
    const bin = path.join(dir, "bin");
    fs.mkdirSync(bin);
    const record = path.join(dir, "home-path");
    let recorded = "";
    t.after(() => {
      if (recorded) fs.rmSync(recorded, { recursive: true, force: true });
    });
    fs.writeFileSync(path.join(bin, runner === "claude" ? "claude" : "cursor-agent"), `#!/usr/bin/env node
const fs = require("node:fs");
const path = require("node:path");
const home = process.env.HOME;
fs.writeFileSync(process.env.CLEANUP_RECORD, home);
const cache = path.join(home, ".cursor/plugins/cache");
const write = () => {
  fs.mkdirSync(cache, { recursive: true });
  fs.writeFileSync(path.join(cache, "keep.txt"), "cache");
};
write();
process.on("SIGTERM", () => {});
setInterval(write, 50);
`, { mode: 0o755 });
    const result = spawnSync("/bin/bash", ["-c", 'source "$1"; run_with_timeout 2 bash "$2" run --cwd "$3" --trace "$4" --prompt test',
      "test", path.join(harness, "lib.sh"), path.join(harness, "runners", `${runner}.sh`), dir, path.join(dir, "trace.jsonl")], {
      encoding: "utf8", timeout: 10000,
      env: { ...process.env, PATH: `${bin}${path.delimiter}${process.env.PATH}`,
        CLEANUP_RECORD: record, ANTHROPIC_API_KEY: "fixture-only", CURSOR_API_KEY: "fixture-only" },
    });
    assert.equal(result.status, 124, result.stderr);
    assert.equal(fs.existsSync(record), true, "stub CLI did not start");
    recorded = fs.readFileSync(record, "utf8");
    assert.equal(fs.existsSync(recorded), false, `temporary home survived: ${recorded}`);
    assert.equal(fs.existsSync(path.join(recorded, ".cursor/plugins/cache/keep.txt")), false);
  });
}

test("a full run that clears the floor and both classes still reports rates", (t) => {
  const rows = [
    { expected: "trigger", loaded_with_skill: true, loaded_without_skill: false, prompt: "one" },
    { expected: "trigger", skipped: true, skip_reason: "timeout", prompt: "two" },
    { expected: "near_miss", loaded_with_skill: true, loaded_without_skill: false, prompt: "three" },
    { expected: "near_miss", loaded_with_skill: false, loaded_without_skill: false, prompt: "four" },
  ];
  const { result, body, summary } = reportEval(t, rows, ["--min-scored", "0.5", "--max-prompts", "0", "--catalog-size", "4"]);
  assert.equal(result.status, 0, result.stderr);
  assert.equal(body.status, "partial");
  assert.equal(body.precision, 0.5);
  assert.equal(body.recall, 1);
  assert.match(summary, /Precision: 0\.5000/);
  assert.match(summary, /Recall: 1\.0000/);
});
