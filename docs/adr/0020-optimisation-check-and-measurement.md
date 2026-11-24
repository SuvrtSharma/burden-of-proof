# ADR-0020: Checking optimisation claims, then measuring the accepted ones

- **Status:** Accepted. Supersedes the storage proposal in ADR-0005 (claim
  records are TOML, not YAML).
- **Date:** 2026-11-07
- **Deciders:** project owner asked for the end-to-end loop; design by the
  agent
- **Cites claims:** the six records in `claims/optimisations/`

## Context

An agent proposes an optimisation and says it is safe and faster. ADR-0002
splits that claim, and ADR-0008 says to check it by asking which guarantees
it drops. This ADR is the working version, for the ledger API.

## Decision

**Claim records** live in `claims/optimisations/*.toml`. TOML because
Python's standard library reads it (`tomllib`), so no PyYAML is needed.
Each record holds: `id`, `kind` (orthodox or unorthodox), `title`, what the
agent says, `config` (the switches it changes), `drops` (the guarantees it
admits to removing), `compensated_by` (Lean claims, one per affected rule)
and, optionally, `refuted_by`.

**The guarantee register** (`claims/guarantees.toml`) lists rules (such as
LEDGER-DURABLE-MONEY) and the guarantees each one needs. Where a guarantee
can be **observed** on a live database, it is (durability, from
`PRAGMA journal_mode` and `synchronous`, using the rule SQLite documents).

**Meaning check** (`python -m burden_of_proof.optcheck`). Rejected if any of these
apply:

- `baseline_lacks_guarantee`: the baseline itself fails an observed
  guarantee.
- `undeclared_drop`: the candidate loses an observed guarantee it didn't
  declare. This is the important one: agents rarely declare what they drop.
- `drop_without_compensation` / `compensation_unproved`: a rule loses a
  guarantee, and there's no Lean claim, or `leancheck` doesn't accept it.
- `refuted_in_lean`: a refutation proof is accepted.
- `differs_from_model`: the candidate store disagrees with the compiled
  spec on any operation of 100 random sequences (seeded). The first
  counterexample is **shrunk** greedily until removing any single operation
  makes it pass.

**Speed** (`python -m bench.run`) is measured only after the meaning check,
over real HTTP:
- one server process per config, with a fresh database seeded with the same
  data;
- a closed-loop client with 8 keep-alive connections and a fixed operation
  mix;
- a 3 s warm-up that's discarded, then 3 timed repetitions, reporting the
  median;
- percentiles computed exactly from every request;
- the environment recorded, with a 90-day expiry.

The baseline is profiled first, to show where its time goes. Every claim is
measured on its own; rejected ones are labelled, to show what speed was on
offer. **Only accepted claims go into the combined configuration.**

## Consequences

- Verdicts don't depend on benchmark noise, and benchmarks never make a
  rejected claim acceptable.
- Lean compensation needs the owner's spec lock (ADR-0004). Without it, a
  drop that needs a proof is rejected, by design.
- The meaning check samples the store against the spec. It doesn't prove
  the SQL.

## Revisit when

Postgres is added (its guarantees go in the register: isolation levels, row
locks), or another observed guarantee becomes checkable.
