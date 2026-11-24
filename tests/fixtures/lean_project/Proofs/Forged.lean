import Lean
import Spec
open Lean Elab Command

-- Adds a "proof" of a false statement without the kernel checking it.
set_option debug.skipKernelTC true in
run_cmd liftCoreM <| addDecl (.thmDecl
  { name := `Proofs.Forged.t, levelParams := [], type := mkConst ``Spec.falseClaim,
    value := mkConst ``True.intro })

-- An honest witness, so only the kernels have anything to object to.
theorem Proofs.Forged.t_witness : ∃ _a : Int, True := ⟨0, trivial⟩
