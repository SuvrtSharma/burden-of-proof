---
name: check-optimisation-claim
description: Judge a claim that a change is "safe and faster" by checking its meaning first (what guarantees it drops, and whether the rules still hold, proved in Lean) and only then measuring speed with interleaved rounds and an expiry date. Use for caching, indexes, skipping work, incremental recomputation, relaxed durability or locking, or any rewrite sold on performance.
---

# Check an optimisation claim

An optimisation claim has two parts. **Meaning** ("it gives the same answer")
can be checked. **Speed** ("it's faster") can only be measured. Check meaning
first; don't time anything that hasn't passed.

## 1. Split the claim

Write the claim as a record (see `claims/optimisations/*.toml` for the shape):

- `agent_says`: the claim in the proposer's words.
- `drops`: every guarantee it removes: a full scan, a lock, a durable commit,
  a filter, recomputation from scratch. Look them up in the guarantee register
  (`claims/guarantees.toml`); each lists the rules that need it.
- For each rule that needs a dropped guarantee: either a statement that
  compensates (proved), or a known refutation.

An undeclared drop is a finding in itself. Where a guarantee can be observed
live (for example, a database's durability setting), observe it; don't trust
the declaration.

## 2. Meaning: prove it keeps the answer, or refute it

The strongest form is **exact equivalence with the slow, obviously correct
version**: "rebuilding from the earliest affected point gives exactly the full
rebuild" rather than "the balance is still right".

1. Test the equivalence exhaustively on small cases first, and count them.
2. Run plausible wrong versions on the same cases, each of which **must fail**:
   - the off-by-one
   - "apply it at the end"
   - the tempting shortcut ("subtract its own effect only")

   If one passes, your test or statement is too weak.
3. Prove it with the `check-lean-claim` skill. leancheck must accept it.
4. If it's false, a proved counterexample is the result. Reproduce it in the
   real code, against that code's own unoptimised run, before calling it a
   property of the code.

## 3. Speed: measure, never prove

Only after meaning passes:

- The same workloads for every engine. Cover the regimes that matter
  (recent versus deep changes, sizes, the mix of operations).
- One discarded warm-up, then at least three timed rounds **in rotated
  order**. Report medians.
- Call it **faster** only if its slowest round beat the baseline's fastest
  round. Otherwise report "no clear difference".
- Record the machine, versions, commit and an **expiry date**. A measurement
  is a fact about one environment, for a while.
- If an engine doesn't finish (a timeout, a heap or stack overflow), record that
  as a result, with its limit. Don't drop the workload.

## 4. Report

| | |
|---|---|
| Verdict | accept / reject / unproved, for meaning; faster / no clear difference / slower, for speed |
| Guarantees dropped | declared and observed |
| Evidence | leancheck verdicts, counterexample, case counts, the wrong versions caught, timing files |
| Limits | readings it depends on, what the model leaves out, the expiry |

Every number comes from a tool run. Nothing is computed in your head.
