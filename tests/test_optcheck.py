"""Each optimisation claim gets the verdict the tooling should reach, for the
right reasons (ADR-0020). Uses the real spec, proofs and store."""

from pathlib import Path

import pytest

from burden_of_proof import optcheck
from reference.ledger.store import Config

ROOT = Path(__file__).resolve().parent.parent
CLAIMS = ROOT / "claims" / "optimisations"
SEQ = 40

# Lean evidence against the ledger spec needs the owner's lock (ADR-0004).
needs_locked_spec = pytest.mark.skipif(
    not (ROOT / "spec.lock.json").is_file(),
    reason="Spec/Ledger.lean is not locked yet: the owner reviews it and runs "
           "`python -m burden_of_proof.speclock update --project .`")


def verdict(name: str, **kw) -> dict:
    return optcheck.check(CLAIMS / f"{name}.toml", sequences=SEQ, **kw)


def codes(v: dict) -> set[str]:
    return {r["code"] for r in v["reasons"]}


@pytest.mark.parametrize("name", ["OPT-REUSE-CONNECTION", "OPT-INDEX-PARTY", "OPT-WAL"])
def test_meaning_preserving_optimisation_is_accepted(name: str) -> None:
    v = verdict(name)
    assert v["verdict"] == "accept", v["reasons"]
    assert v["evidence"]["conformance"]["mismatches"] == 0


def test_wal_normal_is_rejected_for_an_undeclared_durability_drop() -> None:
    v = verdict("OPT-WAL-NORMAL")
    assert v["verdict"] == "reject"
    drop = next(r for r in v["reasons"] if r["code"] == "undeclared_drop")
    assert drop["detail"] == {"guarantees": ["sqlite.durable_commit"], "breaks_rules": ["LEDGER-DURABLE-MONEY"]}
    assert "differs_from_model" not in codes(v)  # results are the same; durability is not


@needs_locked_spec
def test_cached_balance_is_accepted_because_lean_proves_it() -> None:
    v = verdict("OPT-CACHED-BALANCE")
    assert v["verdict"] == "accept", v["reasons"]
    [comp] = v["evidence"]["compensations"]
    assert comp["statement"] == "Spec.cachedBalanceAgrees" and comp["accepted"]


@needs_locked_spec
def test_capped_scan_is_rejected_three_ways() -> None:
    v = verdict("OPT-CAP-SETTLE-SCAN")
    assert v["verdict"] == "reject"
    assert {"compensation_unproved", "refuted_in_lean", "differs_from_model"} <= codes(v)
    shrunk = v["evidence"]["conformance"]["shrunk_counterexample"]
    assert shrunk["model"] != shrunk["store"]


def test_capped_scan_is_rejected_by_conformance_alone() -> None:
    """Needs no Lean evidence: the store disagrees with the compiled spec."""
    v = verdict("OPT-CAP-SETTLE-SCAN")
    assert v["verdict"] == "reject" and "differs_from_model" in codes(v)
    shrunk = v["evidence"]["conformance"]["shrunk_counterexample"]
    bills = [op for op in shrunk["ops"] if op["op"] == "bill"]
    assert len(bills) == 21 and shrunk["ops"][-1]["op"] == "pay"  # one more bill than the cap


def test_without_a_locked_spec_lean_compensation_does_not_count() -> None:
    """Until the owner locks the spec, a drop that needs Lean evidence is rejected."""
    if (ROOT / "spec.lock.json").is_file():
        pytest.skip("spec is locked; covered by the accepted case")
    v = verdict("OPT-CACHED-BALANCE")
    assert v["verdict"] == "reject"
    [comp] = v["evidence"]["compensations"]
    assert comp["violations"] == ["spec_lock_mismatch"]


def test_rollback_journal_with_full_is_not_a_durable_baseline() -> None:
    v = verdict("OPT-INDEX-PARTY", baseline=Config(synchronous="FULL"))
    assert "baseline_lacks_guarantee" in codes(v)
