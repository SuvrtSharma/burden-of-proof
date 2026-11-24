# ADR-0024: Part 2 details: spec scope, what "correct" means, toolchains, disclosure

- **Status:** Accepted
- **Date:** 2026-11-15
- **Deciders:** project owner (answers to Q19 to Q22)
- **Cites claims:** none yet. Candidates P1 to P6 are in reading notes kept in
  the private lab notebook.

## Context

[ADR-0023](0023-part2-external-codebase-precise-ledger-pro.md) approved
Precise Ledger Pro as part 2's system under test, with our own Lean spec as the
oracle. Four details were left open: how much the first spec covers, what the
paper's correctness rule R1 means, whether we may run their code, and who
tells the author what we find.

## Decision

1. **First spec scope (Q22): fixed amounts only.** It covers disbursals,
   payments, backdated payments and reversals, with no interest. The first goal
   is to prove that fork-and-sync reaches the same result as a full rebuild in
   this setting, or to refute it. Daily interest comes second, as a separate
   spec step with its own owner review.
2. **What "correct" means (Q20).** After any sequence of activities, including
   late ones and reversals, two things must hold:
   - the ledger's current balance equals that of a full rebuild;
   - the total effect of each source activity equals its total in a full
     rebuild.

   Historical running balances are not compared, because R2 forbids changing
   them. This matches what the author's own tests assert, which is per-activity
   totals.
3. **Toolchains (Q19).** We may install a Haskell toolchain (GHC and cabal) and
   let Maven download the Java dependencies, both only inside Docker images in
   WSL2, built from pinned official base images. Nothing is installed on
   Windows. The containers get no route to any address in the author's
   configuration, and nothing from that configuration is ever used.
4. **Disclosure (Q21).** The owner tells the author, in one message, once the
   first checks have run. The message covers:
   - the paper's mismatches with its fixture;
   - the code-versus-paper differences;
   - any counterexamples;
   - [public copy: one further item, redacted].

   Nothing about part 2 is published before that.

## Alternatives considered

- **Interest in the first spec:** closer to the paper's example, but much harder
  to prove. It would delay any result, and a failure would be harder to
  attribute.
- **Asking the author what R1 means before starting:** the most faithful
  option, but it blocks all work on their reply. The chosen meaning is the one
  their tests already use.

## Consequences

- The first Lean result is narrower than the paper's claims. It says nothing
  about interest, which is where the paper's worked example has its problems.
  The write-up must say so.
- Two more Docker images to maintain, pinned like part 1's.

## Revisit when

- The fixed-amount spec is proved or refuted. Then do the interest step.
- The author replies, especially about R1.
