# Part 2 spec review (Q24), 2026-11-22

Review of the draft `part2/Spec/Retro.lean` before it is locked. Every finding
below was checked by a tool run; the raw files are in
`evidence/part2/spec-review-2026-11-22/` (Lean 4.35.0, see `toolchain.txt`).
Nothing here edits the spec: changes are proposals for the owner (ADR-0004).

## Findings

### F1. The PR 2 fix breaks same-date ties by arrival, and its test never had ties

- READING 1 orders by `(eff, id)`. LR8: same-date events are ordered by a
  stated rule, "never by arrival".
- The fix on `suvrt/fix-retroactive-reconciliation` sorts by
  `(effectiveAt, createdAt, activityId)`. `createdAt` is arrival: the harness
  sets it to "one minute per arrival position".
- The harness generates **distinct** business times only, and its oracle is a
  stable sort on `effectiveAt`, so it also breaks ties by arrival
  (`harness-distinct-times.txt`). The "0 of 1,216" result therefore says
  nothing about ties.
- A tie changes the outcome. With a disbursal of 10 (id 2) and a payment of 5
  (id 1) at the same instant, the rebuild gives principal 10 and excess 5, and
  the paper's algorithm gives principal 5 and excess 0 (`review.out.txt`).
- Consequence: PR 2's description ("never on the order they arrived") is not
  true for same-instant events. PR 2 has not been opened.
- **Fixed the same day** (fork commit `53a58db`): ties are ordered by
  `(effectiveAt, activityType, activityId)`. A new harness, `Shuffle.hs`, runs
  every arrival order of 11,992 small event sets with ties (181,016 runs): with
  the arrival tie-break 4,659 sets depend on arrival order, with the fix none do
  (`evidence/plp/shuffle-*-2026-11-22.txt`, kept in the private lab notebook). Java 59 and Haskell 67 tests pass.

### F2. Allocation order: the spec hardcodes fee first, but the code takes it per payment

- READING 2 pays fee, then principal, and the rest is excess.
- The code reads the order from each payment's spread string, matching
  components by first letter (`ComputationalSpread.getSpreadConfig`). Fixtures
  use `IPF` (interest, principal, fee) 23 times and `FIP` twice; the default is
  fee, interest, principal.
- With no interest in step 1, `IPF` pays principal before fee, the opposite of
  the spec. Conformance would disagree on any loan with both owed.
- LR12 allows either ("a contract may put fees first; the order is fixed and
  documented").

### F3. `paymentConserved` cannot fail

The statement `-fee - principal + excess = amount` holds for any formula of the
shape `excess = amount - toFee - toPrincipal`. The same proof goes through for
three absurd allocations: everything to excess, principal before fee, and seven
times the payment to fee (`bite.lean`, exit 0). So it does not bite, and its
proof (2026-11-21) shows nothing about allocation.

### F4. `rebuildIgnoresArrival` is false as written

Two arrival orders of the same two accepted events give the same balance but
different states, because the per-event list follows arrival order (`[1, 2]`
against `[2, 1]`, `review.out.txt`). It fails on list order, not on any ledger
behaviour. `rebuild_balance_perm` (proved) covers the balance only.

### F5. The compared state never checks that reversed events net to zero

`forkSyncState` and `rebuildState` list only live events. Their comment says
"a reversed event's total must be zero, so it isn't listed", but nothing checks
that zero. A run that leaves a residue on a reversed event, offset elsewhere,
would pass. LR9 requires that reversing removes all consequences.

### F6. A same-date tie alone gives a disagreement (with our tie rule)

The tie case in F1 is a second, independent counterexample to
`forkSyncMatchesRebuild`: the paper applies an event dated on the ledger's
latest date at the tail (READING 5, Figure 1), which is arrival order. It
violates our LR8, not anything the paper promises: the paper orders ties by
arrival. (Corrected 2026-11-23 after an outside review; this entry first called
it an LR8 violation by the paper.) The existing refutation uses distinct dates,
so it is not affected.

### F7. `isort` in place of `mergeSort`: equal on everything tried

On all 781 lists of up to four events drawn from five, with tied dates and
duplicate ids, `isort` equals `List.mergeSort` for both comparators the spec
uses (`review.out.txt`). Both are stable. This is a test, not a proof.

### F8. The code applies excess to a later disbursal; the spec does not

Found while testing the tie fix. In the code, a disbursal that meets excess
uses it up inside its own entry: in the same-time case, the disbursal's impact
is principal +5 and excess −5 (`shuffle-before-tiefix-2026-11-22.txt`). The
PR 1 fixture shows the same (disbursal `b`: principal 0, excess −10). READING 2
says disbursals and charges don't consume excess, following LR15, under which
applying unapplied funds is a lifecycle event with its own entries.

This doesn't change any decision above, but conformance will report it on any
loan where excess meets a disbursal. Whether the code's netting is acceptable
is a policy question about the code, not the spec.

### Reviewed and unchanged

READINGs 4 to 7 (C2 excludes the reversal itself; Figure 1 classification;
the `(kind, source, date)` idempotency key; bounded fuel reported as `stuck`)
model the paper as written. The refutation's counterexample uses no reversal
and finishes within fuel, so it does not depend on READING 4 or 7.

READING 3 rejects a reversal that arrives before its target, permanently. LR8
allows "rejected or held, by policy". This is why arrival-order independence
can only hold for orders where each reversal arrives after its target.

## Decisions (owner, 2026-11-22)

Recorded in [ADR-0026](../adr/0026-part2-spec-review-decisions.md):
ties stay `(eff, id)` and PR 2 is fixed to match; allocation order is per
payment; early reversals are rejected; and, delegated by the owner, all four
claim fixes are taken. The evidence files above ran against the spec as of
commit `afd9880`; `bite-v2.lean` runs against the edited draft.
