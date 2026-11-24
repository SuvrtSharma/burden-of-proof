import Spec

-- Proves something weaker than any spec statement.
def Proofs.OutsideSpec.weak : Prop := True

theorem Proofs.OutsideSpec.t : Proofs.OutsideSpec.weak := trivial

theorem Proofs.OutsideSpec.leaky : Spec.leaky := trivial
