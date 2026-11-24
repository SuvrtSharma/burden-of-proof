-- LR10's own test, against Precise Ledger Pro's Haskell port: give every event
-- a fixed identity and a business time (ties allowed, on purpose), run EVERY
-- arrival order, and require the same result each time.
--
-- Why a separate harness: in Repro.hs an event's id is its arrival position,
-- so "ties by id" and "ties by arrival" can't be told apart there, and its
-- oracle (a stable sort on effectiveAt) also breaks ties by arrival. Here ids
-- are fixed per event and only the arrival order changes.
--
-- Arrival orders in which a reversal arrives before its target are skipped:
-- the spec rejects such a reversal (ADR-0026), so they are out of LR10's scope.
--
-- Compared (LR8): the balance per component, and each live activity's total
-- impact, looked up by id (independent of arrival order).
--
-- Build and run (no network; GHC boot packages only):
--   ghc -i<their haskell/src> -outputdir /tmp/o -o /tmp/shuffle Shuffle.hs && /tmp/shuffle N
module Main (main) where

import Data.List (sortBy, permutations, elemIndex)
import Data.Ord (comparing)
import Data.Maybe (fromMaybe)
import Data.Time (LocalTime (..), fromGregorian, TimeOfDay (..))
import System.Environment (getArgs)
import Ledger.Types
import Ledger.Core (currentBalance, calculateTotalImpact)
import Ledger.Service (applyLedgerActivities, ActivityLookup (..))

loan :: String
loan = "L1"

-- Business time: 2024-03-01 plus d days, at noon. Same d means an exact tie.
effAt :: Int -> LocalTime
effAt d = LocalTime (fromGregorian 2024 3 (1 + fromIntegral d)) (TimeOfDay 12 0 0)

-- Arrival (createdAt): one minute per arrival position, after every business time.
createdAt' :: Int -> LocalTime
createdAt' p = LocalTime (fromGregorian 2024 4 1) (TimeOfDay 0 p 0)

data Spec = Disb | Chg | Pay5 | Pay20 | Rev Int  -- Rev i: reverse the event at index i of the set
  deriving (Show, Eq)

-- Fixed identities, independent of arrival.
ids :: [String]
ids = ["a", "b", "c", "d", "e"]

-- The event at set index k, arriving at position p.
mk :: Int -> Int -> (Spec, Int) -> LedgerActivity
mk p k (s, d) = case s of
  Disb  -> tx "Disbursal" 10 Credit "P"
  Chg   -> tx "Fee" 3 Credit "F"
  Pay5  -> tx "Payment" 5 Debit "FIP"
  Pay20 -> tx "Payment" 20 Debit "FIP"
  Rev i -> ReversalActivityData loan "Reversal" "Reversal" (ids !! k) (effAt d) (createdAt' p) "Transaction" (ids !! i)
  where
    tx name amt dir spread = TransactionActivity loan name "Transaction" (ids !! k) (effAt d) (createdAt' p) amt dir spread

isRev :: LedgerActivity -> Bool
isRev ReversalActivityData{} = True
isRev _ = False

-- Same lookups as Repro.hs (the Java repository's bounds).
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

liveOf :: [LedgerActivity] -> [LedgerActivity]
liveOf acts = [a | a <- acts, not (isRev a), laActivityId a `notElem` reversed]
  where reversed = [laReversedActivityId r | r@ReversalActivityData{} <- acts]

run :: [LedgerActivity] -> State
run acts =
  let l = fst (applyLedgerActivities (lookupsFor acts) Nothing acts emptyLedger defaultClock)
  in ( asList (currentBalance l)
     , sortBy (comparing fst)
         [ (laActivityId a, maybe [0, 0, 0, 0] asList (calculateTotalImpact "Transaction" (laActivityId a) l))
         | a <- liveOf acts ] )

close :: State -> State -> Bool
close (b1, i1) (b2, i2) = near b1 b2 && map fst i1 == map fst i2 && and (zipWith (\x y -> near (snd x) (snd y)) i1 i2)
  where near xs ys = length xs == length ys && and (zipWith (\x y -> abs (x - y) < 0.005) xs ys)

-- Every event set of up to n events, business times in {0, 1} (so ties are
-- common), reversals only of earlier non-reversal events, each at most once.
setsUpTo :: Int -> [[(Spec, Int)]]
setsUpTo n = concatMap go [1 .. n]
  where
    go 0 = [[]]
    go k = [ pre ++ [(s, d)]
           | pre <- go (k - 1)
           , d <- [0, 1]
           , s <- [Disb, Chg, Pay5, Pay20]
                  ++ [Rev i | (i, (t, _)) <- zip [0 ..] pre, not (isRevS t), Rev i `notElem` map fst pre]
           ]
    isRevS (Rev _) = True
    isRevS _ = False

-- Arrival orders (permutations of set indices) with every reversal after its target.
ordersFor :: [(Spec, Int)] -> [[Int]]
ordersFor set = filter ok (permutations [0 .. length set - 1])
  where
    ok perm = and [ pos k > pos i | (k, (Rev i, _)) <- zip [0 ..] set ]
      where pos x = fromMaybe 0 (elemIndex x perm)

buildIn :: [(Spec, Int)] -> [Int] -> [LedgerActivity]
buildIn set perm = [ mk p k (set !! k) | (p, k) <- zip [0 ..] perm ]

main :: IO ()
main = do
  args <- getArgs
  let n = case args of (a : _) -> read a; [] -> 3
      sets = setsUpTo n
      results = [ (set, [ (perm, run (buildIn set perm)) | perm <- ordersFor set ]) | set <- sets ]
      disagree = [ (set, rs) | (set, rs@((_, r0) : _)) <- results, not (all (close r0 . snd) rs) ]
      runs = sum [ length rs | (_, rs) <- results ]
  putStrLn ("event sets (up to " ++ show n ++ " events, times in {0,1}): " ++ show (length sets))
  putStrLn ("arrival orders run: " ++ show runs)
  putStrLn ("sets whose result depends on arrival order: " ++ show (length disagree))
  case take 1 (sortBy (comparing (length . fst)) disagree) of
    [(set, rs@((p0, r0) : _))] -> do
      putStrLn ("  smallest: " ++ show (zip ids set))
      let (p1, r1) = head [ x | x <- rs, not (close r0 (snd x)) ]
      putStrLn ("    arrival " ++ show (map (ids !!) p0) ++ ": " ++ show r0)
      putStrLn ("    arrival " ++ show (map (ids !!) p1) ++ ": " ++ show r1)
    _ -> pure ()
