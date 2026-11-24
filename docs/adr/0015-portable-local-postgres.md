# ADR-0015: Portable, local-only Postgres for development

- **Status:** Accepted
- **Date:** 2026-11-07
- **Deciders:** project owner
- **Cites claims:** none

## Context

ADR-0014 adds Postgres after SQLite. The machine has no Docker or WSL. The
official Windows installer registers a service that runs all the time and
asks for a superuser password. The owner chose portable binaries that stay
local.

## Decision

- **Binaries:** EDB's portable zip of PostgreSQL **18.6** (the current
  release according to postgresql.org on 2026-11-07), from
  `https://get.enterprisedb.com/postgresql/postgresql-18.6-5-windows-x64-binaries.zip`.
  - Zip SHA-256: `e2246ba91d22345bc3d017586c09ede52d9df180b1eeb480f050445f1cad84e2`.
  - Only `bin`, `lib`, `share`, `include` and the licences are installed,
    to `%LOCALAPPDATA%\Programs\pgsql-18.6`. pgAdmin and StackBuilder are
    left out.
  - ⚠ The executables are **not Authenticode-signed**. Trust rests on the
    official EDB HTTPS source and the recorded hash.
- **Cluster:** data lives in `.local/pg18/data` inside the repo, which is
  git-ignored. It's managed only through `scripts/pg/init.ps1`, `start.ps1`
  and `stop.ps1`. No Windows service; it runs only while started.
- **Local only:** `listen_addresses=localhost`, port 5432. `trust` auth,
  limited to 127.0.0.1 and ::1, so there's no password to manage. Checked:
  the server listens only on `127.0.0.1` and `::1`, and `pg_hba` has no rule
  for any other address. **This is a dev database only. It must never hold
  real data.**
- **Collation:** builtin provider, `C.UTF-8`, so `ORDER BY` on text is
  byte-wise and the same on every machine. Checked: `'b','B','a','_'` sorts
  as `B,_,a,b`. Ordering claims (bug pattern 4) can't depend on the OS
  locale.
- Data page checksums are on (the initdb default in 18).
- The binary path and port can be overridden with `BURDEN_OF_PROOF_PG_BIN` and
  `BURDEN_OF_PROOF_PG_PORT`.

## Alternatives considered

- **Official installer:** adds a permanent service and a password.
- **Docker:** not available on this machine.

## Consequences

- Upgrading means downloading a new zip, recording its hash, pointing
  `BURDEN_OF_PROOF_PG_BIN` at it, and re-initialising (dev data is disposable).
- Benchmarks record the Postgres version and these settings as part of the
  environment (ADR-0002).
- Extensions like `pg_hint_plan` would need building or a matching binary
  ⚠ (not checked).

## Revisit when

Docker or WSL becomes available, a benchmark needs a different version, or
an extension we need isn't available for this build.
