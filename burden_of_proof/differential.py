"""Differential conformance: the real ledger store against the compiled spec
(ADR-0007), spec v2. Random operation sequences run through both, and every
response must be identical. This samples the code. It does not prove it.

The model is `ledgermodel`, built from Spec/Ledger.lean by `lake build`.
Rejected operations must be rejected by both; the error text isn't compared.
"""

from __future__ import annotations

import json
import os
import random
import subprocess
import tempfile
from dataclasses import asdict, dataclass, field
from pathlib import Path

from reference.ledger.store import Config, Ledger, LedgerError

REPO_ROOT = Path(__file__).resolve().parent.parent
MODEL_EXE = REPO_ROOT / ".lake" / "build" / "bin" / ("ledgermodel.exe" if os.name == "nt" else "ledgermodel")
REJECTED = {"error": "rejected"}


class Model:
    """The compiled spec, one JSON operation per line."""

    def __init__(self, exe: Path = MODEL_EXE):
        if not exe.is_file():
            raise FileNotFoundError(f"{exe} missing; run `lake build` in the repo root")
        self.proc = subprocess.Popen([str(exe)], stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                     text=True, encoding="utf-8", bufsize=1)

    def send(self, op: dict) -> dict:
        self.proc.stdin.write(json.dumps(op) + "\n")
        self.proc.stdin.flush()
        out = json.loads(self.proc.stdout.readline())
        return REJECTED if "error" in out else out

    def close(self) -> None:
        self.proc.stdin.close()
        self.proc.wait(timeout=30)


def generate(rng: random.Random, parties: int = 2) -> list[dict]:
    """Half the sequences are random mixes; half pile up open bills and then
    pay a large amount, so long settlements get exercised. Dates come from a
    small range so (date, id) ties happen. Reversals pick earlier payment
    numbers (some already reversed, some that don't exist); a few amounts are
    invalid."""
    ops: list[dict] = []
    payments = 0

    def amount(lo: int, hi: int) -> int:
        return rng.choice([0, -rng.randint(1, 9)]) if rng.random() < 0.05 else rng.randint(lo, hi)

    if rng.random() < 0.5:
        for _ in range(rng.randint(10, 120)):
            p = rng.randint(1, parties)
            kind = rng.choices(["bill", "pay", "reverse", "balance", "open"], [40, 25, 10, 12, 13])[0]
            if kind == "bill":
                ops.append({"op": "bill", "party": p, "date": rng.randint(0, 6), "amount": amount(1, 20)})
            elif kind == "pay":
                ops.append({"op": "pay", "party": p, "amount": amount(1, 60)})
                payments += 1
            elif kind == "reverse":
                ops.append({"op": "reverse", "payment": rng.randint(1, payments + 1)})
            else:
                ops.append({"op": kind, "party": p})
    else:
        p = rng.randint(1, parties)
        for _ in range(rng.randint(15, 40)):
            ops.append({"op": "bill", "party": p, "date": rng.randint(0, 6), "amount": rng.randint(1, 20)})
        ops.append({"op": "pay", "party": p, "amount": rng.randint(100, 800)})
        ops += [{"op": "open", "party": p}, {"op": "reverse", "payment": 1}, {"op": "open", "party": p},
                {"op": "balance", "party": p}]
    return ops


class Ids:
    """Shifts the store's ids so each sequence numbers bills and payments from 1."""

    def __init__(self, bill_offset: int, payment_offset: int):
        self.b, self.p = bill_offset, payment_offset

    def alloc(self, a: dict) -> dict:
        return {"payment": a["payment"] - self.p, "bill": a["bill"] - self.b, "amount": a["amount"]}


def apply(ledger: Ledger, op: dict, party_ids: list[int], ids: Ids) -> dict:
    """Run one operation on the store and express the answer in the model's terms."""
    try:
        if op["op"] == "bill":
            r = ledger.record_bill(party_ids[op["party"] - 1], op["amount"], op["date"])
            return {"bill": r["bill"] - ids.b, "allocations": [ids.alloc(a) for a in r["allocations"]]}
        if op["op"] == "pay":
            r = ledger.record_payment(party_ids[op["party"] - 1], op["amount"])
            return {"payment": r["payment"] - ids.p, "allocations": [ids.alloc(a) for a in r["allocations"]],
                    "advance": r["advance"]}
        if op["op"] == "reverse":
            r = ledger.reverse_payment(op["payment"] + ids.p)
            return {"reversed": r["reversed"] - ids.p, "allocations": [ids.alloc(a) for a in r["allocations"]]}
        if op["op"] == "balance":
            return ledger.balance(party_ids[op["party"] - 1])
        r = ledger.open_bills(party_ids[op["party"] - 1])
        return {"open": [{"bill": b["bill"] - ids.b, "date": b["date"], "outstanding": b["outstanding"]}
                         for b in r["open"]]}
    except LedgerError:
        return REJECTED


@dataclass
class Outcome:
    config: dict
    sequences: int = 0
    operations: int = 0
    mismatches: int = 0
    counterexample: dict | None = None
    seed: int = 0
    notes: list[str] = field(default_factory=list)


def _max_ids(ledger: Ledger) -> Ids:
    with ledger._connection() as conn:
        b = conn.execute("SELECT COALESCE(MAX(id), 0) FROM bills").fetchone()[0]
        p = conn.execute("SELECT COALESCE(MAX(id), 0) FROM payments").fetchone()[0]
    return Ids(b, p)


def run(config: Config, sequences: int = 150, seed: int = 20261107, parties: int = 2) -> Outcome:
    """Each sequence gets fresh parties in one database, with ids shifted back
    to 1 per sequence. Reversing a payment id beyond this sequence's payments
    is rejected by both (the shifted id doesn't exist, or belongs to no
    earlier sequence because ids only grow)."""
    outcome = Outcome(config=asdict(config), seed=seed)
    rng = random.Random(seed)
    model = Model()
    with tempfile.TemporaryDirectory(prefix="burden-of-proof-diff-") as tmp:
        ledger = Ledger(Path(tmp) / "diff.db", config)
        try:
            for n in range(sequences):
                ops = generate(rng, parties)
                model.send({"op": "reset"})
                party_ids = [ledger.create_party(f"s{n}p{i}")["party"] for i in range(parties)]
                ids = _max_ids(ledger)
                for i, op in enumerate(ops):
                    want, got = model.send(op), apply(ledger, op, party_ids, ids)
                    outcome.operations += 1
                    if want != got:
                        outcome.mismatches += 1
                        if outcome.counterexample is None:
                            outcome.counterexample = {"sequence": n, "index": i, "ops": ops[: i + 1],
                                                      "model": want, "store": got}
                        break
                outcome.sequences += 1
        finally:
            ledger.close()
            model.close()
    return outcome


def first_mismatch(config: Config, ops: list[dict], parties: int = 2) -> dict | None:
    """Replay one sequence on a fresh store and model."""
    model = Model()
    with tempfile.TemporaryDirectory(prefix="burden-of-proof-shrink-") as tmp:
        ledger = Ledger(Path(tmp) / "s.db", config)
        try:
            party_ids = [ledger.create_party(f"p{i}")["party"] for i in range(parties)]
            ids = Ids(0, 0)
            for i, op in enumerate(ops):
                want, got = model.send(op), apply(ledger, op, party_ids, ids)
                if want != got:
                    return {"index": i, "model": want, "store": got}
        finally:
            ledger.close()
            model.close()
    return None


def shrink(config: Config, ops: list[dict]) -> list[dict]:
    """Greedily drop operations while the sequence still fails, and keep only
    the prefix up to the first mismatch. Returns a sequence that still fails
    and that no single removal can make shorter."""
    hit = first_mismatch(config, ops)
    assert hit is not None, "shrink needs a failing sequence"
    ops = ops[: hit["index"] + 1]
    changed = True
    while changed:
        changed = False
        for i in range(len(ops) - 1, -1, -1):
            trial = ops[:i] + ops[i + 1:]
            hit = first_mismatch(config, trial) if trial else None
            if hit is not None:
                ops, changed = trial[: hit["index"] + 1], True
    return ops
