-- Differential check of Precise Ledger Pro's Haskell port against itself.
--
-- Arrival run: the events as they arrive, so late events go through the
-- port's fork-and-sync (applyLedgerActivities).
-- Oracle run: the live events (no reversals, nothing reversed) fed in business
-- order to the same engine, so no late-event path is ever taken. That is the
-- "correct branch" of rule LR8, computed with the port's own allocation rules,
-- so a difference can't come from our modelling choices.
--
-- Compared (LR8, ADR-0024): the current balance per component, and each live
-- activity's total impact. Only sequences with distinct business times are
-- used, so same-time ordering plays no part.
--
-- Run (no network needed; uses only GHC boot packages):
--   runghc -i<their haskell/src> Repro.hs
module Main (main) where

import Data.List (sortBy, nub)
import Data.Ord (comparing)
import Data.Time (LocalTime (..), fromGregorian, TimeOfDay (..))
import Ledger.Types
import Ledger.Core (currentBalance, calculateTotalImpact)
import Ledger.Service (applyLedgerActivities, ActivityLookup (..))

loan :: String
loan = "L1"

-- Business time: 2024-03-01 plus d days, at noon.
effAt :: Int -> LocalTime
effAt d = LocalTime (fromGregorian 2024 3 (1 + fromIntegral d)) (TimeOfDay 12 0 0)

-- Arrival (createdAt): 2024-04-01, one minute per position, after every business time.
createdAt' :: Int -> LocalTime
createdAt' p = LocalTime (fromGregorian 2024 4 1) (TimeOfDay 0 p 0)

data Spec = Disb | Chg | Pay5 | Pay20 | Rev Int  -- Rev i: reverse the event at position i
  deriving (Show, Eq)

mk :: Int -> (Spec, Int) -> LedgerActivity
mk p (s, d) = case s of
  Disb  -> tx "Disbursal" 10 Credit "P"
  Chg   -> tx "Fee" 3 Credit "F"
  Pay5  -> tx "Payment" 5 Debit "FIP"
  Pay20 -> tx "Payment" 20 Debit "FIP"
  Rev i -> ReversalActivityData loan "Reversal" "Reversal" (show p) (effAt d) (createdAt' p) "Transaction" (show i)
  where
    tx name amt dir spread = TransactionActivity loan name "Transaction" (show p) (effAt d) (createdAt' p) amt dir spread

isRev :: LedgerActivity -> Bool
isRev ReversalActivityData{} = True
isRev _ = False

-- The lookups a database of all these activities would answer, with the exact
-- bounds of the Java repository (LedgerActivityRepository.java):
--   effective-on-or-after:  effectiveAt >= eff AND transactionTime <  createdAt
--   created-since:          transactionTime > target's AND transactionTime <= createdAt
lookupsFor :: [LedgerActivity] -> ActivityLookup
lookupsFor acts = ActivityLookup
  { lookupActivitiesAfter = \_ eff before ->
      sortBy (comparing laEffectiveAt) [a | a <- acts, laEffectiveAt a >= eff, laCreatedAt a < before]
  , lookupActivitiesCreatedSince = \_ _ aId before ->
      case [laCreatedAt a | a <- acts, laActivityId a == aId] of
        (t : _) -> [a | a <- acts, laCreatedAt a > t, laCreatedAt a <= before]
        [] -> []
  }

emptyLedger :: Ledger
emptyLedger = Ledger loan zeroBalance [] "USD"

type State = ([Double], [(String, [Double])])

asList :: Balance -> [Double]
asList b = [balFee b, balInterest b, balPrincipal b, balExcess b]

stateOf :: Ledger -> [LedgerActivity] -> State
stateOf l live =
  ( asList (currentBalance l)
  , sortBy (comparing fst)
      [ (laActivityId a, maybe [0, 0, 0, 0] asList (calculateTotalImpact "Transaction" (laActivityId a) l)) | a <- live ] )

liveOf :: [LedgerActivity] -> [LedgerActivity]
liveOf acts = [a | a <- acts, not (isRev a), laActivityId a `notElem` reversed]
  where reversed = [laReversedActivityId r | r@ReversalActivityData{} <- acts]

arrival, oracle :: [LedgerActivity] -> State
arrival acts = stateOf (fst (applyLedgerActivities (lookupsFor acts) Nothing acts emptyLedger defaultClock)) (liveOf acts)
oracle acts =
  let live = sortBy (comparing laEffectiveAt) (liveOf acts)
  in stateOf (fst (applyLedgerActivities (lookupsFor live) Nothing live emptyLedger defaultClock)) live

close :: State -> State -> Bool
close (b1, i1) (b2, i2) = near b1 b2 && map fst i1 == map fst i2 && and (zipWith (\x y -> near (snd x) (snd y)) i1 i2)
  where near xs ys = and (zipWith (\x y -> abs (x - y) < 0.005) xs ys)

-- Every sequence of up to n events, with distinct business times 0..n-1,
-- reversals only of earlier non-reversal events, each target at most once.
sequencesUpTo :: Int -> [[(Spec, Int)]]
sequencesUpTo n = concatMap go [0 .. n]
  where
    go 0 = [[]]
    go k = [ pre ++ [(s, d)]
           | pre <- go (k - 1)
           , d <- [0 .. n - 1], d `notElem` map snd pre
           , s <- [Disb, Chg, Pay5, Pay20] ++ [Rev i | (i, (t, _)) <- zip [0 ..] pre, not (isRevS t), Rev i `notElem` map fst pre]
           ]
    isRevS (Rev _) = True
    isRevS _ = False

build :: [(Spec, Int)] -> [LedgerActivity]
build = zipWith mk [0 ..]

main :: IO ()
main = do
  -- The model's smallest candidate: disbursal at t2, a late disbursal at t0,
  -- then a late payment of 20 at t1.
  let lateAfterLate = build [(Disb, 2), (Disb, 0), (Pay20, 1)]
  putStrLn "lateAfterLate (model's candidate):"
  putStrLn ("  arrival run: " ++ show (arrival lateAfterLate))
  putStrLn ("  oracle run:  " ++ show (oracle lateAfterLate))
  putStrLn ("  same: " ++ show (close (arrival lateAfterLate) (oracle lateAfterLate)))
  let seqs = filter (\s -> length (nub (map snd s)) == length s) (sequencesUpTo 3)
      bad = [s | s <- seqs, not (close (arrival (build s)) (oracle (build s)))]
  putStrLn ("sequences of up to 3 events with distinct business times: " ++ show (length seqs))
  putStrLn ("differ from the in-order oracle: " ++ show (length bad))
  mapM_ (\s -> do
          putStrLn ("  " ++ show s)
          putStrLn ("    arrival: " ++ show (arrival (build s)))
          putStrLn ("    oracle:  " ++ show (oracle (build s))))
        (take 5 bad)
  -- Realistic loans: the first event is a disbursal at the earliest business
  -- time, and every later event is dated after it. Up to four events.
  let loans = [ s | s <- filter (\s -> length (nub (map snd s)) == length s) (sequencesUpTo 4)
                  , not (null s), head s == (Disb, 0) ]
      badLoans = [s | s <- loans, not (close (arrival (build s)) (oracle (build s)))]
      balanceDiffers s = let (b1, _) = arrival (build s); (b2, _) = oracle (build s)
                         in not (and (zipWith (\x y -> abs (x - y) < 0.005) b1 b2))
  putStrLn ("loans starting with a disbursal at time 0, up to 4 events: " ++ show (length loans))
  putStrLn ("differ from the in-order oracle: " ++ show (length badLoans))
  putStrLn ("of which the final balance itself differs: " ++ show (length (filter balanceDiffers badLoans)))
  let shortest = take 3 (sortBy (comparing length) (filter balanceDiffers badLoans))
  mapM_ (\s -> do
          putStrLn ("  " ++ show s)
          putStrLn ("    arrival: " ++ show (arrival (build s)))
          putStrLn ("    oracle:  " ++ show (oracle (build s))))
        shortest
  let isRevStep (Rev _, _) = True
      isRevStep _ = False
      lateOnly = take 3 (sortBy (comparing length)
                   (filter (\s -> balanceDiffers s && not (any isRevStep s)) badLoans))
  putStrLn ("of which with no reversals at all: "
            ++ show (length (filter (\s -> balanceDiffers s && not (any isRevStep s)) badLoans)))
  mapM_ (\s -> do
          putStrLn ("  " ++ show s)
          putStrLn ("    arrival: " ++ show (arrival (build s)))
          putStrLn ("    oracle:  " ++ show (oracle (build s))))
        lateOnly
  -- Every realistic loan whose final balance differs, one per line, for diffing runs.
  mapM_ (\s -> putStrLn ("FAIL " ++ show s)) (filter balanceDiffers badLoans)
