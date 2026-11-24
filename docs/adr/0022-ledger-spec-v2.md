# ADR-0022: Ledger spec v2 — the owner's review decisions, and proving invariants of reachable states

- **Status:** Accepted (spec text still awaits the owner's lock). Amends ADR-0009.
- **Date:** 2026-11-07
- **Deciders:** project owner (the four decisions below); proofs by the agent
- **Cites claims:** the 14 records in `claims/lean/` (spec_version = 2)

## Context

The owner reviewed spec v1 and found real gaps, with a second review behind it:
- **Advances never applied to later bills.** Pay 100, then bill 80: the bill stayed
  open at 80 while the balance was −20.
- **The spec was looser than the code.** The spec accepted zero and negative
  amounts, even though the API rejected them.
- **No reversal**, and **"oldest" meant creation order**, not bill date.
- **The settlement properties were too weak.** An implementation that allocates
  nothing satisfied both of them.
- **Invariants were stated for arbitrary states** instead of states the ledger can
  actually reach.
- **Isolation between parties wasn't proved.**
- **Exclusions weren't documented**, and the `omega` note wasn't precise.

## Decision

**The owner's four decisions:**
1. **Advances auto-apply** to new bills.
2. **Zero and negative amounts are rejected**, in the spec as well as the code. The
   spec states that it is a deliberately small DIY ledger, and lists everything left
   out.
3. **Whole-payment reversal is included now.**
4. **"Oldest" means bill date**, with ties broken by bill id.

**How the spec is built:**
- The state holds only **facts**: bills, payments, allocations, and reversed flags.
- **What a bill still owes and what a payment has left are computed** from those
  facts, never stored.
- **After every operation, one settlement step runs:** open bills in (date, id)
  order are matched against advances, oldest payment first, by the greedy step
  `matchUp`.

**What is proved.** Fourteen claims, all accepted by the full pipeline (two
kernels, vacuity witnesses):
- **The matching step on its own:**
  - within limits;
  - settles the maximum — total settled = min(total owed, total advances), which
    rules out "allocate nothing";
  - oldest first.
- **Every state `run` can reach**, via one invariant preserved by every
  operation:
  - unique, increasing ids;
  - positive amounts;
  - every allocation links a bill and a payment of the same party;
  - never over-settled, never over-applied;
  - advances always applied;
  - every view of the balance agrees;
  - the cached balance agrees;
  - reversal restores the balance;
  - parties are isolated;
  - (date, id) order.
- **One refutation:** the capped scan.

**What links the proofs to the code:** the compiled model (`ledgermodel`) and
the store share one JSON contract. Conformance compares them on random sequences
that include date ties, reversals (accepted and rejected) and invalid amounts. It
also **counts** what each run exercised (journal 2026-11-07), so that "zero
mismatches" can't come from tests that never reach the new behaviour.

## Consequences

- The store mirrors the spec's matching step (`store.match_up`) and its order
  (`ORDER BY date, id`). The store deletes a reversed payment's allocations,
  where the spec keeps them but stops counting them; every observable value is
  the same, which conformance checks.
- The API adds `date` on bills and `POST /payments/{id}/reverse`.
- Back-dated bills don't move allocations already made. This is documented as
  an exclusion, not a bug.

## Revisit when

The owner wants credit notes, partial reversals, tenants, scopes or unpriced bills.
Each of those is a spec v3 with its own review.
