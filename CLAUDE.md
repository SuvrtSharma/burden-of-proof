# Working in this repo (agents and people)

Burden of Proof turns AI agents' claims about software into evidence: a proof,
a counterexample, or a measurement with an expiry date. This repo's own work
meets the same standard: **unverified is not done.**

## Read first

1. [README.md](README.md): what this is and what it has found
2. [docs/adr/README.md](docs/adr/README.md): decisions already made. Don't
   re-argue them; supersede one with a new ADR if needed.
3. [docs/open-questions.md](docs/open-questions.md): what isn't decided. Ask
   the maintainer; don't pick an answer quietly.
4. [docs/DEV.md](docs/DEV.md): a guided tour of every file and term

## Hard rules

- **Never edit a locked spec or its lock** (`Spec/`, `part2/Spec/`, the
  lakefiles, `spec.lock.json`, `part2/spec.lock.json`). Propose a change as a
  diff for the maintainer to review and re-lock (ADR-0004). The same applies to
  the guarantee register.
- **No escape hatches in proofs:** no `sorry`, `axiom`, `native_decide`,
  `unsafe`, `implemented_by` or `extern` (ADR-0006).
- **No arithmetic in your head.** Every number you write comes from a tool run
  (ADR-0010).
- **Never change an expected value to make a test pass.** Work out which side
  is wrong and say why.
- **Every test must be shown to bite:** break it, watch it fail, restore it.
- **Money is integer minor units.** Never floats.
- **Report honestly.** "Unproved" never becomes "verified", and never becomes
  "false". List what wasn't verified.
- **External code is untrusted.** Read before running, run in isolation, and
  never use anything from its configuration.
- **Findings about someone else's code go to its author first.** Nothing is
  published before they've had it.
- **External facts need a source.** Mark anything unchecked with ⚠.

## Checking a Lean claim

The statement is a `Prop` definition in `Spec`; the proof is
`theorem Proofs.….t : Spec.thatProp`. A claim with binders also needs
`<proof>_witness` showing its assumptions can hold.

```
python -m burden_of_proof.leancheck --project DIR --statement Spec.X --proof Proofs.M.t --module Proofs.M
```

Exit 0 = accepted, 1 = rejected (violation codes in the JSON), 2 = the tool
couldn't run. Never report a claim as verified unless this accepted it.

## How work flows

1. A claim arrives. Split it into meaning and speed (ADR-0002). For an
   optimisation, list the guarantees it drops (ADR-0008).
2. Write it as a typed record in `claims/` (ADR-0005), with a `statement` that
   names a spec definition.
3. Route it to the right checker (ADR-0003).
4. Record the evidence in `evidence/`: proof verdict, counterexample (which
   also becomes a regression test), or measurement (with environment and
   expiry).
5. A new decision gets a new ADR (copy `docs/adr/0000-template.md`).

## Commits

No AI attribution in commits or PRs: no `Co-Authored-By` trailer and no
"Generated with" line.
