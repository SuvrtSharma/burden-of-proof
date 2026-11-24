import Spec.Retro
open Spec.Retro

-- (a) Same-date tie: the paper applies by arrival, the oracle by id (READING 1 vs 5).
def tieCase : List Event := [⟨2, 0, .disburse 10⟩, ⟨1, 0, .pay 5⟩]
#eval ("tie: rebuild", (rebuild tieCase).1, "forkSync", current (forkSync tieCase).ledger,
       "stuck", (forkSync tieCase).stuck)

-- (b) rebuildIgnoresArrival: two arrival orders of the same accepted events.
def p1 : List Event := [⟨1, 0, .disburse 10⟩, ⟨2, 1, .charge 5⟩]
def p2 : List Event := p1.reverse
#eval ("perm: accepted p1 = p1", accepted p1 == p1, "accepted p2 = p2", accepted p2 == p2)
#eval ("perm: same balance", (rebuildState p1).1 == (rebuildState p2).1,
       "same full state", rebuildState p1 == rebuildState p2)
#eval ("perm: impacts p1", (rebuildState p1).2.map (·.1), "impacts p2", (rebuildState p2).2.map (·.1))

-- (d) isort vs mergeSort, exhaustively on short lists with ties and duplicate ids.
def univ : List Event :=
  [⟨1, 0, .disburse 1⟩, ⟨2, 0, .charge 1⟩, ⟨1, 0, .charge 2⟩, ⟨3, 1, .pay 1⟩, ⟨2, 1, .disburse 3⟩]
def listsUpTo : Nat → List (List Event)
  | 0 => [[]]
  | n + 1 => [[]] ++ ((listsUpTo n).flatMap fun l => univ.map (· :: l))
def allLists := (listsUpTo 4).eraseDups
def entryLe (a b : Nat × Event) : Bool := a.2.eff ≤ b.2.eff
#eval ("sort check: lists", allLists.length,
       "isort = mergeSort (before)", allLists.all fun l => l.isort before == l.mergeSort before,
       "isort = mergeSort (eff only, pairs)",
         allLists.all fun l => let m := l.zipIdx.map (fun (x, i) => (i, x)); m.isort entryLe == m.mergeSort entryLe)
