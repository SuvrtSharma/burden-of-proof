# ADR-0025: Part 2 ledger rules approved; part 2 gets its own Lean project

- **Status:** Accepted
- **Date:** 2026-11-18
- **Deciders:** project owner (approved ledger rules v2, answering Q23)
- **Cites claims:** none yet

## Context

ADR-0024 set the scope of part 2: fixed amounts first, with a full rebuild as
the oracle. The oracle needs rules that come from outside the code under test.
`docs/part2/ledger-rules.md` collects 23 production ledger rules (LR1 to LR23)
from published practice, standards, regulation and case law. The owner
reviewed v1, and every point was applied in v2. The owner then approved v2.

Part 1's spec is locked by `spec.lock.json`, which covers `Spec.lean`,
`Spec/*.lean`, `lakefile.toml` and `lean-toolchain`. Adding a part 2 module to
that library would break the part 1 lock and mix two reviews into one
fingerprint.

## Decision

1. **The approved rules are the source for the part 2 spec.** Any spec
   definition or claim statement cites the rule it encodes (LR number). A rule
   the spec can't express is listed as such, not dropped.
2. **Part 2 is its own Lake project, in `part2/`.**
   - It pins the same Lean toolchain.
   - It has its own `Spec` library, its own `Proofs` library and its own lock,
     `part2/spec.lock.json`, which only the owner creates.
   - The checker runs on it unchanged:
     `python -m burden_of_proof.leancheck --project part2 ...`.
   - Part 1's lock and files stay untouched.
3. **The first spec draft models the paper's algorithms as the paper states
   them (Appendix C), not as the code implements them.** Conformance against
   the Java and Haskell code comes after, and shows where the code and the paper
   differ.
4. **Exploration isn't evidence for a claim.** Running the model on examples
   before any proof (`part2/Explore.lean`) can find candidate counterexamples.
   Each one is reported as unconfirmed until it reproduces against the code
   under test and a Lean refutation is accepted by the checker.

## Alternatives considered

- **Add `Spec/Retro.lean` to the part 1 library:** this breaks the part 1 lock
  and couples two unrelated reviews.
- **Draft the spec from their code:** that defeats the independent oracle the
  owner asked for.

## Consequences

- There are two locks and two Lean projects to keep building, and CI must build
  both once part 2 has proofs.
- Every part 2 claim record names its project, so the checker knows where to
  look.

## Revisit when

- The owner reviews the part 2 spec draft and locks it.
- The interest step (ADR-0024) starts.
