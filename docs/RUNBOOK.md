# Runbook: reproduce every result yourself

Every claim in the write-up comes from one of these commands. Run them in
order in the **Ubuntu (WSL) terminal** and screenshot the outputs marked 📸.
Nothing here needs a password. The commands are read-only on your working
copy except where a step says otherwise.

Times are rough, measured on this machine (i5-10300H, WSL2 VM with 8 CPUs
and 3.8 GB).

---

## 0. Open the terminal and go to the repo

From Windows, open **Ubuntu** from the Start menu (or run `wsl -d Ubuntu-24.04`), then:

```bash
cd "/mnt/d/Burden of Proof"
```

```bash
git log --oneline -1 && git status --short | head
```

📸 This shows which commit you are testing and whether anything is uncommitted.

## 1. Build the two images (once, and after any code change)

```bash
docker build -f docker/ledger.Dockerfile -t burden-of-proof/ledger:dev .
```

```bash
docker build -f docker/checker.Dockerfile -t burden-of-proof/checker:dev .
```

The first build of the checker image downloads the Lean toolchain: about
11 minutes, 4.7 GB. A rebuild takes about 1 minute.

---

## Part A: the proofs

### 2. Read what is being proved

```bash
docker run --rm -t burden-of-proof/checker:dev python -m burden_of_proof spec
```

📸 This prints each statement **verbatim from `Spec/Ledger.lean`**, with
line numbers, and the state of the spec lock. Right now it shows
`✕ no spec.lock.json`: an agent drafted the spec, and nobody has approved it.

Read `Spec/Ledger.lean` in full before the next step. That human review is
the one step no tool can do for you: Lean proves the statements are true,
but only a person can say they mean what we want.

### 3. Lock the spec (owner only)

This is the only step that writes to your working copy. It creates
`spec.lock.json`.

```bash
docker run --rm -v "$PWD:/work" -w /work burden-of-proof/checker:dev python -m burden_of_proof.speclock update --project .
```

```bash
docker build -q -f docker/checker.Dockerfile -t burden-of-proof/checker:dev . && docker run --rm -t burden-of-proof/checker:dev python -m burden_of_proof spec
```

📸 It should now show `✓ every locked file matches spec.lock.json` and the
lock hash. Commit the lock file afterwards (`git add spec.lock.json`), so the
approval is on record.

### 4. Check every Lean claim, step by step

```bash
docker run --rm -t burden-of-proof/checker:dev python -m burden_of_proof prove
```

📸 One block per claim. Each shows the claim in plain words, the exact
statement, and every check it passed:
- the lock;
- the build;
- the shape of the statement and the proof;
- the axioms used;
- the vacuity witness;
- replay by Lean's kernel;
- a second check by an independent kernel (`con-leche`).

There are **14 claims** (spec v2, ADR-0022):
- **settlement:** within limits, settles the maximum, oldest first;
- **every reachable state:**
  - unique ids, positive amounts, same-party allocations;
  - never over-settled, never over-applied;
  - advances always applied;
  - every view of a balance agrees;
  - reversal restores the balance;
  - parties are isolated;
  - (date, id) order;
  - the cached balance agrees;
- **rejection** of non-positive amounts;
- **one refutation**, `LEDGER-CAPPED-SCAN-REFUTED`: a proof that the
  agent's "LIMIT 20" optimisation is false.

About 2 minutes.

### 5. Try to fake a proof, and watch each attempt get caught

```bash
docker run --rm -t burden-of-proof/checker:dev python -m burden_of_proof cheats
```

📸 There are 13 ways to fake a proof, plus one honest control. Highlight
**"Forge the theorem with the kernel switched off"**: the build passes and
`#print axioms` reports no axioms, but both kernels reject it. About 3
minutes.

### 6. See the refuted optimisation evaluated by Lean

```bash
docker run --rm -t burden-of-proof/checker:dev python -m burden_of_proof counterexample
```

📸 Lean computes both versions on the same input: two bills that each owe
5, and an advance of 8. The spec pays bill 1 in full and 3 to bill 2. The
capped version pays only bill 1, leaving 3 unused while bill 2 stays open.

### 7. Run the compiled spec yourself

The spec's own definitions, compiled into a program. This is what the real
server gets compared with.

```bash
printf '%s\n' '{"op":"pay","party":1,"amount":100}' '{"op":"bill","party":1,"date":10,"amount":80}' '{"op":"bill","party":1,"date":5,"amount":50}' '{"op":"reverse","payment":1}' '{"op":"open","party":1}' '{"op":"balance","party":1}' '{"op":"bill","party":1,"date":1,"amount":0}' | docker run --rm -i burden-of-proof/checker:dev .lake/build/bin/ledgermodel
```

📸 One JSON response per operation. Your review case, pay 100 then bill
80, is settled from the advance. The bill dated day 5 takes the next 20.
The reversal reopens both bills, listed in date order. A zero amount is
rejected.

### 8. The test suite, and proof that each test bites

```bash
docker run --rm -t burden-of-proof/checker:dev python -m pytest -q -rs
```

📸 The counts (about 3 minutes).

```bash
docker run --rm -t burden-of-proof/checker:dev python tools/mutate.py
```

📸 29 mutations. Each removes one check from the tooling, and the tests
guarding it must fail. It runs on the container's copy of the code, never
your files. About 25 minutes.

---

## Part B: the system, before and after

The API server and the load generator run in **separate containers on
separate CPUs** (server on 0–3, load on 4–7), on a private Docker network.
Each phase writes its evidence to `evidence/<run-id>/`.

### 9. Before: tests, then measure the baseline

```bash
python3 bench/docker_run.py before
```

📸 The table: requests per second for **each repetition**, the median, p99
latency, and a **sanity** column. The sanity check flags any run where a
trivial read's median is above 10 ms; that would mean it measured the
network, not the database. Our first run had exactly that problem (findings
F-016). About 5 minutes.

### 10. Check: what does each proposed optimisation mean?

```bash
python3 bench/docker_run.py check
```

📸 For each of the six optimisation claims:
- what the agent said;
- the guarantee observed on a live database (durable commit or not);
- conformance against the spec over 100 random operation sequences;
- the Lean evidence, if the claim needs any;
- the verdict, with its reasons and any shrunk counterexample.

No timing is involved in any verdict. About 6 minutes.

### 11. After: apply only what was accepted, and measure again

```bash
python3 bench/docker_run.py after --each
```

This phase measures in **interleaved rounds**. Each round runs every
configuration once, on a fresh server, in a shuffled order that's printed,
and **the baseline is re-measured in each round**. That's needed because
this machine's virtual disk varies its fsync rate by about 4× on its own
(findings F-018). Measured back to back, that drift would look like an
effect of whichever configuration happened to be running.

📸 Two tables:
- the earlier BEFORE run, for reference;
- AFTER: the baseline, each claim on its own (rejected ones labelled), and
  `ALL-ACCEPTED`, all from the same time window.

Read the spread between repetitions before the ratios: a difference smaller
than the spread is no result. About 15 minutes.

### 12. Check the evidence wasn't changed afterwards

```bash
python3 bench/verify_manifest.py
```

📸 Every file of the run is re-hashed against its manifest, which also
records the commit.

---

## What to send back

Tell me the run id from `cat evidence/latest.txt`. The dashboard and the
write-up are built from that run's files, so every figure in them traces to
your screenshots.
