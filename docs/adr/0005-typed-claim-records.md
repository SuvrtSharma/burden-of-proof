# ADR-0005: Typed claim records, not prose

- **Status:** Accepted (schema). Storage **superseded by
  [ADR-0020](0020-optimisation-check-and-measurement.md)**: records are TOML files, read with the
  standard library.
- **Date:** 2026-11-07
- **Deciders:** project owner
- **Cites claims:** none

## Context

Prose claims can't be routed to a checker, re-checked when something changes,
or cited by docs and CI. A claim needs a fixed shape.

## Decision

Each claim is a record with these fields:

| Field | Meaning |
|---|---|
| `id` | stable, upper-kebab, for example `LEDGER-ATTACH-CONSERVES-BALANCE`; never reused |
| `kind` | `invariant` \| `access` \| `concurrency` \| `equivalence` \| `dataflow` \| `performance` |
| `statement` | a name defined in the locked spec (ADR-0004) |
| `relies_on` | guarantee ids from the guarantee register (ADR-0008) |
| `drops` | (optimisation claims) the guarantees this change removes or weakens |
| `evidence` | checker, artifact path, artifact hash, checker-specific result (for example `axioms_ok`) |
| `conformance` | harness, number of cases, mismatches, seed |
| `status` | `proposed` \| `verified` \| `refuted` \| `unproved` \| `measured` \| `expired` |
| `counterexample` | present when `refuted`; also saved as a regression test |
| `recheck` | the paths whose change invalidates the evidence |
| `expires` | required for `performance`; the date after which it becomes `expired` |

Example:

```yaml
id: LEDGER-ATTACH-CONSERVES-BALANCE
kind: invariant
statement: Spec.attach_preserves_every_balance
relies_on: [txn.atomic, lock.row_for_update, iso.read_committed]
evidence: { checker: lean, artifact: proofs/Attach.lean, axioms_ok: true }
conformance: { harness: drt/attach, cases: 100000, mismatches: 0 }
status: verified
recheck: on_change [spec/Ledger.lean, app/payments]
```

**Storage, proposed for phase 1:** one YAML file per claim under `claims/`,
validated against a JSON Schema. It is reviewable in diffs and needs no
service. Whether this later moves to a small service is an open decision.

`unproved` is kept separate from `refuted` on purpose: "we couldn't prove it"
must never be reported as "it's false", or the other way round.

## Alternatives considered

- **Free-text claims:** they can't be machine-checked or cited.
- **A service from the start:** extra infrastructure before there's a single
  claim to store.

## Consequences

- A schema validator is one of the first pieces to build.
- The `drops` field is what makes optimisation claims checkable (ADR-0008).

## Revisit when

Claims need to be submitted by agents outside this repo (phase 4 server), or
the number of claims makes files impractical.
