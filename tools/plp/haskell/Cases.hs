-- Run specific sequences from the Lean model through Precise Ledger Pro's
-- Haskell port: the arrival-order run against an on-time run (the live events
-- arriving in business order, (date, id), with recording times reassigned to
-- match). The port's own engine on both sides, so its allocation rules cancel.
--   ghc -i<their haskell/src> -outputdir /tmp/o -o /tmp/cases Cases.hs && /tmp/cases
module Main (main) where

import Data.List (sortBy)
import Data.Ord (comparing)
import Data.Time (LocalTime (..), fromGregorian, TimeOfDay (..))
import Ledger.Types
import Ledger.Core (currentBalance, calculateTotalImpact)
import Ledger.Service (applyLedgerActivities, ActivityLookup (..))

loan :: String
loan = "L1"

effAt :: Int -> LocalTime
effAt d = LocalTime (fromGregorian 2024 3 (1 + fromIntegral d)) (TimeOfDay 12 0 0)

createdAt' :: Int -> LocalTime
createdAt' p = LocalTime (fromGregorian 2024 4 1) (TimeOfDay 0 p 0)

data K = Disb Double | Chg Double | PayFIP Double | Rev Int deriving Show

-- (id, business day, kind), listed in arrival order.
type Ev = (Int, Int, K)

mk :: Int -> Ev -> LedgerActivity
mk p (i, d, k) = case k of
  Disb a   -> tx "Disbursal" a Credit "P"
  Chg a    -> tx "Fee" a Credit "F"
  PayFIP a -> tx "Payment" a Debit "FIP"
  Rev t    -> ReversalActivityData loan "Reversal" "Reversal" (show i) (effAt d) (createdAt' p) "Transaction" (show t)
  where tx name amt dir spread = TransactionActivity loan name "Transaction" (show i) (effAt d) (createdAt' p) amt dir spread

lookupsFor :: [LedgerActivity] -> ActivityLookup
lookupsFor acts = ActivityLookup
  { lookupActivitiesAfter = \_ eff before ->
      sortBy (comparing laEffectiveAt) [a | a <- acts, laEffectiveAt a >= eff, laCreatedAt a < before]
  , lookupActivitiesCreatedSince = \_ _ aId before ->
      case [laCreatedAt a | a <- acts, laActivityId a == aId] of
        (t : _) -> [a | a <- acts, laCreatedAt a > t, laCreatedAt a <= before]
        [] -> []
  }

isRevK :: K -> Bool
isRevK (Rev _) = True
isRevK _ = False

state :: [Ev] -> ([Double], [(String, [Double])])
state evs =
  let acts = zipWith mk [0 ..] evs
      l = fst (applyLedgerActivities (lookupsFor acts) Nothing acts (Ledger loan zeroBalance [] "USD") defaultClock)
      reversed = [t | (_, _, Rev t) <- evs]
      subjects = [show i | (i, _, k) <- evs, not (isRevK k)]
      asList b = [balFee b, balPrincipal b, balExcess b]
  in (asList (currentBalance l), [(s, maybe [0, 0, 0] asList (calculateTotalImpact "Transaction" s l)) | s <- subjects, read s `notElem` reversed || True])

onTime :: [Ev] -> [Ev]
onTime evs = sortBy (comparing (\(i, d, _) -> (d, i))) [e | e@(i, _, k) <- evs, not (isRevK k), i `notElem` [t | (_, _, Rev t) <- evs]]

report :: String -> [Ev] -> IO ()
report name evs = do
  let s1 = state evs; s2 = state (onTime evs)
  putStrLn (name ++ ": " ++ show evs)
  putStrLn ("  arrival (fee, principal, excess): " ++ show s1)
  putStrLn ("  on time:                          " ++ show s2)
  putStrLn ("  late path agrees with on time: " ++ show (s1 == s2))

main :: IO ()
main = do
  -- Lean model: right under the old date mapping, wrong under READING 8.
  report "now-disagree" [(1, 1, PayFIP 5), (2, 0, Chg 3), (3, 1, PayFIP 5)]
  -- Lean model: wrong under the old mapping, right under READING 8.
  report "now-agree" [(1, 2, PayFIP 5), (2, 0, Chg 3), (3, 1, Chg 3)]
  -- Lean model: wrong under all three readings of the fork's balances (stored,
  -- recomputed, or summed), with distinct dates and no reversal.
  report "robust" [(1, 1, PayFIP 5), (2, 0, Chg 3), (3, 2, PayFIP 5)]
