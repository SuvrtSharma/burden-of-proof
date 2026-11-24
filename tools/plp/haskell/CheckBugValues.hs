module Main where
import Data.Time (LocalTime(..), fromGregorian, TimeOfDay(..))
import Ledger.Types
import Ledger.Core (currentBalance, calculateTotalImpact)
import Ledger.Service (applyLedgerActivities, ActivityLookup(..))
e d = LocalTime (fromGregorian 2024 3 (1+d)) (TimeOfDay 12 0 0)
c p = LocalTime (fromGregorian 2024 4 1) (TimeOfDay p 0 0)
disb i d p = TransactionActivity "L" "Disbursal" "Transaction" i (e d) (c p) 10 Credit "P"
pay  i d p a = TransactionActivity "L" "Payment" "Transaction" i (e d) (c p) a Debit "FIP"
rev  i t d p = ReversalActivityData "L" "Reversal" "Reversal" i (e d) (c p) "Transaction" t
emptyL = Ledger "L" zeroBalance [] "USD"
lk acts = ActivityLookup (\_ ef bf -> [x|x<-acts, laEffectiveAt x>=ef, laCreatedAt x<bf]) (\_ _ _ _ -> [])
run acts = fst (applyLedgerActivities (lk acts) Nothing acts emptyL defaultClock)
main = do
  let dr = [disb "a" 0 0, disb "b" 1 1, rev "r1" "b" 2 2, rev "r2" "a" 3 3]
  putStrLn $ "double reversal  -> " ++ show (currentBalance (run dr)) ++ "   (want principal 0)"
  let bp = [disb "a" 0 0, disb "b" 2 1, pay "c" 1 2 20, disb "d" 3 3]
      l = run bp
  putStrLn $ "backdated payment-> " ++ show (currentBalance l) ++ "   (want principal 10, excess 0)"
  putStrLn $ "  impact d = " ++ show (calculateTotalImpact "Transaction" "d" l) ++ "   (want +10 principal)"
