import Spec

theorem Proofs.NativeDecide.t : Spec.small := by
  unfold Spec.small; native_decide
