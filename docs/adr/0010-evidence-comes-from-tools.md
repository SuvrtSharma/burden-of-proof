# ADR-0010: Evidence comes from tools; tests must bite

- **Status:** Accepted
- **Date:** 2026-11-07
- **Deciders:** project owner
- **Cites claims:** none

## Context

The project's thesis is that agents need reliable data and feedback loops,
because otherwise they confidently chase problems that don't exist. That
applies to the agents building this project too. A figure worked out "in the
head", or a test that never fails, is exactly the kind of unreliable feedback
the project is meant to remove.

## Decision

1. **No arithmetic in anybody's head.** Every figure in code, tests, docs and
   commits comes from a tool. An exact-arithmetic helper, and a check that
   evaluates equations written in the docs (`a × b = c`), are early
   deliverables.
2. **Every test is shown to bite.** Break what it protects, watch it fail,
   then restore it. Record that this was done.
3. **Never change an expected value to make a test pass.** First establish
   which side is wrong, the code or the expectation, and say why.
4. **Every counterexample becomes a permanent regression test.**
5. **Sources for external claims.** Anything not checked against a source is
   marked ⚠ unverified.
6. **Honest reporting.** Every report states what wasn't verified, what
   failed and why. "Unproved" is never rounded up to "verified".
7. **Headline metrics:** false acceptances = 0. The rate of true claims that
   weren't proved is reported, not hidden.

## Alternatives considered

None that keep the project credible.

## Consequences

- Work is slower in the small and much more trustworthy in the large.
- The equation-checking tool has to exist before the docs fill up with
  figures.

## Revisit when

Never weakened. It may only be strengthened.
