import Spec
open Spec Spec.Ledger

namespace Proofs.Ledger

/-! ## Lists of `(id, amount)` -/

def Pos (xs : List (Nat × Int)) : Prop := ∀ x ∈ xs, 0 < x.2

theorem pos_cons {x : Nat × Int} {xs : List (Nat × Int)} : Pos (x :: xs) ↔ 0 < x.2 ∧ Pos xs := by
  simp [Pos]

theorem total_cons (x : Nat × Int) (xs : List (Nat × Int)) : total (x :: xs) = x.2 + total xs := by
  simp [total]

theorem total_nonneg : ∀ {xs : List (Nat × Int)}, Pos xs → 0 ≤ total xs
  | [], _ => by simp [total]
  | x :: xs, h => by
    rw [pos_cons] at h
    have := total_nonneg h.2
    rw [total_cons]; omega

theorem sum_cons_alloc (x : Alloc) (A : List Alloc) :
    ((x :: A).map (·.amount)).sum = x.amount + (A.map (·.amount)).sum := by simp

/-! ## Settles the maximum -/

theorem matchUp_sum (owed adv : List (Nat × Int)) (ho : Pos owed) (ha : Pos adv) :
    ((matchUp owed adv).map (·.amount)).sum = min (total owed) (total adv) := by
  induction owed, adv using matchUp.induct with
  | case1 x =>
    have := total_nonneg ha
    simp [matchUp, total] at *; omega
  | case2 x hx =>
    have := total_nonneg ho
    cases x with
    | nil => exact absurd rfl hx
    | cons y ys => simp [matchUp, total] at *; omega
  | case3 b o bs p a ps hlt ih =>
    rw [pos_cons] at ho ha
    have ih' := ih ho.2 (by rw [pos_cons]; exact ⟨by simp; omega, ha.2⟩)
    rw [matchUp, ite_eq_left hlt, sum_cons_alloc, ih', total_cons, total_cons, total_cons]
    simp only at *
    omega
  | case4 b o bs p a ps hnlt hlt ih =>
    rw [pos_cons] at ho ha
    have ih' := ih (by rw [pos_cons]; exact ⟨by simp; omega, ho.2⟩) ha.2
    rw [matchUp, ite_eq_right hnlt, ite_eq_left hlt, sum_cons_alloc, ih', total_cons, total_cons, total_cons]
    simp only at *
    omega
  | case5 b o bs p a ps hnlt hnlt' ih =>
    rw [pos_cons] at ho ha
    have ih' := ih ho.2 ha.2
    rw [matchUp, ite_eq_right hnlt, ite_eq_right hnlt', sum_cons_alloc, ih', total_cons, total_cons]
    simp only at *
    omega

/-! ## Limits -/

theorem paidTo_cons (x : Alloc) (A : List Alloc) (b : Nat) :
    paidTo (x :: A) b = (if x.bill = b then x.amount else 0) + paidTo A b := by
  by_cases h : x.bill = b <;> simp [paidTo, h]

theorem takenFrom_cons (x : Alloc) (A : List Alloc) (p : Nat) :
    takenFrom (x :: A) p = (if x.payment = p then x.amount else 0) + takenFrom A p := by
  by_cases h : x.payment = p <;> simp [takenFrom, h]

/-- Every allocation is positive and names an offered bill and payment. -/
theorem matchUp_mem (owed adv : List (Nat × Int)) (ho : Pos owed) (ha : Pos adv) :
    ∀ x ∈ matchUp owed adv, 0 < x.amount ∧ x.bill ∈ owed.map (·.1) ∧ x.payment ∈ adv.map (·.1) := by
  induction owed, adv using matchUp.induct with
  | case1 x => simp [matchUp]
  | case2 x hx => cases x with
    | nil => exact absurd rfl hx
    | cons y ys => simp [matchUp]
  | case3 b o bs p a ps hlt ih =>
    rw [pos_cons] at ho ha
    have ih' := ih ho.2 (by rw [pos_cons]; exact ⟨by simp; omega, ha.2⟩)
    intro x hx
    rw [matchUp, ite_eq_left hlt] at hx
    rcases List.mem_cons.mp hx with rfl | hx
    · simp at *; omega
    · obtain ⟨h1, h2, h3⟩ := ih' x hx
      refine ⟨h1, by simp at h2 ⊢; exact Or.inr h2, by simpa using h3⟩
  | case4 b o bs p a ps hnlt hlt ih =>
    rw [pos_cons] at ho ha
    have ih' := ih (by rw [pos_cons]; exact ⟨by simp; omega, ho.2⟩) ha.2
    intro x hx
    rw [matchUp, ite_eq_right hnlt, ite_eq_left hlt] at hx
    rcases List.mem_cons.mp hx with rfl | hx
    · simp at *; omega
    · obtain ⟨h1, h2, h3⟩ := ih' x hx
      refine ⟨h1, by simpa using h2, by simp at h3 ⊢; exact Or.inr h3⟩
  | case5 b o bs p a ps hnlt hnlt' ih =>
    rw [pos_cons] at ho ha
    have ih' := ih ho.2 ha.2
    intro x hx
    rw [matchUp, ite_eq_right hnlt, ite_eq_right hnlt'] at hx
    rcases List.mem_cons.mp hx with rfl | hx
    · simp at *; omega
    · obtain ⟨h1, h2, h3⟩ := ih' x hx
      refine ⟨h1, by simp at h2 ⊢; exact Or.inr h2, by simp at h3 ⊢; exact Or.inr h3⟩

theorem paidTo_absent (A : List Alloc) (b : Nat) (h : ∀ x ∈ A, x.bill ≠ b) : paidTo A b = 0 := by
  induction A with
  | nil => simp [paidTo]
  | cons x A ih =>
    rw [paidTo_cons, if_neg (h x (by simp)), ih (fun y hy => h y (by simp [hy]))]; simp

theorem takenFrom_absent (A : List Alloc) (p : Nat) (h : ∀ x ∈ A, x.payment ≠ p) : takenFrom A p = 0 := by
  induction A with
  | nil => simp [takenFrom]
  | cons x A ih =>
    rw [takenFrom_cons, if_neg (h x (by simp)), ih (fun y hy => h y (by simp [hy]))]; simp

theorem ids_cons {x : Nat × Int} {xs : List (Nat × Int)} :
    ((x :: xs).map (·.1)).Nodup ↔ x.1 ∉ xs.map (·.1) ∧ (xs.map (·.1)).Nodup := by
  simp [List.nodup_cons]

theorem ne_of_mem_tail {y : Nat} {xs : List (Nat × Int)} {t : Nat × Int}
    (hy : y ∉ xs.map (·.1)) (ht : t ∈ xs) : y ≠ t.1 := by
  intro h; apply hy; rw [h]; exact List.mem_map.mpr ⟨t, ht, rfl⟩

theorem bill_absent {y : Nat} {xs : List (Nat × Int)} {A : List Alloc} (hy : y ∉ xs.map (·.1))
    (mem : ∀ x ∈ A, x.bill ∈ xs.map (·.1)) : ∀ x ∈ A, x.bill ≠ y := by
  intro x hx h; apply hy; rw [← h]; exact mem x hx

theorem payment_absent {y : Nat} {xs : List (Nat × Int)} {A : List Alloc} (hy : y ∉ xs.map (·.1))
    (mem : ∀ x ∈ A, x.payment ∈ xs.map (·.1)) : ∀ x ∈ A, x.payment ≠ y := by
  intro x hx h; apply hy; rw [← h]; exact mem x hx

/-- No bill is paid more than it was owed. -/
theorem matchUp_paidTo_le (owed adv : List (Nat × Int)) (ho : Pos owed) (ha : Pos adv)
    (hn : (owed.map (·.1)).Nodup) : ∀ t ∈ owed, paidTo (matchUp owed adv) t.1 ≤ t.2 := by
  induction owed, adv using matchUp.induct with
  | case1 x => simp
  | case2 x hx => cases x with
    | nil => exact absurd rfl hx
    | cons y ys => intro t _; simp [matchUp, paidTo]; have := ho t (by assumption); omega
  | case3 b o bs p a ps hlt ih =>
    have hpos := ho; rw [pos_cons] at ho ha; rw [ids_cons] at hn
    have hadv : Pos ((p, a - o) :: ps) := by rw [pos_cons]; exact ⟨by simp; omega, ha.2⟩
    have mem := matchUp_mem bs ((p, a - o) :: ps) ho.2 hadv
    intro t ht
    rw [matchUp, ite_eq_left hlt, paidTo_cons]
    rcases List.mem_cons.mp ht with rfl | ht
    · rw [paidTo_absent _ _ (bill_absent hn.1 (fun x hx => (mem x hx).2.1))]; simp
    · have hne : b ≠ t.1 := ne_of_mem_tail hn.1 ht
      rw [if_neg hne]; simpa using ih ho.2 hadv hn.2 t ht
  | case4 b o bs p a ps hnlt hlt ih =>
    rw [pos_cons] at ho ha
    have hown : Pos ((b, o - a) :: bs) := by rw [pos_cons]; exact ⟨by simp; omega, ho.2⟩
    have hn' : (((b, o - a) :: bs).map (·.1)).Nodup := by simpa using hn
    rw [ids_cons] at hn
    intro t ht
    rw [matchUp, ite_eq_right hnlt, ite_eq_left hlt, paidTo_cons]
    rcases List.mem_cons.mp ht with rfl | ht
    · have := ih hown ha.2 hn' (b, o - a) (by simp); simp at this ⊢; omega
    · have hne : b ≠ t.1 := ne_of_mem_tail hn.1 ht
      rw [if_neg hne]; simpa using ih hown ha.2 hn' t (by simp [ht])
  | case5 b o bs p a ps hnlt hnlt' ih =>
    rw [pos_cons] at ho ha; rw [ids_cons] at hn
    have mem := matchUp_mem bs ps ho.2 ha.2
    intro t ht
    rw [matchUp, ite_eq_right hnlt, ite_eq_right hnlt', paidTo_cons]
    rcases List.mem_cons.mp ht with rfl | ht
    · rw [paidTo_absent _ _ (bill_absent hn.1 (fun x hx => (mem x hx).2.1))]; simp
    · have hne : b ≠ t.1 := ne_of_mem_tail hn.1 ht
      rw [if_neg hne]; simpa using ih ho.2 ha.2 hn.2 t ht

/-- No payment gives more than its advance. -/
theorem matchUp_takenFrom_le (owed adv : List (Nat × Int)) (ho : Pos owed) (ha : Pos adv)
    (hn : (adv.map (·.1)).Nodup) : ∀ t ∈ adv, takenFrom (matchUp owed adv) t.1 ≤ t.2 := by
  induction owed, adv using matchUp.induct with
  | case1 x => intro t ht; simp [matchUp, takenFrom]; have := ha t ht; omega
  | case2 x hx => simp
  | case3 b o bs p a ps hlt ih =>
    rw [pos_cons] at ho ha
    have hadv : Pos ((p, a - o) :: ps) := by rw [pos_cons]; exact ⟨by simp; omega, ha.2⟩
    have hn' : (((p, a - o) :: ps).map (·.1)).Nodup := by simpa using hn
    rw [ids_cons] at hn
    intro t ht
    rw [matchUp, ite_eq_left hlt, takenFrom_cons]
    rcases List.mem_cons.mp ht with rfl | ht
    · have := ih ho.2 hadv hn' (p, a - o) (by simp); simp at this ⊢; omega
    · have hne : p ≠ t.1 := ne_of_mem_tail hn.1 ht
      rw [if_neg hne]; simpa using ih ho.2 hadv hn' t (by simp [ht])
  | case4 b o bs p a ps hnlt hlt ih =>
    rw [pos_cons] at ho ha
    have hown : Pos ((b, o - a) :: bs) := by rw [pos_cons]; exact ⟨by simp; omega, ho.2⟩
    rw [ids_cons] at hn
    have mem := matchUp_mem ((b, o - a) :: bs) ps hown ha.2
    intro t ht
    rw [matchUp, ite_eq_right hnlt, ite_eq_left hlt, takenFrom_cons]
    rcases List.mem_cons.mp ht with rfl | ht
    · rw [takenFrom_absent _ _ (payment_absent hn.1 (fun x hx => (mem x hx).2.2))]; simp
    · have hne : p ≠ t.1 := ne_of_mem_tail hn.1 ht
      rw [if_neg hne]; simpa using ih hown ha.2 hn.2 t ht
  | case5 b o bs p a ps hnlt hnlt' ih =>
    rw [pos_cons] at ho ha; rw [ids_cons] at hn
    have mem := matchUp_mem bs ps ho.2 ha.2
    intro t ht
    rw [matchUp, ite_eq_right hnlt, ite_eq_right hnlt', takenFrom_cons]
    rcases List.mem_cons.mp ht with rfl | ht
    · rw [takenFrom_absent _ _ (payment_absent hn.1 (fun x hx => (mem x hx).2.2))]; simp; omega
    · have hne : p ≠ t.1 := ne_of_mem_tail hn.1 ht
      rw [if_neg hne]; simpa using ih ho.2 ha.2 hn.2 t ht

/-! ## Oldest first -/

theorem getElem_ne_head {b : Nat} {o : Int} {bs : List (Nat × Int)} (hn : (b, o).1 ∉ bs.map (·.1))
    (i : Nat) (h : i < bs.length) : b ≠ bs[i].1 :=
  ne_of_mem_tail hn (List.getElem_mem h)

/-- A bill receives anything only if every bill before it is paid in full. -/
theorem matchUp_oldest_first (owed adv : List (Nat × Int)) (ho : Pos owed) (ha : Pos adv)
    (hn : (owed.map (·.1)).Nodup) :
    ∀ (i j : Nat) (hi : i < owed.length) (hj : j < owed.length), i < j →
      0 < paidTo (matchUp owed adv) owed[j].1 → paidTo (matchUp owed adv) owed[i].1 = owed[i].2 := by
  induction owed, adv using matchUp.induct with
  | case1 x => intro i j hi; simp at hi
  | case2 x hx => cases x with
    | nil => exact absurd rfl hx
    | cons y ys => intro i j hi hj hij h; simp [matchUp, paidTo] at h
  | case3 b o bs p a ps hlt ih =>
    rw [pos_cons] at ho ha; rw [ids_cons] at hn
    have hadv : Pos ((p, a - o) :: ps) := by rw [pos_cons]; exact ⟨by simp; omega, ha.2⟩
    have mem := matchUp_mem bs ((p, a - o) :: ps) ho.2 hadv
    intro i j hi hj hij h
    rw [matchUp, ite_eq_left hlt] at h ⊢
    cases i with
    | zero =>
      simp only [List.getElem_cons_zero, paidTo_cons]
      rw [paidTo_absent _ _ (bill_absent hn.1 (fun x hx => (mem x hx).2.1))]; simp
    | succ i =>
      cases j with
      | zero => omega
      | succ j =>
        simp only [List.length_cons] at hi hj
        simp only [List.getElem_cons_succ, paidTo_cons] at h ⊢
        rw [if_neg (getElem_ne_head hn.1 i (by omega))]
        rw [if_neg (getElem_ne_head hn.1 j (by omega))] at h
        simpa using ih ho.2 hadv hn.2 i j (by omega) (by omega) (by omega) (by simpa using h)
  | case4 b o bs p a ps hnlt hlt ih =>
    rw [pos_cons] at ho ha
    have hown : Pos ((b, o - a) :: bs) := by rw [pos_cons]; exact ⟨by simp; omega, ho.2⟩
    have hn' : (((b, o - a) :: bs).map (·.1)).Nodup := by simpa using hn
    rw [ids_cons] at hn
    intro i j hi hj hij h
    rw [matchUp, ite_eq_right hnlt, ite_eq_left hlt] at h ⊢
    simp only [List.length_cons] at hi hj
    cases j with
    | zero => omega
    | succ j =>
      simp only [List.getElem_cons_succ, paidTo_cons] at h
      rw [if_neg (getElem_ne_head hn.1 j (by omega))] at h
      have hj' : 0 < paidTo (matchUp ((b, o - a) :: bs) ps) ((b, o - a) :: bs)[j + 1].1 := by
        simpa using h
      cases i with
      | zero =>
        have := ih hown ha.2 hn' 0 (j + 1) (by simp) (by simp; omega) (by omega) hj'
        simp only [List.getElem_cons_zero, paidTo_cons] at this ⊢
        simp at this ⊢; omega
      | succ i =>
        simp only [List.getElem_cons_succ, paidTo_cons]
        rw [if_neg (getElem_ne_head hn.1 i (by omega))]
        have := ih hown ha.2 hn' (i + 1) (j + 1) (by simp; omega) (by simp; omega) (by omega) hj'
        simpa using this
  | case5 b o bs p a ps hnlt hnlt' ih =>
    rw [pos_cons] at ho ha; rw [ids_cons] at hn
    have mem := matchUp_mem bs ps ho.2 ha.2
    intro i j hi hj hij h
    rw [matchUp, ite_eq_right hnlt, ite_eq_right hnlt'] at h ⊢
    cases i with
    | zero =>
      simp only [List.getElem_cons_zero, paidTo_cons]
      rw [paidTo_absent _ _ (bill_absent hn.1 (fun x hx => (mem x hx).2.1))]; simp
    | succ i =>
      cases j with
      | zero => omega
      | succ j =>
        simp only [List.length_cons] at hi hj
        simp only [List.getElem_cons_succ, paidTo_cons] at h ⊢
        rw [if_neg (getElem_ne_head hn.1 i (by omega))]
        rw [if_neg (getElem_ne_head hn.1 j (by omega))] at h
        simpa using ih ho.2 ha.2 hn.2 i j (by omega) (by omega) (by omega) (by simpa using h)

/-! ## The matching statements, as the spec states them -/

theorem wf_iff (xs : List (Nat × Int)) : wellFormed xs ↔ (xs.map (·.1)).Nodup ∧ Pos xs := Iff.rfl

theorem matchWithinLimits : Spec.matchWithinLimits := by
  intro owed adv ho ha
  exact ⟨matchUp_mem owed adv ho.2 ha.2, matchUp_paidTo_le owed adv ho.2 ha.2 ho.1,
    matchUp_takenFrom_le owed adv ho.2 ha.2 ha.1⟩

theorem matchWithinLimits_witness :
    ∃ (owed adv : List (Nat × Int)) (_ : wellFormed owed) (_ : wellFormed adv), True :=
  ⟨[], [], by simp [wellFormed], by simp [wellFormed], trivial⟩

theorem matchSettlesMaximum : Spec.matchSettlesMaximum := by
  intro owed adv ho ha
  exact matchUp_sum owed adv ho.2 ha.2

theorem matchSettlesMaximum_witness :
    ∃ (owed adv : List (Nat × Int)) (_ : wellFormed owed) (_ : wellFormed adv), True :=
  ⟨[], [], by simp [wellFormed], by simp [wellFormed], trivial⟩

theorem matchPaysOldestFirst : Spec.matchPaysOldestFirst := by
  intro owed adv ho ha
  exact matchUp_oldest_first owed adv ho.2 ha.2 ho.1

/-- The hypotheses are reachable: bills of 5 and 5, an advance of 8; bill 2 receives 3. -/
theorem matchPaysOldestFirst_witness :
    ∃ (owed adv : List (Nat × Int)) (_ : wellFormed owed) (_ : wellFormed adv)
      (i j : Nat) (hi : i < owed.length) (hj : j < owed.length) (_ : i < j)
      (_ : 0 < paidTo (matchUp owed adv) owed[j].1), True :=
  ⟨[(1, 5), (2, 5)], [(9, 8)], by simp [wellFormed], by simp [wellFormed], 0, 1,
    by simp, by simp, by omega, by simp [matchUp, paidTo], trivial⟩

/-! ## Rejection, order, and the capped scan -/

theorem rejectsNonPositive : Spec.rejectsNonPositive := by
  intro s q d a h
  exact ⟨by simp [step, h], by simp [step, h]⟩

theorem rejectsNonPositive_witness : ∃ (_ : State) (_ _ : Nat) (a : Int) (_ : a ≤ 0), True :=
  ⟨State.init, 0, 0, 0, Int.le_refl 0, trivial⟩

theorem billBefore_trans (a b c : Bill) (h1 : billBefore a b = true) (h2 : billBefore b c = true) :
    billBefore a c = true := by
  simp [billBefore] at *; omega

theorem billBefore_total (a b : Bill) : (billBefore a b || billBefore b a) = true := by
  simp [billBefore]; omega

theorem settlesOldestFirst : Spec.settlesOldestFirst := by
  intro ops q
  exact List.pairwise_mergeSort billBefore_trans billBefore_total _

theorem settlesOldestFirst_witness : ∃ (_ : List Op) (_ : Nat), True := ⟨[], 0, trivial⟩

/-- Counterexample: bills of 5 and 5 and an advance of 8. With a cap of one
bill, only bill 1 is paid and 3 stays unapplied; in full, bill 2 gets 3. -/
theorem cappedMatchDisagrees : Spec.cappedMatchDisagrees := by
  intro h
  have := h 1 [(1, 5), (2, 5)] [(9, 8)]
  simp [matchUpCapped, matchUp] at this

/-! ## Counting allocations two ways -/

theorem sum_map_add' {α : Type} (L : List α) (g h : α → Int) :
    (L.map fun t => g t + h t).sum = (L.map g).sum + (L.map h).sum := by
  induction L with
  | nil => simp
  | cons x L ih => simp only [List.map_cons, List.sum_cons, ih]; omega

theorem sum_map_zero {α : Type} (L : List α) (g : α → Int) (h : ∀ t ∈ L, g t = 0) :
    (L.map g).sum = 0 := by
  induction L with
  | nil => simp
  | cons x L ih =>
    simp only [List.map_cons, List.sum_cons, h x (by simp), ih (fun t ht => h t (by simp [ht]))]; simp

/-- Summing `c` over the one element of `L` whose key is `y` gives `c`. -/
theorem sum_indicator {α : Type} (L : List α) (k : α → Nat) (y : Nat) (c : Int)
    (hn : (L.map k).Nodup) (hy : y ∈ L.map k) :
    (L.map fun t => if y = k t then c else 0).sum = c := by
  induction L with
  | nil => simp at hy
  | cons x L ih =>
    simp only [List.map_cons, List.nodup_cons] at hn
    simp only [List.map_cons, List.sum_cons]
    by_cases hx : y = k x
    · have rest : (L.map fun t => if y = k t then c else 0).sum = 0 := by
        apply sum_map_zero
        intro t ht
        have : y ≠ k t := by
          intro h; apply hn.1; rw [← hx, h]; exact List.mem_map_of_mem ht
        simp [this]
      rw [rest, if_pos hx, Int.add_zero]
    · simp only [List.map_cons, List.mem_cons] at hy
      rcases hy with h | h
      · exact absurd h hx
      · rw [if_neg hx, ih hn.2 h]; simp

/-- Grouping by key: summing, over every element of `L`, the allocations whose
key matches it gives the sum of all allocations, when every allocation's key
is the key of exactly one element. -/
theorem sum_grouped {α : Type} (L : List α) (k : α → Nat) (A : List Alloc) (f : Alloc → Nat)
    (hn : (L.map k).Nodup) (hA : ∀ a ∈ A, f a ∈ L.map k) :
    (L.map fun t => ((A.filter fun a => f a == k t).map (·.amount)).sum).sum = (A.map (·.amount)).sum := by
  induction A with
  | nil => simp only [List.filter_nil, List.map_nil, List.sum_nil]; exact sum_map_zero L _ (fun _ _ => rfl)
  | cons x A ih =>
    have hx := hA x (by simp)
    have ih' := ih (fun a ha => hA a (by simp [ha]))
    have split : ∀ t, (((x :: A).filter (fun a => f a == k t)).map (·.amount)).sum
        = (if f x = k t then x.amount else 0) + ((A.filter fun a => f a == k t).map (·.amount)).sum := by
      intro t
      rw [List.filter_cons]
      by_cases h : f x = k t
      · simp [h]
      · have hb : (f x == k t) = false := by simpa using h
        rw [hb]; simp [h]
    simp only [split]
    rw [sum_map_add', sum_indicator L k (f x) x.amount hn hx, ih']
    simp

/-! ## The invariant of reachable states -/

structure Base (s : State) : Prop where
  billIds    : (s.bills.map (·.id)).Pairwise (· < ·)
  billsBelow : ∀ b ∈ s.bills, b.id < s.nextBill ∧ 0 < b.amount
  payIds     : (s.payments.map (·.id)).Pairwise (· < ·)
  paysBelow  : ∀ p ∈ s.payments, p.id < s.nextPayment ∧ 0 < p.amount
  allocsOk   : ∀ a ∈ s.allocs, 0 < a.amount ∧
                 ∃ b ∈ s.bills, ∃ p ∈ s.payments, b.id = a.bill ∧ p.id = a.payment ∧ b.party = p.party
  owedOk     : ∀ b ∈ s.bills, 0 ≤ outstanding s b
  advOk      : ∀ p ∈ s.payments, 0 ≤ advance s p

structure Inv (s : State) : Prop extends Base s where
  applied    : ∀ q, openBills s q = [] ∨ advances s q = []
  cacheOk    : ∀ q, s.cache q = balance s q

/-! ### One settlement step -/

/-- The bills offered to the matching step, as `(id, owed)`. -/
def owedList (s : State) (q : Nat) : List (Nat × Int) := (openBills s q).map fun b => (b.id, outstanding s b)
/-- The advances offered to the matching step, as `(id, advance)`. -/
def advList (s : State) (q : Nat) : List (Nat × Int) := (advances s q).map fun p => (p.id, advance s p)
def newAllocs (s : State) (q : Nat) : List Alloc := matchUp (owedList s q) (advList s q)

theorem settle_eq (s : State) (q : Nat) : settleParty s q = { s with allocs := s.allocs ++ newAllocs s q } := rfl

theorem mem_openBills {s : State} {q : Nat} {b : Bill} :
    b ∈ openBills s q ↔ b ∈ s.bills ∧ b.party = q ∧ 0 < outstanding s b := by
  simp [openBills, List.mem_mergeSort]

theorem mem_advances {s : State} {q : Nat} {p : Payment} :
    p ∈ advances s q ↔ p ∈ s.payments ∧ p.party = q ∧ 0 < advance s p := by
  simp [advances]

theorem nodup_of_pairwise_lt {xs : List Nat} (h : xs.Pairwise (· < ·)) : xs.Nodup :=
  h.imp (fun hab => Nat.ne_of_lt hab)

theorem owedList_wf (s : State) (q : Nat) (h : Base s) : wellFormed (owedList s q) := by
  refine ⟨?_, ?_⟩
  · have hsub : ((s.bills.filter fun b => b.party == q && decide (0 < outstanding s b)).map (·.id)).Nodup :=
      (nodup_of_pairwise_lt h.billIds).sublist (List.filter_sublist.map _)
    have hperm := (List.mergeSort_perm (s.bills.filter fun b => b.party == q && decide (0 < outstanding s b)) billBefore).map (·.id)
    simp only [owedList, List.map_map]
    exact hperm.nodup_iff.mpr hsub
  · intro x hx
    simp only [owedList, List.mem_map] at hx
    obtain ⟨b, hb, rfl⟩ := hx
    exact (mem_openBills.mp hb).2.2

theorem advList_wf (s : State) (q : Nat) (h : Base s) : wellFormed (advList s q) := by
  refine ⟨?_, ?_⟩
  · simp only [advList, advances, List.map_map]
    exact (nodup_of_pairwise_lt h.payIds).sublist (List.filter_sublist.map _)
  · intro x hx
    simp only [advList, List.mem_map] at hx
    obtain ⟨p, hp, rfl⟩ := hx
    exact (mem_advances.mp hp).2.2

/-- Distinct ids: two recorded items with the same id are the same item. -/
theorem eq_of_id_eq {α : Type} (k : α → Nat) : ∀ {L : List α}, (L.map k).Nodup →
    ∀ {x y : α}, x ∈ L → y ∈ L → k x = k y → x = y
  | [], _, _, _, hx, _, _ => by simp at hx
  | z :: L, hn, x, y, hx, hy, he => by
    simp only [List.map_cons, List.nodup_cons] at hn
    simp only [List.mem_cons] at hx hy
    rcases hx with rfl | hx <;> rcases hy with rfl | hy
    · rfl
    · exact absurd (he ▸ List.mem_map_of_mem hy) hn.1
    · exact absurd (he.symm ▸ List.mem_map_of_mem hx) hn.1
    · exact eq_of_id_eq k hn.2 hx hy he

theorem bill_eq {s : State} (h : Base s) {b b' : Bill} (hb : b ∈ s.bills) (hb' : b' ∈ s.bills)
    (he : b.id = b'.id) : b = b' :=
  eq_of_id_eq (·.id) (nodup_of_pairwise_lt h.billIds) hb hb' he

theorem payment_eq {s : State} (h : Base s) {p p' : Payment} (hp : p ∈ s.payments) (hp' : p' ∈ s.payments)
    (he : p.id = p'.id) : p = p' :=
  eq_of_id_eq (·.id) (nodup_of_pairwise_lt h.payIds) hp hp' he

theorem live_of_mem {s : State} {p : Payment} (hp : p ∈ s.payments) (hr : p.reversed = false) :
    live s p.id = true := by
  simp only [live, List.any_eq_true]; exact ⟨p, hp, by simp [hr]⟩

/-- What the new allocations refer to. -/
theorem newAllocs_mem {s : State} {q : Nat} (h : Base s) {x : Alloc} (hx : x ∈ newAllocs s q) :
    0 < x.amount ∧ (∃ b ∈ openBills s q, b.id = x.bill) ∧ (∃ p ∈ advances s q, p.id = x.payment) := by
  have m := matchUp_mem _ _ (owedList_wf s q h).2 (advList_wf s q h).2 x hx
  refine ⟨m.1, ?_, ?_⟩
  · have := m.2.1; simp only [owedList, List.map_map, List.mem_map] at this
    obtain ⟨b, hb, he⟩ := this; exact ⟨b, hb, he⟩
  · have := m.2.2; simp only [advList, List.map_map, List.mem_map] at this
    obtain ⟨p, hp, he⟩ := this; exact ⟨p, hp, he⟩

theorem newAllocs_live {s : State} {q : Nat} (h : Base s) {x : Alloc} (hx : x ∈ newAllocs s q) :
    live s x.payment = true := by
  obtain ⟨-, -, p, hp, he⟩ := newAllocs_mem h hx
  have hp' := mem_advances.mp hp
  have hr : p.reversed = false := by
    cases hrev : p.reversed
    · rfl
    · have := hp'.2.2; simp [advance, hrev] at this
  rw [← he]; exact live_of_mem hp'.1 hr

theorem allocatedTo_settle {s : State} {q : Nat} (h : Base s) (bid : Nat) :
    allocatedTo (settleParty s q) bid = allocatedTo s bid + paidTo (newAllocs s q) bid := by
  have hl : live (settleParty s q) = live s := rfl
  simp only [allocatedTo, hl, settle_eq, List.filter_append, List.map_append, List.sum_append, paidTo]
  congr 1
  congr 2
  apply List.filter_congr
  intro x hx
  have hlv := newAllocs_live h hx
  simp only [live] at hlv ⊢
  simp [hlv]

theorem allocatedFrom_settle {s : State} {q : Nat} (pid : Nat) :
    allocatedFrom (settleParty s q) pid = allocatedFrom s pid + takenFrom (newAllocs s q) pid := by
  simp [allocatedFrom, settle_eq, List.filter_append, takenFrom]

theorem outstanding_settle {s : State} {q : Nat} (h : Base s) (b : Bill) :
    outstanding (settleParty s q) b = outstanding s b - paidTo (newAllocs s q) b.id := by
  simp only [outstanding, allocatedTo_settle h]; omega

theorem advance_settle {s : State} {q : Nat} (p : Payment) :
    advance (settleParty s q) p = if p.reversed then 0 else advance s p - takenFrom (newAllocs s q) p.id := by
  by_cases hr : p.reversed <;> simp [advance, hr, allocatedFrom_settle]; omega

/-- A bill the settlement wasn't offered receives nothing. -/
theorem paidTo_not_open {s : State} {q : Nat} (h : Base s) {b : Bill} (hb : b ∈ s.bills)
    (hno : b ∉ openBills s q) : paidTo (newAllocs s q) b.id = 0 := by
  apply paidTo_absent
  intro x hx he
  obtain ⟨-, ⟨b', hb', hid⟩, -⟩ := newAllocs_mem h hx
  have : b' = b := bill_eq h (mem_openBills.mp hb').1 hb (hid.trans he)
  exact hno (this ▸ hb')

/-- A payment the settlement wasn't offered gives nothing. -/
theorem takenFrom_not_adv {s : State} {q : Nat} (h : Base s) {p : Payment} (hp : p ∈ s.payments)
    (hno : p ∉ advances s q) : takenFrom (newAllocs s q) p.id = 0 := by
  apply takenFrom_absent
  intro x hx he
  obtain ⟨-, -, ⟨p', hp', hid⟩⟩ := newAllocs_mem h hx
  have : p' = p := payment_eq h (mem_advances.mp hp').1 hp (hid.trans he)
  exact hno (this ▸ hp')

theorem paidTo_open_le {s : State} {q : Nat} (h : Base s) {b : Bill} (hb : b ∈ openBills s q) :
    paidTo (newAllocs s q) b.id ≤ outstanding s b := by
  have := matchUp_paidTo_le _ _ (owedList_wf s q h).2 (advList_wf s q h).2 (owedList_wf s q h).1
    (b.id, outstanding s b) (by simp only [owedList, List.mem_map]; exact ⟨b, hb, rfl⟩)
  simpa [newAllocs] using this

theorem takenFrom_adv_le {s : State} {q : Nat} (h : Base s) {p : Payment} (hp : p ∈ advances s q) :
    takenFrom (newAllocs s q) p.id ≤ advance s p := by
  have := matchUp_takenFrom_le _ _ (owedList_wf s q h).2 (advList_wf s q h).2 (advList_wf s q h).1
    (p.id, advance s p) (by simp only [advList, List.mem_map]; exact ⟨p, hp, rfl⟩)
  simpa [newAllocs] using this

/-! ### After settling, either every open bill is paid or every advance is used -/

theorem sum_le_sum {α : Type} (f g : α → Int) : ∀ (L : List α), (∀ t ∈ L, f t ≤ g t) →
    (L.map f).sum ≤ (L.map g).sum
  | [], _ => by simp
  | x :: L, hle => by
    simp only [List.map_cons, List.sum_cons]
    have := hle x (by simp)
    have := sum_le_sum f g L (fun t ht => hle t (by simp [ht]))
    omega

/-- If each `f t ≤ g t` and the sums are equal, then each `f t = g t`. -/
theorem eq_of_sum_eq {α : Type} (f g : α → Int) : ∀ (L : List α), (∀ t ∈ L, f t ≤ g t) →
    (L.map f).sum = (L.map g).sum → ∀ t ∈ L, f t = g t
  | [], _, _, t, ht => by simp at ht
  | x :: L, hle, hs, t, ht => by
    simp only [List.map_cons, List.sum_cons] at hs
    have hx := hle x (by simp)
    have hrest : ∀ t ∈ L, f t ≤ g t := fun t ht => hle t (by simp [ht])
    have hsum := sum_le_sum f g L hrest
    have hx' : f x = g x := by omega
    have hL : (L.map f).sum = (L.map g).sum := by omega
    simp only [List.mem_cons] at ht
    rcases ht with rfl | ht
    · exact hx'
    · exact eq_of_sum_eq f g L hrest hL t ht

theorem sum_paidTo_owed {s : State} {q : Nat} (h : Base s) :
    ((owedList s q).map fun t => paidTo (newAllocs s q) t.1).sum = ((newAllocs s q).map (·.amount)).sum := by
  have := sum_grouped (owedList s q) (·.1) (newAllocs s q) (·.bill) (owedList_wf s q h).1
    (fun a ha => (matchUp_mem _ _ (owedList_wf s q h).2 (advList_wf s q h).2 a ha).2.1)
  simpa [paidTo] using this

theorem sum_takenFrom_adv {s : State} {q : Nat} (h : Base s) :
    ((advList s q).map fun t => takenFrom (newAllocs s q) t.1).sum = ((newAllocs s q).map (·.amount)).sum := by
  have := sum_grouped (advList s q) (·.1) (newAllocs s q) (·.payment) (advList_wf s q h).1
    (fun a ha => (matchUp_mem _ _ (owedList_wf s q h).2 (advList_wf s q h).2 a ha).2.2)
  simpa [takenFrom] using this

theorem settle_applied {s : State} {q : Nat} (h : Base s) :
    openBills (settleParty s q) q = [] ∨ advances (settleParty s q) q = [] := by
  have hsum : ((newAllocs s q).map (·.amount)).sum = min (total (owedList s q)) (total (advList s q)) :=
    matchUp_sum _ _ (owedList_wf s q h).2 (advList_wf s q h).2
  by_cases hle : total (owedList s q) ≤ total (advList s q)
  · left
    have heq := eq_of_sum_eq (fun t => paidTo (newAllocs s q) t.1) (·.2) (owedList s q)
      (fun t ht => matchUp_paidTo_le _ _ (owedList_wf s q h).2 (advList_wf s q h).2 (owedList_wf s q h).1 t ht)
      (by rw [sum_paidTo_owed h, hsum]; simp only [total] at hle ⊢; omega)
    apply List.eq_nil_iff_forall_not_mem.mpr
    intro b hb
    have hb' := mem_openBills.mp hb
    rw [outstanding_settle h] at hb'
    by_cases hopen : b ∈ openBills s q
    · have := heq (b.id, outstanding s b) (by simp only [owedList, List.mem_map]; exact ⟨b, hopen, rfl⟩)
      simp at this; omega
    · rw [paidTo_not_open h hb'.1 hopen] at hb'
      exact hopen (mem_openBills.mpr ⟨hb'.1, hb'.2.1, by omega⟩)
  · right
    have heq := eq_of_sum_eq (fun t => takenFrom (newAllocs s q) t.1) (·.2) (advList s q)
      (fun t ht => matchUp_takenFrom_le _ _ (owedList_wf s q h).2 (advList_wf s q h).2 (advList_wf s q h).1 t ht)
      (by rw [sum_takenFrom_adv h, hsum]; simp only [total] at hle ⊢; omega)
    apply List.eq_nil_iff_forall_not_mem.mpr
    intro p hp
    have hp' := mem_advances.mp hp
    rw [advance_settle] at hp'
    by_cases hr : p.reversed
    · simp [hr] at hp'
    · simp only [hr, Bool.false_eq_true, if_false] at hp'
      by_cases hadv : p ∈ advances s q
      · have := heq (p.id, advance s p) (by simp only [advList, List.mem_map]; exact ⟨p, hadv, rfl⟩)
        simp at this; omega
      · rw [takenFrom_not_adv h hp'.1 hadv] at hp'
        exact hadv (mem_advances.mpr ⟨hp'.1, hp'.2.1, by omega⟩)

/-! ### Settlement keeps the base invariant and leaves other parties alone -/

theorem settle_base {s : State} {q : Nat} (h : Base s) : Base (settleParty s q) := by
  constructor
  · exact h.billIds
  · exact h.billsBelow
  · exact h.payIds
  · exact h.paysBelow
  · intro a ha
    simp only [settle_eq, List.mem_append] at ha
    rcases ha with ha | ha
    · exact h.allocsOk a ha
    · obtain ⟨hpos, ⟨b, hb, hbid⟩, ⟨p, hp, hpid⟩⟩ := newAllocs_mem h ha
      have hb' := mem_openBills.mp hb; have hp' := mem_advances.mp hp
      exact ⟨hpos, b, hb'.1, p, hp'.1, hbid, hpid, hb'.2.1.trans hp'.2.1.symm⟩
  · intro b hb
    rw [outstanding_settle h]
    by_cases hopen : b ∈ openBills s q
    · have := paidTo_open_le h hopen; omega
    · rw [paidTo_not_open h hb hopen]; have := h.owedOk b hb; omega
  · intro p hp
    rw [advance_settle]
    by_cases hr : p.reversed
    · simp [hr]
    · simp only [hr, Bool.false_eq_true, if_false]
      by_cases hadv : p ∈ advances s q
      · have := takenFrom_adv_le h hadv; omega
      · rw [takenFrom_not_adv h hp hadv]; have := h.advOk p hp; omega

theorem outstanding_settle_other {s : State} {q : Nat} (h : Base s) {b : Bill} (hb : b ∈ s.bills)
    (hq : b.party ≠ q) : outstanding (settleParty s q) b = outstanding s b := by
  rw [outstanding_settle h, paidTo_not_open h hb (fun ho => hq (mem_openBills.mp ho).2.1)]; omega

theorem advance_settle_other {s : State} {q : Nat} (h : Base s) {p : Payment} (hp : p ∈ s.payments)
    (hq : p.party ≠ q) : advance (settleParty s q) p = advance s p := by
  rw [advance_settle, takenFrom_not_adv h hp (fun ha => hq (mem_advances.mp ha).2.1)]
  by_cases hr : p.reversed <;> simp [hr, advance]

theorem openBills_settle_other {s : State} {q r : Nat} (h : Base s) (hr : r ≠ q) :
    openBills (settleParty s q) r = openBills s r := by
  simp only [openBills]
  congr 1
  apply List.filter_congr
  intro b hb
  by_cases hp : b.party = r
  · rw [outstanding_settle_other h hb (hp ▸ hr)]
  · have hf : (b.party == r) = false := by simpa using hp
    rw [hf, Bool.false_and, Bool.false_and]

theorem advances_settle_other {s : State} {q r : Nat} (h : Base s) (hr : r ≠ q) :
    advances (settleParty s q) r = advances s r := by
  simp only [advances]
  apply List.filter_congr
  intro p hp
  by_cases hpp : p.party = r
  · rw [advance_settle_other h hp (hpp ▸ hr)]
  · have hf : (p.party == r) = false := by simpa using hpp
    rw [hf, Bool.false_and, Bool.false_and]

theorem balance_settle (s : State) (q r : Nat) : balance (settleParty s q) r = balance s r := rfl

/-- Settling party `q` restores the whole invariant, given it held for every other party. -/
theorem settle_inv {s : State} {q : Nat} (h : Base s) (happ : ∀ r, r ≠ q → openBills s r = [] ∨ advances s r = [])
    (hc : ∀ r, s.cache r = balance s r) : Inv (settleParty s q) where
  toBase := settle_base h
  applied r := by
    by_cases hr : r = q
    · subst hr; exact settle_applied h
    · rw [openBills_settle_other h hr, advances_settle_other h hr]; exact happ r hr
  cacheOk r := hc r

/-! ### Recording a bill -/

def addBill (s : State) (q d : Nat) (a : Int) : State :=
  { s with bills := s.bills ++ [⟨s.nextBill, q, d, a⟩], nextBill := s.nextBill + 1, cache := adjust s.cache q a }

theorem step_bill (s : State) (q d : Nat) (a : Int) (ha : 0 < a) :
    step s (.bill q d a) = settleParty (addBill s q d a) q := by
  simp [step, addBill, show ¬ a ≤ 0 by omega]

theorem outstanding_addBill (s : State) (q d : Nat) (a : Int) (b : Bill) :
    outstanding (addBill s q d a) b = outstanding s b := rfl

theorem advance_addBill (s : State) (q d : Nat) (a : Int) (p : Payment) :
    advance (addBill s q d a) p = advance s p := rfl

theorem allocatedTo_next {s : State} (h : Base s) : allocatedTo s s.nextBill = 0 := by
  apply sum_map_zero
  intro x hx
  rw [List.mem_filter] at hx
  obtain ⟨hxa, hb⟩ := hx
  obtain ⟨-, b, hbm, -, -, hid, -, -⟩ := h.allocsOk x hxa
  have := (h.billsBelow b hbm).1
  simp only [Bool.and_eq_true, beq_iff_eq] at hb
  omega

theorem balance_addBill (s : State) (q d : Nat) (a : Int) (r : Nat) :
    balance (addBill s q d a) r = balance s r + (if r = q then a else 0) := by
  by_cases hr : r = q
  · subst hr; simp [balance, addBill, List.filter_append]; omega
  · have : (q == r) = false := by simpa using Ne.symm hr
    simp [balance, addBill, List.filter_append, this, hr]

theorem addBill_base {s : State} (h : Base s) (q d : Nat) (a : Int) (ha : 0 < a) :
    Base (addBill s q d a) := by
  constructor
  · simp only [addBill, List.map_append, List.map_cons, List.map_nil]
    rw [List.pairwise_append]
    refine ⟨h.billIds, by simp, ?_⟩
    intro x hx y hy
    simp only [List.mem_map] at hx; simp at hy
    obtain ⟨b, hb, rfl⟩ := hx
    rw [hy]; exact (h.billsBelow b hb).1
  · intro b hb
    simp only [addBill, List.mem_append, List.mem_singleton] at hb
    rcases hb with hb | rfl
    · have := h.billsBelow b hb; exact ⟨by simp [addBill]; omega, this.2⟩
    · exact ⟨by simp [addBill], ha⟩
  · exact h.payIds
  · exact h.paysBelow
  · intro x hx
    obtain ⟨hpos, b, hb, p, hp, hrest⟩ := h.allocsOk x hx
    exact ⟨hpos, b, by simp [addBill, hb], p, hp, hrest⟩
  · intro b hb
    rw [outstanding_addBill]
    simp only [addBill, List.mem_append, List.mem_singleton] at hb
    rcases hb with hb | rfl
    · exact h.owedOk b hb
    · simp only [outstanding, allocatedTo_next h]; omega
  · intro p hp; rw [advance_addBill]; exact h.advOk p hp

theorem openBills_addBill_other {s : State} (q d : Nat) (a : Int) {r : Nat} (hr : r ≠ q) :
    openBills (addBill s q d a) r = openBills s r := by
  have : (q == r) = false := by simpa using Ne.symm hr
  simp only [openBills, outstanding_addBill]
  simp [addBill, List.filter_append, this]
  rfl

theorem addBill_then_settle {s : State} (h : Inv s) (q d : Nat) (a : Int) (ha : 0 < a) :
    Inv (step s (.bill q d a)) := by
  rw [step_bill s q d a ha]
  apply settle_inv (addBill_base h.toBase q d a ha)
  · intro r hr; rw [openBills_addBill_other q d a hr]; exact h.applied r
  · intro r
    rw [balance_addBill]
    simp only [addBill, adjust]
    rw [h.cacheOk r]
    by_cases hr : r = q <;> simp [hr]

/-! ### Recording a payment -/

def addPay (s : State) (q : Nat) (a : Int) : State :=
  { s with payments := s.payments ++ [⟨s.nextPayment, q, a, false⟩], nextPayment := s.nextPayment + 1,
           cache := adjust s.cache q (-a) }

theorem step_pay (s : State) (q : Nat) (a : Int) (ha : 0 < a) :
    step s (.pay q a) = settleParty (addPay s q a) q := by
  simp [step, addPay, show ¬ a ≤ 0 by omega]

theorem alloc_payment_lt {s : State} (h : Base s) {x : Alloc} (hx : x ∈ s.allocs) : x.payment < s.nextPayment := by
  obtain ⟨-, -, -, p, hp, -, hid, -⟩ := h.allocsOk x hx
  rw [← hid]; exact (h.paysBelow p hp).1

theorem live_addPay_old {s : State} (h : Base s) (q : Nat) (a : Int) {x : Alloc} (hx : x ∈ s.allocs) :
    live (addPay s q a) x.payment = live s x.payment := by
  have := alloc_payment_lt h hx
  simp [live, addPay, List.any_append]; omega

theorem allocatedTo_addPay {s : State} (h : Base s) (q : Nat) (a : Int) (bid : Nat) :
    allocatedTo (addPay s q a) bid = allocatedTo s bid := by
  simp only [allocatedTo]
  congr 2
  apply List.filter_congr
  intro x hx
  rw [show (addPay s q a).allocs = s.allocs from rfl] at hx
  rw [live_addPay_old h q a hx]

theorem outstanding_addPay {s : State} (h : Base s) (q : Nat) (a : Int) (b : Bill) :
    outstanding (addPay s q a) b = outstanding s b := by
  simp only [outstanding, allocatedTo_addPay h]

theorem advance_addPay (s : State) (q : Nat) (a : Int) (p : Payment) :
    advance (addPay s q a) p = advance s p := rfl

theorem allocatedFrom_next {s : State} (h : Base s) : allocatedFrom s s.nextPayment = 0 := by
  apply sum_map_zero
  intro x hx
  rw [List.mem_filter] at hx
  have := alloc_payment_lt h hx.1
  simp only [beq_iff_eq] at hx; omega

theorem balance_addPay (s : State) (q : Nat) (a : Int) (r : Nat) :
    balance (addPay s q a) r = balance s r - (if r = q then a else 0) := by
  by_cases hr : r = q
  · subst hr; simp [balance, addPay, List.filter_append]; omega
  · have : (q == r) = false := by simpa using Ne.symm hr
    simp [balance, addPay, List.filter_append, this, hr]

theorem addPay_base {s : State} (h : Base s) (q : Nat) (a : Int) (ha : 0 < a) : Base (addPay s q a) := by
  constructor
  · exact h.billIds
  · exact h.billsBelow
  · simp only [addPay, List.map_append, List.map_cons, List.map_nil]
    rw [List.pairwise_append]
    refine ⟨h.payIds, by simp, ?_⟩
    intro x hx y hy
    simp only [List.mem_map] at hx; simp at hy
    obtain ⟨p, hp, rfl⟩ := hx
    rw [hy]; exact (h.paysBelow p hp).1
  · intro p hp
    simp only [addPay, List.mem_append, List.mem_singleton] at hp
    rcases hp with hp | rfl
    · have := h.paysBelow p hp; exact ⟨by simp [addPay]; omega, this.2⟩
    · exact ⟨by simp [addPay], ha⟩
  · intro x hx
    obtain ⟨hpos, b, hb, p, hp, hrest⟩ := h.allocsOk x hx
    exact ⟨hpos, b, hb, p, by simp [addPay, hp], hrest⟩
  · intro b hb; rw [outstanding_addPay h]; exact h.owedOk b hb
  · intro p hp
    rw [advance_addPay]
    simp only [addPay, List.mem_append, List.mem_singleton] at hp
    rcases hp with hp | rfl
    · exact h.advOk p hp
    · simp only [advance, Bool.false_eq_true, if_false, allocatedFrom_next h]; omega

theorem openBills_addPay {s : State} (h : Base s) (q : Nat) (a : Int) (r : Nat) :
    openBills (addPay s q a) r = openBills s r := by
  simp only [openBills, outstanding_addPay h]; rfl

theorem advances_addPay_other (s : State) (q : Nat) (a : Int) {r : Nat} (hr : r ≠ q) :
    advances (addPay s q a) r = advances s r := by
  have : (q == r) = false := by simpa using Ne.symm hr
  simp only [advances, advance_addPay]
  simp [addPay, List.filter_append, this]
  rfl

theorem addPay_then_settle {s : State} (h : Inv s) (q : Nat) (a : Int) (ha : 0 < a) :
    Inv (step s (.pay q a)) := by
  rw [step_pay s q a ha]
  apply settle_inv (addPay_base h.toBase q a ha)
  · intro r hr
    rw [openBills_addPay h.toBase, advances_addPay_other s q a hr]; exact h.applied r
  · intro r
    rw [balance_addPay]
    simp only [addPay, adjust]
    rw [h.cacheOk r]
    by_cases hr : r = q <;> simp [hr]; omega

/-! ### Reversing a payment -/

def flip (pid : Nat) (x : Payment) : Payment := if x.id == pid then { x with reversed := true } else x

def revState (s : State) (p : Payment) : State :=
  { s with payments := s.payments.map (flip p.id), cache := adjust s.cache p.party p.amount }

theorem map_eq_self {α : Type} (f : α → α) : ∀ (l : List α), (∀ x ∈ l, f x = x) → l.map f = l
  | [], _ => rfl
  | x :: l, h => by
    simp only [List.map_cons, h x (by simp), map_eq_self f l (fun y hy => h y (by simp [hy]))]

/-- The payment list, split around one payment; no other payment shares its id. -/
theorem split_payments {s : State} (h : Base s) {p : Payment} (hp : p ∈ s.payments) :
    ∃ l1 l2, s.payments = l1 ++ p :: l2 ∧ (∀ x ∈ l1, x.id ≠ p.id) ∧ (∀ x ∈ l2, x.id ≠ p.id) := by
  obtain ⟨l1, l2, he⟩ := List.append_of_mem hp
  have hn := nodup_of_pairwise_lt h.payIds
  rw [he] at hn
  simp only [List.map_append, List.map_cons, List.nodup_append, List.nodup_cons, List.mem_map] at hn
  refine ⟨l1, l2, he, ?_, ?_⟩
  · intro x hx hid
    exact hn.2.2 x.id ⟨x, hx, rfl⟩ p.id (by simp) hid
  · intro x hx hid
    exact hn.2.1.1 ⟨x, hx, hid⟩

theorem flip_payments {s : State} (h : Base s) {p : Payment} (hp : p ∈ s.payments) :
    ∃ l1 l2, s.payments = l1 ++ p :: l2 ∧ s.payments.map (flip p.id) = l1 ++ { p with reversed := true } :: l2 ∧
      (∀ x ∈ l1, x.id ≠ p.id) ∧ (∀ x ∈ l2, x.id ≠ p.id) := by
  obtain ⟨l1, l2, he, h1, h2⟩ := split_payments h hp
  refine ⟨l1, l2, he, ?_, h1, h2⟩
  rw [he, List.map_append, List.map_cons, map_eq_self _ l1 (fun x hx => by simp [flip, h1 x hx]),
    map_eq_self _ l2 (fun x hx => by simp [flip, h2 x hx])]
  simp [flip]

theorem advance_rev (s : State) (p x : Payment) : advance (revState s p) x = advance s x := rfl

theorem live_rev {s : State} (h : Base s) {p : Payment} (hp : p ∈ s.payments) (hr : p.reversed = false) (y : Nat) :
    live (revState s p) y = (live s y && y != p.id) := by
  obtain ⟨l1, l2, he, hf, h1, h2⟩ := flip_payments h hp
  simp only [live, revState]
  rw [hf, he]
  simp only [List.any_append, List.any_cons]
  by_cases hy : y = p.id
  · subst hy
    have e1 : l1.any (fun x => x.id == p.id && !x.reversed) = false := by
      simp only [List.any_eq_false]; intro x hx; simp [h1 x hx]
    have e2 : l2.any (fun x => x.id == p.id && !x.reversed) = false := by
      simp only [List.any_eq_false]; intro x hx; simp [h2 x hx]
    simp [e1, e2]
  · have : (p.id == y) = false := by simpa using Ne.symm hy
    simp [this, hy]

theorem balance_rev {s : State} (h : Base s) {p : Payment} (hp : p ∈ s.payments) (hr : p.reversed = false) (r : Nat) :
    balance (revState s p) r = balance s r + (if r = p.party then p.amount else 0) := by
  obtain ⟨l1, l2, he, hf, -, -⟩ := flip_payments h hp
  simp only [balance, revState]
  rw [hf, he]
  simp only [List.filter_append, List.filter_cons, List.map_append, List.sum_append]
  by_cases hq : p.party = r
  · subst hq; simp [hr]; omega
  · have : (p.party == r) = false := by simpa using hq
    simp [this, Ne.symm hq]

theorem flip_id (pid : Nat) (x : Payment) : (flip pid x).id = x.id := by
  unfold flip; split <;> rfl
theorem flip_party (pid : Nat) (x : Payment) : (flip pid x).party = x.party := by
  unfold flip; split <;> rfl
theorem flip_amount (pid : Nat) (x : Payment) : (flip pid x).amount = x.amount := by
  unfold flip; split <;> rfl

/-- Requiring more of a summand never increases a sum of non-negative amounts. -/
theorem sum_filter_mono (P Q : Alloc → Bool) : ∀ (A : List Alloc), (∀ a ∈ A, 0 ≤ a.amount) →
    (∀ a ∈ A, P a = true → Q a = true) →
    ((A.filter P).map (·.amount)).sum ≤ ((A.filter Q).map (·.amount)).sum
  | [], _, _ => by simp
  | a :: A, hpos, himp => by
    have ih := sum_filter_mono P Q A (fun x hx => hpos x (by simp [hx])) (fun x hx => himp x (by simp [hx]))
    have ha := hpos a (by simp)
    by_cases hp : P a = true
    · have hq := himp a (by simp) hp
      simp [List.filter_cons, hp, hq]; omega
    · simp only [Bool.not_eq_true] at hp
      by_cases hq : Q a = true
      · simp [List.filter_cons, hp, hq]; omega
      · simp only [Bool.not_eq_true] at hq
        simp [List.filter_cons, hp, hq]; omega

theorem revState_base {s : State} (h : Base s) {p : Payment} (hp : p ∈ s.payments) (hr : p.reversed = false) :
    Base (revState s p) := by
  constructor
  · exact h.billIds
  · exact h.billsBelow
  · simp only [revState, List.map_map]
    have : ((·.id) ∘ flip p.id) = (·.id : Payment → Nat) := funext (flip_id p.id)
    rw [this]; exact h.payIds
  · intro x hx
    simp only [revState, List.mem_map] at hx
    obtain ⟨y, hy, rfl⟩ := hx
    rw [flip_id, flip_amount]; exact h.paysBelow y hy
  · intro a ha
    obtain ⟨hpos, b, hb, p0, hp0, hbid, hpid, hparty⟩ := h.allocsOk a ha
    refine ⟨hpos, b, hb, flip p.id p0, ?_, hbid, by rw [flip_id]; exact hpid, by rw [flip_party]; exact hparty⟩
    exact List.mem_map_of_mem hp0
  · intro b hb
    have hle : allocatedTo (revState s p) b.id ≤ allocatedTo s b.id := by
      simp only [allocatedTo]
      apply sum_filter_mono
      · intro a ha; exact Int.le_of_lt (h.allocsOk a ha).1
      · intro a _ hP
        rw [live_rev h hp hr] at hP
        simp only [Bool.and_eq_true] at hP ⊢
        exact ⟨hP.1, hP.2.1⟩
    have := h.owedOk b hb
    simp only [outstanding] at this ⊢; omega
  · intro x hx
    rw [advance_rev]
    simp only [revState, List.mem_map] at hx
    obtain ⟨y, hy, rfl⟩ := hx
    by_cases hid : y.id = p.id
    · simp [flip, hid, advance]
    · have : flip p.id y = y := by simp [flip, hid]
      rw [this]; exact h.advOk y hy

theorem outstanding_rev_other {s : State} (h : Base s) {p : Payment} (hp : p ∈ s.payments) (hr : p.reversed = false)
    {b : Bill} (hb : b ∈ s.bills) (hq : b.party ≠ p.party) : outstanding (revState s p) b = outstanding s b := by
  simp only [outstanding, allocatedTo]
  congr 3
  apply List.filter_congr
  intro a ha
  rw [live_rev h hp hr]
  by_cases hbill : a.bill = b.id
  · obtain ⟨-, b', hb', p0, hp0, hbid, hpid, hparty⟩ := h.allocsOk a ha
    have hbb : b' = b := bill_eq h hb' hb (hbid.trans hbill)
    have hne : a.payment ≠ p.id := by
      intro he
      have : p0 = p := payment_eq h hp0 hp (hpid.trans he)
      exact hq (hbb ▸ this ▸ hparty)
    have hb2 : (a.payment != p.id) = true := by simpa using hne
    rw [hb2, Bool.and_true]
  · have : (a.bill == b.id) = false := by simpa using hbill
    simp [this]

theorem openBills_rev_other {s : State} (h : Base s) {p : Payment} (hp : p ∈ s.payments) (hr : p.reversed = false)
    {r : Nat} (hrq : r ≠ p.party) : openBills (revState s p) r = openBills s r := by
  simp only [openBills]
  congr 1
  apply List.filter_congr
  intro b hb
  by_cases hbr : b.party = r
  · rw [outstanding_rev_other h hp hr hb (hbr ▸ hrq)]
  · have hf : (b.party == r) = false := by simpa using hbr
    rw [hf, Bool.false_and, Bool.false_and]

theorem advances_rev_other {s : State} (h : Base s) {p : Payment} (hp : p ∈ s.payments)
    {r : Nat} (hrq : r ≠ p.party) : advances (revState s p) r = advances s r := by
  obtain ⟨l1, l2, he, hf, -, -⟩ := flip_payments h hp
  have hf1 : (p.party == r) = false := by simpa using Ne.symm hrq
  simp only [advances, advance_rev]
  show List.filter _ (s.payments.map (flip p.id)) = _
  rw [hf, he]
  simp [List.filter_append, List.filter_cons, hf1]
  rfl

theorem find_reverse {s : State} {pid : Nat} {p : Payment}
    (hfind : s.payments.find? (fun x => x.id == pid && !x.reversed) = some p) :
    p ∈ s.payments ∧ p.id = pid ∧ p.reversed = false := by
  have hmem := List.mem_of_find?_eq_some hfind
  have hpred := List.find?_some hfind
  simp only [Bool.and_eq_true, beq_iff_eq, Bool.not_eq_true'] at hpred
  exact ⟨hmem, hpred.1, hpred.2⟩

theorem step_reverse {s : State} {pid : Nat} {p : Payment}
    (hfind : s.payments.find? (fun x => x.id == pid && !x.reversed) = some p) :
    step s (.reverse pid) = settleParty (revState s p) p.party := by
  obtain ⟨-, hid, -⟩ := find_reverse hfind
  simp only [step, hfind, revState, hid]
  rfl

theorem rev_then_settle {s : State} (h : Inv s) {pid : Nat} {p : Payment}
    (hfind : s.payments.find? (fun x => x.id == pid && !x.reversed) = some p) :
    Inv (step s (.reverse pid)) := by
  obtain ⟨hp, -, hr⟩ := find_reverse hfind
  rw [step_reverse hfind]
  apply settle_inv (revState_base h.toBase hp hr)
  · intro r hrq
    rw [openBills_rev_other h.toBase hp hr hrq, advances_rev_other h.toBase hp hrq]; exact h.applied r
  · intro r
    rw [balance_rev h.toBase hp hr]
    simp only [revState, adjust]
    rw [h.cacheOk r]
    by_cases hrq : r = p.party <;> simp [hrq]

/-! ### Every operation keeps the invariant, so every reachable state has it -/

theorem init_inv : Inv State.init where
  billIds := by simp [State.init]
  billsBelow := by simp [State.init]
  payIds := by simp [State.init]
  paysBelow := by simp [State.init]
  allocsOk := by simp [State.init]
  owedOk := by simp [State.init]
  advOk := by simp [State.init]
  applied q := by left; simp [openBills, State.init]
  cacheOk q := by simp [State.init, balance]

theorem step_inv {s : State} (h : Inv s) : ∀ op, Inv (step s op)
  | .bill q d a => by
    by_cases ha : a ≤ 0
    · rw [(rejectsNonPositive s q d a ha).1]; exact h
    · exact addBill_then_settle h q d a (by omega)
  | .pay q a => by
    by_cases ha : a ≤ 0
    · rw [(rejectsNonPositive s q 0 a ha).2]; exact h
    · exact addPay_then_settle h q a (by omega)
  | .reverse pid => by
    cases hfind : s.payments.find? (fun x => x.id == pid && !x.reversed) with
    | none => simp only [step, hfind]; exact h
    | some p => exact rev_then_settle h hfind

theorem foldl_inv : ∀ (ops : List Op) {s : State}, Inv s → Inv (ops.foldl step s)
  | [], _, h => h
  | op :: ops, _, h => foldl_inv ops (step_inv h op)

theorem run_inv (ops : List Op) : Inv (run ops) := foldl_inv ops init_inv

/-! ## The ledger statements -/

theorem reachableInvariants : Spec.reachableInvariants := by
  intro ops
  have h := (run_inv ops).toBase
  exact ⟨h.billIds, h.billsBelow, h.payIds, h.paysBelow, h.allocsOk⟩

theorem reachableInvariants_witness : ∃ (_ : List Op), True := ⟨[], trivial⟩

theorem sum_pos_nonneg (A : List Alloc) (h : ∀ a ∈ A, 0 < a.amount) : 0 ≤ (A.map (·.amount)).sum := by
  induction A with
  | nil => simp
  | cons a A ih =>
    simp only [List.map_cons, List.sum_cons]
    have := h a (by simp); have := ih (fun x hx => h x (by simp [hx])); omega

theorem allocatedTo_nonneg {s : State} (h : Base s) (bid : Nat) : 0 ≤ allocatedTo s bid :=
  sum_pos_nonneg _ (fun a ha => (h.allocsOk a (List.mem_filter.mp ha).1).1)

theorem allocatedFrom_nonneg {s : State} (h : Base s) (pid : Nat) : 0 ≤ allocatedFrom s pid :=
  sum_pos_nonneg _ (fun a ha => (h.allocsOk a (List.mem_filter.mp ha).1).1)

theorem neverOverSettled : Spec.neverOverSettled := by
  intro ops b hb
  have h := run_inv ops
  refine ⟨h.owedOk b hb, ?_⟩
  have := allocatedTo_nonneg h.toBase b.id
  simp only [outstanding]; omega

theorem neverOverSettled_witness : ∃ (ops : List Op) (b : Bill) (_ : b ∈ (run ops).bills), True :=
  ⟨[.bill 1 1 5], ⟨1, 1, 1, 5⟩, by simp [run, step, settleParty, State.init], trivial⟩

theorem neverOverApplied : Spec.neverOverApplied := by
  intro ops p hp
  have h := run_inv ops
  refine ⟨h.advOk p hp, ?_⟩
  have := (h.paysBelow p hp).2
  have := allocatedFrom_nonneg h.toBase p.id
  simp only [advance]; split <;> omega

theorem neverOverApplied_witness : ∃ (ops : List Op) (p : Payment) (_ : p ∈ (run ops).payments), True :=
  ⟨[.pay 1 5], ⟨1, 1, 5, false⟩, by simp [run, step, settleParty, State.init], trivial⟩

theorem advancesAlwaysApplied : Spec.advancesAlwaysApplied := fun ops q => (run_inv ops).applied q

theorem advancesAlwaysApplied_witness : ∃ (_ : List Op) (_ : Nat), True := ⟨[], 0, trivial⟩

theorem cachedBalanceAgrees : Spec.cachedBalanceAgrees := fun ops q => (run_inv ops).cacheOk q

theorem cachedBalanceAgrees_witness : ∃ (_ : List Op) (_ : Nat), True := ⟨[], 0, trivial⟩

theorem run_append (ops : List Op) (op : Op) : run (ops ++ [op]) = step (run ops) op := by
  simp [run, List.foldl_append]

theorem find_live {s : State} (h : Base s) {p : Payment} (hp : p ∈ s.payments) (hr : p.reversed = false) :
    s.payments.find? (fun x => x.id == p.id && !x.reversed) = some p := by
  cases hfind : s.payments.find? (fun x => x.id == p.id && !x.reversed) with
  | none =>
    have := List.find?_eq_none.mp hfind p hp
    simp [hr] at this
  | some p' =>
    obtain ⟨hp', hid, -⟩ := find_reverse hfind
    rw [payment_eq h hp' hp hid]

theorem reversalRestoresBalance : Spec.reversalRestoresBalance := by
  intro ops p hp hr
  have h := (run_inv ops).toBase
  rw [run_append, step_reverse (find_live h hp hr)]
  refine ⟨?_, ?_⟩
  · rw [balance_settle, balance_rev h hp hr]; simp
  · intro q hq
    rw [balance_settle, balance_rev h hp hr]
    simp [hq]

theorem reversalRestoresBalance_witness :
    ∃ (ops : List Op) (p : Payment) (_ : p ∈ (run ops).payments) (_ : p.reversed = false), True :=
  ⟨[.pay 1 5], ⟨1, 1, 5, false⟩, by simp [run, step, settleParty, State.init], rfl, trivial⟩

/-! ### Every view of a balance agrees -/

theorem sum_map_sub {α : Type} (L : List α) (f g : α → Int) :
    (L.map fun x => f x - g x).sum = (L.map f).sum - (L.map g).sum := by
  induction L with
  | nil => simp
  | cons x L ih => simp only [List.map_cons, List.sum_cons, ih]; omega

theorem sum_ite_filter {α : Type} (L : List α) (c : α → Bool) (g : α → Int) :
    (L.map fun x => if c x then 0 else g x).sum = ((L.filter fun x => !c x).map g).sum := by
  induction L with
  | nil => simp
  | cons x L ih => cases hc : c x <;> simp [List.filter_cons, hc, ih]

theorem filter_and {α : Type} (L : List α) (p q : α → Bool) :
    (L.filter p).filter q = L.filter (fun x => p x && q x) := by
  induction L with
  | nil => rfl
  | cons x L ih => cases hp : p x <;> cases hq : q x <;> simp [List.filter_cons, hp, hq, ih]

/-- Allocations summed bill by bill equal allocations summed payment by payment. -/
theorem allocations_two_ways {s : State} (h : Base s) (q : Nat) :
    ((s.bills.filter (·.party == q)).map fun b => allocatedTo s b.id).sum =
      ((s.payments.filter fun p => p.party == q && !p.reversed).map fun p => allocatedFrom s p.id).sum := by
  let Bq := s.bills.filter (·.party == q)
  let Pq := s.payments.filter fun p => p.party == q && !p.reversed
  have hBn : (Bq.map (·.id)).Nodup := (nodup_of_pairwise_lt h.billIds).sublist (List.filter_sublist.map _)
  have hPn : (Pq.map (·.id)).Nodup := (nodup_of_pairwise_lt h.payIds).sublist (List.filter_sublist.map _)
  -- the allocations from a live payment of `q`, which are exactly those to a bill of `q`
  let A := s.allocs.filter fun a => (Pq.map (·.id)).contains a.payment
  have hsame : ∀ a ∈ s.allocs, (live s a.payment && (Bq.map (·.id)).contains a.bill) =
      (Pq.map (·.id)).contains a.payment := by
    intro a ha
    obtain ⟨-, b, hb, p, hp, hbid, hpid, hparty⟩ := h.allocsOk a ha
    apply Bool.eq_iff_iff.mpr
    simp only [Bool.and_eq_true, List.contains_iff_mem, List.mem_map, live, List.any_eq_true]
    constructor
    · rintro ⟨⟨p', hp', hl⟩, ⟨b', hb', hb'id⟩⟩
      simp only [Bool.and_eq_true, beq_iff_eq, Bool.not_eq_true'] at hl
      have hpp : p' = p := payment_eq h hp' hp (hl.1.trans hpid.symm)
      have hbm := List.mem_filter.mp hb'
      have hbb : b' = b := bill_eq h hbm.1 hb (hb'id.trans hbid.symm)
      subst hpp; subst hbb
      refine ⟨p', List.mem_filter.mpr ⟨hp', ?_⟩, hl.1⟩
      simp only [Bool.and_eq_true, beq_iff_eq, Bool.not_eq_true'] at hbm ⊢
      exact ⟨hparty ▸ hbm.2, hl.2⟩
    · rintro ⟨p', hp', hid⟩
      have hpm := List.mem_filter.mp hp'
      have hpp : p' = p := payment_eq h hpm.1 hp (hid.trans hpid.symm)
      subst hpp
      simp only [Bool.and_eq_true, beq_iff_eq, Bool.not_eq_true'] at hpm
      refine ⟨⟨p', hpm.1, by simp [hid, hpm.2.2]⟩, b, List.mem_filter.mpr ⟨hb, by simp [hparty, hpm.2.1]⟩, hbid⟩
  have lhs : (Bq.map fun b => allocatedTo s b.id).sum = (A.map (·.amount)).sum := by
    have hg := sum_grouped Bq (·.id) A (·.bill) hBn (by
      intro a ha
      have hm := List.mem_filter.mp ha
      have h2 := hsame a hm.1
      rw [hm.2] at h2
      have h3 := (Bool.and_eq_true _ _).mp h2
      simpa [List.contains_iff_mem] using h3.2)
    rw [← hg]
    congr 1
    apply List.map_congr_left
    intro b hb
    simp only [allocatedTo, A, filter_and]
    congr 2
    apply List.filter_congr
    intro a ha
    have hbq : (Bq.map (·.id)).contains b.id = true := by
      simp only [List.contains_iff_mem]; exact List.mem_map_of_mem hb
    rw [← hsame a ha]
    by_cases hab : a.bill = b.id
    · simp only [hab, hbq, beq_self_eq_true, Bool.and_true, Bool.true_and]
    · have : (a.bill == b.id) = false := by simpa using hab
      simp [this]
  have rhs : (Pq.map fun p => allocatedFrom s p.id).sum = (A.map (·.amount)).sum := by
    have hg := sum_grouped Pq (·.id) A (·.payment) hPn (by
      intro a ha
      simpa [List.contains_iff_mem] using (List.mem_filter.mp ha).2)
    rw [← hg]
    congr 1
    apply List.map_congr_left
    intro p hp
    simp only [allocatedFrom, A, filter_and]
    congr 2
    apply List.filter_congr
    intro a ha
    have hpq : (Pq.map (·.id)).contains p.id = true := by
      simp only [List.contains_iff_mem]; exact List.mem_map_of_mem hp
    by_cases hap : a.payment = p.id
    · rw [hap, hpq, Bool.true_and]
    · have : (a.payment == p.id) = false := by simpa using hap
      simp [this]
  exact lhs.trans rhs.symm

theorem viewsAgree : Spec.viewsAgree := by
  intro ops q
  have h := (run_inv ops).toBase
  have hfilt : ((run ops).payments.filter (·.party == q)).filter (fun p => !p.reversed) =
      (run ops).payments.filter (fun p => p.party == q && !p.reversed) := filter_and _ _ _
  have e1 : ((run ops).bills.filter (·.party == q)).map (outstanding (run ops)) =
      ((run ops).bills.filter (·.party == q)).map (fun b => b.amount - allocatedTo (run ops) b.id) := rfl
  have e2 : ((run ops).payments.filter (·.party == q)).map (advance (run ops)) =
      ((run ops).payments.filter (·.party == q)).map
        (fun p => if p.reversed then 0 else p.amount - allocatedFrom (run ops) p.id) := rfl
  rw [e1, e2, sum_map_sub, sum_ite_filter, hfilt, sum_map_sub, allocations_two_ways h q]
  simp only [balance, show (fun x : Bill => x.amount) = Bill.amount from rfl,
    show (fun x : Payment => x.amount) = Payment.amount from rfl]
  omega

theorem viewsAgree_witness : ∃ (_ : List Op) (_ : Nat), True := ⟨[], 0, trivial⟩

/-! ### Parties are isolated -/

theorem partyView_eq {s t : State} {r : Nat}
    (hb : t.bills.filter (·.party == r) = s.bills.filter (·.party == r))
    (ho : ∀ b ∈ s.bills.filter (·.party == r), outstanding t b = outstanding s b)
    (hp : t.payments.filter (·.party == r) = s.payments.filter (·.party == r))
    (ha : ∀ p ∈ s.payments.filter (·.party == r), advance t p = advance s p)
    (hbal : balance t r = balance s r) : partyView t r = partyView s r := by
  have e1 : (s.bills.filter (·.party == r)).map (fun b => (b, outstanding t b)) =
      (s.bills.filter (·.party == r)).map (fun b => (b, outstanding s b)) :=
    List.map_congr_left (fun b hb => by rw [ho b hb])
  have e2 : (s.payments.filter (·.party == r)).map (fun p => (p, advance t p)) =
      (s.payments.filter (·.party == r)).map (fun p => (p, advance s p)) :=
    List.map_congr_left (fun p hp => by rw [ha p hp])
  simp only [partyView, hb, hp, hbal, e1, e2]

theorem party_of_filter {α : Type} {party : α → Nat} {L : List α} {r : Nat} {x : α}
    (hx : x ∈ L.filter (party · == r)) : x ∈ L ∧ party x = r := by
  have := List.mem_filter.mp hx; simpa using this

theorem partiesIsolated : Spec.partiesIsolated := by
  intro ops op r hop
  have h := run_inv ops
  rw [run_append]
  cases op with
  | bill q d a =>
    have hq : q ≠ r := fun e => hop (by simp [opParty, e])
    by_cases ha : a ≤ 0
    · rw [(rejectsNonPositive _ q d a ha).1]
    · have ha' : 0 < a := by omega
      have hB := addBill_base h.toBase q d a ha'
      have hqr : (q == r) = false := by simpa using hq
      rw [step_bill _ q d a ha']
      apply partyView_eq
      · show (addBill (run ops) q d a).bills.filter _ = _
        simp [addBill, List.filter_append, hqr]
      · intro b hb
        obtain ⟨hbm, hbr⟩ := party_of_filter hb
        rw [outstanding_settle_other hB (by simp [addBill, hbm]) (hbr ▸ Ne.symm hq), outstanding_addBill]
      · rfl
      · intro p hp
        obtain ⟨hpm, hpr⟩ := party_of_filter hp
        rw [advance_settle_other hB hpm (hpr ▸ Ne.symm hq), advance_addBill]
      · rw [balance_settle, balance_addBill]; simp [Ne.symm hq]
  | pay q a =>
    have hq : q ≠ r := fun e => hop (by simp [opParty, e])
    by_cases ha : a ≤ 0
    · rw [(rejectsNonPositive _ q 0 a ha).2]
    · have ha' : 0 < a := by omega
      have hB := addPay_base h.toBase q a ha'
      have hqr : (q == r) = false := by simpa using hq
      rw [step_pay _ q a ha']
      apply partyView_eq
      · rfl
      · intro b hb
        obtain ⟨hbm, hbr⟩ := party_of_filter hb
        rw [outstanding_settle_other hB hbm (hbr ▸ Ne.symm hq), outstanding_addPay h.toBase]
      · show (addPay (run ops) q a).payments.filter _ = _
        simp [addPay, List.filter_append, hqr]
      · intro p hp
        obtain ⟨hpm, hpr⟩ := party_of_filter hp
        rw [advance_settle_other hB (by simp [addPay, hpm]) (hpr ▸ Ne.symm hq), advance_addPay]
      · rw [balance_settle, balance_addPay]; simp [Ne.symm hq]
  | reverse pid =>
    cases hfind : (run ops).payments.find? (fun x => x.id == pid && !x.reversed) with
    | none => simp only [step, hfind]
    | some p =>
      have hpr : p.party ≠ r := fun e => hop (by simp [opParty, hfind, e])
      obtain ⟨hp, -, hrev⟩ := find_reverse hfind
      have hB := revState_base h.toBase hp hrev
      rw [step_reverse hfind]
      apply partyView_eq
      · rfl
      · intro b hb
        obtain ⟨hbm, hbr⟩ := party_of_filter hb
        rw [outstanding_settle_other hB hbm (hbr ▸ Ne.symm hpr),
          outstanding_rev_other h.toBase hp hrev hbm (hbr ▸ Ne.symm hpr)]
      · obtain ⟨l1, l2, he, hf, -, -⟩ := flip_payments h.toBase hp
        have hf1 : (p.party == r) = false := by simpa using hpr
        show List.filter _ ((run ops).payments.map (flip p.id)) = List.filter _ (run ops).payments
        rw [hf, he]
        simp [List.filter_append, List.filter_cons, hf1]
      · intro x hx
        obtain ⟨hxm, hxr⟩ := party_of_filter hx
        have hne : x.id ≠ p.id := by
          intro he; have := payment_eq h.toBase hxm hp he; exact hpr (this ▸ hxr)
        have hmem : x ∈ (revState (run ops) p).payments := by
          show x ∈ (run ops).payments.map (flip p.id)
          exact List.mem_map.mpr ⟨x, hxm, by simp [flip, hne]⟩
        rw [advance_settle_other hB hmem (hxr ▸ Ne.symm hpr), advance_rev]
      · rw [balance_settle, balance_rev h.toBase hp hrev]; simp [Ne.symm hpr]

theorem partiesIsolated_witness :
    ∃ (ops : List Op) (op : Op) (r : Nat) (_ : opParty (run ops) op ≠ some r), True :=
  ⟨[], .bill 1 1 5, 2, by simp [opParty], trivial⟩

end Proofs.Ledger
