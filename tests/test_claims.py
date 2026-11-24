"""Every claim record parses and names things that exist (ADR-0005, ADR-0020).

Added after a broken record (an apostrophe turned into a quote) shipped
unnoticed, because nothing read claims/lean except the CLI.
"""

import re
import tomllib
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parent.parent
SPEC = (ROOT / "Spec" / "Ledger.lean").read_text(encoding="utf-8")
PROOFS = (ROOT / "Proofs" / "Ledger.lean").read_text(encoding="utf-8")
LEAN = sorted((ROOT / "claims" / "lean").glob("*.toml"))
OPT = sorted((ROOT / "claims" / "optimisations").glob("*.toml"))


def defined_in(source: str, kind: str, name: str) -> bool:
    return re.search(rf"^{kind} {re.escape(name)}\b", source, re.MULTILINE) is not None


@pytest.mark.parametrize("path", LEAN + OPT + [ROOT / "claims" / "guarantees.toml"], ids=lambda p: p.name)
def test_record_parses(path: Path) -> None:
    tomllib.loads(path.read_text(encoding="utf-8"))


@pytest.mark.parametrize("path", LEAN, ids=lambda p: p.name)
def test_lean_claim_points_at_real_definitions(path: Path) -> None:
    c = tomllib.loads(path.read_text(encoding="utf-8"))
    assert c["id"] == path.stem
    assert c["statement"].startswith("Spec.") and defined_in(SPEC, "def", c["statement"].removeprefix("Spec."))
    assert c["proof"].startswith("Proofs.Ledger.")
    assert defined_in(PROOFS, "theorem", c["proof"].removeprefix("Proofs.Ledger."))


def test_every_spec_statement_has_a_claim() -> None:
    """No proved statement is left out of the claim records, and vice versa."""
    stated = set(re.findall(r"^def (\w+) : Prop", SPEC.split("namespace Spec\n", 1)[1], re.MULTILINE))
    stated -= {"wellFormed", "cappedMatchAgrees"}   # a helper predicate, and the statement that is refuted
    claimed = {tomllib.loads(p.read_text(encoding="utf-8"))["statement"].removeprefix("Spec.") for p in LEAN}
    assert claimed == stated
