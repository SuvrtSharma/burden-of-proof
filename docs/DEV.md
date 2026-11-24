# DEV.md: how this project works, for someone learning it

This explains what every file and name in the repo is, why each decision
was made, and what each technical term means. It's written for the owner
to learn from, and for any agent or person picking the work up. The formal
decisions are the ADRs in [adr/](adr/README.md); this file is the guided
tour.

---

## 1. The idea in one paragraph

An AI agent says something about code, such as "this optimisation is safe and
faster". We don't take its word. We split the claim into **meaning** (does
it still do the right thing?) and **speed** (is it faster?). Meaning is
checked by tools: a Lean 4 proof, a check of the running database's
settings, and a comparison of the real code against an executable spec.
Speed is only *measured*, and only for claims whose meaning passed. Every
result is written to a file with a fingerprint, so anyone can check it later.

---

## 2. Map of the repository

| Path | What it is | Who writes it |
|---|---|---|
| `Spec/Ledger.lean` | **The spec**: the ledger's rules written in Lean 4. What "correct" means. | Drafted by the agent; **reviewed and locked by the owner** |
| `Spec.lean` | The entry point that imports everything in `Spec/` | same |
| `spec.lock.json` | Fingerprints of the spec files. If anyone edits the spec, checks fail. | **Owner only** (`python -m burden_of_proof.speclock update`) |
| `Proofs/Ledger.lean` | Proofs of the spec's statements | agent |
| `LedgerModel.lean` | The spec compiled into a runnable program (`ledgermodel`) | agent |
| `lakefile.toml`, `lean-toolchain`, `lake-manifest.json` | Lean's build files. `lean-toolchain` pins the exact Lean version (4.35.0) | agent; the first two are locked |
| `tools/leancheck/Main.lean` | The proof inspector, a Lean program (step 4 of the check) | agent |
| `tools/mutate.py` | Breaks each check on purpose to prove the tests catch it | agent |
| `burden_of_proof/leancheck.py` | The whole proof check, steps 1–7 (section 5) | agent |
| `burden_of_proof/speclock.py` | Creates and verifies `spec.lock.json` | agent |
| `burden_of_proof/differential.py` | Runs random operations through the real store and the compiled spec, and compares | agent |
| `burden_of_proof/optcheck.py` | Judges an optimisation claim's meaning | agent |
| `burden_of_proof/cli.py` | Readable terminal reports (`python -m burden_of_proof prove`, and so on) | agent |
| `reference/ledger/store.py` | The real system: ledger storage on SQLite, with one switch per optimisation | agent |
| `reference/ledger/server.py` | The real system: HTTP API over the store | agent |
| `claims/lean/*.toml` | Records of Lean claims (what is proved, by which theorem) | agent |
| `claims/optimisations/*.toml` | Records of optimisation claims (what the agent proposed and admitted) | agent |
| `claims/guarantees.toml` | The guarantee register: what the system relies on, and which rule needs it | owner-reviewed |
| `bench/loadgen.py` | Load generator: many HTTP clients, records every request | agent |
| `bench/docker_run.py` | Orchestrates `before` / `check` / `after` in Docker | agent |
| `bench/verdicts.py` | Runs `optcheck` on every claim (inside the checker container) | agent |
| `bench/fsync_probe.py` | Measures raw disk sync speed, with no database | agent |
| `bench/verify_manifest.py` | Re-checks every evidence file's fingerprint | agent |
| `docker/*.Dockerfile` | Recipes for the two container images | agent |
| `tests/` | Tests of the tooling itself, including deliberately broken "fixture" proofs | agent |
| `evidence/` | **Raw results** of every run, plus `findings.json` (what we learned) | tools; findings by the agent |
| `dashboard/index.html` | The evidence dashboard page | agent |
| `docs/adr/` | Architecture Decision Records: one file per decision | agent, approved by the owner |
| `docs/journal/` | The daily learning log (kept in the private lab notebook, not in this repo) | agent |
| `docs/RUNBOOK.md` | Commands for the owner to run and screenshot | agent |
| `docs/DEPENDENCIES.md` | Every library and tool: why it's used, and how far to trust it | agent |
| `docs/DEV.md` | This guide | agent |

---

## 3. Naming conventions

| Pattern | Example | Meaning |
|---|---|---|
| `ADR-NNNN` | ADR-0017 | Architecture Decision Record number N. Numbers are never reused; a changed decision gets a new ADR. |
| `OPT-…` | `OPT-WAL-NORMAL` | An **optimisation claim** (`claims/optimisations/`). |
| `LEDGER-…` | `LEDGER-SETTLE-CONSERVES` | A **Lean claim** about the ledger (`claims/lean/`). |
| `Spec.x` | `Spec.settleConserves` | A *statement* in the locked spec: a `def … : Prop` (a definition whose value is a proposition). |
| `Proofs.Ledger.x` | `Proofs.Ledger.settleConserves` | The theorem that proves `Spec.x`. |
| `…_witness` | `Proofs.Ledger.settleConserves_witness` | Shows that the statement's assumptions can actually be met (the vacuity guard, section 5). |
| `F-NNN` | F-016 | A **finding** in `evidence/findings.json`. Kinds: finding, failure, mistake, caught. |
| `M…`, `N…`, `R…`, `D…` | M1, N4, R1, D7 | **Mutations** in `tools/mutate.py`. M = original Lean pipeline checks, N = checks added later, R = the refutation rule, D = the optimisation and system tooling. |
| `Q…` | Q15 | An open question for the owner (`docs/open-questions.md`). |
| Run id `YYYYMMDDTHHMMSSZ` | `20261107T090049Z` | A run's start time in **UTC** (the `Z`), so folders sort by time. |
| `<config>-rep<N>` | `baseline-rep2` | Repetition N of a configuration in the old back-to-back runs. |
| `<config>-round<N>-rep1` | `OPT-WAL-round2-rep1` | Interleaved runs (from F-018 on): configuration X in round N. |
| Violation codes | `disallowed_axiom` | Why the proof checker rejected something (section 5). |
| `sqlite.…`, `app.…` | `sqlite.durable_commit` | A **guarantee** in the register: something a rule relies on. |

---

## 4. What every evidence file is

A run folder `evidence/<run-id>/` holds:

| File | Contents |
|---|---|
| `before.json` | The baseline measured before any change, plus the environment and git state |
| `verdicts.json` | The meaning verdict for every optimisation claim, with all its evidence |
| `benchmark.json` | Everything measured (each configuration, each repetition, per operation, per second) |
| `samples/*.csv.gz` | **Every individual request**: operation, HTTP status, start time and latency in nanoseconds |
| `tests.xml`, `tests.log` | The test suite's results inside the checker container (JUnit format) |
| `verdicts.log` | What the verdict step printed |
| `manifest.json` | A **SHA-256** of every file above, plus the git commit and whether the tree was "dirty" |

Shared files in `evidence/`:
- `findings.json`: everything learned, failures included.
- `index.json`: every run, and whether it's valid.
- `latest.txt`: the newest run id.
- `mutations-2026-11-07.json`: raw mutation results.
- `nagle-experiment-…txt` and `fsync-probe-…txt`: raw experiment output.

**How to check a fingerprint yourself:**

```bash
sha256sum "evidence/20261107T090049Z/benchmark.json"
```

That must print the same hex string as `manifest.json`. Or check all of a
run's files at once:

```bash
python3 bench/verify_manifest.py evidence/20261107T090049Z
```

**"dirty": true** means the code had uncommitted changes when that run was
made, so the commit alone doesn't reproduce it exactly. Runs 1 and 2 were
dirty, because the code was still changing. The owner's run should start from
a clean commit.

---

## 5. How a Lean claim is checked (the seven steps)

`python -m burden_of_proof prove` shows these one by one. Any failure rejects the
claim.

1. **The spec lock matches.** Nobody edited the spec since the owner
   approved it. *Code:* `spec_lock_mismatch`.
2. **`lake build` succeeds.** *Codes:* `build_failed`, `proof_module_missing`.
3. **The statement is real:** a `Prop` defined in the spec, built only from
   Lean's core library and the spec. *Codes:* `statement_missing`,
   `statement_not_in_spec`, `statement_not_prop`,
   `statement_uses_outside_spec`.
4. **The proof proves exactly that statement,** is a `theorem`, and lives
   under `Proofs`. *Codes:* `proof_missing`, `proof_not_in_proofs`,
   `proof_not_theorem`, `proof_statement_mismatch`.
5. **No escape hatches.** The axioms used are within
   `propext, Classical.choice, Quot.sound`, and none of our code is
   `unsafe`, `implemented_by` or `extern`. *Codes:* `disallowed_axiom`,
   `unsafe`, `implemented_by`, `extern`.
6. **The vacuity guard.** If the statement has assumptions, a `_witness`
   theorem shows they can all be met. Otherwise "if 1 = 2 then anything"
   would count as a proof. *Codes:* `vacuity_witness_missing`,
   `vacuity_witness_mismatch`.
7. **Two kernels re-check everything.** `leanchecker` replays the compiled
   code through Lean's kernel, and `con-leche` checks it again,
   independently. *Codes:* `kernel_replay_failed`, `second_kernel_failed`.
   Step 7 exists because of finding F-001: a forged theorem passed every
   other step.

---

## 6. How an optimisation claim is judged (`optcheck`)

1. **Observe guarantees** on a live database: read SQLite's
   `journal_mode` and `synchronous` settings, and decide whether a commit is
   durable, using SQLite's documented rule. Losing a guarantee without
   declaring it gives `undeclared_drop`.
2. **Declared drops need proofs.** If a claim admits it drops a guarantee, a
   Lean proof must show the affected rule still holds. A failure gives
   `drop_without_compensation` or `compensation_unproved`.
3. **Known refutations.** If Lean proved the claim false, the code is
   `refuted_in_lean`.
4. **Conformance.** 100 random operation sequences go through the store and
   the compiled spec; any difference gives `differs_from_model`. The shortest
   failing sequence is found by **shrinking**: repeatedly delete an operation
   while it still fails.

Only after all of that is anything timed.

---

## 7. Glossary

- **Lean 4.** A programming language and proof checker. When it accepts a
  proof, the statement is mathematically true, *of the model*.
- **Kernel.** The small core of Lean that actually checks proofs.
  Everything else is convenience. "Kernel replay" re-checks compiled proofs
  with it.
- **Axiom.** Something assumed rather than proved. `sorry` is an axiom
  meaning "trust me"; we only allow Lean's three standard ones.
- **Vacuous truth.** "Every unicorn is blue" is true because there are no
  unicorns. A statement whose assumptions can never hold proves nothing,
  which is why the witness exists.
- **Spec / model.** A precise description of what the system should do. Here
  it's Lean code that also *runs*.
- **Conformance / differential testing.** Feed the same inputs to the spec
  and to the real code, and compare the outputs exactly.
- **Counterexample / shrinking.** A concrete input that breaks a claim.
  Shrinking makes it as small as possible, so a person can understand it.
- **Guarantee.** Something the platform promises and our rules rely on, such
  as "a committed payment survives a power cut".
- **Durable commit.** Once the database says "saved", the data survives a
  crash or power loss.
- **WAL (write-ahead log).** A SQLite journal mode: changes go to a log file
  first, so readers aren't blocked by writers.
- **`synchronous`.** How often SQLite forces data to disk: OFF(0), NORMAL(1),
  FULL(2), EXTRA(3). Higher is safer and slower.
- **fsync.** The operating-system call that forces data onto the physical
  disk. It's slow, and on this laptop its speed varies (F-018).
- **Index.** A lookup structure that lets the database find rows without
  scanning the whole table. It never changes results, only speed.
- **p50 / p95 / p99.** Percentiles of latency. p99 = 12 ms means 99% of
  requests finished within 12 ms. The median (p50) shows the typical
  request; p99 shows the slow tail that users notice.
- **Throughput (req/s).** Successful requests completed per second.
- **Repetition and spread.** We repeat each measurement. If repetitions
  disagree by 30%, a 10% difference between configurations means nothing.
- **Interleaving.** Alternating configurations in shuffled rounds, so
  background drift hits all of them equally.
- **Nagle's algorithm and delayed ACK.** Two TCP features that, together,
  can delay small replies by about 40 ms. Our first benchmark measured this
  instead of the database (F-016). `TCP_NODELAY` turns Nagle off.
- **SHA-256 / hash / fingerprint.** A 64-character hex summary of a file's
  bytes. Change one byte and the hash changes completely. It proves a file
  wasn't altered.
- **git commit / dirty tree.** The commit identifies the exact code. "Dirty"
  means there were uncommitted changes.
- **Docker image / container.** An image is a frozen recipe and filesystem;
  a container is a running copy of one. Our server and load generator are
  separate containers.
- **WSL2.** Windows Subsystem for Linux: a real Linux kernel in a
  lightweight VM on Windows.
- **Mutation testing ("bite").** Break the code on purpose. If no test
  fails, the tests weren't protecting it.

---

## 8. Decisions taken, and why

Each has an ADR with the full reasoning.

| ADR | Decision | Why, in one line |
|---|---|---|
| 0002 | Meaning is checked; speed is only measured | Speed depends on hardware and noise; a proof of speed is only a proof about a model |
| 0003 | Lean 4 at the centre, specialist tools later | Executable spec, small trusted kernel, AWS Cedar precedent |
| 0004 | The spec is reviewed and hash-locked by a person | Lean checks the proof, not that the statement means what we want |
| 0005, 0020 | Claims are typed TOML records | Machines can route, re-check and cite them; TOML needs no extra library |
| 0006, 0017, 0018 | Seven-step proof check, two kernels, vacuity guard | Every one of these was needed to stop a real cheat (fixtures in `tests/`) |
| 0007 | The real code is compared with the compiled spec | Proofs cover the model; conformance links the model to the code |
| 0008 | The guarantee register | Optimisations usually "work" by dropping a guarantee; make that visible |
| 0009, 0012 | A ledger as the first domain, built here | Many money rules, expensive bugs; there's no outside app |
| 0010 | Evidence from tools; every test must bite | No figure worked out by hand; a test that can't fail proves nothing |
| 0014, 0015 | SQLite first, then Postgres (portable) | SQLite runs anywhere; Postgres adds isolation levels |
| 0016 | Python for the tooling | Standard library has exact fractions and SQLite; no installs needed |
| 0019, 0021 | A stdlib HTTP API, run in Docker inside WSL2 | Isolated, reproducible, and the same SQLite build everywhere |

**Decisions made inside the code, not in an ADR yet:**
- **Baseline `synchronous=EXTRA`, not FULL:** SQLite documents FULL with a
  rollback journal as not durable (F-008).
- **Server `TCP_NODELAY`:** otherwise the benchmark measures TCP (F-016).
- **Interleaved measurement rounds:** the disk drifts on its own (F-018).
- **Clean replays cached in memory, never on disk:** a cache file could be
  forged to skip the kernel check (F-004).
- **Integers for money, never floats:** `0.1 * 3 == 0.3` is `False` in
  Python.

---

## 9. What the agent read and when (session log, 2026-11-07)

So you can see where each fact came from:

| When | Read | For |
|---|---|---|
| Start | Your KT document and LinkedIn post | Intent → README, ADRs 0001–0010 |
| Lean install | `raw.githubusercontent.com/leanprover/elan/master/elan-init.ps1` (read in full before running) | Installing elan |
| Lean checks | `#print axioms` output on test files | F-002, F-003 |
| Toolchain | `~/.elan/toolchains/…/bin/` listing; `--help` of each tool | Found `leanchecker`, `con-leche` |
| Postgres | `postgresql.org/versions.json`; EDB's binaries page | Version 18.6 and its download (ADR-0015) |
| Durability | `sqlite.org/pragma.html#pragma_synchronous` | The durability rule (F-008, `claims/guarantees.toml`) |
| WSL | `learn.microsoft.com/en-us/windows/wsl/install` | Your install commands |
| Docker | `docs.docker.com/engine/install/ubuntu/` | The Docker install script |
| Benchmarks | `evidence/<run>/benchmark.json` (every repetition, per operation, per second) | F-016, F-017, F-018, F-020 |
| Your blog | `D:\Potfolio` (content guide, posts, `mdx-components.tsx`) | Matching the write-up to your site |

Raw command outputs from the session are in the journal
(the private lab notebook) and in `evidence/`.

---

## 10. How to learn the code, in this order

1. `Spec/Ledger.lean`: what the system *should* do. Short and commented.
2. `reference/ledger/store.py`: what it *does*, in plain Python and SQL.
3. `burden_of_proof/differential.py`: how the two are compared.
4. `Proofs/Ledger.lean`: how the statements are proved.
5. `burden_of_proof/leancheck.py`, then `tools/leancheck/Main.lean`: how a proof is
   checked.
6. `burden_of_proof/optcheck.py` and `claims/`: how an optimisation is judged.
7. `bench/`: how speed is measured.
8. `tests/fixtures/lean_project/Proofs/*.lean`: the fake proofs, one cheat
   per file.
