# ADR-0016: Python for the tooling around Lean

- **Status:** Accepted
- **Date:** 2026-11-07
- **Deciders:** project owner
- **Cites claims:** none

## Context

Lean does the proving, but everything around it needs a language. That
includes the claim schema and validator, the spec hash lock, the check
pipeline (running `lake`, parsing `#print axioms`), the exact-arithmetic and
equation checker, the differential harness, and benchmarks. Python 3.14 and
Node 24 were both installed. The owner chose Python.

## Decision

- Tooling is **Python 3.14**, in a project-local virtual environment
  (`.venv/`, git-ignored), with dependencies declared in `pyproject.toml`.
- **Prefer the standard library**, which already covers what the evidence
  rules need:
  - `fractions.Fraction` and `int` for exact arithmetic, never `float` for
    money (ADR-0010)
  - `hashlib` for the spec lock
  - `subprocess` to drive `lake`
  - `sqlite3` and `json`
- Third-party packages are added only when needed, each with a reason in
  the commit that adds it. pytest is the first. Expected later: PyYAML (claim
  records), jsonschema (claim validation), Hypothesis (random operation
  sequences), and a Postgres driver.
- Tests use **pytest**. Every test must be shown to bite (ADR-0010).
- Measurements made through Python record that the `sqlite3` module links
  SQLite 3.50.4, not the CLI's 3.54.1 (ADR-0014).

## Alternatives considered

- **Node / TypeScript:** also viable. Python's standard library has exact
  fractions, SQLite built in, and first-class bindings for Z3 (for the
  later SMT track).

## Consequences

- Contributors need Python 3.14 and the venv. The setup command is in
  CLAUDE.md.
- If a measurement needs a specific SQLite version, we may have to ship our
  own SQLite build instead of the one Python bundles.

## Revisit when

A tool has to run inside an environment where Python isn't available (for
example a published skill with other runtime constraints).
