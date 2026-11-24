import Spec

def Proofs.ImplementedBy.fast (n : Nat) : Nat := n + 1

/-- Compiled code runs `fast`, which disagrees with this definition. -/
@[implemented_by Proofs.ImplementedBy.fast]
def Proofs.ImplementedBy.f (n : Nat) : Nat := n

theorem Proofs.ImplementedBy.t : Spec.conserve := by
  have _h : Proofs.ImplementedBy.f 0 = 0 := rfl
  intro a b x; omega
