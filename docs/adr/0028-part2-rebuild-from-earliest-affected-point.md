# ADR-0028: Part 2: rebuild from the earliest affected point (a meaning-preserving optimisation)

- **Status:** Accepted
- **Date:** 2026-11-24
- **Deciders:** project owner (approved the spec diff)
- **Cites claims:** `Spec.Retro.rebuildFromInsertExact`, `Spec.Retro.rebuildFromRemoveExact`
  (accepted by `leancheck` against the owner's lock, 2026-11-24:
  `evidence/part2/leancheck-2026-11-24-locked/`)

## Context

The project's track asks which optimisations keep their meaning. In part 2,
the paper's fork-and-sync is an optimisation of full reconstruction (its §2.3
calls reconstruction correct "but at high computational cost"), and the checker
has refuted it (ADR-0027). Our fix fell back to the full rebuild, the expensive
baseline. The natural cheaper step is to rebuild only from the earliest point a
change affects. No claim covered it.

## Decision

The spec defines the optimised step and states that it is exact:

- `rebuildFromInsert`: when an event `e` arrives and becomes live, keep the
  effects of everything before its place in business order, start from the
  running balance there (`balanceAt`), and re-apply `e` and what follows.
- `rebuildFromRemove`: when the live event `t` is reversed, keep everything
  before it, start from the balance there, and re-apply what follows it.
- `rebuildFromInsertExact` and `rebuildFromRemoveExact`: each equals the full
  rebuild, balance and every event's effect.

Evidence: `evidence/part2/rebuild-from-earliest-2026-11-24/NOTES.md`. In
short: tested on 54,928 arrival and 27,120 reversal cases first; proved; every
plausible wrong variant fails (including subtracting a reversed event's own
effect locally, wrong in 5,004 cases); and accepted by `leancheck` in a preview
against a throwaway lock.

## Alternatives considered

- **State it about acceptance** (an accepted event becomes live) rather than
  the live set: stronger, but needs a further invariant about reversals' targets.
  Deferred; the claims state the live-set effect as a hypothesis.
- **Fix fork-and-sync instead:** shown earlier to make things worse
  (`evidence/plp/clock-fix-experiment-2026-11-18.*`, kept in the private lab notebook).

## Consequences

- Part 2 now has a proved meaning-preserving optimisation, not only a refuted
  one. The speed half (ADR-0002) is still open: the step re-applies `n − k + 1`
  events instead of `n + 1`, and nothing is measured yet.
- The owner's lock no longer matches the spec; it is re-created, then all seven
  proofs are checked against it.
- Like the full rebuild, the step recomputes effects after the affected point;
  meeting the paper's audit requirement (R2) is left to an implementation.

## Speed, measured 2026-11-24

On Precise Ledger Pro's Haskell port, over 32 workloads
(`evidence/part2/speed-2026-11-24/NOTES.md`), the step equals the full rebuild on
every workload, and is faster than it on all 32 under part 1's strict rule:
from 1.96× to 155.94×, median 11.86×. The gain is largest when late activities
are recent. These figures expire 2027-02-22.

The same run found that the port's fork-and-sync does not finish on workloads
that mix reversals with late activities (15 of 16), down to a four-activity
case that the model of the paper and the Java service also fail to finish.

## Revisit when

- the speed measurement expires (2027-02-22), or their ledger's data structures change;
- interest enters the model, when "nothing before the affected point changes"
  must be re-proved with daily accruals.
