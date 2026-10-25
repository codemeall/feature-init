"use strict";

const assert = require("node:assert/strict");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const { spawnSync } = require("node:child_process");
const { test } = require("node:test");

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
