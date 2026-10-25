"use strict";

const { spawn } = require("node:child_process");
const { constants } = require("node:os");

const seconds = Number(process.argv[2]);
const command = process.argv[3];
if (!Number.isFinite(seconds) || seconds <= 0 || !command) {
  process.stderr.write("timeout needs a positive duration and a command\n");
  process.exit(2);
}

// A separate POSIX process group includes the runner and its agent descendants.
// Node is already required by the harness; use the same supervisor on macOS/Linux.
const child = spawn(command, process.argv.slice(4), { detached: true, stdio: "inherit" });
let stopping = false;
const deadline = setTimeout(() => stop("SIGTERM", 124), seconds * 1000);

function signalGroup(signal) {
  if (!child.pid) return;
  try {
    process.kill(-child.pid, signal);
  } catch (error) {
    if (error.code !== "ESRCH") throw error;
  }
}

function stop(signal, status) {
  if (stopping) return;
  stopping = true;
  clearTimeout(deadline);
  signalGroup(signal);
  // Let wrappers clean up temporary credentials, then kill any remaining child,
  // even when the wrapper has already exited or the agent ignored SIGTERM.
  setTimeout(() => {
    signalGroup("SIGKILL");
    process.exit(status);
  }, 1000);
}

process.on("SIGINT", () => stop("SIGINT", 130));
process.on("SIGTERM", () => stop("SIGTERM", 143));
child.on("error", (error) => {
  clearTimeout(deadline);
  process.stderr.write(`${command}: ${error.message}\n`);
  process.exit(error.code === "ENOENT" ? 127 : 126);
});
child.on("exit", (code, signal) => {
  if (stopping) return;
  clearTimeout(deadline);
  // The runner can exit while background descendants remain in its process
  // group. Timeout and signal paths already signal that group. A normal exit
  // must too. Ignore a group that is already gone, and do not replace the
  // runner status when the signal itself fails.
  try {
    signalGroup("SIGTERM");
  } catch {
    // signalGroup ignores ESRCH. Any other error is ignored here on purpose.
  }
  process.exit(code === null ? 128 + constants.signals[signal] : code);
});
