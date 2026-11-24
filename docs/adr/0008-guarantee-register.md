# ADR-0008: Guarantee register for optimisation claims

- **Status:** Accepted
- **Date:** 2026-11-07
- **Deciders:** project owner
- **Cites claims:** none

## Context

Most optimisations that "bypass a rule of the stack" are fast because they
remove a guarantee the platform provides. Without a list of those guarantees,
the question "is this safe?" has no fixed form. With one, it becomes: **do all
of our rules still hold with guarantee G removed from the model?**

Examples: dropping `FOR UPDATE` removes a row lock; `synchronous_commit = off`
removes durable commit; replica reads remove freshness; skipping the tenant
filter removes an access check. Direct SQLite B-tree access, which skips the
VDBE, may remove constraint checks, triggers, index maintenance or locking.
⚠ Exactly which ones it removes is still to be established for this
workload.

## Decision

- Maintain a first-class **guarantee register**: stable ids for everything
  the system relies on from its platform, for example `txn.atomic`,
  `lock.row_for_update`, `iso.read_committed`, `durable.commit`,
  `constraint.unique`, `filter.tenant_every_query`,
  `auth.session_every_action`.
- Each guarantee says how it is represented in the models, as an assumption
  that can be switched off.
- Claims declare `relies_on`. Optimisation claims must also declare `drops`.
- The checker re-runs **every** rule with the dropped guarantees removed,
  not only the rule the agent mentioned.
- Whether "the stack supports X" is itself a claim that can be checked, for
  example "Postgres has native planner hints" (it doesn't; that needs
  `pg_hint_plan`).
- An optimisation that drops a guarantee it **didn't declare** is the most
  important thing to catch. Detecting undeclared drops is a phase-3 research
  item.

## Alternatives considered

- **Judging each optimisation case by case:** it doesn't scale, and it
  misses side effects on rules nobody mentioned.

## Consequences

- Every model needs switches for its guarantees, which shapes how the TLA+/P
  and Lean models are written from day one.
- The register is reviewed like the spec. Agents propose additions.

## Revisit when

Phase 3 begins. Detailed design follows then.
