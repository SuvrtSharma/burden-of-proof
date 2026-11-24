-- Trace of scenario 1 (double reversal) through Precise Ledger Pro's Haskell
-- port: the ledger and the clock after each activity, then the second
-- reversal step by step, using the port's own exported functions in the same
-- order as its reverseLedgerActivity. Run with the same lookups as Repro.hs
-- (the Java repository's query bounds).
--   runghc -i<their haskell/src> TraceDoubleReversal.hs
module Main (main) where

import Data.List (sortBy)
import Data.Ord (comparing)
import Data.Time (LocalTime (..), fromGregorian, TimeOfDay (..))
import Ledger.Types
import Ledger.Core (currentBalance, calculateTotalImpact, rollbackToEntryBeforeActivity, addEntry)
import Ledger.Service (applyLedgerActivities, applyLedgerActivity, syncWithRetroactiveLedger, ActivityLookup (..))

loan :: String
loan = "L1"

effAt, made :: Int -> LocalTime
effAt d = LocalTime (fromGregorian 2024 3 (1 + fromIntegral d)) (TimeOfDay 12 0 0)
made p = LocalTime (fromGregorian 2024 4 1) (TimeOfDay 0 p 0)

disb :: String -> Int -> Int -> LedgerActivity
disb i d p = TransactionActivity loan "Disbursal" "Transaction" i (effAt d) (made p) 10 Credit "P"

rev :: String -> String -> Int -> Int -> LedgerActivity
rev i target d p = ReversalActivityData loan "Reversal" "Reversal" i (effAt d) (made p) "Transaction" target

acts :: [LedgerActivity]
acts = [disb "a" 0 0, disb "b" 1 1, rev "r1" "b" 2 2, rev "r2" "a" 3 3]

lkup :: ActivityLookup
lkup = ActivityLookup
  { lookupActivitiesAfter = \_ eff before ->
      sortBy (comparing laEffectiveAt) [x | x <- acts, laEffectiveAt x >= eff, laCreatedAt x < before]
  , lookupActivitiesCreatedSince = \_ _ aId before ->
      case [laCreatedAt x | x <- acts, laActivityId x == aId] of
        (t : _) -> [x | x <- acts, laCreatedAt x > t, laCreatedAt x <= before]
        [] -> []
  }

showEntry :: LedgerEntry -> String
showEntry e = "    " ++ leEntryType e ++ " src=" ++ leSourceLedgerActivityId e
  ++ " principal " ++ show (lePrincipal e) ++ " -> running " ++ show (lePrincipalBalance e)

showLedger :: String -> Ledger -> LedgerClock -> IO ()
showLedger label l c = do
  putStrLn (label ++ "  (clock now = " ++ show (clockNow c) ++ ", principal = " ++ show (balPrincipal (currentBalance l)) ++ ")")
  mapM_ (putStrLn . showEntry) (ledgerEntries l)

main :: IO ()
main = do
  let empty = Ledger loan zeroBalance [] "USD"
      step (l, c) x = applyLedgerActivity lkup Nothing x l c
      states = scanl step (empty, defaultClock) acts
  mapM_ (\(x, (l, c)) -> showLedger ("after " ++ laActivityId x) l c) (zip acts (tail states))

  -- The second reversal, step by step, starting from the state after r1.
  let (l2, c2) = states !! 3
      r2 = acts !! 3
      Just impact = calculateTotalImpact "Transaction" "a" l2
      comp = LedgerEntry loan "" "Reversal" 0 (negate (balPrincipal impact)) 0 0 0 0 0 0 0 (effAt 3) (made 3) "Transaction" "a"
      l3 = addEntry comp l2
      fork = rollbackToEntryBeforeActivity "Transaction" "a" l3
      replay = sortBy (comparing laEffectiveAt) (filter (/= r2) (lookupActivitiesCreatedSince lkup loan "Transaction" "a" (clockNow c2)))
      (fork', _) = applyLedgerActivities lkup Nothing replay fork c2
      synced = syncWithRetroactiveLedger l3 fork' (clockNow c2) (made 3) (length (ledgerEntries fork))
  putStrLn ""
  putStrLn "inside r2 (reverse a):"
  putStrLn ("  clock now when r2 starts: " ++ show (clockNow c2) ++ "   (r1 was created at " ++ show (made 2) ++ ")")
  putStrLn ("  replay set (created after a, at or before clock now, without r2): " ++ show (map laActivityId replay))
  showLedger "  fork after replay" fork' c2
  putStrLn ("  primary impact of b: " ++ show (fmap balPrincipal (calculateTotalImpact "Transaction" "b" l3))
            ++ "   fork impact of b: " ++ show (fmap balPrincipal (calculateTotalImpact "Transaction" "b" fork')))
  showLedger "  primary after SYNC" synced c2
