import Spec.Retro
open Spec.Retro
/-! Every sequence of up to 3 events (ids 1..n in arrival order, dates 0..2,
kinds as in Explore.lean plus reversals of earlier events), with forkSync's
compared state and how many adjustment entries it posted. Run before and after
a spec change and diff the outputs. -/
def kinds : List Kind := [.disburse 10, .charge 3, .pay 5 .feeFirst, .pay 20 .feeFirst]
def seqs : Nat → List (List Event)
  | 0 => [[]]
  | n + 1 => (seqs n) ++ ((seqs n).filter (·.length == n)).flatMap fun pre =>
      let id := pre.length + 1
      let ks := kinds ++ (pre.map fun e => Kind.reverse e.id)
      (List.range 3).flatMap fun d => ks.map fun k => pre ++ [⟨id, d, k⟩]
def all3 := (seqs 3).filter (·.length > 0)
def line (evs : List Event) : String :=
  let r := forkSync evs
  s!"{(repr evs).pretty 100000} | stuck {r.stuck} | adj {(r.ledger.filter (·.kind == .adjustment)).length} | state {(repr (forkSyncState evs)).pretty 100000} | eqRebuild {forkSyncState evs == rebuildState evs}"
#eval IO.println s!"sequences: {all3.length}"
#eval do for s in all3 do IO.println (line s)
