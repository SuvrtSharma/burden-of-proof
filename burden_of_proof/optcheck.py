"""Checks the meaning of an optimisation claim (ADR-0008, ADR-0020).
Speed is measured separately (bench/run.py), and only for accepted claims
does it count.

A claim is accepted only if all of these hold:
1. Observed guarantees: every guarantee the baseline holds and the
   candidate doesn't, measured on a live database, was declared in `drops`.
2. Declared drops: every rule that needs a dropped guarantee has a
   compensating Lean claim, and `burden_of_proof.leancheck` accepts it.
3. No refutation: a `refuted_by` Lean claim, if given, is not accepted.
4. Conformance: the candidate store agrees with the compiled spec on every
   operation of the random sequences (with a shrunk counterexample if not).

    python -m burden_of_proof.optcheck claims/optimisations/OPT-WAL.toml [...]
"""

from __future__ import annotations

import argparse
import json
import sys
import tempfile
import tomllib
from dataclasses import asdict
from pathlib import Path

from burden_of_proof import differential, leancheck
from reference.ledger.store import Config, Ledger

REPO_ROOT = Path(__file__).resolve().parent.parent
REGISTER = REPO_ROOT / "claims" / "guarantees.toml"
ROLLBACK_MODES = {"delete", "truncate", "persist"}


def observe(config: Config) -> dict:
    """Guarantees that can be read off a live database with this config."""
    with tempfile.TemporaryDirectory(prefix="burden-of-proof-observe-") as tmp:
        ledger = Ledger(Path(tmp) / "o.db", config)
        try:
            pragmas = ledger.observed_pragmas()
        finally:
            ledger.close()
    mode, sync = pragmas["journal_mode"], pragmas["synchronous"]
    # sqlite.org/pragma.html: WAL is durable at FULL (2) or above; a rollback
    # journal needs EXTRA (3). See claims/guarantees.toml for the quotes.
    durable = (mode == "wal" and sync >= 2) or (mode in ROLLBACK_MODES and sync >= 3)
    return {"pragmas": pragmas, "held": {"sqlite.durable_commit": durable}}


def lean_verdict(entry: dict) -> dict:
    r = leancheck.check(REPO_ROOT, statement=entry["statement"], proof=entry["proof"], module=entry["module"])
    return {"statement": entry["statement"], "proof": entry["proof"], "accepted": r.accepted,
            "violations": r.codes(), "axioms": r.axioms}


def check(claim_path: Path, sequences: int = 100, baseline: Config = Config()) -> dict:
    claim = tomllib.loads(claim_path.read_text(encoding="utf-8"))
    register = tomllib.loads(REGISTER.read_text(encoding="utf-8"))
    candidate = baseline.with_changes(claim.get("config", {}))
    declared = set(claim.get("drops", []))
    reasons: list[dict] = []
    evidence: dict = {}

    # 1. Observed guarantees, baseline vs candidate.
    base_obs, cand_obs = observe(baseline), observe(candidate)
    evidence["observed"] = {"baseline": base_obs, "candidate": cand_obs}
    missing_in_baseline = [g for g, held in base_obs["held"].items() if not held]
    if missing_in_baseline:
        reasons.append({"code": "baseline_lacks_guarantee", "detail": missing_in_baseline})
    lost = [g for g, held in cand_obs["held"].items() if base_obs["held"][g] and not held]
    undeclared = sorted(set(lost) - declared)
    if undeclared:
        rules = sorted({r for g in undeclared for r in register["guarantees"][g]["required_by"]})
        reasons.append({"code": "undeclared_drop", "detail": {"guarantees": undeclared, "breaks_rules": rules}})

    # 2. Declared drops need compensation for every rule they touch.
    compensations = claim.get("compensated_by", [])
    evidence["compensations"] = []
    for g in sorted(declared | set(lost)):
        for rule in register["guarantees"][g]["required_by"]:
            offered = [c for c in compensations if c["rule"] == rule]
            if not offered:
                reasons.append({"code": "drop_without_compensation", "detail": {"guarantee": g, "rule": rule}})
            for c in offered:
                v = lean_verdict(c)
                evidence["compensations"].append(v)
                if not v["accepted"]:
                    reasons.append({"code": "compensation_unproved", "detail": v})

    # 3. Known refutation.
    if "refuted_by" in claim:
        v = lean_verdict(claim["refuted_by"])
        evidence["refutation"] = v
        if v["accepted"]:
            reasons.append({"code": "refuted_in_lean", "detail": v})

    # 4. Conformance against the compiled spec.
    outcome = differential.run(candidate, sequences=sequences)
    evidence["conformance"] = asdict(outcome)
    if outcome.mismatches:
        small = differential.shrink(candidate, outcome.counterexample["ops"])
        hit = differential.first_mismatch(candidate, small)
        evidence["conformance"]["shrunk_counterexample"] = {"ops": small, **hit}
        reasons.append({"code": "differs_from_model",
                        "detail": f"{outcome.mismatches} of {outcome.sequences} sequences; "
                                  f"shortest failing sequence has {len(small)} operations"})

    return {"id": claim["id"], "title": claim["title"], "kind": claim["kind"], "agent_says": claim["agent_says"],
            "config": asdict(candidate), "declared_drops": sorted(declared),
            "verdict": "accept" if not reasons else "reject", "reasons": reasons, "evidence": evidence}


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(prog="python -m burden_of_proof.optcheck")
    ap.add_argument("claims", nargs="+", type=Path)
    ap.add_argument("--sequences", type=int, default=100)
    args = ap.parse_args(argv)
    results = [check(p, args.sequences) for p in args.claims]
    print(json.dumps(results, indent=2))
    return 0 if all(r["verdict"] == "accept" for r in results) else 1


if __name__ == "__main__":
    sys.exit(main())
