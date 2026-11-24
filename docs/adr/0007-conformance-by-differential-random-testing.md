# ADR-0007: Conformance by differential random testing against an executable model

- **Status:** Accepted, **amended by [ADR-0012](0012-own-reference-system-and-test-suite.md)**.
  The conformance target is our own reference system in `reference/`. How
  the harness drives it follows from that system's stack (still open).
- **Date:** 2026-11-07
- **Deciders:** project owner
- **Cites claims:** none

## Context

Proofs cover the model, not the real code. The gap between the two is where
the production bugs actually happened (KT §7). Cedar closes this gap with
differential random testing between its Lean model and its Rust code.

## Decision

- The Lean spec is **executable**. The same definitions that are proved
  about are compiled with `lake exe` into a driver that reads a JSON sequence
  of operations and prints the resulting state as canonical JSON.
- A harness generates random operation sequences, runs each one through the
  model and through the real code, and **diffs the results exactly**. No
  tolerances, because money is integers.
- Each run records its seed, number of cases and number of mismatches in the
  claim's `conformance` field. Any mismatch is minimised into a regression
  fixture.
- Reports say plainly that conformance **samples** the code. It doesn't
  prove it.
- Planted-bug tests: mutate the model or the code, and conformance must flag
  the mutation.

## Alternatives considered

- **Hand-written example tests only:** they miss the combinations that
  random sequences find.
- **Verifying the real code directly (Kani/Verus):** valuable later, but
  heavy, and tied to one language.

## Consequences

- The model has to stay fast enough to run thousands of sequences. This is
  why Lean was chosen over slower executable specs.
- How the harness drives the target app (as a dependency or subprocess, or
  through ported fixtures) is an open decision.

## Revisit when

The first conformance target is connected. Its mechanism gets its own ADR.
