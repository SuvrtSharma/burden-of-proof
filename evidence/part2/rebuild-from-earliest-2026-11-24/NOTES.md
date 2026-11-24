# Rebuild from the earliest affected point, 2026-11-24 (approved by the owner, ADR-0028)

An optimisation of the oracle, and a proof that it keeps its meaning. Lean
4.35.0. Raw files here.

## The claim

A full rebuild re-applies every live event. When one event arrives late, or
one is reversed, nothing before it in business order changes. So a system can
keep the effects and the running balance up to that point and re-apply only
what follows. The spec proposal (`git diff -- part2/Spec`) defines that step
for each case (`rebuildFromInsert`, `rebuildFromRemove`) and states that it
equals the full rebuild, balance and every event's effect:

- `rebuildFromInsertExact`: if `e` becomes a new live event;
- `rebuildFromRemoveExact`: if the arriving event takes the live event `t` out
  of the live set.

## Evidence

- `pretest.lean` / `pretest.out.txt`: tested before proving, on every sequence
  of up to 3 events and every next event. 54,928 arrival cases (17,584 of them
  backdated) and 27,120 reversal cases (14,400 not the last event in business
  order): no failures.
- Proofs: `part2/Proofs/Retro.lean`, section "Rebuild from the earliest
  affected point". Applying a list in two halves equals applying it whole; the
  new business-ordered list is the old one with the event inserted, or removed,
  at that point (using the sort-uniqueness lemmas and the distinct-id facts
  proved earlier).
- Vacuity witnesses on interesting cases: a payment arriving before both
  earlier events (`insE_backdated`), and a reversal of the first event with two
  after it (`remR_not_last`).
- `leancheck-preview-*.json`: on a scratch copy with a throwaway lock (not the
  owner's), both new claims are accepted, and the five claims already accepted
  against the owner's lock still are. Axioms: propext, Classical.choice,
  Quot.sound for the optimisation claims.
- `bite.lean` / `bite.out.txt`: plausible wrong versions fail on the same
  cases.
  - Arrival. Applying the late event at the end as if on time fails on 17,584
    (every backdated case). Putting it one place too late fails on 17,584, one
    place too early on 43,024.
  - Reversal. Keeping the reversed event fails on all 27,120. Restarting one
    event too late (the reversed effect stays in, the next event is skipped)
    also fails on all 27,120.
  - Reversal, done locally: subtracting the reversed event's own effect and
    re-applying nothing after it is right in 22,116 cases but **wrong in
    5,004**. Those are the cases where what follows depends on the balance,
    such as a later payment's allocation. That is why the step re-applies what
    follows.
- `proof-bite.txt`: in a scratch copy, the arrival step mutated to restart one
  event later and the reversal step to keep the reversed event; both proofs
  then fail to build.

## What this does not show

- **Speed.** The step re-applies `n − k + 1` events instead of `n + 1` (`k`
  events before the affected point). That is the saving it offers; nothing has
  been measured.
- **Acceptance.** The hypotheses state the effect on the live set ("`e` becomes
  live", "`t` leaves it"). That an accepted event or reversal has exactly that
  effect is not proved here.
- **Audit (R2).** Like the full rebuild, the step recomputes the effects after
  the affected point. How an implementation records that, rather than
  overwriting entries, is outside the claim.
- **Their code.** This is an optimisation of our oracle. It isn't a claim about
  Precise Ledger Pro, whose fork-and-sync is a different optimisation, and one
  the checker has refuted.
