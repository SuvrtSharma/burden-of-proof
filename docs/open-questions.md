# Open questions

Agents ask the owner about these and never decide them silently. Once an
answer exists, record it in an ADR and move the entry to "Resolved", with a
link.

## Open

| # | Question | Needed by |
|---|---|---|
| Q1 | The final project name ("Burden of Proof" is a placeholder, ADR-0013) | before publishing |
| Q2 | TLA+ or P for concurrency models (Java 21 is already installed, which TLA+ needs) | concurrency track |
| Q3 | Z3 or cvc5 for SMT | access track |
| Q5 | Claim registry: in-repo files (TOML now, [ADR-0020](adr/0020-optimisation-check-and-measurement.md)), or a small service | phase 4 at the latest |
| Q16 | Turn on branch protection for `main`, requiring CI to pass (ADR-0018) | before agents push to `main` unsupervised |
| Q17 | Part 2's codebase: Precise Ledger Pro (owner, 2026-11-15). Known: Java 21 Quarkus with H2 or Postgres, a pure Haskell port, an arXiv draft, MIT ⚠; nothing in its configuration is ever used. Approved as part 2 ([ADR-0023](adr/0023-part2-external-codebase-precise-ledger-pro.md)). Details settled in [ADR-0024](adr/0024-part2-scope-oracle-toolchains-disclosure.md) | before part 2 starts |
| Q24 | ~~Owner review of the part 2 spec draft~~ **Resolved 2026-11-23:** decisions in [ADR-0026](adr/0026-part2-spec-review-decisions.md) and [ADR-0027](adr/0027-part2-recording-time-and-refutation-statement.md); locked by the owner (`part2/spec.lock.json`) | before any part 2 claim counts | Review: `docs/part2/spec-review-2026-11-22.md`. |

## Resolved

| # | Question | Answer |
|---|---|---|
| Q4 | How conformance drives the target app | The target is our own reference system ([ADR-0012](adr/0012-own-reference-system-and-test-suite.md)). The mechanism follows from Q12 |
| Q6 | The stack of the production app and the server | There is no separate project. Everything is built here ([ADR-0012](adr/0012-own-reference-system-and-test-suite.md)) |
| Q7 | Is the SQLite server work part of this repo? | Yes. Nothing exists outside this repo ([ADR-0012](adr/0012-own-reference-system-and-test-suite.md)) |
| Q8 | What "rediscover pattern 1" means in phase 1 | Pattern 1 is dropped. It belongs to another project ([ADR-0012](adr/0012-own-reference-system-and-test-suite.md)) |
| Q9 | Public or private? | Private to start. The end goal is tools and skills for AI agents ([ADR-0013](adr/0013-private-github-repo-placeholder-name.md)) |
| Q10 | Initialise git? | Yes, plus a private GitHub repo ([ADR-0013](adr/0013-private-github-repo-placeholder-name.md)) |
| Q12 | Reference system's application language | Python stdlib HTTP on SQLite, no Docker ([ADR-0019](adr/0019-reference-ledger-api.md)); the owner may override |
| Q13 | Tooling language | Python 3.14 in a project venv ([ADR-0016](adr/0016-python-for-tooling.md)) |
| Q14 | Postgres install method | Portable binaries, local only ([ADR-0015](adr/0015-portable-local-postgres.md)) |
| Q11 | Install elan and Lean? | Yes. Install whatever is needed, while still asking before each install (CLAUDE.md) |
| Q19 | Install GHC/cabal and let Maven download Java dependencies? | Yes, only inside Docker in WSL2, from pinned bases, with no route to their config's addresses ([ADR-0024](adr/0024-part2-scope-oracle-toolchains-disclosure.md)) |
| Q20 | What the paper's R1 means | The current balance and each activity's total equal a full rebuild; historical running balances aren't compared ([ADR-0024](adr/0024-part2-scope-oracle-toolchains-disclosure.md)) |
| Q21 | Who tells the author, and when | The owner, in one message after the first checks run, before anything is published ([ADR-0024](adr/0024-part2-scope-oracle-toolchains-disclosure.md)) |
| Q22 | First spec scope | Fixed amounts first (no interest); daily interest as a second step ([ADR-0024](adr/0024-part2-scope-oracle-toolchains-disclosure.md)) |
| Q23 | Owner review of the part 2 ledger rules | v2 approved by the owner, 2026-11-18 ([ADR-0025](adr/0025-part2-ledger-rules-and-project.md)) |
| Q18 | Approve ADR-0023: an external codebase for part 2 | Approved by the owner, 2026-11-15 ([ADR-0023](adr/0023-part2-external-codebase-precise-ledger-pro.md)) |
| Q15 | Owner review of the draft ledger spec, then lock it | Reviewed and locked by the owner (commit 04fee63, [ADR-0022](adr/0022-ledger-spec-v2.md)) |
