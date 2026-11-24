import Spec

-- True, but only because the hypothesis can never hold. No witness.
theorem Proofs.Vacuous.t : Spec.vacuous := by intro a h; omega

-- A witness for a different, easier proposition.
theorem Proofs.Vacuous.u : Spec.vacuous := by intro a h; omega
theorem Proofs.Vacuous.u_witness : ∃ _a : Int, True := ⟨0, trivial⟩

-- The right witness proposition, "proved" with sorry.
theorem Proofs.Vacuous.v : Spec.vacuous := by intro a h; omega
theorem Proofs.Vacuous.v_witness : ∃ a : Int, ∃ _ : a < a, True := sorry
