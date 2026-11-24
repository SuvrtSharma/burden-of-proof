import Spec

unsafe def Proofs.Unsafe.u : Nat := 0

-- Lean itself refuses a safe theorem that uses an unsafe definition.
theorem Proofs.Unsafe.t : Spec.small := by
  have _h : Proofs.Unsafe.u = Proofs.Unsafe.u := rfl
  unfold Spec.small; decide
