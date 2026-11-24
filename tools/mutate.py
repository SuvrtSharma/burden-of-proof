"""Show that every check bites (ADR-0010): remove one check at a time, run the
tests that guard it, expect them to fail, then restore the file byte-for-byte.

Run it on a copy of the code, such as inside the checker container:

    docker run --rm -t burden-of-proof/checker:dev python tools/mutate.py

It edits files in the tree it runs in, so never point it at your working
copy while you are editing. Prints one line per mutation and exits non-zero
if any mutation fails to bite or a file isn't restored.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import subprocess
import sys
from pathlib import Path

MAIN, LC, SL = "tools/leancheck/Main.lean", "burden_of_proof/leancheck.py", "burden_of_proof/speclock.py"
DF, OC, SV, ST = "burden_of_proof/differential.py", "burden_of_proof/optcheck.py", "reference/ledger/server.py", "reference/ledger/store.py"
LG = "bench/loadgen.py"

# (name, file, text to find (exactly once), replacement, pytest -k selector)
MUTATIONS = [
    ("M1 no kernel replay", LC, "    for failure in failures:\n", "    for failure in []:\n", "forged"),
    ("M2 axiom allowlist ignored", MAIN, "let bad := axs.filter fun a => !allowedAxioms.contains a",
     "let bad := axs.filter fun _ => false", "Sorry or Axiom or NativeDecide or v_witness"),
    ("M3 allowlist emptied", MAIN, "def allowedAxioms : List Name := [``propext, ``Classical.choice, ``Quot.sound]",
     "def allowedAxioms : List Name := []", "honest"),
    ("M4 implemented_by not checked", MAIN, "if let some impl := Compiler.getImplementedBy? env n then",
     "if let some impl := (none : Option Name) then", "ImplementedBy"),
    ("M5 extern not checked", MAIN, "if isExtern env n then", "if false then", "Extern"),
    ("M6 proof type not compared", MAIN, "if pci.type != mkConst stmt then", "if false then", "proof_statement_mismatch"),
    ("M7 statement module not checked", MAIN, "if rootOf env stmt != `Spec then", "if false then", "statement_not_in_spec"),
    ("M8 statement deps not checked", MAIN, "unless outside.isEmpty do", "unless true do", "statement_uses_outside_spec"),
    ("M9 lock not verified by pipeline", LC, "    if not lock.ok:\n", "    if False:\n", "edited_spec_is_rejected"),
    ("M10 hashing broken", SL, "return hashlib.sha256(path.read_bytes()).hexdigest()", 'return "0" * 64', "test_speclock"),
    ("M11 lakefile not locked", SL, 'for name in ("Spec.lean", "lakefile.toml", "lean-toolchain"):',
     'for name in ("Spec.lean", "lean-toolchain"):', "lakefile"),
    ("N1 vacuity guard off", MAIN, "if let some expected := expectedWitness then",
     "if let some expected := (none : Option Expr) then", "Vacuous or witness_is_required"),
    ("N2 witness type not compared", MAIN, "unless ← runMeta env (isDefEq wci.type expected) do", "unless true do",
     "vacuity_witness_mismatch"),
    ("N3 witness hygiene ignored", MAIN, "      vs := vs ++ wvs\n", "      vs := vs\n", "v_witness"),
    ("N4 no second kernel", LC, "failure = second_kernel(lake, project, module, decls)", "failure = None", "forged"),
    ("N5 statement type not checked", MAIN,
     "if !sci.isDefinition || !sci.levelParams.isEmpty || sci.type != .sort .zero then", "if false then",
     "statement_not_prop"),
    ("N6 proof module root not checked", MAIN, "if rootOf env thm != `Proofs then", "if false then", "proof_not_in_proofs"),
    ("N7 theorem kind not checked", MAIN, '| _ => vs := vs.push (v "proof_not_theorem" s!"{thm} is not a theorem")',
     "| _ => pure ()", "proof_not_theorem"),
    ("N8 build failure ignored", LC, '    if proc.returncode != 0:\n        return reject("build_failed"',
     '    if False:\n        return reject("build_failed"', "does_not_build"),
    ("R1 refutation exemption removed", MAIN, "if xs.isEmpty || conclusion.isConstOf ``False then",
     "if xs.isEmpty then", "refute or witness_is_required"),
    ("D1 differential never compares", DF, "                    if want != got:\n", "                    if False:\n",
     "planted or capped"),
    ("D2 durability rule always true", OC,
     'durable = (mode == "wal" and sync >= 2) or (mode in ROLLBACK_MODES and sync >= 3)', "durable = True",
     "wal_normal or durable_baseline"),
    ("D3 undeclared drop ignored", OC, "    if undeclared:\n", "    if False:\n", "wal_normal"),
    ("D4 unproved compensation ignored", OC, '                if not v["accepted"]:\n', "                if False:\n",
     "without_a_locked_spec or three_ways"),  # one guard runs before the owner locks the spec, one after
    ("D5 server answers balance wrongly", SV, "return self._send(200, ledger.balance(party))",
     "return self._send(200, ledger.open_bills(party))", "http_api"),
    ("D6 money validation off", ST, "if type(value) is not int or value <= 0:", "if value is None:", "money"),
    ("D8 percentile rank rounded down", LG, "rank = max(1, -(-len(sorted_ns) * q // 100))",
     "rank = max(1, len(sorted_ns) * q // 100)", "percentile"),
    ("D9 errors counted as successes", LG, "ok = sorted(s.ns for s in group if 200 <= s.status < 300)",
     "ok = sorted(s.ns for s in group)", "only_2xx"),
    ("D7 Nagle left on", SV, "        disable_nagle_algorithm = nodelay\n", "        disable_nagle_algorithm = False\n", "nagle"),
]


def sha(p: Path) -> str:
    return hashlib.sha256(p.read_bytes()).hexdigest()


def tail(p: subprocess.CompletedProcess) -> str:
    return p.stdout.strip().splitlines()[-1] if p.stdout.strip() else p.stderr.strip()[-300:]


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--root", type=Path, default=Path(__file__).resolve().parent.parent)
    ap.add_argument("--out", type=Path)
    ap.add_argument("-k", help="only mutations whose name contains this")
    args = ap.parse_args(argv)
    sys.stdout.reconfigure(encoding="utf-8")  # Windows consoles default to cp1252
    root = args.root
    files = sorted({m[1] for m in MUTATIONS})
    before = {f: sha(root / f) for f in files}
    rows = []
    for name, rel, old, new, sel in MUTATIONS:
        if args.k and args.k not in name:
            continue
        path = root / rel
        original = path.read_bytes()
        text = original.decode("utf-8")
        n = text.count(old)
        if n != 1:
            rows.append({"mutation": name, "result": f"TARGET FOUND {n} TIMES", "summary": ""})
            print(f"\033[31m✕ {name:38}\033[0m target text found {n} times", flush=True)
            continue
        try:
            path.write_bytes(text.replace(old, new).encode("utf-8"))
            p = subprocess.run([sys.executable, "-m", "pytest", "-q", "-p", "no:cacheprovider", "tests", "-k", sel],
                               cwd=root, capture_output=True, text=True, encoding="utf-8", errors="replace")
            bit = p.returncode == 1 and "failed" in tail(p)
            rows.append({"mutation": name, "result": "BITES" if bit else "DOES NOT BITE", "summary": tail(p)})
            mark = "\033[32m✓ bites\033[0m" if bit else "\033[31m✕ DOES NOT BITE\033[0m"
            print(f"{mark}  {name:38} {tail(p)}", flush=True)
        finally:
            path.write_bytes(original)
    restored = before == {f: sha(root / f) for f in files}
    print(f"\nfiles restored byte-for-byte: {'yes' if restored else 'NO'}")
    print(f"mutations that bit: {sum(r['result'] == 'BITES' for r in rows)} of {len(rows)}")
    if args.out:
        args.out.write_text(json.dumps({"rows": rows, "restored": restored}, indent=2), encoding="utf-8")
    return 0 if restored and all(r["result"] == "BITES" for r in rows) else 1


if __name__ == "__main__":
    sys.exit(main())
