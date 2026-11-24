# ADR-0026: Part 2 spec review: tie rule, allocation order, early reversals, claim fixes

- **Status:** Accepted (the decisions). The lock itself is the owner's step.
- **Date:** 2026-11-22
- **Deciders:** project owner (answering Q24)
- **Cites claims:** none yet (part 2 claims don't count until the lock)

## Context

Q24 asked the owner to review the part 2 spec draft (`part2/Spec/Retro.lean`)
before locking it. The review (`docs/part2/spec-review-2026-11-22.md`, raw
output in `evidence/part2/spec-review-2026-11-22/`) found:

- the PR 2 fix breaks same-date ties by arrival (`createdAt`), against LR8 and
  READING 1, and its harness never generated a tie (F1);
- the spec hardcodes fee-first allocation, but the code reads the order from
  each payment's spread (`IPF` in 23 fixtures, `FIP` in 2) (F2);
- three claim statements were wrong: `paymentConserved` could not fail (F3),
  `rebuildIgnoresArrival` was false on list order alone (F4), and the compared
  state never checked that reversed events net to zero (F5);
- a same-date tie alone makes the paper's algorithm disagree with the oracle
  (F6), and `isort` equals `mergeSort` on every list tried (F7).

## Decision

1. **Ties: keep `(eff, id)`** (READING 1, LR8 "never by arrival"). The PR 2 fix
   is changed to order ties by activity id, not `createdAt`. Its harness gains
   same-date cases with an oracle that orders ties by id, and PR 2 is
   re-verified before it is opened.
2. **Allocation order is per payment.** `Kind.pay` carries an `Alloc`
   (`feeFirst` for the code's `FIP`, `principalFirst` for its `IPF` with no
   interest owed). LR12 allows either by contract.
3. **A reversal that arrives before its target is rejected** (READING 3, as
   drafted). LR10's arrival-independence is stated only for arrival orders in
   which every event is accepted.
4. **The owner delegated the claim fixes**, asking to keep the spec's behaviour
   and fix the bugs with the real-world choice. All four proposals were taken.
   None changes what the model does:
   - `paymentConserved` now states the allocation rules: never negative, never
     more than is owed, excess only once everything owed is paid, and the
     order respected. The old identity is kept as its first clause.
   - `rebuildIgnoresArrival` compares the balance and each event's effect looked
     up by id (`impactOf`), not the arrival-ordered list.
   - The compared state covers `subjects` (every accepted non-reversal event),
     so reversed events are checked to net to zero (LR9).
   - READINGs 4 to 7 and the `isort` swap stay as written. The tie case becomes a
     second refutation of `forkSyncMatchesRebuild` (`forkSync_ne_rebuild_on_tie`).
     (Wording corrected 2026-11-23; see the amendment.)

## Alternatives considered

- **Ties by arrival**, to match the code: contradicts LR8; rejected.
- **Keep PR 2 as it is** and only correct its description: leaves an LR8
  violation in a fix we would be proposing to the author; rejected.
- **Fee-first only**, with conformance limited to `FIP` payments: would exclude
  23 of the 25 payment fixtures; rejected.
- **Hold early reversals** until the target arrives: more realistic but a larger
  change and harder to prove; deferred (see Revisit).

## Consequences

- The draft is ready for the owner to lock with
  `python -m burden_of_proof.speclock update --project part2` (ADR-0025: only the
  owner creates `part2/spec.lock.json`).
- The claims are stronger: each new statement was shown to reject the cases the
  old one let through (`bite-v2.out.txt`).
- `rebuildIgnoresArrival` is tested (4,203 reorderings) but not yet proved.
- PR 2 must be redone before it can be opened.

## Revisit when

- the owner wants early reversals held rather than rejected;
- interest enters the model (step 2), when `Alloc` must cover interest too;
- conformance finds a spread order the two `Alloc` values can't express.

## Amendment, 2026-11-23

An outside review pointed out that this ADR called the tie case "a second
refutation of the paper". It isn't. The paper orders same-date events by
arrival and doesn't promise otherwise; the disagreement is with our rule LR8.
The theorem refutes `forkSyncMatchesRebuild` as we stated it, with our tie
rule. No decision above changes.
Since then, `rebuildIgnoresArrival` (listed under Consequences as tested but
not proved) has been proved, and `leancheck` accepted it, with its vacuity
witness, against the lock the owner created on 2026-11-23.
