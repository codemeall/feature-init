---
name: feature-init
description: >-
  Drive the feature-init 3-doc development process (feature.md / plan.md / progress.md) for any
  feature in any repo. Use this skill whenever the user wants to start, plan, document, resume,
  hand off, review, or track a feature or improvement — including phrases like "new feature",
  "start an idea", "scaffold feature docs", "continue where we left off", "resume the feature",
  "record this decision", "update progress", "hand off this work", or when the user points at a
  docs/<feature>/ folder containing feature.md or progress.md. Also use it when a session is
  running out of context and work state must be written down for the next agent or developer.
---

# feature-init — 3-Doc Feature Lifecycle Copilot

One folder per feature: `<repo>/docs/<feature-slug>/` with exactly 3 docs. You are the copilot
that creates them, fills them, keeps them truthful, and uses them to hand work between sessions,
agents, and people. The docs are the memory — not the chat.

| Doc | Holds | Changes when |
|---|---|---|
| `feature.md` | What & why: problem, concept, scope, decisions table, acceptance criteria | Scope or a decision changes |
| `plan.md` | How: contracts to freeze, milestones with exit gates, release checklist, risks | The plan itself changes |
| `progress.md` | Live state: now / done-left / findings / open questions / next / sign-offs | Every state change |

Stages (the `Stage:` field in feature.md): `Idea → Discovery → Design → Build → Released`.

## Step 0 — Detect the mode

Read the situation, then jump to the matching workflow below:

- No `docs/<slug>/` folder yet, user describes a new feature/improvement → **START**
- `feature.md` exists with only "Why" filled, idea approved → **DISCOVERY**
- All 3 docs exist, decisions not all Accepted → **DESIGN / REVIEW**
- Decisions Accepted, Stage: Build → **BUILD**
- Session nearing its limit, or user says "hand off" / "wrap up" → **HANDOFF**
- User says "continue" / "resume" / points at an existing feature folder → **RESUME**
- Change to an already-built feature → small fix: no docs, just do it; real change: add a
  decision row + plan item to that feature's existing docs (never a new folder).

## START — new feature

1. Scaffold. Prefer the bundled script; fall back to manual copy if it can't run:
   `scripts/new-feature.sh <repo-path> <feature-slug>` (feature.md only), or
   `mkdir -p <repo>/docs/<slug> && cp assets/templates/feature.md <repo>/docs/<slug>/` then
   replace `<Feature>` with the title and `<YYYY-MM-DD>` with today.
   If the user keeps a master checkout of feature-init (e.g. a sibling folder of the repo),
   use its `templates/` instead of the bundled copies — the master may be newer.
2. Fill **only the Why section** with the user (problem, who, why now). Set `Stage: Idea`.
   Resist filling more — a killed idea should have cost one page.
3. Tell the user: get the "worth investigating?" gate decision, then run DISCOVERY.

## DISCOVERY — investigate before designing

1. Add the other two docs: `scripts/new-feature.sh <repo> <slug> --continue` (or copy
   `plan.md` + `progress.md` from templates the same way).
2. Explore the actual codebase. Every claim that the design will rest on goes into
   `progress.md` → Code-verified findings **with a file citation** (`path/file.ts`) and a
   verdict ✔ confirmed / ⚠️ gap / ❌ assumption corrected. Wrong assumptions you catch here are
   the highest-value output of the whole process — this step is why designs don't collapse in
   week 3.
3. Fill `feature.md` What / Users / Scope (each MVP row cites its code substrate) and draft
   Decisions rows as `Proposed` — never silently decide storage, ingestion, build-vs-reuse, or
   scope cuts. One line of rationale + the alternative rejected.
4. Draft `plan.md`: contracts (data model, API shapes, shared artifacts) marked `Proposed`,
   then milestones, each with an explicit exit gate.

## DESIGN / REVIEW — close decisions

- To review as a fresh agent: read `progress.md` → `feature.md` → `plan.md`, verify the code
  citations are real, challenge each Proposed decision, report issues. Don't edit the docs —
  the owner applies accepted feedback; rejected feedback becomes one line in the decision's
  "Why (alt. rejected)" so it never gets re-litigated.
- Approval = every decision row `Accepted` + contracts frozen + a Sign-offs row in
  `progress.md`. Then set `Stage: Build`. Writing code from a non-Accepted decision is the one
  hard prohibition in this process.

## BUILD — item by item

1. Read `progress.md` "Now" and "Next actions". Do the top item — one item at a time.
2. After each item: tick Done/Left, update "Now", commit the code **and** `progress.md` in the
   same commit (so git history is the audit trail of state).
3. Surprise mid-build (schema won't work, dependency missing)? Stop, add a `Proposed` decision
   row to `feature.md`, get it decided, then continue. Undocumented workarounds are how docs
   rot.
4. Milestone done only when its exit gate in `plan.md` is met; M(n+1) never starts early.

## HANDOFF — before this session ends

Update `progress.md` so the next reader needs nothing else:

- **Now**: stage, milestone, blockers, whether code is committed.
- **Done/Left**: tick reality, not intention.
- **Half-done state** (the critical part): which file, what's wired, what's not, and the
  pattern to copy — e.g. "widget grid: data wiring done for 3 of 6 widgets; next is
  `sources-widget.tsx`; copy the pattern in `installs-widget.tsx`".
- **Next actions**: ordered, concrete, doable without asking questions.

Keep only current state — superseded detail lives in git history. A handoff is good when a
stranger (human or AI) can resume from the file alone.

## RESUME — picking work up

Read in this order: `progress.md` → `feature.md` → `plan.md`. Then confirm the top Next action
with the user (or just do it, if instructed) and enter BUILD. Never re-derive state from chat
history or re-explore code that findings already cover — that's the token waste this process
exists to prevent.

## Rules that keep the docs trustworthy

1. Each fact lives in exactly one doc; cross-reference, never copy.
2. Code-verify every claim — cite `path/file.ts`.
3. Complete beats short: cut filler, never substance. A doc past a few hundred lines signals
   the feature should split, not that the doc should be trimmed.
4. Tables over prose; one-line decision rationale, expand only contested decisions.
5. Absolute dates only (no "yesterday") — docs outlive sessions.

Full process rationale and team workflow: `references/process.md` (read when the user asks
about gates, reviews, or team roles rather than day-to-day doc work).
