# ADR-0002: Split every claim into meaning and speed

- **Status:** Accepted
- **Date:** 2026-11-07
- **Deciders:** project owner
- **Cites claims:** none

## Context

Agents often bundle a correctness claim and a performance claim into one
sentence: "add this hint, it's faster and returns the same rows". The two
parts need different kinds of evidence:

- **Meaning** (the results are unchanged and the rules still hold) can be
  proved or refuted over a model.
- **Speed** depends on hardware, data, the planner and the cache state. A
  "proof" of speed is a proof about a cost model, and that model's accuracy
  is itself an empirical question.

Optimising my own server (prepared statement reuse, indexes that remove a
sort, direct SQLite B-tree access to skip VDBE bytecode) produces exactly this
kind of bundled claim.

## Decision

1. Every incoming claim is split into a **meaning** part and a **speed**
   part. Either part may be empty.
2. The meaning part goes to a checker (see ADR-0003). The speed part goes
   **only** to the measurement protocol, and it never receives a "proved"
   status.
3. A speed result is valid only together with its recorded environment:
   hardware, OS, stack versions, data size and shape, configuration, warm or
   cold cache, the number of runs, and the variance. It also carries an
   **expiry or re-check date**.
4. **Profile before you accept.** A performance claim is not accepted until
   a measurement has shown where the time actually goes. This stops agents
   "optimising" a cost that isn't the bottleneck.
5. If a speed claim relies on removing a guarantee, its meaning part must
   declare that guarantee (ADR-0008).

## Alternatives considered

- **Prove speed with a cost model:** that only moves the problem, because
  the model still has to be validated by measurement. It is allowed as a
  supporting argument, never as the evidence.
- **Accept the benchmarks agents report:** they lack a recorded environment
  and can't be reproduced.

## Consequences

- An optimisation can be "meaning: verified, speed: unmeasured". That is an
  honest, useful state.
- Measured results go stale, so the registry has to track expiry dates.
- The detailed measurement protocol is still to be designed (phase 3).

## Revisit when

A cost model is shown, by measurement, to predict this workload within an
agreed error. Even then, it only supports the evidence.
