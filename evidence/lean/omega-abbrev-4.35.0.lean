-- Reproduction for Spec/Ledger.lean's note on `abbrev Money := Int` (Lean 4.35.0).
-- The same goal is proved over `Int` and fails over an `abbrev` of `Int`.
-- Run: lake env lean evidence/lean/omega-abbrev-4.35.0.lean
abbrev M := Int

example (x y : Int) (h : x ≤ y) : x - 1 < y := by omega   -- proved

example (x y : M) (h : x ≤ y) : x - 1 < y := by omega     -- fails on 4.35.0: "No usable constraints found"

-- Unfolding the abbrev first makes it work, so the limitation is in how omega
-- collects atoms, not in the logic:
example (x y : M) (h : x ≤ y) : x - 1 < y := by simp only [M] at *; omega
