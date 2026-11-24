"""Write a catalog of every claim and every mutation, read straight from the repo.

The evidence dashboard shows it next to the proof and mutation results, so a
reader sees what each claim says in English, the exact Lean statement it was
checked against, and what each mutation removed. Nothing is typed by hand:

    .venv\\Scripts\\python.exe tools/claims_catalog.py --out evidence/claims-catalog.json

Every source file is listed with its SHA-256, together with the git commit.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import subprocess
import sys
import tomllib
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SPEC = ROOT / "Spec" / "Ledger.lean"


def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def rel(path: Path) -> str:
    return path.relative_to(ROOT).as_posix()


def spec_statements(text: str) -> dict[str, dict]:
    """Each `def NAME : Prop :=` with its doc comment, its text and its lines."""
    lines = text.split("\n")
    out: dict[str, dict] = {}
    for i, line in enumerate(lines):
        m = re.match(r"def (\w+) : Prop :=", line)
        if not m:
            continue
        end = i
        while end + 1 < len(lines) and lines[end + 1].strip() and not lines[end + 1].startswith(("def ", "/-", "end ", "theorem ")):
            end += 1
        doc, j = "", i - 1
        if j >= 0 and lines[j].rstrip().endswith("-/"):
            k = j
            while k >= 0 and "/--" not in lines[k]:
                k -= 1
            doc = " ".join(" ".join(lines[k:j + 1]).replace("/--", "").replace("-/", "").split())
        out[m.group(1)] = {"lean": "\n".join(lines[i:end + 1]), "doc": doc, "lines": [i + 1, end + 1]}
    return out


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--out", type=Path, required=True)
    args = ap.parse_args()

    stmts = spec_statements(SPEC.read_text(encoding="utf-8"))
    sources = [SPEC]

    lean = []
    for f in sorted((ROOT / "claims" / "lean").glob("*.toml")):
        c = tomllib.loads(f.read_text(encoding="utf-8"))
        name = c["statement"].removeprefix("Spec.")
        s = stmts.get(name)
        if s is None:
            print(f"{rel(f)}: {c['statement']} is not a Prop definition in {rel(SPEC)}", file=sys.stderr)
            return 1
        lean.append({"id": c["id"], "kind": c["kind"], "says": c["says"], "statement": c["statement"],
                     "proof": c["proof"], "spec_version": c["spec_version"], "doc": s["doc"],
                     "lean": s["lean"], "spec_lines": s["lines"], "file": rel(f)})
        sources.append(f)

    opts = []
    for f in sorted((ROOT / "claims" / "optimisations").glob("*.toml")):
        c = tomllib.loads(f.read_text(encoding="utf-8"))
        comp = [{"rule": x.get("rule", ""), "statement": x["statement"],
                 "lean": stmts.get(x["statement"].removeprefix("Spec."), {}).get("lean", "")}
                for x in c.get("compensated_by", [])]
        opts.append({"id": c["id"], "kind": c["kind"], "title": c["title"], "agent_says": c["agent_says"],
                     "config": c.get("config", {}), "drops": c.get("drops", []), "compensated_by": comp,
                     "refuted_by": c.get("refuted_by", ""), "file": rel(f)})
        sources.append(f)

    sys.path.insert(0, str(ROOT / "tools"))
    import mutate  # the same list tools/mutate.py runs

    muts = [{"mutation": n, "file": f, "find": a, "replace": b, "tests": k} for n, f, a, b, k in mutate.MUTATIONS]
    sources.append(ROOT / "tools" / "mutate.py")

    commit = subprocess.run(["git", "rev-parse", "HEAD"], cwd=ROOT, capture_output=True, text=True).stdout.strip()
    dirty = subprocess.run(["git", "status", "--porcelain", "--"] + [rel(p) for p in sources], cwd=ROOT,
                           capture_output=True, text=True).stdout.strip()
    doc = {"generated_by": "python tools/claims_catalog.py", "git_commit": commit, "sources_dirty": bool(dirty),
           "sources": {rel(p): sha(p) for p in sources}, "lean_claims": lean, "optimisations": opts,
           "mutations": muts}
    args.out.write_text(json.dumps(doc, indent=1, ensure_ascii=False) + "\n", encoding="utf-8", newline="\n")
    print(f"{len(lean)} Lean claims, {len(opts)} optimisation claims, {len(muts)} mutations -> {args.out}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
