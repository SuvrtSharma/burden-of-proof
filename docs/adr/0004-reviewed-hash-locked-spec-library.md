# ADR-0004: Reviewed, hash-locked spec library

- **Status:** Accepted, **amended by [ADR-0017](0017-lean-check-pipeline-as-built.md)**.
  The statement is a `Prop` definition in the spec, and the proof's type must be exactly
  that constant. The lock also covers `lakefile.toml` and `lean-toolchain`.
- **Date:** 2026-11-07
- **Deciders:** project owner
- **Cites claims:** none

## Context

Lean guarantees that a proof proves its stated theorem. It does **not**
guarantee that the theorem means what the English claim says. The central way
this fails: *an agent proves a subtly different (weaker, vacuous, or
redefined) statement and then reports the original claim as verified.* For
example, it might add a hypothesis that is never satisfiable, redefine
`balance`, or prove the theorem about a helper instead of the real operation.

## Decision

1. `spec/` holds the domain model, the operations and the rules. People
   write it or review it. Agents may **draft** spec changes, but only as a
   proposal for the owner to approve.
2. Every spec file is hash-locked. A lock file records the SHA-256 of each
   spec file, and the check pipeline refuses to run if any hash doesn't match.
   Only the owner updates the lock, as an explicit, reviewed step. Hashes
   are taken over LF bytes, and `.gitattributes` forces `eol=lf`, so a
   Windows CRLF checkout doesn't break the lock.
3. A claim's `statement` must be a **name defined in the spec**, such as
   `Spec.attach_preserves_every_balance`. Proofs live in `proofs/` and prove
   exactly that name.
4. A claim whose statement refers to anything outside the spec is rejected
   (cheat test, ADR-0006).
5. A vacuity guard: every rule with hypotheses has an accompanying check that
   the hypotheses can be satisfied, for example a concrete witness state.
   ⚠ The design of this guard is still to be worked out.

## Alternatives considered

- **Trust agents to state theorems faithfully:** this is exactly the failure
  the project exists to prevent.
- **Code review alone, without hashes:** review doesn't stop an edit made
  later. Hashes make tampering mechanical to detect.

## Consequences

- Spec changes are slower, by design.
- Agents working here must **never** edit `spec/` or the lock file. They
  propose a change instead (see [CLAUDE.md](../../CLAUDE.md)).
- Each new domain needs a human-reviewed spec. This is listed as a limit,
  not hidden.

## Revisit when

A stronger mechanism exists, such as signed spec releases or CI that enforces
branch protection on `spec/`.
