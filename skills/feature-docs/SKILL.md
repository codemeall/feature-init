---
name: feature-docs
description: >-
  Writes, converts, syncs and looks up tracked as-built feature docs (overview, decisions, tickets) in docs/<feature>/feature-docs/. Use when the user says "write the feature docs", "document this feature", "convert these docs", "sync the feature docs", "what did we decide about X", or when a .scratch spec or ticket changed after its docs were written.
---

# feature-docs

Feature docs preserve what a feature does, why choices were made, and what remains unverified for a reader without the original conversation. The local-markdown configuration of Matt Pocock's skills uses `.scratch/<feature>/`; consult `docs/agents/issue-tracker.md` when present rather than assuming every tracker uses local files.

Write three human documents under `docs/<feature>/feature-docs/`:

| File | Owns |
|---|---|
| `overview.md` | User problem, current capabilities, contracts, navigation and verification summary |
| `decisions.md` | Choices, recorded reasons, rejected alternatives and unresolved intent conflicts |
| `tickets.md` | Delivery slices, acceptance criteria, evidence and remaining checks |
| `sources.json` | Script-owned source, document and evidence baselines; never hand-edit |

One fact has one home; other files link to it by decision/ticket ID. Remove template writing instructions from finished docs; retain useful navigation and status legends. Use the local feature slug. The script is `bash scripts/feature-docs.sh`; read `--help` for command syntax. Read `references/example.md` when an evidence row or finished document is unclear.

## Evidence and decisions

**Code inspected** supports only what the opened file/symbol demonstrates. **Test passed** requires an actual result, command, scope and date. **Runtime verified** requires an observed scenario, environment and date. Inherited results name their source and say **not rerun**. A test file is code evidence, not a passing result. Mark unsupported claims **unverified**, with the check still needed.

Acceptance criteria determine suitable evidence: inspection may establish a static contract; a performance limit needs measurement. Source triage labels and discovery `resolved` states are not delivery evidence. Ticket states and decision states are defined in their templates.

Code establishes observed implementation; explicit agreements establish accepted intent. Keep a discrepancy visible until resolved. Record undocumented rationale as **Not recorded** and unknown historical dates as **Unknown**. An observed implementation choice is **Observed**, not automatically **Accepted**. A source's disappearance changes provenance; withdrawal requires evidence of cancellation. Preserve superseded decisions and withdrawn tickets.

## Pick the mode

- Full or partial implementation needs its first record → **WRITE**.
- The user points at existing documentation → **CONVERT**.
- Sources, implementation or evidence changed, or the user requests reconciliation → **SYNC**.
- Before speccing, ticketing or changing a documented feature → **LOOKUP**.

Use the existing feature folder for later changes. A fix affecting no documented claim needs no content edit. When the repo lacks `docs/FEATURES.md`, offer the optional retrieval setup in `references/setup.md` after writing the first record.

## WRITE

1. Read the spec, tickets including comments, and relevant build decisions. For `map.md`, typed discovery tickets, research/prototype answers or Fleet evidence, read `references/sources.md`. Classify inputs before mapping them: an answered research question is not a shipped capability.
2. Run `new <repo> <feature>`. Read implementation and available verification evidence until every delivery criterion has an evidence assessment or an explicit gap. Preserve only durable conclusions from discovery.
3. Fill the templates. Aim for a 300–600-word overview without padding; complex features may need more. Cite repository-relative files actually inspected. Put acceptance detail in tickets and rationale in decisions; overview gaps link to those IDs. Record significant agreed choices and meaningful deviations, not every incidental implementation detail.
4. Run `check <repo> <feature>` and resolve its structural findings. Review the claims yourself: the command cannot establish semantic truth.
5. Run `stamp <repo> <feature> --evidence <file> ...` with the implementation, test or configuration files inspected to support the record. The first version-2 stamp requires a nonempty explicit list; each `--evidence` names one file. Later omission reuses the recorded list; supplying a list replaces it. Source documents are tracked separately. Use `--source <dir>` for a different local source folder, or `--evidence-only` for conversion without one.
6. Report written files, partial/planned work, verification gaps and glossary/ADR candidates. Stamping records reviewed baselines; it does not validate behavior.

## SYNC

1. Run `status <repo> [<feature>]`. Distinguish source, document and evidence drift, missing files, legacy **REVIEW REQUIRED**, and planned/partial reminders. Matching baselines are mechanical checks, not proof of correctness. An explicit reconciliation request or known implementation change still warrants review.
2. Read changed sources and affected evidence, using `diff` for source changes. Reconcile changed claims in their owning files. Comments may revise an agreement; chronology alone does not establish approval. Keep unresolved contradictions attributed. For moved code, verify the replacement path and update citations. Removal alone supplies neither a reason nor cancellation.
3. Reassess affected criteria, including partial/planned tickets. Update implementation and verification independently. A new accepted choice gets a new decision ID; supersede the earlier accepted choice only when replacement is established.
4. Run `check`. Update `Updated:` only when document content changes. Stamp after reconciliation when a baseline changes; supply the complete evidence list if membership changed. With missing local sources, use `--evidence-only` to retain the last source baseline while updating documents/evidence. A source-free conversion remains source-free on later stamps.
5. Report reconciled changes and unresolved gaps. If neither content nor baselines changed, leave dates and stamps untouched. Missing scratch material is not a reason to discard the tracked record.

## CONVERT

1. Read the supplied material and `references/convert.md`. Use one folder per feature; resolve genuinely ambiguous feature boundaries before writing.
2. Run `new`, map content into the three files, and check claims against appropriate evidence. Preserve relevant proposed choices and conflicts. Mark claims the available material cannot settle as unverified.
3. Record origins on the overview's `Source:` line. Run `check`, then stamp with explicit evidence and a continuing local source folder, or `--evidence-only` when none exists.
4. Leave originals in place. Report their paths and any agent pointers needing repointing; remove originals only with authorization.

## LOOKUP

1. Read `docs/FEATURES.md`, or list `docs/*/feature-docs/`, and select the affected feature.
2. Read its overview for context, then decisions before proposing changes. Read tickets for relevant criteria, evidence and unfinished work.
3. Cite decisions in the new spec/ticket: “builds on D3” or “proposes to supersede D5.” Preserve current accepted intent until an approved change replaces it; reconcile the record through SYNC.

## Glossary and ADRs

Find domain conventions through `docs/agents/domain.md`; otherwise check the root glossary and `docs/adr/`. Use established terms. Cite existing ADRs instead of duplicating their reasoning; an ADR remains authoritative for the decision it governs. Flag contradictions rather than silently erasing either source.

Report new domain terms as glossary candidates and cross-feature contracts or conventions as ADR candidates. Keep feature-local records concise; use the repo's existing process for promotion.
