"""The claims catalog quotes the spec exactly, for every claim record."""

import sys
import tomllib
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "tools"))

import claims_catalog  # noqa: E402


def test_every_lean_claim_is_quoted_whole_and_verbatim():
    text = (ROOT / "Spec" / "Ledger.lean").read_text(encoding="utf-8")
    stmts = claims_catalog.spec_statements(text)
    lines = text.split("\n")
    for f in sorted((ROOT / "claims" / "lean").glob("*.toml")):
        name = tomllib.loads(f.read_text(encoding="utf-8"))["statement"].removeprefix("Spec.")
        s = stmts[name]
        first, last = s["lines"]
        assert s["lean"] == "\n".join(lines[first - 1:last]), name
        assert s["lean"].startswith(f"def {name} : Prop :=")
        # whole: the next line closes the definition (blank, or the next item)
        assert last == len(lines) or not lines[last].startswith("  "), name
        assert s["doc"], f"{name} has no doc comment"
