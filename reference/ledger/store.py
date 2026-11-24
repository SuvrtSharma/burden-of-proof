"""Ledger storage on SQLite (spec v2), with one switch per candidate optimisation.

The meaning of every operation is `Spec.Ledger` (Spec/Ledger.lean, v2), and
responses use the same JSON shapes as the compiled model (`ledgermodel`), so
the conformance harness can compare them exactly.

A deliberately small do-it-yourself ledger (see the spec header for what's
left out). Money is an integer number of minor units; floats and bools are
refused.
"""

from __future__ import annotations

import sqlite3
import threading
from dataclasses import asdict, dataclass, replace
from pathlib import Path


@dataclass(frozen=True)
class Config:
    """Baseline values are the straightforward implementation. Each other
    value is a candidate optimisation (see claims/optimisations/).

    The baseline uses synchronous=EXTRA, not FULL: SQLite documents FULL with
    a rollback journal as "maybe not durable" (sqlite.org/pragma.html,
    fetched 2026-11-07), and the guarantee check rejected DELETE+FULL."""
    connection_per_request: bool = True
    journal_mode: str = "DELETE"
    synchronous: str = "EXTRA"
    index_party: bool = False
    cached_balance: bool = False
    settle_scan_cap: int | None = None

    def with_changes(self, changes: dict) -> Config:
        unknown = set(changes) - set(asdict(self))
        if unknown:
            raise ValueError(f"unknown config keys: {sorted(unknown)}")
        return replace(self, **changes)


class LedgerError(Exception):
    def __init__(self, status: int, message: str):
        super().__init__(message)
        self.status = status


SCHEMA = """
CREATE TABLE IF NOT EXISTS parties (
    id      INTEGER PRIMARY KEY,
    name    TEXT NOT NULL,
    balance INTEGER NOT NULL DEFAULT 0   -- maintained only with cached_balance
);
CREATE TABLE IF NOT EXISTS bills (
    id          INTEGER PRIMARY KEY,
    party_id    INTEGER NOT NULL REFERENCES parties(id),
    date        INTEGER NOT NULL CHECK (date >= 0),
    amount      INTEGER NOT NULL CHECK (amount > 0),
    outstanding INTEGER NOT NULL CHECK (outstanding >= 0 AND outstanding <= amount)
);
CREATE TABLE IF NOT EXISTS payments (
    id       INTEGER PRIMARY KEY,
    party_id INTEGER NOT NULL REFERENCES parties(id),
    amount   INTEGER NOT NULL CHECK (amount > 0),
    advance  INTEGER NOT NULL CHECK (advance >= 0 AND advance <= amount),
    reversed INTEGER NOT NULL DEFAULT 0 CHECK (reversed IN (0, 1))
);
CREATE TABLE IF NOT EXISTS allocations (
    id         INTEGER PRIMARY KEY,
    payment_id INTEGER NOT NULL REFERENCES payments(id),
    bill_id    INTEGER NOT NULL REFERENCES bills(id),
    amount     INTEGER NOT NULL CHECK (amount > 0)
);
"""

INDEXES = """
CREATE INDEX IF NOT EXISTS bills_party ON bills(party_id, date, id);
CREATE INDEX IF NOT EXISTS payments_party ON payments(party_id, id);
CREATE INDEX IF NOT EXISTS allocations_payment ON allocations(payment_id);
"""


def money(value: object) -> int:
    if type(value) is not int or value <= 0:
        raise LedgerError(400, "amount must be a positive integer number of minor units")
    return value


def day(value: object) -> int:
    if type(value) is not int or value < 0:
        raise LedgerError(400, "date must be a non-negative integer day number")
    return value


def match_up(owed: list[tuple[int, int]], adv: list[tuple[int, int]]) -> list[tuple[int, int, int]]:
    """Mirrors `Spec.Ledger.matchUp`: (bill, owed) against (payment, advance),
    both in order; returns (payment, bill, amount)."""
    out, owed, adv = [], list(owed), list(adv)
    i = j = 0
    while i < len(owed) and j < len(adv):
        (b, o), (p, a) = owed[i], adv[j]
        if o < a:
            out.append((p, b, o)); adv[j] = (p, a - o); i += 1
        elif a < o:
            out.append((p, b, a)); owed[i] = (b, o - a); j += 1
        else:
            out.append((p, b, o)); i += 1; j += 1
    return out


class Ledger:
    def __init__(self, path: Path | str, config: Config = Config()):
        self.path = str(path)
        self.config = config
        self._local = threading.local()
        with self._connection() as conn:
            conn.executescript(SCHEMA)
            if config.index_party:
                conn.executescript(INDEXES)

    # -- connections -----------------------------------------------------

    def _open(self) -> sqlite3.Connection:
        conn = sqlite3.connect(self.path, isolation_level=None, check_same_thread=False, timeout=30)
        conn.execute(f"PRAGMA journal_mode={self.config.journal_mode}")
        conn.execute(f"PRAGMA synchronous={self.config.synchronous}")
        conn.execute("PRAGMA foreign_keys=ON")
        return conn

    class _Borrow:
        def __init__(self, ledger: Ledger):
            self.ledger = ledger

        def __enter__(self) -> sqlite3.Connection:
            if self.ledger.config.connection_per_request:
                self.conn = self.ledger._open()
            else:
                conn = getattr(self.ledger._local, "conn", None)
                if conn is None:
                    conn = self.ledger._local.conn = self.ledger._open()
                self.conn = conn
            return self.conn

        def __exit__(self, *exc) -> None:
            if self.ledger.config.connection_per_request:
                self.conn.close()

    def _connection(self) -> _Borrow:
        return Ledger._Borrow(self)

    def close(self) -> None:
        conn = getattr(self._local, "conn", None)
        if conn is not None:
            conn.close()
            self._local.conn = None

    # -- transactions ----------------------------------------------------------

    @staticmethod
    def _write(conn: sqlite3.Connection, fn):
        """One write transaction. BEGIN IMMEDIATE takes the write lock before
        anything is read (guarantee sqlite.atomic_write_txn)."""
        conn.execute("BEGIN IMMEDIATE")
        try:
            out = fn()
            conn.execute("COMMIT")
            return out
        except BaseException:
            conn.execute("ROLLBACK")
            raise

    @staticmethod
    def _read(conn: sqlite3.Connection, fn):
        """Several reads from one snapshot (guarantee sqlite.read_snapshot)."""
        conn.execute("BEGIN")
        try:
            return fn()
        finally:
            conn.execute("COMMIT")

    @staticmethod
    def _require_party(conn: sqlite3.Connection, party: int) -> None:
        if conn.execute("SELECT 1 FROM parties WHERE id = ?", (party,)).fetchone() is None:
            raise LedgerError(404, f"no party {party}")

    def _adjust_cache(self, conn: sqlite3.Connection, party: int, delta: int) -> None:
        if self.config.cached_balance:
            conn.execute("UPDATE parties SET balance = balance + ? WHERE id = ?", (delta, party))

    def _settle(self, conn: sqlite3.Connection, party: int) -> list[dict]:
        """Mirrors `Spec.Ledger.settleParty`: unapplied advances settle open
        bills, oldest bill date first (ties by id), oldest payment first."""
        sql = ("SELECT id, outstanding FROM bills WHERE party_id = ? AND outstanding > 0 "
               "ORDER BY date, id")
        if self.config.settle_scan_cap is not None:
            sql += f" LIMIT {int(self.config.settle_scan_cap)}"
        owed = conn.execute(sql, (party,)).fetchall()
        adv = conn.execute("SELECT id, advance FROM payments WHERE party_id = ? AND reversed = 0 "
                           "AND advance > 0 ORDER BY id", (party,)).fetchall()
        out = []
        for p, b, x in match_up(owed, adv):
            conn.execute("UPDATE bills SET outstanding = outstanding - ? WHERE id = ?", (x, b))
            conn.execute("UPDATE payments SET advance = advance - ? WHERE id = ?", (x, p))
            conn.execute("INSERT INTO allocations (payment_id, bill_id, amount) VALUES (?, ?, ?)", (p, b, x))
            out.append({"payment": p, "bill": b, "amount": x})
        return out

    # -- operations ----------------------------------------------------------

    def create_party(self, name: str) -> dict:
        if not isinstance(name, str) or not name:
            raise LedgerError(400, "name must be a non-empty string")
        with self._connection() as conn:
            pid = self._write(conn, lambda: conn.execute(
                "INSERT INTO parties (name) VALUES (?)", (name,)).lastrowid)
        return {"party": pid}

    def record_bill(self, party: int, amount: object, date: object) -> dict:
        amount, date = money(amount), day(date)
        with self._connection() as conn:
            def tx():
                self._require_party(conn, party)
                bill = conn.execute("INSERT INTO bills (party_id, date, amount, outstanding) VALUES (?, ?, ?, ?)",
                                    (party, date, amount, amount)).lastrowid
                self._adjust_cache(conn, party, amount)
                return {"bill": bill, "allocations": self._settle(conn, party)}
            return self._write(conn, tx)

    def record_payment(self, party: int, amount: object) -> dict:
        amount = money(amount)
        with self._connection() as conn:
            def tx():
                self._require_party(conn, party)
                pay = conn.execute("INSERT INTO payments (party_id, amount, advance) VALUES (?, ?, ?)",
                                   (party, amount, amount)).lastrowid
                self._adjust_cache(conn, party, -amount)
                allocations = self._settle(conn, party)
                advance = conn.execute("SELECT advance FROM payments WHERE id = ?", (pay,)).fetchone()[0]
                return {"payment": pay, "allocations": allocations, "advance": advance}
            return self._write(conn, tx)

    def reverse_payment(self, payment: int) -> dict:
        with self._connection() as conn:
            def tx():
                row = conn.execute("SELECT party_id, amount FROM payments WHERE id = ? AND reversed = 0",
                                   (payment,)).fetchone()
                if row is None:
                    raise LedgerError(409, "no live payment")
                party, amount = row
                for bill, x in conn.execute("SELECT bill_id, amount FROM allocations WHERE payment_id = ?",
                                            (payment,)).fetchall():
                    conn.execute("UPDATE bills SET outstanding = outstanding + ? WHERE id = ?", (x, bill))
                conn.execute("DELETE FROM allocations WHERE payment_id = ?", (payment,))
                conn.execute("UPDATE payments SET reversed = 1, advance = 0 WHERE id = ?", (payment,))
                self._adjust_cache(conn, party, amount)
                return {"reversed": payment, "allocations": self._settle(conn, party)}
            return self._write(conn, tx)

    def balance(self, party: int) -> dict:
        with self._connection() as conn:
            def tx():
                if self.config.cached_balance:
                    row = conn.execute("SELECT balance FROM parties WHERE id = ?", (party,)).fetchone()
                    if row is None:
                        raise LedgerError(404, f"no party {party}")
                    return row[0]
                self._require_party(conn, party)
                billed = conn.execute("SELECT COALESCE(SUM(amount), 0) FROM bills WHERE party_id = ?",
                                      (party,)).fetchone()[0]
                paid = conn.execute("SELECT COALESCE(SUM(amount), 0) FROM payments WHERE party_id = ? "
                                    "AND reversed = 0", (party,)).fetchone()[0]
                return billed - paid
            return {"balance": self._read(conn, tx)}

    def open_bills(self, party: int) -> dict:
        with self._connection() as conn:
            def tx():
                self._require_party(conn, party)
                return conn.execute("SELECT id, date, outstanding FROM bills WHERE party_id = ? "
                                    "AND outstanding > 0 ORDER BY date, id", (party,)).fetchall()
            return {"open": [{"bill": b, "date": d, "outstanding": x} for b, d, x in self._read(conn, tx)]}

    # -- bulk seeding for benchmarks --------------------------------------------

    def seed(self, parties: int, bills_per_party: int, amount: int = 1000) -> None:
        """Parties with unpaid, dated bills, inserted in bulk (not part of the API)."""
        with self._connection() as conn:
            def tx():
                conn.executemany("INSERT INTO parties (name, balance) VALUES (?, ?)",
                                 [(f"party-{i}", bills_per_party * amount if self.config.cached_balance else 0)
                                  for i in range(1, parties + 1)])
                rows = [(p, (k * 7919) % 365, amount, amount)
                        for k in range(bills_per_party) for p in range(1, parties + 1)]
                conn.executemany("INSERT INTO bills (party_id, date, amount, outstanding) VALUES (?, ?, ?, ?)", rows)
            self._write(conn, tx)

    def observed_pragmas(self) -> dict:
        """What the database actually runs with, for the guarantee check."""
        with self._connection() as conn:
            return {"journal_mode": conn.execute("PRAGMA journal_mode").fetchone()[0].lower(),
                    "synchronous": conn.execute("PRAGMA synchronous").fetchone()[0],
                    "sqlite_version": sqlite3.sqlite_version}
