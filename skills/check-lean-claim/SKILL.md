---
name: check-lean-claim
description: Prove or refute a claim about code or a design in Lean 4, and accept the result only if burden_of_proof.leancheck accepts it against a locked spec. Use when someone (or you) claims a rule always holds, two versions behave the same, or an optimisation keeps its meaning, and the claim can be stated over a model.
---

# Check a claim in Lean

A claim counts as **verified** only when `leancheck` accepts its proof against
a spec a person has locked. Anything else is **unproved**, which is not the
same as false.

## 1. State it against the spec, not the code

- The statement is a `Prop` definition in the spec (`Spec.…`). If none fits,
  draft one and **stop for the person who owns the spec** to review and lock
  it. Never edit a locked spec or its lock file yourself.
- Write down every reading you had to choose where the source (a paper, a
  ticket, the code) leaves something open. A result that depends on a reading
  must say so.
- Write the meaning in one plain sentence next to it. If you can't, the
  statement is probably wrong.

## 2. Make sure it can fail

Before proving anything:

- Evaluate it on small concrete cases (`#eval`, or `decide` on a concrete
  instance). A claim you think is true should hold on them.
- Write at least one plausible wrong version (an off-by-one, the shortcut an
  engineer would take) and check that it **fails**. If no wrong version fails,
  the statement says too little: strengthen it.
- If the statement has binders, prove they can all be satisfied: a theorem
  named `<proof>_witness` that mirrors the statement's binders and hypotheses
  and ends in `True`, for example
  `∃ (evs : List Event) (e : Event), ∃ (_ : live (evs ++ [e]) = live evs ++ [e]), True`.
  A theorem with an impossible premise is true and useless; leancheck rejects
  one without a witness (`vacuity_witness_missing`).

## 3. Prove or refute

- **Proof:** `theorem Proofs.M.t : Spec.thatProp`, typed exactly as the
  statement (otherwise `proof_statement_mismatch`).
- **Refutation:** prove the negation with one concrete, terminating
  counterexample. Keep the counterexample as data: it becomes a regression
  test.
- Never use `sorry`, `axiom`, `native_decide`, `unsafe`, `implemented_by` or
  `extern`. leancheck rejects them (`disallowed_axiom`).

## 4. Check it

```
python -m burden_of_proof.leancheck --project DIR --statement Spec.X --proof Proofs.M.t --module Proofs.M
```

| Exit | Meaning | What you report |
|---|---|---|
| 0 | accepted: exact statement, no escape hatch, two kernels, witness present | **verified**, with the JSON verdict |
| 1 | rejected; violation codes in the JSON | **not verified**, and why |
| 2 | the tool couldn't run | **not checked**, and the error |

Violation codes: `statement_missing`, `proof_missing`, `proof_module_missing`,
`proof_statement_mismatch`, `spec_lock_mismatch`, `build_failed`,
`disallowed_axiom`, `vacuity_witness_missing`, `vacuity_witness_mismatch`,
`kernel_replay_failed`, `second_kernel_failed`.

## 5. Report

- Quote the verdict file, the lock's SHA-256, and the statement in plain words.
- Say what the proof is about: **the model**. Connecting it to real code needs
  a mapping, or a reproduction in that code against its own on-time run.
- List every reading the result depends on, and everything not checked.
- Never round "unproved" up to "verified", or down to "false".
