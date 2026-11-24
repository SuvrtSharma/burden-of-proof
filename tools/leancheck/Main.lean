/-
leancheck: checks one claimed proof inside an already-built Lake project
(ADR-0006).

Usage (run through `lake env` in the target project so LEAN_PATH is set):

    leancheck <proof-module> <statement> <proof>

The statement is a `Prop`-valued definition in the locked spec (ADR-0004).
The proof is a theorem whose type must be exactly that constant. Prints one
JSON object on stdout. Exit code 0 = no violations, 1 = violations,
2 = could not run.

Kernel replay (`leanchecker`) is a separate step run by the Python driver;
this program does not re-check proofs, it only inspects the environment.
-/
import Lean
open Lean Meta

namespace LeanCheck

/-- The only axioms a proof may depend on. An allowlist, never a blocklist:
`native_decide` shows up as an auxiliary axiom with a generated name. -/
def allowedAxioms : List Name := [``propext, ``Classical.choice, ``Quot.sound]

/-- Module roots the spec statement may depend on. -/
def specDepRoots : List Name := [`Init, `Spec]

/-- Module roots that are ours, and so inspected declaration by declaration. -/
def ourRoots : List Name := [`Spec, `Proofs]

structure Violation where
  code   : String
  detail : String

def Violation.toJson (v : Violation) : Json :=
  Json.mkObj [("code", Json.str v.code), ("detail", Json.str v.detail)]

def moduleOf? (env : Environment) (n : Name) : Option Name :=
  (env.getModuleIdxFor? n).map fun idx => env.header.moduleNames[idx.toNat]!

def rootOf (env : Environment) (n : Name) : Name :=
  match moduleOf? env n with
  | some m => m.getRoot
  | none   => .anonymous

def usedConstants (ci : ConstantInfo) : Array Name :=
  ci.type.getUsedConstants ++
    ((ci.value? (allowOpaque := true)).map (·.getUsedConstants) |>.getD #[])

/-- Every constant reachable from `todo`, expanding only constants for which
`expand` holds. Constants that aren't expanded are still included. -/
partial def closure (env : Environment) (expand : Name → Bool) :
    List Name → NameSet → NameSet
  | [], seen => seen
  | n :: rest, seen =>
    if seen.contains n then closure env expand rest seen
    else
      let seen := seen.insert n
      if !expand n then closure env expand rest seen
      else match env.find? n with
        | none    => closure env expand rest seen
        | some ci => closure env expand ((usedConstants ci).toList ++ rest) seen

def axiomsOf (env : Environment) (n : Name) : IO (Array Name) := do
  let ctx : Core.Context := { fileName := "<leancheck>", fileMap := default }
  let (axs, _) ← (collectAxioms n : CoreM (Array Name)).toIO ctx { env }
  return axs

def sortedStrings (ns : Array Name) : List String :=
  (ns.map toString).toList.mergeSort

def runMeta (env : Environment) (x : MetaM α) : IO α := do
  let ctx : Core.Context := { fileName := "<leancheck>", fileMap := default }
  let (a, _) ← (x.run' {} {}).toIO ctx { env }
  return a

/-- `∃ x₁, … ∃ xₙ, True` over every binder of the statement, hypotheses
included. Provable exactly when the hypotheses can all be satisfied, so a
proof of it rules out a vacuous statement. `none` if there are no binders,
or if the conclusion is `False`: a refutation such as `¬ P` claims exactly
that its hypotheses can't hold. -/
def nonvacuityProp (stmtValue : Expr) : MetaM (Option Expr) :=
  forallTelescopeReducing stmtValue fun xs conclusion => do
    if xs.isEmpty || conclusion.isConstOf ``False then return none
    let mut body := mkConst ``True
    for x in xs.reverse do
      body ← mkAppM ``Exists #[← mkLambdaFVars #[x] body]
    return some body

def witnessName (proof : Name) : Name := proof.appendAfter "_witness"

/-- Checks every theorem we rely on: it lives under Proofs, is a theorem,
uses only allowed axioms, and reaches no unsafe, implemented_by or extern
declaration of ours. -/
def checkTheorem (env : Environment) (thm : Name) (ci : ConstantInfo) :
    IO (Array Violation × Array Name) := do
  let mut vs : Array Violation := #[]
  let v (code detail : String) : Violation := { code, detail }
  if rootOf env thm != `Proofs then
    vs := vs.push (v "proof_not_in_proofs"
      s!"{thm} is defined in module {moduleOf? env thm}, not under Proofs")
  match ci with
  | .thmInfo _ => pure ()
  | _ => vs := vs.push (v "proof_not_theorem" s!"{thm} is not a theorem")

  let axs ← axiomsOf env thm
  let bad := axs.filter fun a => !allowedAxioms.contains a
  unless bad.isEmpty do
    vs := vs.push (v "disallowed_axiom" s!"{thm} depends on {sortedStrings bad}")

  -- Escape hatches in our own declarations that the theorem reaches.
  let ours := closure env (fun n => ourRoots.contains (rootOf env n)) [thm] {}
  for n in sortedStrings ours.toArray |>.map String.toName do
    unless ourRoots.contains (rootOf env n) do continue
    if let some ci := env.find? n then
      if ci.isUnsafe then
        vs := vs.push (v "unsafe" s!"{n} is unsafe")
    if let some impl := Compiler.getImplementedBy? env n then
      vs := vs.push (v "implemented_by" s!"{n} is implemented_by {impl}")
    if isExtern env n then
      vs := vs.push (v "extern" s!"{n} is extern")
  return (vs, axs)

def check (env : Environment) (stmt proof : Name) :
    IO (Array Violation × Array Name × Option Name) := do
  let mut vs : Array Violation := #[]
  let v (code detail : String) : Violation := { code, detail }
  let mut expectedWitness : Option Expr := none

  -- The statement: a Prop-valued definition in the spec, built only from
  -- core and spec definitions.
  match env.find? stmt with
  | none => vs := vs.push (v "statement_missing" s!"{stmt} is not defined")
  | some sci =>
    if rootOf env stmt != `Spec then
      vs := vs.push (v "statement_not_in_spec"
        s!"{stmt} is defined in module {moduleOf? env stmt}, not in the spec")
    if !sci.isDefinition || !sci.levelParams.isEmpty || sci.type != .sort .zero then
      vs := vs.push (v "statement_not_prop"
        s!"{stmt} must be a definition of type Prop with no universe parameters")
    let deps := closure env (fun n => rootOf env n == `Spec) [stmt] {}
    let outside := deps.toList.filter fun n => !specDepRoots.contains (rootOf env n)
    unless outside.isEmpty do
      vs := vs.push (v "statement_uses_outside_spec"
        s!"{stmt} depends on {sortedStrings outside.toArray}")
    if let some value := sci.value? then
      expectedWitness ← runMeta env (nonvacuityProp value)

  -- The proof: a theorem in Proofs whose type is exactly the statement.
  let mut axs : Array Name := #[]
  match env.find? proof with
  | none => vs := vs.push (v "proof_missing" s!"{proof} is not defined")
  | some pci =>
    if pci.type != mkConst stmt then
      vs := vs.push (v "proof_statement_mismatch"
        s!"{proof} proves {pci.type}, not exactly {stmt}")
    let (tvs, taxs) ← checkTheorem env proof pci
    vs := vs ++ tvs
    axs := taxs

  -- The vacuity guard: a statement with binders needs a witness that they
  -- can all be satisfied.
  let mut witness : Option Name := none
  if let some expected := expectedWitness then
    let w := witnessName proof
    witness := some w
    match env.find? w with
    | none => vs := vs.push (v "vacuity_witness_missing"
        s!"{stmt} has binders, so {w} must prove {expected}")
    | some wci =>
      unless ← runMeta env (isDefEq wci.type expected) do
        vs := vs.push (v "vacuity_witness_mismatch"
          s!"{w} proves {wci.type}, not {expected}")
      let (wvs, waxs) ← checkTheorem env w wci
      vs := vs ++ wvs
      axs := (axs ++ waxs).toList.eraseDups.toArray
  return (vs, axs, witness)

end LeanCheck

open LeanCheck in
def main (args : List String) : IO UInt32 := do
  match args with
  | [modStr, stmtStr, proofStr] =>
    try
      initSearchPath (← findSysroot)
      let mod := modStr.toName
      let env ← importModules #[{ module := mod }] {}
      let (vs, axs, witness) ← check env stmtStr.toName proofStr.toName
      let ourModules := env.header.moduleNames.filter (ourRoots.contains ·.getRoot)
      let out := Json.mkObj [
        ("ok", Json.bool vs.isEmpty),
        ("module", Json.str modStr),
        ("statement", Json.str stmtStr),
        ("proof", Json.str proofStr),
        ("witness", match witness with | some w => Json.str (toString w) | none => Json.null),
        ("violations", Json.arr (vs.map Violation.toJson)),
        ("axioms", Json.arr ((sortedStrings axs).toArray.map Json.str)),
        ("our_modules", Json.arr (sortedStrings ourModules |>.toArray.map Json.str))]
      IO.println out.compress
      return if vs.isEmpty then 0 else 1
    catch e =>
      IO.println (Json.mkObj [("ok", Json.bool false), ("error", Json.str (toString e))]).compress
      return 2
  | _ =>
    IO.eprintln "usage: leancheck <proof-module> <statement> <proof>"
    return 2
