# ADR-0014: Databases for the reference system: SQLite first, then Postgres

- **Status:** Accepted
- **Date:** 2026-11-07
- **Deciders:** project owner
- **Cites claims:** none

## Context

Optimisation claims are only meaningful against a real engine, and the
guarantees an optimisation can drop differ by engine. SQLite is embedded,
single-writer, with `synchronous` and `journal_mode` pragmas and a B-tree you
can reach under the VDBE. Postgres is client-server, with MVCC, isolation
levels, `FOR UPDATE`, `synchronous_commit` and replicas. The owner wants to
test both.

## Decision

1. **The reference system supports SQLite and Postgres** behind the same
   operations, so the same claim can be checked on both engines and the
   verdicts compared.
2. **Order of work:** SQLite first, because it needs no server and already
   runs on this machine. Postgres follows. More engines are added only when
   the owner asks.
3. **One guarantee register per engine** (ADR-0008). A guarantee id says
   which engine it belongs to, for example `sqlite.synchronous_full` or
   `pg.iso.read_committed`. A claim that holds on one engine is never assumed
   to hold on the other.
4. **The engine version is part of every measurement's environment**
   (ADR-0002). This matters today: on this machine, Python 3.14.10's built-in
   `sqlite3` module links SQLite **3.50.4**, while the `sqlite3` CLI is
   **3.54.1** (checked on 2026-11-07). The same query timed through each can
   differ just because of the version.

## Alternatives considered

- **Postgres only:** loses the unorthodox SQLite ideas (direct B-tree
  access, skipping the VDBE).
- **SQLite only:** loses isolation levels, row locks and replicas, which are
  most of the interesting guarantees.
- **An ORM to hide the engine:** it would hide exactly the guarantees we
  want to see. Engine-specific SQL stays explicit.

## Consequences

- Twice as many guarantee lists and benchmark environments to maintain.
- Postgres needs installing later. That needs the owner's approval, and an
  install method that suits a machine without Docker.
- If benchmarks need a specific SQLite version, we pin and ship our own
  SQLite build instead of relying on whatever Python bundles.

## Revisit when

The owner asks for another engine, or Postgres work starts (its install
method gets recorded then).
