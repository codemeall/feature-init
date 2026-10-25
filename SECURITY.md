# Security policy

## Reporting a vulnerability

Report a vulnerability privately through GitHub security advisories on this repository:

<https://github.com/codemeall/feature-init/security/advisories/new>

Do not open a public issue for a suspected vulnerability.

GitHub only accepts that form when private vulnerability reporting is enabled for the repository. If the form is unavailable, that setting is off and a maintainer has to enable it before a report can be filed.

Expect a first response within 7 days. After a report is confirmed, the advisory thread will carry the remediation plan. This policy does not promise a remediation date.

## Supported versions

| Version | Supported |
| --- | --- |
| 2.x | Yes |
| 1.x | No |

## What the installer does

The installer is `install.sh`. The npm entry point `bin/feature-docs.js` only starts `bash` on that script and forwards the arguments. Both were read for this policy. Neither makes a network call. Neither downloads code, templates, or instructions. The installer copies local files. It does not read those files as instructions, and it does not follow instructions from fetched content, because it never fetches any.

### What it reads

- The command arguments: `claude`, `cursor`, `codex`, `antigravity`, `all`, `--project`, `--force`, `--uninstall`, and `--remove-legacy`.
- The local directory `skills/feature-docs` next to `install.sh`. That directory is the copy source.
- Whether the destination path already exists.
- Whether a `--project` path is an existing directory. If it is not, the script exits with an error and writes nothing.
- Whether a legacy `feature-init` directory sits beside the destination. The script prints a note when it does. With `--uninstall --remove-legacy`, it deletes that directory.

### What it writes

A global install (no `--project`) writes only these skill directories, creating a missing parent directory when it has to:

- `$HOME/.claude/skills/feature-docs`
- `$HOME/.cursor/skills/feature-docs`
- `$HOME/.codex/skills/feature-docs`
- `$HOME/.gemini/config/skills/feature-docs`

A project install (`--project <repo>`) writes only these skill directories:

- `<repo>/.claude/skills/feature-docs`
- `<repo>/.cursor/skills/feature-docs`
- `<repo>/.codex/skills/feature-docs`
- `<repo>/.agents/skills/feature-docs`

The Antigravity project path is `<repo>/.agents/skills`, not `<repo>/.gemini/config/skills`. The global Antigravity path is `$HOME/.gemini/config/skills`.

The copy sets the executable bit on `scripts/feature-docs.sh` inside the destination. `--force` deletes an existing `feature-docs` directory at that destination and copies a new one. `--uninstall` deletes the `feature-docs` directory for the named agents. `--remove-legacy` is valid only with `--uninstall`, and it also deletes a legacy `feature-init` directory in that same parent. The installer does not write anywhere else.
