# Setup and dependencies: what we use, why, and how far to trust it

Every library, tool and runtime in the project: what it's for, why this one,
and how reliable it is **for the way we use it**. "Reliable" here means two
things. Is the component itself trustworthy, and did *we* check the part we
depend on? Where we didn't, this file says so.

Facts marked **(checked)** were read from the running environment or from
the official documentation on 2026-11-07; the command or source is given.
⚠ marks anything not verified.

---

## 1. How the project is set up

```
Windows 11 laptop (Intel i5-10300H)
└── WSL2: Ubuntu 24.04.5 LTS, kernel 6.18.54.1, 8 CPUs, 3.8 GB RAM, systemd
    └── Docker Engine 29.9.3 (docs.docker.com apt repository)
        ├── image burden-of-proof/checker:dev ── Python 3.14.10 + Lean 4.35.0 toolchain + the whole repo
        │     runs: tests, proofs, cheats, mutations, optimisation verdicts
        └── image burden-of-proof/ledger:dev ── Python 3.14.10 + reference/ + bench/loadgen.py
              runs as two containers per measurement, on a private network:
              ├── server (CPUs 0-3) + its own named volume (ext4 inside the VM)
              └── load generator (CPUs 4-7)
```

- **Both images share one base, pinned by digest:**
  `python:3.14-slim@sha256:af8a5aa14780…`. It contains Python 3.14.10,
  SQLite 3.46.1 and OpenSSL 3.5.7 (checked: `docker run … python -c …`).
  The same SQLite build serves the benchmark and the conformance checks.
- **Lean** is pinned by `lean-toolchain` (`leanprover/lean4:v4.35.0`), and
  `elan` installs exactly that version.
- **Also on Windows**, for development without Docker: Python 3.14.10 (with
  SQLite 3.50.4), Lean 4.35.0, Node 24, Java 21, and portable Postgres 18.6
  (not used yet).
- **Results from different environments are never compared.** There are
  three SQLite versions on this machine (F-011).

Setup steps: [RUNBOOK.md](RUNBOOK.md) §0–1. Why this setup:
[ADR-0016](adr/0016-python-for-tooling.md),
[ADR-0019](adr/0019-reference-ledger-api.md),
[ADR-0021](adr/0021-isolated-environment-wsl-docker.md).

---

## 2. Third-party dependencies

The Python code imports **nothing outside the standard library**, except
**pytest**, and pytest only runs the tests. That's deliberate (ADR-0016). Every
extra package is extra code to trust, and supply-chain risk to manage.

| Dependency | Version | What we use it for | Why this one | How far to trust it |
|---|---|---|---|---|
| **pytest** | 9.2.0 | Runs `tests/` | The standard Python test runner | Only runs tests; it never touches a result. Its verdicts are themselves checked by mutation testing (§5). |
| **Lean 4** (with `lake`) | 4.35.0 | Spec, proofs, compiled model | Small trusted kernel, executable specs (AWS Cedar precedent, ADR-0003) | The kernel is the trusted part. Tactics, elaboration and `lake` are not; that's why we re-check with kernels. |
| **leanchecker** (ships with Lean) | 4.35.0 | Replays compiled proofs through Lean's kernel | The official replay tool | It caught the forged theorem that everything else missed (F-001). It uses the *same* kernel as Lean. |
| **leanexport + con-leche** (ship with Lean) | 3.1.0 / 4.35.0 | Second, independent kernel | It doesn't share code with Lean's kernel | It rejected the forged theorem independently (F-001). ⚠ Its claims of having proofs about itself were not examined. |
| **lean4lean** (ships with Lean) | 4.35.0 | Not used | — | Couldn't read this toolchain's own files: "incompatible header" (F-005). |
| **elan** | 4.2.4 | Installs the pinned Lean toolchain | Lean's official installer | Its script was read in full before it ran; it downloads from GitHub releases. |
| **Docker Engine** | 29.9.3 | Isolation of every run | No Docker Desktop app needed | Mature. Resource pinning (`--cpuset-cpus`) is documented Docker behaviour ⚠ (CPU isolation isn't perfect under WSL2). |
| **python:3.14-slim** image | digest `af8a5aa1…` | Base of both images | The official Python image | Pinned by digest, so it can't change underneath us. |
| **d3** v7 | supplied by the dashboard | Charts on the evidence dashboard | Provided by the dashboard runtime | Only *draws* numbers; every number comes from a dataset with its source shown. |
| **Postgres** | 18.6 (EDB binaries) | Not used yet | Portable and local only (ADR-0015) | The binaries aren't Authenticode-signed; the zip's SHA-256 is recorded instead. |

---

## 3. The Python standard library, module by module

The standard library is maintained by CPython's core developers and ships
with CPython's own test suite. That makes it the most-used and most-reviewed
Python code there is, but "standard" doesn't mean "no traps". For each
module: where we use it, and the trap that matters to us.

| Module | Used in | For | Why this one | Reliability for our use, and the trap to know |
|---|---|---|---|---|
| `sqlite3` | `reference/ledger/store.py` | The ledger's database | Built in; SQLite is the most widely deployed database engine | It **wraps whatever SQLite C library Python was built with**: 3.46.1 in the container, 3.50.4 on Windows Python (checked). So the version is always recorded. `threadsafety = 3` (checked), so connections can be shared between threads; we still use one per thread or one per request. We set `isolation_level=None` and issue `BEGIN IMMEDIATE`/`COMMIT` ourselves, so we control every transaction rather than relying on the module's implicit ones. Correctness is checked by conformance against the spec (§5). |
| `http.server` (`ThreadingHTTPServer`, `BaseHTTPRequestHandler`) | `reference/ledger/server.py` | The HTTP API | Built in; nothing to install | It uses one thread per connection, fine at our scale. **Trap (checked): `socketserver` leaves Nagle's algorithm on (`disable_nagle_algorithm = False`).** That cost about 45 ms per small response in run 1 (F-016). We now set it to `True`, and a test plus mutation D7 guard it. The Python docs say not to use `http.server` in production ⚠; it's here as a reference system, not a product. |
| `http.client` | `bench/loadgen.py` | Load-generator HTTP client | Built in; keeps connections alive | **Sets `TCP_NODELAY` itself (checked in the source)**, so the client wasn't the Nagle culprit. |
| `threading` | `bench/loadgen.py`, `store.py` | Concurrent clients; per-thread connections | Built in | **The container runs CPython 3.14.10 *with the GIL* (checked).** Only one thread runs Python code at a time. Clients mostly wait on the network, so that's acceptable, but at the highest throughput (about 1,240 req/s in run 2) ⚠ the load generator may itself be the bottleneck. Not yet ruled out. |
| `time.perf_counter_ns` | `bench/loadgen.py`, CLI | Latency of each request | A monotonic clock with the highest resolution available | **Container: `clock_gettime(CLOCK_MONOTONIC)`, 1 ns resolution, monotonic, not adjustable (checked).** Windows: `QueryPerformanceCounter`, 100 ns (checked). Wall-clock jumps can't distort latencies. |
| `random` | `bench/loadgen.py`, `burden_of_proof/differential.py` | Seeded workloads and operation sequences | Reproducible from a seed | Mersenne Twister, *"one of the most extensively tested random number generators in existence"*, and *"completely unsuitable for cryptographic purposes"* (docs.python.org/3/library/random.html). We don't use it for security. **Trap (checked in the docs): only `random()` is guaranteed to give the same sequence across Python versions; `randint` and `choices`, which we use, may change.** So a seed reproduces a workload only on the same Python version, which is one reason the image pins 3.14.10. Each thread has its own `Random(seed)` instance, so threads don't disturb each other's sequences; the *interleaving* of requests across threads isn't reproducible. |
| `statistics.median` | `bench/docker_run.py` | Medians of repetitions | Exact; averages the two middle values for an even count | Checked: `median([1, 2, 3, 4]) == 2.5`. |
| *our own* `percentile`, `histogram` | `bench/loadgen.py` | p50/p95/p99 and latency histograms | Nearest-rank, from every sample; no estimation | **Ours, so not trusted by default.** `tests/test_loadgen.py` checks them on known values; mutations D8 (rank rounded down) and D9 (errors counted as successes) bite. These tests were added on 2026-11-07, after the first two runs had already used the code. |
| `json` | everywhere | Evidence files, model I/O, HTTP bodies | Built in | Integers are exact at any size. **Floats are binary floating point**, which is why money is always an integer number of minor units, and the store refuses floats (tests and mutation D6). |
| `tomllib` | `burden_of_proof/optcheck.py`, CLI, orchestrator | Reads claim records and the register | Built in since Python 3.11; read-only | Avoids PyYAML (ADR-0020). Read-only, so the tools can't accidentally rewrite a claim. |
| `hashlib` (SHA-256) | `burden_of_proof/speclock.py`, manifests, samples | Spec lock, evidence fingerprints | Built in, backed by OpenSSL (3.5.7 in the container, checked) | SHA-256 has no known practical collisions. It proves a file *wasn't changed*; it doesn't prove *who* made it. Signing would be the next step. |
| `gzip` | `bench/loadgen.py` | Compresses per-request samples | Built in | Lossless, and the `.gz` file's SHA-256 goes in the manifest. |
| `subprocess` | `leancheck.py`, `differential.py`, orchestrator | Runs `lake`, Lean tools, `docker`, the model | Built in | Always called with argument lists, never a shell string, so a path with a space or an apostrophe (this repo's own folder) can't break or inject a command. |
| `tempfile` | tests, `leancheck.py`, `differential.py`, CLI | Throwaway projects and databases | Built in | Deleted automatically, so experiments never touch the repo. |
| `shutil`, `pathlib`, `os` | everywhere | Files and paths | Built in | — |
| `dataclasses`, `argparse`, `functools`, `collections`, `re`, `io`, `platform`, `datetime`, `socket`, `urllib.request`, `sys` | various | Plumbing: records, CLIs, caching, counters, environment facts | Built in | Nothing we rely on for a result, except `platform`, which records the environment. |
| `cProfile`, `pstats` | `bench/run.py` | Profiles the baseline before optimising | Built in | Deterministic profiling **adds overhead per function call**, so it shows *where* time goes, not how much a request costs. Never quote its times as latency. |

---

## 4. Our own code that results depend on

Not libraries, but just as important to trust, so each has a check:

| Code | What depends on it | How it's checked |
|---|---|---|
| `store.settle` (Python) and `Spec.Ledger.settle` (Lean) | Every payment | Conformance: the two must agree on every random operation (`tests/test_ledger.py`); a planted bug is caught |
| `burden_of_proof/leancheck.py`, `tools/leancheck/Main.lean` | Every "verified" verdict | 13 cheat fixtures; 19 pipeline mutations |
| `burden_of_proof/optcheck.py` | Every optimisation verdict | Tests for each verdict; mutations D2–D4 |
| `burden_of_proof/differential.py` | Every "conforms to the spec" claim | A planted bug is caught; mutation D1 |
| `bench/loadgen.py` | Every latency and throughput figure | `tests/test_loadgen.py`; mutations D8, D9 |
| `bench/docker_run.py` | Run orchestration, interleaving, the sanity check | ⚠ **No unit tests.** Exercised end to end by the smoke test; its outputs are traceable through the manifest. |

---

## 5. How reliability is checked overall

1. **Tests**: `python -m pytest`.
2. **Mutation testing**: `tools/mutate.py` removes one check at a time
   (29 mutations). Each must make its tests fail, which shows the tests can
   catch a broken check, not just that they pass.
3. **Two kernels** for every proof.
4. **Conformance** of the real store with the compiled spec.
5. **Instrument checks**:
   - the benchmark's sanity floor (F-016);
   - the raw fsync probe (F-018);
   - interleaved rounds.
6. **Fingerprints** of every evidence file, with the commit and dirty state.

## 6. Known gaps

- The load generator may be the bottleneck at the highest throughput (GIL).
  Not yet ruled out ⚠.
- `bench/docker_run.py` has no unit tests.
- CPU isolation between containers under WSL2 isn't perfect ⚠.
- con-leche's proofs about itself weren't examined ⚠.
- Hashes prove integrity, not authorship (no signing yet).
