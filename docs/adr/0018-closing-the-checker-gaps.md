# ADR-0018: Closing the checker gaps: vacuity guard, second kernel, CI

- **Status:** Accepted. Amends ADR-0017.
- **Date:** 2026-11-07
- **Deciders:** project owner (asked for the gaps to be closed)
- **Cites claims:** none

## Context

ADR-0017 listed four gaps: no vacuity guard, one kernel only, checker code
not protected, and seven violation codes with no test that bites.

## Decision

1. **Vacuity guard.** If a statement has binders, `leancheck` builds
   `∃ x₁, … ∃ xₙ, True` over all of them, hypotheses included. A theorem
   `<proof>_witness` must prove it, and its type must be definitionally
   equal to the generated proposition [`vacuity_witness_missing`,
   `vacuity_witness_mismatch`]. The witness gets the same axiom and
   escape-hatch checks as the proof. A statement with no binders needs no
   witness. **Refutations are exempt:** when the conclusion is `False` (as
   in `¬ P`), "the hypotheses are unsatisfiable" *is* the claim.
   - Limit: the witness shows the hypotheses can be met, not that they are
     the *right* hypotheses. That still rests on human review.
2. **Second, independent kernel.** After `leanchecker`, the proof and witness
   are exported with `leanexport` and checked from scratch by `con-leche`
   (both ship with Lean 4.35.0) [`second_kernel_failed`]. Measured: about
   5 s to export, about 1 s to check 1260 declarations. The forged
   `skipKernelTC` theorem is rejected by both kernels independently. ⚠
   con-leche's own claims about itself (a "verified" mode with theorems
   about the checker) were not examined.
3. **CI** (`.github/workflows/ci.yml`) runs the whole suite on every push,
   on GitHub's machines, from the pushed commit. That's the defence for
   the checker code (`tools/leancheck`, `burden_of_proof/`), which an agent in the
   same working tree could otherwise edit. **Branch protection on `main`
   (requiring CI to pass) is a repository setting that the owner turns
   on.**
4. **Tests now bite for every code:** `statement_missing`,
   `statement_not_prop`, `proof_not_in_proofs`, `proof_not_theorem`,
   `build_failed` and `proof_module_missing` have fixtures. `unsafe` can't
   be reached: Lean refuses to build a safe theorem that uses an unsafe
   definition, and a test shows it surfaces as `build_failed`.

## Evidence

32 pipeline tests. 19 mutations, each removing one check, and every one
made its tests fail (journal, 2026-11-07).

## Consequences

- Every checked claim now costs one more export and second-kernel run, a
  few seconds.
- Proof authors write a `_witness` theorem for any statement with binders.

## Revisit when

A toolchain bump (re-run the cheat suite), or if con-leche stops shipping
with the toolchain.
