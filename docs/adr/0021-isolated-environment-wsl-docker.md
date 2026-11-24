# ADR-0021: Isolated environment: WSL2 + Docker Engine, separate containers

- **Status:** Accepted. Amends ADR-0019 (which ran natively).
- **Date:** 2026-11-07
- **Deciders:** project owner (asked for isolation, enabled WSL2); setup by the agent
- **Cites claims:** none

## Context

ADR-0019 ran the reference API as native Windows processes. The owner said
isolation through Docker/WSL would have been better and should have been
offered (findings F-013). The owner installed WSL2 with Ubuntu 24.04.

## Decision

- **WSL2, Ubuntu 24.04.5 LTS**, kernel 6.18.54.1-microsoft-standard-WSL2,
  systemd as PID 1. The VM has 8 CPUs and about 3.8 GB of RAM (recorded on
  every run).
- **Docker Engine 29.9.3** (Compose v5.7.0) from Docker's apt repository,
  inside the distro. Docker Desktop is not used. Commands are from
  docs.docker.com/engine/install/ubuntu (fetched 2026-11-07). The user
  The owner's WSL user is in the `docker` group; `hello-world` ran as that user.
- **Two images, one base pinned by digest**
  (`python:3.14-slim@sha256:af8a5aa1…`: Python 3.14.10, SQLite 3.46.1):
  - `docker/ledger.Dockerfile`: the API server and the load generator.
  - `docker/checker.Dockerfile`: elan and the Lean toolchain pinned by
    `lean-toolchain`, plus the whole suite. Conformance runs on the **same
    SQLite build** the benchmark measures, and on Linux, which CI also uses.
- **Benchmark topology** (`bench/docker_run.py`, run with the distro's
  Python): for each configuration, a fresh server container pinned to CPUs
  0–3 with its own named volume, and a load-generator container pinned to
  CPUs 4–7, on a private Docker network. HTTP never leaves the VM.
- **Evidence** goes in `evidence/<run-id>/`: test results (JUnit), verdicts,
  the benchmark, gzipped per-request samples, and a manifest of SHA-256
  hashes with the git commit and whether the tree was dirty.

## Alternatives considered

- **Docker Desktop:** an extra Windows application, and its licence terms
  differ for larger companies ⚠ (not checked). Engine inside WSL is enough.
- **Native Windows (ADR-0019):** not isolated; a third SQLite version; kept
  only as history.

## Consequences

- Results from different environments are never compared with each other:
  three SQLite versions are in play (F-011).
- The checker image is large (4.71 GB, mostly the Lean toolchain). A
  first build took 653 s; a rebuild with cached layers took 58 s.
- 3.8 GB of VM memory is small, so the benchmark data size is chosen to fit.

## Revisit when

The owner wants a bigger VM (`.wslconfig`), or the benchmarks move to
dedicated hardware.
