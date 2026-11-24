import Spec

/-- Compiled code calls a C symbol instead of this definition. -/
@[extern "burden_of_proof_fake_symbol"]
def Proofs.Extern.g (n : Nat) : Nat := n

theorem Proofs.Extern.t : Spec.conserve := by
  have _h : Proofs.Extern.g 0 = 0 := rfl
  intro a b x; omega
