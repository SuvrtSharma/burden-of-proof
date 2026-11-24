import Spec.Retro
open Spec.Retro
/-! Bite checks for the claims as fixed on 2026-11-22 (run against the edited draft). -/

-- paymentConserved, as a Bool check on one allocation `d` of payment `a` against balance `b`.
def conservedOK (b : Bal) (a : Int) (o : Alloc) (d : Bal) : Bool :=
  let F := max b.fee 0; let P := max b.principal 0
  (-d.fee - d.principal + d.excess == a) && (0 ≤ -d.fee) && (-d.fee ≤ F) && (0 ≤ -d.principal) &&
  (-d.principal ≤ P) && (0 ≤ d.excess) && (!(0 < d.excess) || (-d.fee == F && -d.principal == P)) &&
  (o != .feeFirst || !(0 < -d.principal) || -d.fee == F) &&
  (o != .principalFirst || !(0 < -d.fee) || -d.principal == P)

def b0 : Bal := ⟨5, 10, 0⟩   -- owes fee 5 and principal 10
-- The three absurd allocations that passed the old statement now fail it:
#eval ("all to excess", conservedOK b0 8 .feeFirst ⟨0, 0, 8⟩)
#eval ("principal first, stated fee first", conservedOK b0 8 .feeFirst ⟨0, -8, 0⟩)
#eval ("7x to fee", conservedOK b0 8 .feeFirst ⟨-56, 0, -48⟩)
-- The spec's own effect passes on a grid (the theorem proves it for all inputs):
def grid : List (Bal × Int × Alloc) := Id.run do
  let mut out := []
  for f in [-3, 0, 4, 9] do for p in [-2, 0, 6, 15] do for a in [1, 4, 7, 20] do
    for o in [Alloc.feeFirst, .principalFirst] do out := (⟨f, p, 0⟩, a, o) :: out
  return out
#eval ("spec effect on grid", grid.length, grid.all fun (b, a, o) => conservedOK b a o (effect b (.pay a o)))

-- rebuildIgnoresArrival as fixed: exhaustive test on short accepted lists and all their reorderings.
def perms : List Event → List (List Event)
  | [] => [[]]
  | x :: xs => (perms xs).flatMap fun p => (List.range (p.length + 1)).map fun i => p.take i ++ [x] ++ p.drop i
def evU : List Event :=
  [⟨1, 0, .disburse 10⟩, ⟨1, 1, .charge 3⟩, ⟨2, 0, .pay 5 .feeFirst⟩, ⟨2, 2, .pay 5 .principalFirst⟩,
   ⟨3, 1, .disburse 4⟩, ⟨3, 0, .reverse 1⟩, ⟨4, 2, .reverse 2⟩, ⟨4, 1, .charge 2⟩]
def lists : Nat → List (List Event)
  | 0 => [[]]
  | n + 1 => [[]] ++ ((lists n).flatMap fun l => evU.map (· :: l))
def accLists := ((lists 4).eraseDups).filter fun l => accepted l == l
def pairs := accLists.flatMap fun l => ((perms l).filter fun l' => accepted l' == l').map (l, ·)
def newHolds (l l' : List Event) : Bool :=
  (rebuildState l).1 == (rebuildState l').1 &&
  (List.range 6).all fun id => impactOf (rebuildState l) id == impactOf (rebuildState l') id
#eval ("fixed rebuildIgnoresArrival: accepted lists", accLists.length, "pairs", pairs.length,
       "holds on all", pairs.all fun (l, l') => newHolds l l',
       "old statement holds on all", pairs.all fun (l, l') => rebuildState l == rebuildState l')
-- F5: reversed events are now in the compared state, with the zero the rebuild gives them.
def dbl : List Event := [⟨1, 0, .disburse 10⟩, ⟨2, 1, .disburse 10⟩, ⟨3, 2, .reverse 2⟩, ⟨4, 3, .reverse 1⟩]
#eval ("double reversal subjects", (subjects dbl).map (·.id), "live", (live dbl).map (·.id),
       "rebuild", rebuildState dbl, "forkSync", forkSyncState dbl, "stuck", (forkSync dbl).stuck)
