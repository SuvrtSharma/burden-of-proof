/-
Running the draft spec on examples (ADR-0025, decision 4). This is not part of
the spec and is not evidence for any claim: a mismatch found here is a
candidate counterexample until it reproduces against the code under test and a
Lean refutation is accepted by the checker.

Run: `lake env lean Explore.lean` from `part2/`.
-/
import Spec.Retro
open Spec.Retro

/-! ## The paper's section 7 scenario, without interest (step 1 has none)

Amounts in cents. Dates as day numbers: 1 = 2024-03-01, and so on. Business
timestamps add hours: eff = day * 100 + hour. -/

def paperNoInterest : List Event := [
  ⟨123, 100, .disburse 100000000⟩,    -- disbursal $1,000,000, 03-01
  ⟨234, 313, .pay 1000000 .principalFirst⟩,           -- payment #234 $10,000, 03-03 13:00
  ⟨456, 510, .pay 500000 .principalFirst⟩,            -- payment #456 $5,000, 03-05 10:00
  ⟨900, 513, .reverse 234⟩,           -- reversal of #234, 03-05 13:00
  ⟨768, 314, .pay 400000 .principalFirst⟩ ]           -- backdated payment #768 $4,000, 03-03 14:00

#eval (forkSync paperNoInterest).stuck
#eval forkSyncState paperNoInterest == rebuildState paperNoInterest
#eval forkSyncState paperNoInterest
#eval (forkSync paperNoInterest).ledger.length

/-! ## Every short sequence from a small alphabet

Kinds: disburse 10, charge 3, pay 5, pay 20; business timestamps 0, 1, 2; and
a reversal of any earlier event. Ids are assigned two ways: in arrival order,
and against it, so that same-timestamp ties test the "never by arrival" rule
(LR8, LR10). -/

def baseKinds : List Kind := [.disburse 10, .charge 3, .pay 5 .feeFirst, .pay 20 .feeFirst]
def effs : List Nat := [0, 1, 2]

/-- All sequences of length `n`. `mkId pos` gives the id of the event at that
arrival position. -/
def seqs (mkId : Nat → Nat) : Nat → List (List Event)
  | 0 => [[]]
  | n + 1 =>
    (seqs mkId n).flatMap fun pre =>
      let pos := pre.length
      let plain := baseKinds.flatMap fun k => effs.map fun d => pre ++ [⟨mkId pos, d, k⟩]
      let revs := pre.filter (fun e => !isReversal e) |>.flatMap fun t =>
        effs.map fun d => pre ++ [⟨mkId pos, d, .reverse t.id⟩]
      plain ++ revs

structure Tally where
  total : Nat := 0
  stuck : Nat := 0
  mismatch : Nat := 0
  firstMismatch : Option (List Event) := none

def tally (xs : List (List Event)) : Tally :=
  xs.foldl (fun t evs =>
    let r := forkSync evs
    let t := { t with total := t.total + 1 }
    if r.stuck then { t with stuck := t.stuck + 1 }
    else if forkSyncState evs == rebuildState evs then t
    else { t with mismatch := t.mismatch + 1,
                  firstMismatch := t.firstMismatch <|> some evs }) {}

def report (label : String) (t : Tally) : String :=
  s!"{label}: {t.total} sequences, {t.stuck} ran out of fuel, {t.mismatch} differ from the rebuild"

def upTo (mkId : Nat → Nat) (n : Nat) : List (List Event) :=
  (List.range (n + 1)).flatMap (seqs mkId)

#eval report "ids in arrival order, length <= 3" (tally (upTo (· + 1) 3))
#eval report "ids against arrival order, length <= 3" (tally (upTo (fun p => 50 - p) 3))
#eval (tally (upTo (· + 1) 3)).firstMismatch
#eval (tally (upTo (fun p => 50 - p) 3)).firstMismatch

/-! ## Separating the causes

Same-timestamp ties are one cause: the rebuild orders ties by id (LR8 as
approved), while the paper appends ties in arrival order. To see whether
anything else differs, count mismatches among sequences whose timestamps are
all distinct, where no tie rule is involved. -/

def distinctEffs (evs : List Event) : Bool :=
  let ds := evs.map (·.eff)
  ds.eraseDups.length == ds.length

#eval report "ids in arrival order, distinct timestamps, length <= 3"
  (tally ((upTo (· + 1) 3).filter distinctEffs))
#eval ((upTo (· + 1) 3).filter distinctEffs |> tally).firstMismatch

/-! The smallest such case, traced: two disbursals, the second backdated, then
a backdated payment. -/

def lateAfterLate : List Event :=
  [⟨1, 2, .disburse 10⟩, ⟨2, 0, .disburse 10⟩, ⟨3, 1, .pay 20 .feeFirst⟩]

#eval (forkSync lateAfterLate).ledger
#eval forkSyncState lateAfterLate
#eval rebuildState lateAfterLate
