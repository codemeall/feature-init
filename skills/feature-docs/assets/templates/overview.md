# <Feature>

> Summary: <one sentence saying what this feature does; it is the feature's line in docs/FEATURES.md>
> Feature docs: the tracked, as-built record of this feature. Updated: <YYYY-MM-DD>
> Read order: this file → `decisions.md` → `tickets.md`. Each fact lives in one of the three.
> Source: `<.scratch/feature, or "converted from <paths> on <date>">` (local and untracked; `sources.json` records the last sync)

## Problem

Who had the problem and what it was, from their side.

## Solution

What the feature does for that person, in one paragraph. Use the repo's glossary terms.

## What was built

One row per capability that exists in the code today. Cite the file that proves it, as a path from the repo root in backticks: `status` checks that every such path still exists.

| Capability | Where (`path/file`) | Notes |
|---|---|---|

## How it fits together

The modules, interfaces, data and contracts a later change has to respect. Point at the code; restate only what the code cannot say.

## Testing

What is tested, at which seam, and the command that runs it. List any agreed check that is still outstanding, with the date it was last known to be.

## Out of scope

Deliberately not built, each with its reason.

## Not built yet

Specified or ticketed but absent from the code. Empty when the feature is complete.
