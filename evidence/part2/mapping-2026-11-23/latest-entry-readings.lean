import Spec.Retro
open Spec.Retro
def two : List Event := [⟨1, 2, .disburse 10⟩, ⟨2, 0, .disburse 10⟩]
def l2 := (forkSync two).ledger
-- "most recent entry" read as the LAST-APPENDED entry: its date is 0, so the
-- payment (date 1) is in-order and is applied directly at the tail.
#eval ("last-appended entry's date", (l2.getLast?.map (·.eff)), "latest date (our reading)", latestEff l2)
#eval ("payment applied at tail: balance after", (current l2).add (effect (current l2) (.pay 20 .feeFirst)))
#eval ("our reading (forkSync)", current (forkSync (two ++ [⟨3, 1, .pay 20 .feeFirst⟩])).ledger,
       "adjustments made", ((forkSync (two ++ [⟨3, 1, .pay 20 .feeFirst⟩])).ledger.filter (·.kind == .adjustment)).length)
