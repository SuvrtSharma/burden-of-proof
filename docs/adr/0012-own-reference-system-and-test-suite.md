# ADR-0012: Build our own reference system and test suite; drop the lost-update pattern

- **Status:** Accepted. Amends ADR-0007 and ADR-0009. Amended by ADR-0023: part 2
  checks an external codebase.
- **Date:** 2026-11-07
- **Deciders:** project owner
- **Cites claims:** none

## Context

The KT document assumed an existing production ledger app as the
conformance target and the source of ground-truth bugs (KT §7). The owner has
clarified the following:

- There is **no separate project**. Everything is built from scratch here.
- The KT document described intent, not facts that are fixed. The bug
  patterns are useful as *planted* bugs, but they are not a record of
  production incidents.
- **Pattern 1** (lost update on concurrent writes, i.e. landing the same data
  twice) belongs to a different project and is **dropped** from this one.

## Decision

1. **Reference system:** we build a small, realistic SaaS service in
   `reference/`. It is the code under test for conformance, planted bugs and
   optimisation benchmarks. Its stack is an open question (see
   open-questions Q12).
2. **Our own test suite:** the bug and claim corpora in `corpus/` are made
   here. KT §7 patterns 2–6 become **planted bugs**: each one is introduced
   on purpose, either in the model or in the reference code, and the tools
   must find it.
3. **Pattern 1 is removed** from the corpus and from every done criterion,
   along with the `FOR UPDATE` lost-update example verdict built on it.
   Concurrency as a *kind* of claim stays in scope for a later track
   (ADR-0011).
4. **Phase 1 done criterion (replaces the one in ADR-0009):** the ledger
   rules are proved in Lean; planted patterns 2–4 are found in the model;
   each fixed version is accepted; the cheat tests pass.
5. **Conformance target (amends ADR-0007):** the reference system. The
   mechanism for driving it follows from its stack.
6. A **capability map** ([capability-map.md](../capability-map.md)) records,
   for each SaaS concern, whether Lean 4 could model it, prove it and run it,
   and what it cost. This is the main research output of track 1.

## Alternatives considered

- **Wait for an external app:** there isn't one.
- **Use an open-source SaaS app as the target:** possible later as a second
  target. Its size would hide the early learning.

## Consequences

- We control both the model and the code, so planted bugs are easy to make.
  The risk is building a target that is too convenient. To counter it, the
  reference system follows ordinary SaaS conventions, not proof-friendly
  ones.
- The ledger domain from KT §6 stays as the first model.

## Revisit when

The reference system's stack is chosen, or a real external codebase becomes
available.
