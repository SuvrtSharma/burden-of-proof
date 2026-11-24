/-
The ledger behind the reference API (ADR-0009, ADR-0019). Spec version 2.

DRAFT, written by an agent on 2026-11-07 from the owner's review decisions,
waiting for the owner's review. Until it is locked, no claim against it counts.

**This is a deliberately small, do-it-yourself ledger, not an accounting
system.** It has parties, dated bills, payments, advances that settle new bills
automatically, and whole-payment reversals. Its purpose is to be precise
enough to prove things about.

Deliberately left out, so no claim here covers them:
- tenants (one ledger, no tenant isolation) and scope (no site or project on
  bills or payments);
- unpriced bills (every bill has its amount when it is recorded);
- currencies, taxes, credit notes, partial refunds, write-offs, due dates and
  interest;
- partial reversals (a reversal undoes a whole payment) and reversing a bill;
- back-dated reshuffling: bills are settled oldest-first *at the moment of
  settlement*, so recording a bill with an earlier date does not move
  allocations already made;
- concurrency (one operation at a time; the store's locking is out of scope);
- party existence (the API checks it; the model accepts any party number).

Money is an integer number of minor units (`Int`), never a float. It is
written `Int`, not `abbrev Money := Int`: on Lean 4.35.0, `omega` fails on
the same goal stated over such an abbrev ("No usable constraints found")
unless the abbrev is unfolded first. Reproduction:
`evidence/lean/omega-abbrev-4.35.0.lean`, with its output beside it.

Every `def … : Prop` in `namespace Spec` below only *states* a claim. A claim
counts as true only once `python -m godshand prove` accepts its proof.

The state stores only facts: bills, payments, allocations of payments to
bills, and which payments are reversed. What a bill still owes and what a
payment has left as an advance are *computed* from those facts, never stored.
-/
namespace Spec.Ledger

structure Bill where
  id     : Nat
  party  : Nat
  date   : Nat      -- a day number; used only to order bills
  amount : Int
  deriving Repr, DecidableEq

structure Payment where
  id       : Nat
  party    : Nat
  amount   : Int
  reversed : Bool
  deriving Repr, DecidableEq

/-- `amount` of payment `payment` was applied to bill `bill`. -/
structure Alloc where
  payment : Nat
  bill    : Nat
  amount  : Int
  deriving Repr, DecidableEq

inductive Op where
  | bill    (party date : Nat) (amount : Int)
  | pay     (party : Nat) (amount : Int)
  | reverse (payment : Nat)
  deriving Repr, DecidableEq

structure State where
  bills       : List Bill      -- in the order they were recorded
  payments    : List Payment   -- in the order they were recorded
  allocs      : List Alloc
  nextBill    : Nat
  nextPayment : Nat
  /-- A running balance per party, kept up to date by every operation.
  The cached-balance optimisation reads this instead of summing rows. -/
  cache       : Nat → Int

def State.init : State :=
  { bills := [], payments := [], allocs := [], nextBill := 1, nextPayment := 1, cache := fun _ => 0 }

/-! ## What is derived from the facts -/

/-- A payment counts only while it exists and is not reversed. -/
def live (s : State) (pid : Nat) : Bool :=
  s.payments.any fun p => p.id == pid && !p.reversed

/-- What live payments have applied to bill `bid`. -/
def allocatedTo (s : State) (bid : Nat) : Int :=
  ((s.allocs.filter fun a => a.bill == bid && live s a.payment).map (·.amount)).sum

/-- What payment `pid` has applied to bills. -/
def allocatedFrom (s : State) (pid : Nat) : Int :=
  ((s.allocs.filter fun a => a.payment == pid).map (·.amount)).sum

/-- What a bill still owes. -/
def outstanding (s : State) (b : Bill) : Int := b.amount - allocatedTo s b.id

/-- What a payment has left over, unapplied. A reversed payment has none. -/
def advance (s : State) (p : Payment) : Int :=
  if p.reversed then 0 else p.amount - allocatedFrom s p.id

/-- A party's balance: everything billed minus every payment that still counts. -/
def balance (s : State) (q : Nat) : Int :=
  ((s.bills.filter (·.party == q)).map (·.amount)).sum
    - ((s.payments.filter fun p => p.party == q && !p.reversed).map (·.amount)).sum

/-! ## Settlement order: oldest bill date first, ties broken by bill id -/

def billBefore (a b : Bill) : Bool := a.date < b.date || (a.date == b.date && a.id ≤ b.id)

/-- A party's bills that still owe something, oldest first. -/
def openBills (s : State) (q : Nat) : List Bill :=
  (s.bills.filter fun b => b.party == q && decide (0 < outstanding s b)).mergeSort billBefore

/-- A party's payments with an unapplied advance, oldest payment first. -/
def advances (s : State) (q : Nat) : List Payment :=
  s.payments.filter fun p => p.party == q && decide (0 < advance s p)

/-! ## Applying advances to open bills -/

/-- Match `(bill id, owed)` against `(payment id, advance)`, both in order:
each bill takes from the oldest advance until it is paid or the advances
run out. -/
def matchUp : List (Nat × Int) → List (Nat × Int) → List Alloc
  | [], _ => []
  | _, [] => []
  | (b, o) :: bs, (p, a) :: ps =>
    if o < a then ⟨p, b, o⟩ :: matchUp bs ((p, a - o) :: ps)
    else if a < o then ⟨p, b, a⟩ :: matchUp ((b, o - a) :: bs) ps
    else ⟨p, b, o⟩ :: matchUp bs ps
termination_by bs ps => bs.length + ps.length

/-- After every operation, a party's unapplied advances settle its open bills. -/
def settleParty (s : State) (q : Nat) : State :=
  { s with allocs := s.allocs ++
      matchUp ((openBills s q).map fun b => (b.id, outstanding s b))
              ((advances s q).map fun p => (p.id, advance s p)) }

def adjust (cache : Nat → Int) (q : Nat) (delta : Int) : Nat → Int :=
  fun r => if r = q then cache r + delta else cache r

/-- One operation. Invalid input is rejected and changes nothing:
amounts must be positive, and only a live payment can be reversed. -/
def step (s : State) : Op → State
  | .bill q d a =>
    if a ≤ 0 then s else
    settleParty { s with bills := s.bills ++ [⟨s.nextBill, q, d, a⟩],
                         nextBill := s.nextBill + 1,
                         cache := adjust s.cache q a } q
  | .pay q a =>
    if a ≤ 0 then s else
    settleParty { s with payments := s.payments ++ [⟨s.nextPayment, q, a, false⟩],
                         nextPayment := s.nextPayment + 1,
                         cache := adjust s.cache q (-a) } q
  | .reverse pid =>
    match s.payments.find? (fun p => p.id == pid && !p.reversed) with
    | none => s
    | some p =>
      settleParty { s with payments := s.payments.map (fun x => if x.id == pid then { x with reversed := true } else x),
                           cache := adjust s.cache p.party p.amount } p.party

def run (ops : List Op) : State := ops.foldl step State.init

/-! ## The capped-scan optimisation (OPT-CAP-SETTLE-SCAN): look at only the first `k` open bills -/

def matchUpCapped (k : Nat) (bills advs : List (Nat × Int)) : List Alloc := matchUp (bills.take k) advs

end Spec.Ledger

namespace Spec
open Ledger

/-! ## Statements (what claims prove)

### Settlement: the matching step on its own

`owed` lists `(bill id, amount owed)` in settlement order and `adv` lists
`(payment id, advance)` oldest first. Ids are distinct and amounts positive,
which reachable states guarantee (`reachableInvariants`). -/

def wellFormed (xs : List (Nat × Int)) : Prop := (xs.map (·.1)).Nodup ∧ ∀ x ∈ xs, 0 < x.2

def paidTo (A : List Alloc) (bid : Nat) : Int := ((A.filter (·.bill == bid)).map (·.amount)).sum
def takenFrom (A : List Alloc) (pid : Nat) : Int := ((A.filter (·.payment == pid)).map (·.amount)).sum
def total (xs : List (Nat × Int)) : Int := (xs.map (·.2)).sum

/-- Every allocation is positive, goes to an offered bill from an offered
payment, and no bill or payment receives or gives more than offered. -/
def matchWithinLimits : Prop :=
  ∀ (owed adv : List (Nat × Int)), wellFormed owed → wellFormed adv →
    (∀ x ∈ matchUp owed adv, 0 < x.amount ∧ x.bill ∈ owed.map (·.1) ∧ x.payment ∈ adv.map (·.1)) ∧
    (∀ b ∈ owed, paidTo (matchUp owed adv) b.1 ≤ b.2) ∧
    (∀ p ∈ adv, takenFrom (matchUp owed adv) p.1 ≤ p.2)

/-- As much debt as possible is settled: the total matched is the smaller of
everything owed and every advance. (Allocating nothing does not satisfy this.) -/
def matchSettlesMaximum : Prop :=
  ∀ (owed adv : List (Nat × Int)), wellFormed owed → wellFormed adv →
    ((matchUp owed adv).map (·.amount)).sum = min (total owed) (total adv)

/-- Oldest first: a bill receives anything only if every bill before it in
the order is paid in full. -/
def matchPaysOldestFirst : Prop :=
  ∀ (owed adv : List (Nat × Int)), wellFormed owed → wellFormed adv →
    ∀ (i j : Nat) (hi : i < owed.length) (hj : j < owed.length), i < j →
      0 < paidTo (matchUp owed adv) owed[j].1 → paidTo (matchUp owed adv) owed[i].1 = owed[i].2

/-! ### Reachable states: what holds for every state `run` can produce -/

/-- Ids are unique, increasing in recording order and below the next id;
every bill and payment amount is positive; every allocation is positive and
refers to a recorded bill and payment of the same party. -/
def reachableInvariants : Prop :=
  ∀ (ops : List Op), let s := run ops
    (s.bills.map (·.id)).Pairwise (· < ·) ∧ (∀ b ∈ s.bills, b.id < s.nextBill ∧ 0 < b.amount) ∧
    (s.payments.map (·.id)).Pairwise (· < ·) ∧ (∀ p ∈ s.payments, p.id < s.nextPayment ∧ 0 < p.amount) ∧
    (∀ a ∈ s.allocs, 0 < a.amount ∧ ∃ b ∈ s.bills, ∃ p ∈ s.payments, b.id = a.bill ∧ p.id = a.payment ∧ b.party = p.party)

/-- Which party an operation is about (`none` for a reversal of an unknown or
already reversed payment, which changes nothing). -/
def opParty (s : State) : Op → Option Nat
  | .bill q _ _ => some q
  | .pay q _ => some q
  | .reverse pid => (s.payments.find? fun p => p.id == pid && !p.reversed).map (·.party)

/-- Everything about one party: its bills with what they owe, its payments
with their advances, and its balance. -/
def partyView (s : State) (r : Nat) : List (Bill × Int) × List (Payment × Int) × Int :=
  ((s.bills.filter (·.party == r)).map fun b => (b, outstanding s b),
   (s.payments.filter (·.party == r)).map fun p => (p, advance s p),
   balance s r)

/-- Parties are isolated: an operation about one party changes nothing about
any other party. -/
def partiesIsolated : Prop :=
  ∀ (ops : List Op) (op : Op) (r : Nat), opParty (run ops) op ≠ some r →
    partyView (run (ops ++ [op])) r = partyView (run ops) r

/-! ### The ledger's rules -/

/-- Bills and payments must be positive; anything else is rejected and changes nothing. -/
def rejectsNonPositive : Prop :=
  ∀ (s : State) (q d : Nat) (a : Int), a ≤ 0 → step s (.bill q d a) = s ∧ step s (.pay q a) = s

/-- No bill is ever settled beyond what it owes, and none is owed more than its amount. -/
def neverOverSettled : Prop :=
  ∀ (ops : List Op), ∀ b ∈ (run ops).bills,
    0 ≤ outstanding (run ops) b ∧ outstanding (run ops) b ≤ b.amount

/-- No payment is ever applied beyond its amount. -/
def neverOverApplied : Prop :=
  ∀ (ops : List Op), ∀ p ∈ (run ops).payments,
    0 ≤ advance (run ops) p ∧ advance (run ops) p ≤ p.amount

/-- Advances are applied automatically: a party never has an open bill and an
unapplied advance at the same time. -/
def advancesAlwaysApplied : Prop :=
  ∀ (ops : List Op) (q : Nat), openBills (run ops) q = [] ∨ advances (run ops) q = []

/-- Every view of a balance agrees: billed minus paid equals what the bills
still owe minus what the payments have left as advances (KT bug pattern 3). -/
def viewsAgree : Prop :=
  ∀ (ops : List Op) (q : Nat),
    balance (run ops) q =
      (((run ops).bills.filter (·.party == q)).map (outstanding (run ops))).sum
        - (((run ops).payments.filter (·.party == q)).map (advance (run ops))).sum

/-- Reversing a live payment raises its party's balance by exactly its amount,
and changes no other party's balance. -/
def reversalRestoresBalance : Prop :=
  ∀ (ops : List Op) (p : Payment), p ∈ (run ops).payments → p.reversed = false →
    balance (run (ops ++ [.reverse p.id])) p.party = balance (run ops) p.party + p.amount ∧
    ∀ q, q ≠ p.party → balance (run (ops ++ [.reverse p.id])) q = balance (run ops) q

/-- Bills are always settled in a fixed order: oldest date first, ties broken
by bill id, so the same data always settles the same way (KT bug pattern 4). -/
def settlesOldestFirst : Prop :=
  ∀ (ops : List Op) (q : Nat), (openBills (run ops) q).Pairwise fun a b => billBefore a b = true

/-- The running balance always equals the balance worked out from the facts. -/
def cachedBalanceAgrees : Prop :=
  ∀ (ops : List Op) (q : Nat), (run ops).cache q = balance (run ops) q

/-- The capped scan matches like the full scan. (False.) -/
def cappedMatchAgrees : Prop :=
  ∀ (k : Nat) (bills advs : List (Nat × Int)), matchUpCapped k bills advs = matchUp bills advs

/-- The refutation of `cappedMatchAgrees`. -/
def cappedMatchDisagrees : Prop := ¬ cappedMatchAgrees

end Spec
