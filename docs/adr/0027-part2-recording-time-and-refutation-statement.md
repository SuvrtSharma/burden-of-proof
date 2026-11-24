# ADR-0027: Part 2 spec: recording time (READING 8), a refutation statement, explicit matches

- **Status:** Accepted
- **Date:** 2026-11-23
- **Deciders:** project owner (approved the spec diff)
- **Cites claims:** none yet (part 2 claims count once checked against the new lock)

## Context

An outside review of the part 2 Lean files (2026-11-23) pointed out that the
spec gave an adjustment its triggering event's arrival index as its effective
date. The paper gives it the activity's `createdAt` (C1 step 7, C2 step 8), and
both implementations do the same (upstream `06bb4ce`). In the model the
arrival index sat on the same scale as business dates, so adjustments could be
read as business days.

The checker can't accept a refutation of `forkSyncMatchesRebuild` without a
spec proposition stating it, and its second kernel couldn't evaluate the
refutation, because Lean compiles a catch-all `match` branch to
`Nat.hasNotBit`, which uses `Nat.land`.

Evidence: `evidence/part2/readings8-2026-11-23/NOTES.md`.

## Decision

1. **READING 8.** `recordedAt log pos` dates an adjustment after the business
   date of every event that has arrived up to and including the triggering
   one, increasing in arrival order. It uses only events that have arrived. A
   first version used the whole log and broke append-only (7,944 violations
   in 119,100 cases); this one has none, like the committed spec.
2. **`forkSyncDisagreesWithRebuild : Prop := ¬ forkSyncMatchesRebuild`**, so a
   refutation can be checked, as part 1 does with `cappedMatchDisagrees`.
3. **No catch-all branches** in `isReversal`, `reversedIds`, `accept` and
   `applyOne`: every constructor is spelled out, with the same meaning.

## Alternatives considered

- **A separate recording timestamp on each event.** More faithful (it allows
  future-dated events) but a larger change to every definition and proof.
  Deferred: step 1's scope is late events.
- **Dating adjustments after every business date in the whole log.** Not
  causal: later arrivals changed earlier adjustments, breaking LR3.

## Consequences

- 50 of 3,432 short sequences change result, all ones that post adjustments;
  disagreements with the rebuild go from 150 to 156.
- A second counterexample, `robustCex`, holds whichever way a fork's balances
  are read. It depends on READING 8. The original Haskell port reproduces it
  exactly; the Java service reproduces its wrong per-activity impact but not
  its balance.
- The owner's lock of 2026-11-23 no longer matches the spec. The owner
  re-creates it; then `forkSyncDisagreesWithRebuild`, `rebuildIgnoresArrival`
  and `paymentConserved` are re-checked. All three pass in a preview against a
  throwaway lock.
- "Same meaning" for the spelled-out matches rests on identical results over
  3,432 sequences, not on a proof.

## Revisit when

- future-dated events come into scope (then a per-event recording time);
- the second kernel evaluates `Nat.land`, if the explicit matches get in the way.
