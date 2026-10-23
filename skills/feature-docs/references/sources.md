# Source interpretation

Read this guide when a local tracker includes comments, wayfinding or discovery material, or when Fleet records supply build evidence. Keep conclusions that affect behavior, decisions or acceptance; the tracked docs are not a transcript archive.

## Matt Pocock's local tracker

Read `docs/agents/issue-tracker.md` for the repository's convention. In the local-markdown configuration:

| Input | Use |
|---|---|
| `spec.md` | Problem, intended behavior, implementation/testing decisions and scope |
| `issues/NN-*.md` including `## Comments` | Agreed criteria, blocking edges, later clarification and attributed verification reports |
| `map.md` | Pointers to investigation answers, decisions-so-far and unresolved questions |
| `Type: research`, `prototype` or `grilling`, with `## Answer` | Evidence or conclusions that informed a choice; not implementation delivery |
| `Type: task` or an ordinary delivery ticket | A candidate delivery slice, assessed against its criteria and current evidence |

A discovery ticket's `resolved` state establishes only that an answer was recorded. Read the answer behind the map's pointer. A prototype may establish a design trade-off without proving the production implementation or its performance.

Preserve material conclusions in their owning document: rationale in decisions, a current contract in overview, acceptance evidence in tickets. Cite the source and retain enough context to understand the conclusion after `.scratch` disappears. An optional **Discovery outcomes** table in tickets can link important discovery IDs to those records; omit it when it adds no navigation value. Keep only a decision-rich prototype snippet when prose would lose the essential constraint.

A newly added map, comment or answer is already covered by recursive Markdown source hashing. `stamp` is a baseline, not a guarantee every source claim has been reviewed.

## Fleet records

For a Fleet run, consult `.fleet/runs/<run>/notes.md`, plan decisions, worker reports and the lead's evidence. Prefer actual check output over a summary claim. The lead's acceptance timestamp can establish delivery only for the criteria and scope that were accepted; it does not imply a device, service or production check occurred.

Fleet records outside the configured source directory are not automatically source-hashed. Preserve the material result with its origin/date in the tracked docs. Include a local evidence file explicitly with `--evidence` when continued monitoring of that file is useful.

## Contradictions and missing history

Resolve claims by their kind: inspected code supports implementation, recorded agreement supports intent, and an actual check supports its tested scope. Explicit later acceptance can replace an earlier agreement; the newest timestamp alone does not establish that.

Keep a material unresolved conflict attributed in decisions, linking the relevant ticket or capability. Preserve relevant Proposed choices instead of deleting them because code currently does something else. An observed deviation does not supersede an accepted decision on its own.

When a source disappears, preserve the established record and note the provenance gap if it affects confidence. An issue removed during scratch cleanup may still describe delivered work. Use withdrawn only with cancellation evidence. Record missing reasons as Not recorded and unknown historical dates as Unknown.
