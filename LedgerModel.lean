-- The spec's ledger (v2), compiled into a program for the conformance harness
-- (ADR-0007). Reads one JSON operation per line and prints one JSON response
-- per line. Uses only definitions from Spec.Ledger; it adds nothing but I/O.
import Lean.Data.Json
import Spec
open Lean Spec.Ledger

def allocJson (a : Alloc) : Json :=
  Json.mkObj [("payment", a.payment), ("bill", a.bill), ("amount", a.amount)]

/-- The allocations the last operation added. -/
def added (before after : State) : Json :=
  Json.arr ((after.allocs.drop before.allocs.length).map allocJson).toArray

def respond (s : State) (j : Json) : Except String (State × Json) := do
  let op ← j.getObjValAs? String "op"
  match op with
  | "reset" => return (State.init, Json.mkObj [("ok", true)])
  | "bill" =>
    let p ← j.getObjValAs? Nat "party"
    let d ← j.getObjValAs? Nat "date"
    let a ← j.getObjValAs? Int "amount"
    if a ≤ 0 then return (s, Json.mkObj [("error", "invalid amount")]) else
    let s' := step s (.bill p d a)
    return (s', Json.mkObj [("bill", s.nextBill), ("allocations", added s s')])
  | "pay" =>
    let p ← j.getObjValAs? Nat "party"
    let a ← j.getObjValAs? Int "amount"
    if a ≤ 0 then return (s, Json.mkObj [("error", "invalid amount")]) else
    let s' := step s (.pay p a)
    let adv := match s'.payments.find? (·.id == s.nextPayment) with
      | some pay => advance s' pay
      | none => 0
    return (s', Json.mkObj [("payment", s.nextPayment), ("allocations", added s s'), ("advance", adv)])
  | "reverse" =>
    let pid ← j.getObjValAs? Nat "payment"
    match s.payments.find? (fun x => x.id == pid && !x.reversed) with
    | none => return (s, Json.mkObj [("error", "no live payment")])
    | some _ =>
      let s' := step s (.reverse pid)
      return (s', Json.mkObj [("reversed", pid), ("allocations", added s s')])
  | "balance" =>
    let p ← j.getObjValAs? Nat "party"
    return (s, Json.mkObj [("balance", balance s p)])
  | "open" =>
    let p ← j.getObjValAs? Nat "party"
    let bills := (openBills s p).map fun b =>
      Json.mkObj [("bill", b.id), ("date", b.date), ("outstanding", outstanding s b)]
    return (s, Json.mkObj [("open", Json.arr bills.toArray)])
  | other => throw s!"unknown op {other}"

partial def loop (stdin : IO.FS.Stream) (stdout : IO.FS.Stream) (s : State) : IO Unit := do
  let line ← stdin.getLine
  if line.isEmpty then return
  let line := line.trimAscii.toString
  if line.isEmpty then loop stdin stdout s else
  match Json.parse line >>= respond s with
  | .ok (s', out) => stdout.putStrLn out.compress; stdout.flush; loop stdin stdout s'
  | .error e => stdout.putStrLn (Json.mkObj [("error", e)]).compress; stdout.flush; loop stdin stdout s

def main : IO Unit := do
  loop (← IO.getStdin) (← IO.getStdout) State.init
