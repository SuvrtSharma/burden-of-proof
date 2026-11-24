"""Readable terminal reports for people (and screenshots). Machine-readable
JSON stays in burden_of_proof.leancheck / burden_of_proof.optcheck; this only presents it.

    python -m burden_of_proof spec             the locked statements and the lock itself
    python -m burden_of_proof prove            every Lean claim in claims/lean, step by step
    python -m burden_of_proof cheats           each way to fake a proof, and what rejects it
    python -m burden_of_proof counterexample   Lean evaluating the refuted optimisation
"""

from __future__ import annotations

import argparse
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import time
import tomllib
from pathlib import Path

from burden_of_proof import leancheck, speclock

ROOT = Path(__file__).resolve().parent.parent
FIXTURE = ROOT / "tests" / "fixtures" / "lean_project"

# ---------------------------------------------------------------- formatting

COLOR = sys.stdout.isatty() or bool(os.environ.get("FORCE_COLOR"))


def paint(text: str, code: str) -> str:
    return f"\033[{code}m{text}\033[0m" if COLOR else text


def ok(text: str) -> str: return paint(text, "32")
def bad(text: str) -> str: return paint(text, "31")
def dim(text: str) -> str: return paint(text, "2")
def bold(text: str) -> str: return paint(text, "1")


def rule(title: str) -> None:
    width = min(shutil.get_terminal_size((100, 20)).columns, 100)
    print("\n" + bold(f"━━ {title} " + "━" * max(3, width - len(title) - 4)))


def row(label: str, value: str = "") -> None:
    print(f"  {dim(label.ljust(11))}{value}")


# ---------------------------------------------------------------- the spec

def spec_text(name: str) -> tuple[str, int]:
    """The doc comment and definition of `Spec.<name>` as written in the locked spec."""
    short = name.removeprefix("Spec.")
    lines = (ROOT / "Spec" / "Ledger.lean").read_text(encoding="utf-8").splitlines()
    for i, line in enumerate(lines):
        if re.match(rf"^def {re.escape(short)}\b", line):
            start = i
            while start > 0 and lines[start - 1].strip() and not lines[start - 1].startswith("def "):
                start -= 1
            end = i + 1
            while end < len(lines) and lines[end].startswith("  "):
                end += 1
            return "\n".join(lines[start:end]), i + 1
    return f"(definition of {name} not found)", 0


def lean_claims() -> list[dict]:
    return [tomllib.loads(p.read_text(encoding="utf-8")) for p in sorted((ROOT / "claims" / "lean").glob("*.toml"))]


def cmd_spec(_args) -> int:
    rule("The locked spec")
    report = speclock.verify(ROOT)
    if report.ok:
        row("Lock", ok("✓ every locked file matches spec.lock.json"))
        row("Lock hash", speclock.lock_digest(ROOT))
    else:
        row("Lock", bad("✕ " + report.describe()))
        row("", dim("The owner reviews Spec/ and runs: python -m burden_of_proof.speclock update --project ."))
    for rel, digest in speclock.current_hashes(ROOT).items():
        row("", f"{digest[:16]}…  {rel}")
    for c in lean_claims():
        text, line = spec_text(c["statement"])
        rule(f"{c['statement']}   (Spec/Ledger.lean:{line})")
        print("\n".join("  " + l for l in text.splitlines()))
    return 0 if report.ok else 1


# ---------------------------------------------------------------- proofs

STEPS = [
    ("lock", "spec lock matches", {"spec_lock_mismatch"}),
    ("build", "lake build", {"build_failed", "proof_module_missing"}),
    ("statement", "statement is a Prop in the spec, built only from Init and Spec",
     {"statement_missing", "statement_not_in_spec", "statement_not_prop", "statement_uses_outside_spec"}),
    ("proof", "proof is a theorem under Proofs whose type is exactly the statement",
     {"proof_missing", "proof_not_in_proofs", "proof_not_theorem", "proof_statement_mismatch"}),
    ("axioms", "axioms within the allowlist (propext, Classical.choice, Quot.sound)", {"disallowed_axiom"}),
    ("hatches", "no unsafe, implemented_by or extern in our declarations", {"unsafe", "implemented_by", "extern"}),
    ("witness", "vacuity guard: hypotheses can be satisfied", {"vacuity_witness_missing", "vacuity_witness_mismatch"}),
    ("replay", "kernel replay (leanchecker)", {"kernel_replay_failed"}),
    ("second", "second, independent kernel (con-leche)", {"second_kernel_failed"}),
]


def show_steps(result: leancheck.Result) -> None:
    stopped = False
    for key, label, mine in STEPS:
        hit = [v for v in result.violations if v.code in mine]
        if stopped:
            print(f"  {dim('–')} {dim(label + '  (not run)')}")
            continue
        if hit:
            print(f"  {bad('✕')} {label}")
            for v in hit:
                print(f"      {bad(v.code)}: {v.detail.strip().splitlines()[0][:160] if v.detail.strip() else ''}")
            if key in ("lock", "build"):
                stopped = True
            continue
        extra = ""
        if key == "axioms":
            extra = dim("  uses: " + (", ".join(result.axioms) or "no axioms at all"))
        elif key == "witness":
            extra = dim(f"  {result.witness}" if result.witness else "  not needed (no binders, or a refutation)")
        elif key == "replay":
            reused = f", {len(result.replay_reused)} reused this run" if result.replay_reused else ""
            extra = dim(f"  {', '.join(result.replayed_modules)}{reused}")
        elif key == "lock":
            extra = dim(f"  {result.lock_sha256[:16]}…")
        print(f"  {ok('✓')} {label}{extra}")


def cmd_prove(args) -> int:
    results = []
    for c in lean_claims():
        rule(c["id"])
        row("Claim", c["says"])
        text, line = spec_text(c["statement"])
        row("Statement", f"{c['statement']}  {dim(f'(Spec/Ledger.lean:{line})')}")
        for l in text.splitlines():
            if l.startswith("def ") or l.startswith("  "):
                row("", dim(l.rstrip()))
        row("Proof", c["proof"])
        t = time.perf_counter()
        r = leancheck.check(ROOT, statement=c["statement"], proof=c["proof"], module=c["module"])
        secs = time.perf_counter() - t
        show_steps(r)
        verdict = ok(bold("VERIFIED")) if r.accepted else bad(bold("NOT VERIFIED"))
        kind = " (refutation: the optimisation it names is false)" if c["kind"] == "refutation" and r.accepted else ""
        print(f"  {verdict}{kind}   {dim(f'{secs:.1f} s')}")
        results.append({"id": c["id"], "accepted": r.accepted, "seconds": round(secs, 1), **json.loads(r.to_json())})
    rule("Summary")
    for r in results:
        print(f"  {ok('✓') if r['accepted'] else bad('✕')} {r['id']}")
    if args.out:
        Path(args.out).write_text(json.dumps(results, indent=2), encoding="utf-8")
        print(dim(f"\n  JSON written to {args.out}"))
    return 0 if all(r["accepted"] for r in results) else 1


# ---------------------------------------------------------------- cheats

CHEATS = [
    ("Honest proof (control)", "Proofs.Honest", "Spec.conserve", "Proofs.Honest.conserve", None),
    ("`sorry` instead of a proof", "Proofs.Sorry", "Spec.falseClaim", "Proofs.Sorry.t", "disallowed_axiom"),
    ("Declare the false claim as an axiom", "Proofs.Axiom", "Spec.falseClaim", "Proofs.Axiom.t", "disallowed_axiom"),
    ("`native_decide` (trusts the compiler)", "Proofs.NativeDecide", "Spec.small", "Proofs.NativeDecide.t", "disallowed_axiom"),
    ("Forge the theorem with the kernel switched off", "Proofs.Forged", "Spec.falseClaim", "Proofs.Forged.t", "kernel_replay_failed"),
    ("`implemented_by`: compiled code differs from the definition", "Proofs.ImplementedBy", "Spec.conserve", "Proofs.ImplementedBy.t", "implemented_by"),
    ("`extern`: compiled code calls C instead", "Proofs.Extern", "Spec.conserve", "Proofs.Extern.t", "extern"),
    ("Prove something weaker, claim the real thing", "Proofs.OutsideSpec", "Spec.falseClaim", "Proofs.OutsideSpec.t", "proof_statement_mismatch"),
    ("Point the claim at a statement outside the spec", "Proofs.OutsideSpec", "Proofs.OutsideSpec.weak", "Proofs.OutsideSpec.t", "statement_not_in_spec"),
    ("Spec statement that leaks a non-spec definition", "Proofs.OutsideSpec", "Spec.leaky", "Proofs.OutsideSpec.leaky", "statement_uses_outside_spec"),
    ("Vacuous statement (its hypothesis never holds)", "Proofs.Vacuous", "Spec.vacuous", "Proofs.Vacuous.t", "vacuity_witness_missing"),
    ("Witness for an easier proposition", "Proofs.Vacuous", "Spec.vacuous", "Proofs.Vacuous.u", "vacuity_witness_mismatch"),
    ("Witness 'proved' with sorry", "Proofs.Vacuous", "Spec.vacuous", "Proofs.Vacuous.v", "disallowed_axiom"),
    ("A definition dressed up as a theorem", "Proofs.NotTheorem", "Spec.small", "Proofs.NotTheorem.t", "proof_not_theorem"),
]


def cmd_cheats(_args) -> int:
    rule("Trying to fake a proof (fixture project; the spec there is test-only)")
    with tempfile.TemporaryDirectory(prefix="burden-of-proof-cheats-") as tmp:
        proj = Path(tmp) / "proj"
        shutil.copytree(FIXTURE, proj, ignore=shutil.ignore_patterns(".lake"))
        speclock.write_lock(proj)
        all_good = True
        for title, module, stmt, proof, expect in CHEATS:
            r = leancheck.check(proj, statement=stmt, proof=proof, module=module)
            if expect is None:
                good = r.accepted
                verdict = ok("✓ accepted") if good else bad("✕ rejected (should be accepted)")
            else:
                good = (not r.accepted) and expect in r.codes()
                verdict = ok("✓ rejected") if good else bad("✕ NOT rejected as expected")
            all_good &= good
            print(f"\n  {bold(title)}")
            print(f"    {verdict}   {dim('caught by: ' + (', '.join(r.codes()) or 'nothing (honest)'))}")
            first = next((v for v in r.violations if v.code == expect), None)
            if first and first.detail.strip():
                print(f"    {dim(first.detail.strip().splitlines()[0][:150])}")
        print()
        print(ok(bold("  Every cheat was rejected and the honest proof accepted.")) if all_good
              else bad(bold("  Some cheat was NOT handled as expected.")))
        return 0 if all_good else 1


# ---------------------------------------------------------------- counterexample

COUNTEREXAMPLE = """import Spec
open Spec.Ledger
-- Two bills that each owe 5 (as (bill id, owed)), one advance of 8 (as (payment id, advance)).
#eval matchUp [(1, 5), (2, 5)] [(9, 8)]            -- the spec: look at every open bill
#eval matchUpCapped 1 [(1, 5), (2, 5)] [(9, 8)]    -- the optimisation: look at only the first one
#print axioms Proofs.Ledger.cappedMatchDisagrees
"""


def cmd_counterexample(_args) -> int:
    rule("The capped-scan optimisation, evaluated by Lean on its counterexample")
    print(dim("  Each line: the allocations made, as (payment, bill, amount)"))
    print()
    with tempfile.TemporaryDirectory(prefix="burden-of-proof-ce-") as tmp:
        f = Path(tmp) / "Counterexample.lean"
        f.write_text(COUNTEREXAMPLE.replace("import Spec", "import Spec\nimport Proofs.Ledger"), encoding="utf-8")
        print("\n".join("  " + l for l in COUNTEREXAMPLE.splitlines()[1:]))
        print(bold("\n  Lean's output:"))
        p = subprocess.run([leancheck.lake_exe(), "env", "lean", str(f)], cwd=ROOT, capture_output=True, text=True)
        for line in (p.stdout + p.stderr).splitlines():
            print("  " + re.sub(r"^.*?Counterexample\.lean:\d+:\d+: ", "", line))
        return p.returncode


def main(argv: list[str] | None = None) -> int:
    sys.stdout.reconfigure(encoding="utf-8")  # Windows consoles default to cp1252
    ap = argparse.ArgumentParser(prog="python -m burden_of_proof")
    sub = ap.add_subparsers(dest="cmd", required=True)
    sub.add_parser("spec")
    p = sub.add_parser("prove")
    p.add_argument("--out")
    sub.add_parser("cheats")
    sub.add_parser("counterexample")
    args = ap.parse_args(argv)
    return {"spec": cmd_spec, "prove": cmd_prove, "cheats": cmd_cheats, "counterexample": cmd_counterexample}[args.cmd](args)


if __name__ == "__main__":
    sys.exit(main())
