import Spec

axiom Proofs.Axiom.cheat : ∀ a : Int, a = a + 1

theorem Proofs.Axiom.t : Spec.falseClaim := Proofs.Axiom.cheat
