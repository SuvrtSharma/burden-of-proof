# ADR-0023: Part 2 checks an external codebase, Precise Ledger Pro

- **Status:** Accepted. Amends ADR-0012. Details settled in
  [ADR-0024](0024-part2-scope-oracle-toolchains-disclosure.md).
- **Date:** 2026-11-15
- **Deciders:** project owner (approved 2026-11-15)
- **Cites claims:** none yet. The candidate claims (P1 to P12) are in reading
  notes kept in the private lab notebook.

## Context

ADR-0012 decided that we build our own reference system, and part 1 did. Its
one weakness is circularity: the agent wrote both the spec and the code it was
checked against, which the first write-up says plainly.

The owner chose a real codebase for part 2 (Q17, decided 2026-11-15):
Precise Ledger Pro, a loan ledger with Java (Quarkus) and Haskell reference
implementations and an arXiv draft. The draft claims that its fork-and-sync
algorithm handles late and reversed transactions correctly, auditably and more
cheaply than a full rebuild. Its author has publicly asked for critical
feedback (the owner shared the post on 2026-11-15).

A read-only survey found (details in the reading notes, kept private):

- The central claim is an optimisation with a meaning part: fork-and-sync
  against full reconstruction. That fits the meaning-then-speed method
  (ADR-0002) exactly.
- [Public copy: the rest of this survey, about the author's code and paper,
  is redacted. Under decision 5 below, findings go to the author privately
  first, and the owner decides what is published.]

## Decision

1. **Part 2's system under test is Precise Ledger Pro, at a pinned commit**
   (`06bb4ce` today). It lives outside this repo, in its own folder, and is
   treated as untrusted: read before run, and nothing from it executes on the
   host.
2. **The spec is ours.** A new Lean module models the paper's algorithms and the
   full-rebuild oracle, with integer-cent money. It is drafted from the paper
   and the code, then reviewed and locked by the owner, exactly as for spec v2.
   The paper's prose is not the spec; where the paper is ambiguous (R1), we ask.
3. **Order of work:**
   1. spec without interest;
   2. meaning claims P1 to P6;
   3. conformance of the Haskell port, then the Java service, against the
      compiled model and against each other;
   4. daily interest;
   5. speed against a full rebuild.
4. **Running their code needs the owner's approval first:** a GHC toolchain for
   Haskell, and Maven dependencies for Java. It runs in Docker inside WSL2, like
   part 1. Nothing connects to any address in their configuration.
5. **Findings about their work go to the author privately before anything is
   published.** The owner decides
   what is published and when.

## Alternatives considered

- **Keep extending our own ledger.** It's cheaper, but it leaves the
  circularity in place, and the owner has already chosen a real codebase.
- **Check only the paper's arithmetic and write it up.** That's useful to the
  author, but it is a review, not evidence about the algorithm. It also uses
  none of the tooling this project exists to test.
- **Run their test suite and report pass or fail.** A pass shows agreement with
  the project's own expectations. An independent oracle is the point.

## Consequences

- The toolkit is tested on code its agent didn't write, which is the claim the
  write-ups make next.
- We now need toolchains for a second and third language (Haskell, Java) and an
  adapter for each. Both are new maintenance.
- Publishing depends on the author: their work, their response, and the timing
  of their arXiv submission.

## Revisit when

- The owner's answers in ADR-0024 change.
- The author responds, or the upstream code moves past the pinned commit.
- The first counterexample, or the first proof of P1, lands.
