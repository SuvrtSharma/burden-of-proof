# Architecture Decision Records

One file per decision, numbered and never renumbered. To change a decision,
write a new ADR that **supersedes** the old one, and set the old one's status
to `Superseded by ADR-NNNN`. Never rewrite history in place, except to fix
typos or broken links.

Statuses: `Proposed` (still waiting on an open question) · `Accepted` ·
`Superseded by ADR-NNNN` · `Deprecated`.

Once claims exist, an ADR that depends on a fact cites the claim id (for
example `LEDGER-ATTACH-CONSERVES-BALANCE`) instead of restating the fact. CI
will fail if a cited claim stops holding (phase 4).

Copy [0000-template.md](0000-template.md) to start a new ADR.

| # | Title | Status |
|---|---|---|
| [0001](0001-record-architecture-decisions.md) | Record architecture decisions as ADRs | Accepted |
| [0002](0002-split-claims-into-meaning-and-speed.md) | Split every claim into meaning and speed | Accepted |
| [0003](0003-lean4-canonical-with-specialist-checkers.md) | Lean 4 as canonical spec; specialist checkers by claim kind | Accepted |
| [0004](0004-reviewed-hash-locked-spec-library.md) | Reviewed, hash-locked spec library | Accepted, amended by 0017 |
| [0005](0005-typed-claim-records.md) | Typed claim records, not prose | Accepted; storage superseded by 0020 (TOML) |
| [0006](0006-lean-check-pipeline-no-escape-hatches.md) | Lean check pipeline with no escape hatches | Accepted, amended by 0017 |
| [0007](0007-conformance-by-differential-random-testing.md) | Conformance by differential random testing against an executable model | Accepted, amended by 0012 |
| [0008](0008-guarantee-register.md) | Guarantee register for optimisation claims | Accepted |
| [0009](0009-ledger-first-domain.md) | Ledger with allocations as the first domain | Accepted, amended by 0012 and 0022 |
| [0010](0010-evidence-comes-from-tools.md) | Evidence comes from tools; tests must bite | Accepted |
| [0011](0011-gods-hand-umbrella-toolkit.md) | God's Hand is an umbrella toolkit; Lean 4 is the first track | Accepted |
| [0012](0012-own-reference-system-and-test-suite.md) | Build our own reference system and test suite; drop the lost-update pattern | Accepted, amended by 0023 |
| [0013](0013-private-github-repo-placeholder-name.md) | Private GitHub repo under a placeholder name | Accepted |
| [0014](0014-databases-sqlite-then-postgres.md) | Databases for the reference system: SQLite first, then Postgres | Accepted |
| [0015](0015-portable-local-postgres.md) | Portable, local-only Postgres for development | Accepted |
| [0016](0016-python-for-tooling.md) | Python for the tooling around Lean | Accepted |
| [0017](0017-lean-check-pipeline-as-built.md) | The Lean check pipeline as built: statements as spec Props, kernel replay required | Accepted, amended by 0018 |
| [0018](0018-closing-the-checker-gaps.md) | Closing the checker gaps: vacuity guard, second kernel, CI | Accepted |
| [0019](0019-reference-ledger-api.md) | Reference ledger API: Python stdlib HTTP on SQLite, no Docker | Accepted, amended by 0021 |
| [0020](0020-optimisation-check-and-measurement.md) | Checking optimisation claims, then measuring the accepted ones | Accepted |
| [0021](0021-isolated-environment-wsl-docker.md) | Isolated environment: WSL2 + Docker Engine, separate containers | Accepted |
| [0022](0022-ledger-spec-v2.md) | Ledger spec v2: the owner's review decisions, and invariants of reachable states | Accepted |
| [0023](0023-part2-external-codebase-precise-ledger-pro.md) | Part 2 checks an external codebase, Precise Ledger Pro | Accepted |
| [0024](0024-part2-scope-oracle-toolchains-disclosure.md) | Part 2 details: spec scope, what "correct" means, toolchains, disclosure | Accepted |
| [0025](0025-part2-ledger-rules-and-project.md) | Part 2 ledger rules approved; part 2 gets its own Lean project | Accepted |
| [0026](0026-part2-spec-review-decisions.md) | Part 2 spec review: tie rule, allocation order, early reversals, claim fixes | Accepted |
| [0027](0027-part2-recording-time-and-refutation-statement.md) | Part 2 spec: recording time (READING 8), a refutation statement, explicit matches | Accepted |
| [0028](0028-part2-rebuild-from-earliest-affected-point.md) | Part 2: rebuild from the earliest affected point (a meaning-preserving optimisation) | Accepted |
| [0029](0029-public-name-and-curated-public-repo.md) | Public name Burden of Proof, and a curated public repo | Accepted |
