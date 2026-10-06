#!/usr/bin/env node
// npx entry point: runs install.sh from the package, whatever directory npx resolved it to.
const { spawnSync } = require("child_process");
const path = require("path");

const script = path.join(__dirname, "..", "install.sh");
const result = spawnSync("bash", [script, ...process.argv.slice(2)], { stdio: "inherit" });
if (result.error) {
  console.error(`feature-docs: could not run bash (${result.error.message})`);
  process.exit(1);
}
process.exit(result.status ?? 1);
