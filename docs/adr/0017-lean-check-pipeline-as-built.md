# ADR-0017: The Lean check pipeline as built: statements as spec Props, kernel replay required

- **Status:** Accepted. Amends ADR-0004 and ADR-0006. **Amended by
  [ADR-0018](0018-closing-the-checker-gaps.md)**: the vacuity guard, the second kernel, CI and the
  missing bite tests are now in place.
- **Date:** 2026-11-07
- **Deciders:** project owner (approved building the pipeline)
- **Cites claims:** none (this is the tool that will produce them)

## Context

ADR-0006 listed six checks. Building them showed that the list as written
**would accept a false proof**. A file can add a "theorem" of
`∀ a : Int, a = a + 1` with `set_option debug.skipKernelTC true` and a raw
`addDecl`. On Lean 4.35.0:

- `lake build` succeeds;
- `#print axioms` reports that it *does not depend on any axioms*;
- an environment inspection of the compiled module finds nothing wrong.

Only replaying the module through the kernel (`leanchecker`, which ships with
the toolchain) rejects it: *"declaration type mismatch … has type True but
it is expected to have type Spec.falseClaim"*. The fixture is
`tests/fixtures/lean_project/Proofs/Forged.lean`.

ADR-0004 also left open how a proof is tied to the reviewed statement.

## Decision

**Shape of a claim.** The statement is a **`Prop`-valued definition in the
locked spec**, for example `def Spec.conserve : Prop := ∀ a b x : Int, …`.
The proof is a theorem under `Proofs` whose type is **exactly that constant**
(`theorem Proofs.X.t : Spec.conserve`). The meaning lives only in the locked
file, so an agent can't restate it in the proof file.

**The pipeline** (`python -m burden_of_proof.leancheck`). Any failure rejects the
claim. Violation codes are shown in brackets.

1. The spec lock matches. It covers `Spec.lean`, `Spec/**.lean`,
   `lakefile.toml` and `lean-toolchain` [`spec_lock_mismatch`]. The lakefile
   and toolchain are locked because they can pass options to every file.
2. The target's toolchain equals the checker's (otherwise the tool can't
   run).
3. `lake build` succeeds [`build_failed`].
4. `tools/leancheck` (a Lean program) inspects the compiled environment:
   - the statement exists [`statement_missing`], is in a `Spec` module
     [`statement_not_in_spec`], is a `Prop` definition with no universe
     parameters [`statement_not_prop`], and depends only on `Init` and `Spec`
     [`statement_uses_outside_spec`];
   - the proof exists [`proof_missing`], is in a `Proofs` module
     [`proof_not_in_proofs`], is a theorem [`proof_not_theorem`], and its
     type is syntactically the statement constant
     [`proof_statement_mismatch`];
   - its axioms are within the **allowlist** `propext`, `Classical.choice`,
     `Quot.sound` [`disallowed_axiom`]. This catches `sorryAx`, user axioms,
     and `native_decide`'s generated auxiliary axioms;
   - no Spec/Proofs declaration it reaches is `unsafe`, `implemented_by` or
     `extern` [`unsafe`, `implemented_by`, `extern`]. Core Lean is trusted,
     because core uses `extern` everywhere for compiled code.
5. **Kernel replay is required.** `leanchecker` is run on every Spec/Proofs
   module the proof's environment loads [`kernel_replay_failed`].
6. The result records the hashes of the lock file, the proof file and the
   toolchain.

**Replay reuse.** Measured on 2026-11-07, replay costs about 4.9 s **per
module** whatever its size (`--fresh`, which replays core too, took 75 s).
Clean replays are remembered **in memory for one process only**, keyed on
the toolchain plus the SHA-256 of every Spec/Proofs `.olean` in the project.
Failures are never remembered, and results list `replay_reused`. A cache on
disk was rejected because an agent could forge it. With this, the test
suite went from 208 s to 75 s.

## Known gaps (not yet covered, kept visible)

- **No vacuity guard yet:** a spec Prop with impossible hypotheses is
  trivially provable. The spec is reviewed by people, so this rests on
  review until a guard exists (ADR-0004 item 5).
- **The checker is trusted but not locked.** `tools/leancheck` and
  `burden_of_proof/` are protected by git review, not by the spec lock. An agent in
  the same working tree could edit them, so CI on a protected branch is the
  real defence (ADR-0004, "Revisit when").
- **One kernel.** `leanchecker` uses Lean's own kernel. The toolchain also
  ships independent checkers (`leanexport` feeding `nanoda_bin`, and
  `con-leche`/`con-ron`, which state theorems about themselves); wiring a
  second kernel is future work. ⚠ Their details are unverified.
- **Untested violation codes:** `unsafe` (Lean already refuses a safe
  theorem that uses an unsafe constant, so no fixture could be built),
  `statement_missing`, `statement_not_prop`, `proof_not_in_proofs`,
  `proof_not_theorem`, `build_failed` and `proof_module_missing`. These have
  code but no test that is shown to bite yet.
- Spec statements may use only `Init`. `Std` would need an explicit
  decision.

## Consequences

- Claim records (ADR-0005) carry `statement` (the spec Prop), `proof` (the
  theorem) and the proof module.
- Every check costs a few seconds per module, almost all of it kernel
  replay. That is acceptable for CI; agents doing interactive loops should
  check in batches.

## Revisit when

- The toolchain is bumped: re-run the cheat suite, especially the forged and
  `native_decide` fixtures, since escape-hatch names change between
  versions.
- A second kernel is added, or a vacuity guard is designed.
