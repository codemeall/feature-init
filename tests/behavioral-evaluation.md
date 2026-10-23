# Behavioral evaluation

The shell suite tests deterministic command behavior. It does not prove that an agent reconciles intent, implementation and rationale correctly.

## Independent exercise

Copy `fixtures/reconciliation/repo/` to an isolated temporary directory. Give a fresh evaluator only that directory, the current skill, and `fixtures/reconciliation/request.md`. Do not give it this rubric, previous findings, or an expected document. The request prohibits test execution and repository-wide setup. Inspect its artifacts after completion.

## Expected facts — evaluator must not see this section beforehand

- Current implementation exports visible rows in order, escapes cells, always uses commas, emits ISO UTC dates, and buffers the complete result.
- Commas are the accepted v1 choice despite earlier research suggesting semicolons. The downstream-import constraint is the recorded reason.
- Workspace-localized dates remain accepted but unimplemented. Code does not authorize changing the requirement.
- No reason for buffering is recorded. A performance benefit must not be invented.
- Ticket 01 is delivered on 2026-10-19. Ticket 02 is partial: date column exists, locale formatting is absent, and memory acceptance is unverified. Ticket 03 is withdrawn on 2026-10-19 for the recorded report-menu reason.
- Existing D1 and D2 retain their identities. Material accepted clarification and test strategy survive, without turning a rejected research option into accepted behavior.
- The worker's 2026-10-19 test report is historical. It is not a current execution or proof of load, browser, or production behavior.
- Both code and test evidence belong in the manifest. Test-file hashes establish freshness, not a passing result.

## Scoring

Score each dimension 0 (missing/wrong), 1 (usable with omissions), or 2 (complete and clear). Require 2 for fidelity, evidence discipline, and retrieval; total at least 11/12. Any invented acceptance/rationale/test success or destructive action fails regardless of score.

| Dimension | Observable outcome |
|---|---|
| Fidelity | Material expected facts above are preserved, including conflict and incomplete work |
| Evidence discipline | Claims identify their support and distinguish implementation, intent, historical checks and unknowns |
| Retrieval | A new reader can answer what exists, why, remaining acceptance and verification limits without scratch |
| History | Existing IDs and dated changes remain usable; no silent rewriting or fabricated delivery date |
| Compactness | Three human docs, short overview, one authoritative place per fact, no copied source dump |
| Repeatability | Check passes, evidence is explicit, and unchanged stamp/check does not alter the record |

## Fresh-session follow-up

After scoring, copy only generated docs, code and tests to a second temporary checkout. Ask another fresh evaluator: “What delimiter/date behavior is accepted and implemented, why, which work remains, and what verification can we rely on?” Its answer must recover these distinctions without local planning files. Then change the implementation content without changing its path and verify that `status` reports evidence drift despite absent scratch.

## Broader manual fixtures before a substantial workflow release

1. Ordinary fully implemented feature with evidence from spec, tickets, comments and dated results.
2. The conflict/partial-delivery fixture above.
3. Same-path code and test edits, then an evidence-file rename.
4. Fresh checkout without scratch or private snapshots.
5. Explicit supersession followed by source-file cleanup and two unchanged syncs: preserve delivered history and stable IDs/dates.
6. Legacy conversion with `M3.1`, a significant Proposed choice and tests not rerun; preserve originals and source uncertainty.
7. Invalid scaffold, missing docs, duplicate IDs, dangling supersession and unsupported manifests; reject safely.

Mechanical fixtures cover the command portions of 3–7. Agent semantic behavior in 1, 2, 5 and 6 requires artifact review; passing shell tests alone is not evidence that those behaviors passed.
