# ADR-0003: Lean 4 as canonical spec; specialist checkers by claim kind

- **Status:** Accepted
- **Date:** 2026-11-07
- **Deciders:** project owner
- **Cites claims:** none

## Context

No single formal method suits every kind of claim. Precedents (sources in
KT §12 (in the private design notes)):

- **Cedar** (AWS) uses an executable Lean model with proofs, and checks the
  production Rust against that model with differential random testing. Lean
  was chosen for its fast runtime and small trusted kernel.
- **Zelkova** (AWS IAM) encodes policies to SMT and answers questions about
  every possible request, typically in milliseconds.
- AWS used **TLA+** and later added **P** and property-based testing,
  because TLA+ was hard for many engineers to adopt.
- **Cosette** and **Alive2** show that equivalence checking is useful, but
  it is incomplete or bounded.

## Decision

- **Lean 4** holds the reviewed, canonical spec (domain model and rules) and
  is used for unbounded "for all inputs" proofs, such as balancing,
  conservation, reversals, rollback and rounding.
- Specialist checkers are used where they are far more productive:

  | Claim kind | Checker |
  |---|---|
  | `invariant` | Lean 4 |
  | `access` | SMT (Z3 or cvc5, choice still open) |
  | `concurrency` | TLA+ or P (choice still open) |
  | `equivalence` | differential testing against a real DB first; SMT or Cosette-style later |
  | `dataflow` | static analysis (CodeQL-style) ⚠ tooling not chosen |
  | `performance` | measurement protocol (ADR-0002) |
  | implementation (Rust) | Kani / Verus ⚠ unverified details, later |

- When a specialist checker models something that is also in the Lean spec,
  the two must agree on shared definitions. Where both can run, a
  cross-check test confirms that.

## Alternatives considered

- **Lean for everything:** concurrency and policy questions are far cheaper
  in a model checker or an SMT solver, which also produce counterexamples
  automatically.
- **TLA+ as the centre:** weaker for unbounded arithmetic proofs, and not
  executable as a fast model for conformance.
- **Coq/Rocq or Isabelle:** viable, but Lean has the Cedar precedent, a fast
  compiled runtime, and LLMs that write it fairly well.

## Consequences

- Several toolchains to install and maintain over time. Java is needed for
  TLA+. Each install needs the owner's approval first.
- Translating between the Lean spec and the other checkers' models is a
  place where bugs can hide, so it needs tests.

## Revisit when

Phase 2 chooses TLA+ or P and Z3 or cvc5. Each choice gets its own ADR.
