import Spec.Retro
open Spec.Retro
def cex : List Event := [⟨1, 2, .disburse 10⟩, ⟨2, 0, .disburse 10⟩, ⟨3, 1, .pay 20 .feeFirst⟩]
#eval ("rebuild", (rebuild cex).1, "forkSync", current (forkSync cex).ledger)
def two : List Event := cex.take 2
#eval ("ledger after two arrivals", (forkSync two).ledger.map fun e => (e.source, e.eff, e.delta.principal, e.running.principal))
#eval ("forkAtDate .. 1", (forkAtDate (forkSync two).ledger 1).map fun e => (e.source, e.eff, e.running.principal),
       "current of fork", (current (forkAtDate (forkSync two).ledger 1)).principal,
       "sum of its deltas", ((forkAtDate (forkSync two).ledger 1).foldl (fun a x => a.add x.delta) Bal.zero).principal)
