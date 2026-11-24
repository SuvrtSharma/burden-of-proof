# Capability map: what Lean 4 can model in a modern SaaS system

The main research output of track 1 (ADR-0012). Each row is filled in **only
from evidence**: a proof file, a counterexample or a measured run. An honest
"no" or "too costly" is as valuable as a "yes".

Columns:

- **Model:** can we express it as executable Lean definitions?
- **Prove:** did we prove the rule for all inputs, with no escape hatches?
- **Run:** is the model fast enough for differential testing?
- **Cost:** effort spent and what was hard (recorded at the time)
- **Evidence:** claim ids or files

Values: `untested` · `yes` · `partial` · `no` · `out of reach` (with a note).

## Correctness concerns

| Concern | Model | Prove | Run | Cost | Evidence |
|---|---|---|---|---|---|
| Balances derived from bills, payments and allocations | untested | untested | untested | | |
| Conservation (Σ balances = billed − paid) | untested | untested | untested | | |
| Over-allocation limits (per payment, per bill) | untested | untested | untested | | |
| Reversal / restore conserves totals | untested | untested | untested | | |
| Deterministic ordering with unique tie-break | untested | untested | untested | | |
| Exact integer rounding (half-up once) | untested | untested | untested | | |
| Tenant isolation (no cross-tenant reads/writes) | untested | untested | untested | | |
| Role-based access rules | untested | untested | untested | | |
| Idempotent request handling (retries) | untested | untested | untested | | |
| Soft delete and its interaction with totals | untested | untested | untested | | |
| Schema migration preserves data meaning | untested | untested | untested | | |
| State machines (invoice draft → issued → paid → void) | untested | untested | untested | | |
| Pagination or caps never change totals (bug pattern 5) | untested | untested | untested | | |

## Optimisation concerns (meaning only; speed is measured separately)

| Optimisation | Kind | Guarantee touched | Model | Prove | Evidence |
|---|---|---|---|---|---|
| Add an index | orthodox | none | untested | untested | |
| Reuse prepared statements | orthodox | none ⚠ (schema changes invalidate them) | untested | untested | |
| Index chosen to avoid a sort | orthodox | ordering ⚠ only if the order is fully determined | untested | untested | |
| Batch writes in one transaction | orthodox | atomicity grows | untested | untested | |
| Cache a derived balance | orthodox | freshness | untested | untested | |
| Denormalise a total into a column | unorthodox | single source of truth | untested | untested | |
| `synchronous = OFF` / async commit | unorthodox | durable commit | untested | untested | |
| Direct SQLite B-tree access (skip VDBE) | unorthodox | constraints, triggers, index upkeep ⚠ | untested | untested | |
| Drop a filter because ids are unguessable | unorthodox | access check | untested | untested | |
