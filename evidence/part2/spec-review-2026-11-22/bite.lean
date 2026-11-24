import Spec.Retro
open Spec.Retro
-- paymentConserved's statement, re-proved by the same tactic for three absurd allocations.
def allToExcess (b : Bal) (a : Int) : Bal := ⟨0, 0, a⟩
def principalFirst (b : Bal) (a : Int) : Bal :=
  let toP := min a (max b.principal 0); let toF := min (a - toP) (max b.fee 0); ⟨-toF, -toP, a - toF - toP⟩
def sevenTimesToFee (b : Bal) (a : Int) : Bal := ⟨-(7 * a), 0, a - 7 * a⟩
theorem t1 : ∀ (b : Bal) (a : Int), let d := allToExcess b a; -d.fee - d.principal + d.excess = a := by
  intro b a; simp only [allToExcess]; omega
theorem t2 : ∀ (b : Bal) (a : Int), let d := principalFirst b a; -d.fee - d.principal + d.excess = a := by
  intro b a; simp only [principalFirst]; omega
theorem t3 : ∀ (b : Bal) (a : Int), let d := sevenTimesToFee b a; -d.fee - d.principal + d.excess = a := by
  intro b a; simp only [sevenTimesToFee]; omega
#print axioms t3
