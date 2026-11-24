# ADR-0019: Reference ledger API: Python stdlib HTTP on SQLite, no Docker

- **Status:** Accepted (application language proposed by an agent; the
  owner may override). Resolves open question Q12. **Amended by
  [ADR-0021](0021-isolated-environment-wsl-docker.md)**: it now runs in Docker inside WSL2, not natively.
- **Date:** 2026-11-07
- **Deciders:** project owner asked for a real end-to-end system; language
  chosen by the agent
- **Cites claims:** none

## Context

The owner asked for a real environment: API requests to a server, run end to
end, benchmarked before and after optimisations. Docker was suggested as a
possibility. On this Windows machine, Docker needs WSL2 or Hyper-V switched
on, which is a system setting change, so it wasn't used.

## Decision

- `reference/ledger/`: an HTTP/1.1 keep-alive JSON API (`server.py`, stdlib
  `ThreadingHTTPServer`) over a SQLite store (`store.py`). It's Python
  because the tooling is Python (ADR-0016) and nothing needs installing.
- Its meaning is `Spec.Ledger` (`Spec/Ledger.lean`). The responses use the
  same JSON shapes as the compiled spec (`ledgermodel`), so conformance can
  compare them exactly.
- Every candidate optimisation is one switch in `store.Config`. The
  baseline is the straightforward implementation: a connection per request,
  a rollback journal, no indexes, balances summed from rows, and a full scan
  of open bills.
- **Baseline durability is `synchronous=EXTRA`.** The first baseline used
  `FULL`, and the guarantee check rejected it: SQLite documents FULL with a
  rollback journal as *"not necessarily durable across a power loss"*.
- Writes use `BEGIN IMMEDIATE`. Multi-statement reads run in one
  transaction, so a balance is never computed from two snapshots.
- Server and load generator run as separate processes on the same machine,
  over localhost.

## Consequences

- Python's GIL caps throughput. Absolute numbers are about this stack, not
  about SQLite. Comparisons between configs on the same stack are the
  point.
- Postgres (ADR-0014) is the next engine. The store's interface is the
  seam.

## Revisit when

The owner wants another application language, or Docker/WSL becomes
available.
