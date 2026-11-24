# Burden of Proof

**Tools and agent skills that make an AI agent's claims about software carry
their own evidence.**

An agent says *"this optimisation is safe"*, *"this rewrite behaves the same"*,
*"this is faster"*. Today those claims are mostly taken on trust. Here, each
claim is split in two:

- **Meaning**, which can be checked: a Lean 4 proof against a spec a person
  reviewed and locked, or a concrete counterexample.
- **Speed**, which can only be measured: interleaved timed rounds, medians, a
  strict rule for calling anything faster, and an expiry date.

Meaning is checked first. Nothing is timed until it passes.

## What it has found so far

| Case study | What was checked | Result |
|---|---|---|
| **Part 1: an agent-built ledger** | Six optimisations an agent proposed for a ledger API it wrote | 14 of 14 Lean claims accepted against the owner's locked spec; one optimisation refuted by a proved counterexample; one undeclared durability drop caught by a live guarantee check |
| **Part 2: a published algorithm** | *Fork-and-sync*, from a draft paper on correcting a loan ledger for late events ([Precise Ledger Pro](https://github.com/v1bh0r/precise-ledger-pro), MIT) | 7 of 7 proofs accepted: 3 counterexamples where the modelled fork-and-sync and a full rebuild part ways, 2 rebuild properties, and a cheaper rebuild **proved exact**. In the project's own Haskell port that rebuild is faster on all 32 workloads, median 11.86× (expires 2027-02-22) |

Write-ups, with every figure traced to an evidence file in this repo:

- [I made AI agents prove their claims. The benchmark lied first.](https://suvrtsharma.vercel.app/blog/making-ai-agents-prove-their-claims)
- [How the claim checker is built](https://suvrtsharma.vercel.app/blog/how-the-claim-checker-is-built)
- [A ledger I didn't write: checking a paper's open question with Lean 4](https://suvrtsharma.vercel.app/blog/a-ledger-i-didnt-write)
- Dashboards: [part 1](https://suvrtsharma.vercel.app/results/gods-hand) and
  [part 2](https://suvrtsharma.vercel.app/results/retroactive-ledger)

## What's in the box

| Piece | What it does |
|---|---|
| [`burden_of_proof/leancheck.py`](burden_of_proof/leancheck.py) + [`tools/leancheck/`](tools/leancheck) | Accepts a Lean proof only if it proves *exactly* the locked statement, uses no escape hatch (`sorry`, extra axioms, `native_decide`, `extern`…), replays in two independent kernels, and comes with a witness that its assumptions can hold |
| [`burden_of_proof/speclock.py`](burden_of_proof/speclock.py) | SHA-256 lock over the spec. Change one character and every proof is rejected until a person reviews and re-locks it |
| [`burden_of_proof/optcheck.py`](burden_of_proof/optcheck.py) | Optimisation claims: which guarantees each drops, checked against a [guarantee register](claims/guarantees.toml), live observation and differential runs |
| [`bench/`](bench) | The measurement protocol: discarded warm-up, rotated interleaved rounds, medians, expiry |
| [`skills/`](skills) | Claude Code skills that put an agent through the same steps |
| [`agents/`](agents) | A fresh-context reviewer agent that tries to break a claim before anyone believes it |

## Use it from an agent

Copy a skill into your project (or `~/.claude/skills/`):

```
skills/check-lean-claim/          prove or refute a claim in Lean, checked by leancheck
skills/check-optimisation-claim/  meaning first, then speed, for "this is safe and faster"
agents/claim-reviewer.md          an adversarial review before you report anything
```

The skills never let an agent say "verified" unless the checker accepted the
proof, and they report "unproved" as unproved, never as false.

## Run it yourself

Needs Python 3.14 and [elan](https://github.com/leanprover/elan) (the Lean
version comes from `lean-toolchain`, 4.35.0). No Mathlib.

```
python -m venv .venv
.venv/bin/python -m pip install -e ".[dev]"      # Windows: .venv\Scripts\python.exe
(cd tools/leancheck && lake build) && lake build
(cd part2 && lake build Proofs)                   # leancheck checks built proofs; it doesn't build them
.venv/bin/python -m pytest                        # minutes, mostly kernel replay
```

Check one claim:

```
python -m burden_of_proof.leancheck --project part2 \
  --statement Spec.Retro.rebuildFromInsertExact \
  --proof Proofs.Retro.rebuildFromInsertExact --module Proofs.Retro
```

Exit 0 means accepted, 1 rejected (violation codes in the JSON), 2 the tool
couldn't run. [docs/RUNBOOK.md](docs/RUNBOOK.md) reproduces every published
result.

## Rules this repo holds itself to

- **Unverified is not done.** "Unproved" never becomes "verified", and never
  becomes "false".
- **The spec is reviewed by a person and locked.** Lean checks the proof; it
  can't check that the English was translated correctly.
- **No arithmetic in anyone's head.** Every figure comes from a tool run, and
  every test is shown to fail when what it protects is broken.
- **Money is integer minor units.** Never floats.

The decisions behind these are in [docs/adr/](docs/adr/README.md).

## Layout

```
burden_of_proof/   the checker, the spec lock, the optimisation checker
tools/leancheck/   the Lean program that inspects compiled proofs
Spec/ Proofs/      part 1: the locked ledger spec and its proofs
part2/             part 2: the locked model of fork-and-sync, and its proofs
claims/            typed claim records and the guarantee register
reference/ bench/  part 1's reference ledger API and the measurement harness
tools/plp/         part 2's harnesses for the Haskell port and Java service
evidence/          raw outputs of every published run
skills/ agents/    for Claude Code
docs/              ADRs, runbook, developer tour, part 2 mapping and rules
```

## About the name, and what isn't here

The project's working name was *God's Hand*. The locked specs, their lakefiles
and the recorded evidence still say `godshand`: changing a single byte of a
locked file voids every proof until it is reviewed again, and evidence records
what actually ran. The part 2 Java harnesses keep their class names for the same
reason.

This is a curated public copy. The lab notebook stays private: the daily
journal, the original design notes, reading notes on Precise Ledger Pro that
haven't yet gone to its author, early runs, and full Java logs that print the
project's configuration. Where a document cites one of those, it says so.

## Limits

- Each domain needs a spec a person reviews. Agents draft it; people approve it.
- Proofs are about the model. Connecting a model to real code takes a mapping
  and conformance tests, and conformance samples; it doesn't prove.
- Speed never gets a proof, and every measurement expires.

## Licence

[Apache-2.0](LICENSE).
