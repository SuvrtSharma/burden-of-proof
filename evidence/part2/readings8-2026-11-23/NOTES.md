# READING 8 and related spec changes, 2026-11-23 (approved by the owner, ADR-0027)

Raw files here. Lean 4.35.0. "Committed" means the spec at HEAD d060616/9d0629d
(the one the owner locked on 2026-11-23); "proposed" means the working tree.

## What the proposal changes (`git diff -- part2/Spec`)

1. **READING 8**, `recordedAt`: an adjustment's effective date is the triggering
   event's recording time, placed after the business date of every event that
   has **arrived so far**, increasing in arrival order. The paper passes
   `a.createdAt` (C1 step 7) and `r.createdAt` (C2 step 8); both
   implementations pass the activity's `createdAt` (Haskell `Service.hs` lines
   147–152 and 301–303; Java `LedgerService.java` lines 175 and 214, upstream
   `06bb4ce`). The committed spec used the bare arrival index, on the same
   scale as business dates.
2. **`forkSyncDisagreesWithRebuild`**: the refutation as a spec proposition,
   so `leancheck` can accept it (part 1 does the same with
   `cappedMatchDisagrees`).
3. **Catch-all `match` branches spelled out** in `isReversal`, `reversedIds`,
   `accept` and `applyOne`. Lean compiles a catch-all to `Nat.hasNotBit`, which
   uses `Nat.land`; the checker's second kernel rejected the refutation with
   `con-leche: not implemented yet: unsupported Nat.div/mod environment
   (Nat.land) [at def Nat.land, fold position 349] (--verified)`. Evidence the
   meaning is unchanged: on all 3,432 sequences, `fingerprint-after.txt` before
   and after the rewrite is byte-identical (checked with `cmp`, recorded for
   the earlier non-causal run as `fingerprint-after-explicit-matches-noncausal.txt`).
   This is a bounded test, not a proof of equality. Side effect: `isReversal`
   and `forkSync` no longer depend on `propext`.

## A regression caught and fixed

The first version of `recordedAt` took the latest date over the **whole** log,
later arrivals included. `appendonly.lean` checks LR3 (the ledger before an
event is a prefix of the ledger after it) over 119,100 sequence-and-next-event
pairs (`appendonly.out.txt`):

| Spec | Append-only violations |
|---|---|
| committed | 0 |
| first proposal (whole-log `recordedAt`) | 7,944 |
| proposed (causal `recordedAt`) | 0 |

Files from the first proposal are kept with a `-noncausal` suffix.

## Effect on results (`comparison.txt`, `fingerprint-*.txt`, `explore-*.txt`)

Over 3,432 sequences of up to three events: 50 results change, all in runs
that post adjustments. 22 were wrong and now agree with the rebuild; 28 were
right and now disagree. Disagreements: 150 → 156. Runs ending with a negative
fee or excess: 42 → 50 (16 become negative, 8 stop). Explore.lean's counts:
150 / 893 / 58 → 156 / 891 / 54. On these short sequences the causal and
whole-log versions give identical results; they differ only when more events
arrive, which `appendonly.lean` tests.

## Against the code (`code-check-original-haskell.txt`, `code-check-original-java.log.gz`)

Original upstream code (`06bb4ce`), arrival order against an on-time run of
the same engine:

- Smallest case that flips to **disagree** (pay 5 on day 1, fee 3 on day 0,
  pay 5 on day 1): the Haskell port's result equals the proposed spec's
  **exactly** (fee −3, excess 4, and every per-event value).
- Smallest case that flips to **agree** (pay 5 on day 2, fee 3 on day 0, fee 3
  on day 1): the port still disagrees, and its final balance (excess −1)
  equals the **committed** spec's; its per-event values match neither. There
  the port's late fee consumes excess (impact excess −3), the netting of
  review finding F8 that the spec doesn't model, so this case doesn't isolate
  the date mapping.
- **Reading-robust case** (pay 5 on day 1, fee 3 on day 0, pay 5 on day 2;
  `Proofs.Retro.robustCex`): the Haskell port gives exactly the model's state
  (fee −3, excess 4). The Java service gives the same wrong impact for the
  last payment (fee −3, excess 2, against excess 5 on time) but reports the
  on-time balance (fee 0, excess 7), with impacts that don't sum to it.

## Checker

- `leancheck-preview-*.json`: on a scratch copy of the proposal with a
  throwaway lock (not the owner's), `forkSyncDisagreesWithRebuild`,
  `rebuildIgnoresArrival` and `paymentConserved` are all accepted, second
  kernel included. This is a preview: the real verdicts need the owner's lock.
- `refutation-bite.txt`: in a scratch copy, `forkSyncState` replaced by the
  rebuild's state (as if fork-and-sync were correct). All three refutations
  (`cex_disagrees`, `robust_disagrees`, `tie_disagrees`) then fail to build.
