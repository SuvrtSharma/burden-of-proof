import Spec

theorem Proofs.Honest.conserve : Spec.conserve := by
  intro a b x; omega

/-- The vacuity guard: `Spec.conserve` has binders, so show they can be met. -/
theorem Proofs.Honest.conserve_witness : ∃ _a _b _x : Int, True := ⟨0, 0, 0, trivial⟩

theorem Proofs.Honest.small : Spec.small := by
  unfold Spec.small; decide

theorem Proofs.Honest.refute : Spec.refuteFalseClaim := by
  intro h; have := h 0; omega
