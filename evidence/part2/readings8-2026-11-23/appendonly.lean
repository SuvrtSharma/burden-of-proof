import Spec.Retro
open Spec.Retro
/-! LR3 / the spec's `appendOnly`, tested exhaustively: for every sequence of up
to 3 events and every next event (dates 0..3 and 9, every kind, a reversal of
each earlier event), when neither run is stuck, the ledger before must be a
prefix of the ledger after. -/
def kinds : List Kind := [.disburse 10, .charge 3, .pay 5 .feeFirst, .pay 20 .feeFirst]
def seqs : Nat → List (List Event)
  | 0 => [[]]
  | n + 1 => (seqs n) ++ ((seqs n).filter (·.length == n)).flatMap fun pre =>
      let id := pre.length + 1
      let ks := kinds ++ (pre.map fun e => Kind.reverse e.id)
      (List.range 3).flatMap fun d => ks.map fun k => pre ++ [⟨id, d, k⟩]
def nexts (pre : List Event) : List Event :=
  let id := pre.length + 1
  let ks := kinds ++ (pre.map fun e => Kind.reverse e.id)
  [0, 1, 2, 3, 9].flatMap fun d => ks.map fun k => ⟨id, d, k⟩
def pairs := ((seqs 3).filter (·.length > 0)).flatMap fun s => (nexts s).map (s, ·)
def violates (p : List Event × Event) : Bool :=
  let a := forkSync p.1; let b := forkSync (p.1 ++ [p.2])
  !a.stuck && !b.stuck && !(a.ledger.isPrefixOf b.ledger)
#eval let bad := pairs.filter violates
  IO.println s!"pairs tested: {pairs.length}, append-only violations: {bad.length}"
#eval match ((pairs.filter violates).toArray.qsort (fun x y => (repr x).pretty.length < (repr y).pretty.length)).toList.head? with
  | some p => IO.println s!"smallest violation: {(repr p).pretty 100000}"
  | none => IO.println "no violation"
