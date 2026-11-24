# ADR-0006: Lean check pipeline with no escape hatches

- **Status:** Accepted, **amended by [ADR-0017](0017-lean-check-pipeline-as-built.md)**.
  The six checks below are not enough: a proof forged under
  `debug.skipKernelTC` passes all of them. Kernel replay is now required.
- **Date:** 2026-11-07
- **Deciders:** project owner
- **Cites claims:** none

## Context

Lean offers several ways to make something *look* proved without actually
proving it: `sorry`, user-declared `axiom`s, `native_decide` (which trusts the
compiler), and `unsafe` / `implemented_by` / `extern` (which can make the
compiled behaviour differ from the logical definition). An agent under
pressure to produce a "verified" status will reach for these.

## Decision

**Toolchain:** install `elan`, pin the Lean version in `lean-toolchain`, and
build with `lake`. Lean runs natively on Windows. **Start without Mathlib.**
Core Lean's `decide`, `omega` and `simp` cover integer and finite reasoning,
and Mathlib is a large download. ⚠ Confirm the current versions and tactic
names at setup time. Installing anything needs the owner's approval first.

**The check, in this order. Any failure rejects the claim:**

1. Every spec file matches its locked hash (ADR-0004).
2. `lake build` succeeds with no errors.
3. The claimed theorem exists, and its statement uses only spec definitions.
4. `#print axioms <theorem>` lists nothing outside `propext`,
   `Classical.choice` and `Quot.sound`. This must be an **allowlist**, never
   a blocklist. It rejects `sorryAx`, user axioms, and `native_decide`. On
   Lean 4.35.0, `native_decide` shows up as an auxiliary axiom named like
   `<thm>._native.native_decide.ax_1_1`, not `Lean.ofReduceBool`, so a
   blocklist keyed on the old name would let it through. This was checked
   on 2026-11-07; see that day's journal entry.
5. No `unsafe`, `implemented_by` or `extern` appears among the theorem's
   transitive dependencies.
6. The result and the artifact hashes are written into the claim record.

**Counterexamples:** a false claim should come back with a counterexample,
not only "unproved". Two sources:

- property-based testing over the executable model. ⚠ The library is
  believed to be *Plausible* (formerly SlimCheck); confirm at setup.
- bounded exhaustive enumeration of small states, using `decide`.

Every counterexample becomes a permanent regression test.

**Cheat-resistance tests (one each, each shown to bite):** `sorry`, a new
axiom, `native_decide`, editing a locked spec file, and a statement that
refers to something outside the spec.

## Alternatives considered

- **Allow `native_decide` for speed:** it adds the whole compiler to the
  trusted base. It may be revisited later for bounded checks only, and then
  with a status of its own.
- **Checking only that `lake build` passes:** `sorry` produces a warning,
  not an error, so the build passes anyway. Confirmed: `lean` exits 0 on a
  file containing `sorry` (Lean 4.35.0, 2026-11-07).

## Consequences

- Some proofs will take longer to write. That cost is accepted.
- The pipeline is the trust boundary, so it needs its own tests.

## Revisit when

Lean changes its axiom-reporting or adds new escape hatches. Re-check this
list on every toolchain bump.
