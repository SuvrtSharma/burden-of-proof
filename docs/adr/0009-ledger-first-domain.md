# ADR-0009: Ledger with allocations as the first domain

- **Status:** Accepted, **amended by [ADR-0012](0012-own-reference-system-and-test-suite.md)**.
  There is no external production app; the bug patterns are planted, not
  ground truth; pattern 1 is dropped; the phase-1 done criterion is replaced.
- **Date:** 2026-11-07
- **Deciders:** project owner
- **Cites claims:** none

## Context

The first domain should be rich in "for all inputs" rules, expensive when
wrong, and backed by real bugs, so the tool can be judged against ground
truth instead of invented examples. The owner runs a production ledger app in
which each pattern in KT §7 actually happened.

## Decision

- **Domain:** parties, bills (possibly unpriced), payments, allocations of
  payments to bills, a scope (site or project) on bills and payments, and
  tenants. The full list of operations and rules is in
  KT §6 (in the private design notes).
- **Money is an integer count of minor currency units. Never floats.** If a
  rule rounds, model the rounding exactly (for example half-up, once, on a
  payable total) and prove where it can and can't happen.
- `balance(party)` is **derived, never stored**. There is one definition,
  and every view uses it, which is the fix for bug pattern 3.
- Ordering of writes is deterministic, with ties broken by a unique key
  (bug pattern 4).
- **Ground-truth corpus:** the six bug patterns in KT §7, plus every
  plausible-but-wrong optimisation in KT §2.
- **Phase 1 is done when** patterns 1–4 are rediscovered in the model without
  help, each fixed version is accepted, and the cheat tests pass.

## Alternatives considered

- **An invented toy domain:** there would be no ground truth to measure
  against.
- **Starting with access control:** a narrower set of rules, and better
  suited to SMT (phase 2).

## Consequences

- Pattern 1 (lost update) is a concurrency bug. The Lean model can show the
  rule that breaks, but the interleaving itself is phase-2 work (TLA+/P).
  ⚠ What "rediscovered in the model" means for pattern 1 in phase 1 needs
  confirming.
- The details of the real app aren't needed to start. They are shared later
  for conformance.

## Revisit when

The production app details arrive, or a rule turns out to be ambiguous in
English. Either way, it goes to the owner and does not get resolved by an
agent's interpretation.
