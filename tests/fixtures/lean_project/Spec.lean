-- Fixture spec for the pipeline's own tests. Not a real domain.
import Proofs.Weak

namespace Spec

/-- True: moving `x` from one account to another conserves the total. -/
def conserve : Prop := ∀ a b x : Int, (a - x) + (b + x) = a + b

/-- False: no integer equals its successor. -/
def falseClaim : Prop := ∀ a : Int, a = a + 1

/-- True and decidable, for the `native_decide` cheat. -/
def small : Prop := 2 + 2 = 4

/-- Leaks a definition from outside the spec into a statement. -/
def leaky : Prop := Proofs.Weak.weak

/-- Vacuous: provable only because `a < a` never holds. -/
def vacuous : Prop := ∀ a : Int, a < a → a = a + 1

/-- A refutation: `falseClaim` is false. No witness needed. -/
def refuteFalseClaim : Prop := ¬ falseClaim

/-- Not a Prop at all. -/
def notProp : Nat := 3

/-- A theorem placed in the spec instead of under Proofs. -/
theorem inSpec : small := by unfold small; decide

end Spec
