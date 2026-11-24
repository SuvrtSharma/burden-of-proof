"""The reference ledger conforms to the compiled spec, and conformance
testing catches a planted bug (ADR-0007, ADR-0019)."""

import http.client
import json
import socket
import subprocess
import sys
import time
from pathlib import Path

import pytest

from burden_of_proof import differential
from reference.ledger import store
from reference.ledger.store import Config, Ledger, LedgerError

ROOT = Path(__file__).resolve().parent.parent


def test_baseline_conforms_to_the_spec() -> None:
    outcome = differential.run(Config(), sequences=30)
    assert outcome.mismatches == 0, outcome.counterexample
    assert outcome.operations > 0


def test_planted_settlement_bug_is_caught(monkeypatch: pytest.MonkeyPatch) -> None:
    """Apply one unit less than the matching step says: plausible, and wrong."""
    real = store.match_up
    monkeypatch.setattr(store, "match_up", lambda owed, adv: [(p, b, x - 1) if x > 1 else (p, b, x)
                                                            for p, b, x in real(owed, adv)])
    outcome = differential.run(Config(), sequences=30)
    assert outcome.mismatches > 0
    small = differential.shrink(Config(), outcome.counterexample["ops"])
    assert differential.first_mismatch(Config(), small) is not None
    assert len(small) <= len(outcome.counterexample["ops"])


@pytest.mark.parametrize("amount", [2.5, True, 0, -5, "10", None])
def test_money_must_be_a_positive_integer(tmp_path: Path, amount) -> None:
    ledger = Ledger(tmp_path / "l.db")
    party = ledger.create_party("p")["party"]
    with pytest.raises(LedgerError) as e:
        ledger.record_bill(party, amount, 1)
    assert e.value.status == 400


@pytest.mark.parametrize("date", [-1, 1.5, "3", None])
def test_bill_date_must_be_a_non_negative_integer(tmp_path: Path, date) -> None:
    ledger = Ledger(tmp_path / "l.db")
    party = ledger.create_party("p")["party"]
    with pytest.raises(LedgerError) as e:
        ledger.record_bill(party, 100, date)
    assert e.value.status == 400


def test_advance_settles_a_later_bill(tmp_path: Path) -> None:
    """The owner's review case: pay 100, then bill 80. The advance pays the bill."""
    ledger = Ledger(tmp_path / "l.db")
    party = ledger.create_party("p")["party"]
    assert ledger.record_payment(party, 100) == {"payment": 1, "allocations": [], "advance": 100}
    assert ledger.record_bill(party, 80, 10) == {"bill": 1, "allocations": [{"payment": 1, "bill": 1, "amount": 80}]}
    assert ledger.open_bills(party) == {"open": []}
    assert ledger.balance(party) == {"balance": -20}


def test_unknown_party_is_404(tmp_path: Path) -> None:
    with pytest.raises(LedgerError) as e:
        Ledger(tmp_path / "l.db").balance(99)
    assert e.value.status == 404


def test_http_api_matches_the_spec_end_to_end(tmp_path: Path) -> None:
    with socket.socket() as s:
        s.bind(("127.0.0.1", 0))
        port = s.getsockname()[1]
    proc = subprocess.Popen([sys.executable, "-m", "reference.ledger.server", "--db", str(tmp_path / "e2e.db"),
                             "--port", str(port)], cwd=ROOT, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    model = differential.Model()
    try:
        conn = None
        for _ in range(100):
            try:
                conn = http.client.HTTPConnection("127.0.0.1", port, timeout=10)
                conn.request("GET", "/health")
                conn.getresponse().read()
                break
            except OSError:
                time.sleep(0.1)

        def call(method, path, body=None):
            conn.request(method, path, body=json.dumps(body) if body else None,
                         headers={"Content-Type": "application/json"})
            r = conn.getresponse()
            return r.status, json.loads(r.read())

        assert call("POST", "/parties", {"name": "acme"}) == (201, {"party": 1})
        ops = [{"op": "pay", "party": 1, "amount": 100}, {"op": "bill", "party": 1, "date": 10, "amount": 80},
               {"op": "bill", "party": 1, "date": 5, "amount": 50}, {"op": "open", "party": 1},
               {"op": "reverse", "payment": 1}, {"op": "open", "party": 1}, {"op": "balance", "party": 1}]
        for op in ops:
            if op["op"] == "bill":
                method, path, body = "POST", "/parties/1/bills", {"amount": op["amount"], "date": op["date"]}
            elif op["op"] == "pay":
                method, path, body = "POST", "/parties/1/payments", {"amount": op["amount"]}
            elif op["op"] == "reverse":
                method, path, body = "POST", f"/payments/{op['payment']}/reverse", None
            elif op["op"] == "open":
                method, path, body = "GET", "/parties/1/open-bills", None
            else:
                method, path, body = "GET", "/parties/1/balance", None
            status, got = call(method, path, body)
            assert status in (200, 201)
            assert got == model.send(op), op
        assert call("POST", "/payments/1/reverse")[0] == 409   # already reversed
        assert call("POST", "/parties/1/bills", {"amount": 1.5, "date": 1})[0] == 400
    finally:
        model.close()
        proc.terminate()
        proc.wait(timeout=30)


def test_server_disables_nagle_by_default() -> None:
    """Without TCP_NODELAY every small response waits ~40 ms for a delayed ACK,
    and benchmarks measure TCP instead of the database (findings F-016)."""
    from reference.ledger.server import make_handler
    assert make_handler(Ledger.__new__(Ledger)).disable_nagle_algorithm is True
