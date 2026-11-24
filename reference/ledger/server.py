"""HTTP API over the ledger store (stdlib only, HTTP/1.1 keep-alive).

    POST /parties                       {"name": "..."}  -> {"party": id}
    POST /parties/{id}/bills            {"amount": n, "date": d} -> {"bill": id, "allocations": [...]}
    POST /parties/{id}/payments         {"amount": n}    -> {"payment": id, "allocations": [...], "advance": n}
    POST /payments/{id}/reverse                          -> {"reversed": id, "allocations": [...]}
    GET  /parties/{id}/balance                           -> {"balance": n}
    GET  /parties/{id}/open-bills                        -> {"open": [...]}
    GET  /health                                         -> {"ok": true, "config": {...}}

    python -m reference.ledger.server --db PATH --port 8080 \\
        [--config '{"journal_mode": "WAL"}'] [--seed PARTIES,BILLS]
"""

from __future__ import annotations

import argparse
import json
import re
from dataclasses import asdict
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

from reference.ledger.store import Config, Ledger, LedgerError

ROUTE = re.compile(r"^/parties/(\d+)/(bills|payments|balance|open-bills)$")
REVERSE = re.compile(r"^/payments/(\d+)/reverse$")


def make_handler(ledger: Ledger, nodelay: bool = True):
    class Handler(BaseHTTPRequestHandler):
        protocol_version = "HTTP/1.1"
        # TCP_NODELAY. Without it, headers and body leave as two small writes and
        # the second waits for the client's delayed ACK: a ~40 ms floor on every
        # small response (findings F-016).
        disable_nagle_algorithm = nodelay

        def log_message(self, *args) -> None:  # keep benchmarks quiet
            pass

        def _send(self, status: int, body: dict) -> None:
            data = json.dumps(body, separators=(",", ":")).encode()
            self.send_response(status)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(data)))
            self.end_headers()
            self.wfile.write(data)

        def _body(self) -> dict:
            length = int(self.headers.get("Content-Length") or 0)
            try:
                body = json.loads(self.rfile.read(length) or b"{}")
            except json.JSONDecodeError:
                raise LedgerError(400, "body must be JSON")
            if not isinstance(body, dict):
                raise LedgerError(400, "body must be a JSON object")
            return body

        def _dispatch(self, method: str) -> None:
            try:
                if method == "GET" and self.path == "/health":
                    return self._send(200, {"ok": True, "config": asdict(ledger.config), "tcp_nodelay": nodelay})
                if method == "POST" and self.path == "/parties":
                    return self._send(201, ledger.create_party(self._body().get("name")))
                rv = REVERSE.match(self.path)
                if method == "POST" and rv:
                    return self._send(200, ledger.reverse_payment(int(rv.group(1))))
                m = ROUTE.match(self.path)
                if not m:
                    return self._send(404, {"error": "not found"})
                party, what = int(m.group(1)), m.group(2)
                if method == "POST" and what == "bills":
                    body = self._body()
                    return self._send(201, ledger.record_bill(party, body.get("amount"), body.get("date")))
                if method == "POST" and what == "payments":
                    return self._send(201, ledger.record_payment(party, self._body().get("amount")))
                if method == "GET" and what == "balance":
                    return self._send(200, ledger.balance(party))
                if method == "GET" and what == "open-bills":
                    return self._send(200, ledger.open_bills(party))
                return self._send(405, {"error": "method not allowed"})
            except LedgerError as e:
                return self._send(e.status, {"error": str(e)})

        def do_GET(self) -> None:
            self._dispatch("GET")

        def do_POST(self) -> None:
            self._dispatch("POST")

    return Handler


def main(argv: list[str] | None = None) -> None:
    ap = argparse.ArgumentParser(prog="python -m reference.ledger.server")
    ap.add_argument("--db", required=True)
    ap.add_argument("--host", default="127.0.0.1")
    ap.add_argument("--port", type=int, default=8080)
    ap.add_argument("--config", default="{}", help="JSON object of Config changes from baseline")
    ap.add_argument("--seed", default="", help="PARTIES,BILLS_PER_PARTY to bulk-load before serving")
    ap.add_argument("--no-tcp-nodelay", action="store_true", help="leave Nagle's algorithm on (for the F-016 experiment)")
    args = ap.parse_args(argv)
    ledger = Ledger(args.db, Config().with_changes(json.loads(args.config)))
    if args.seed:
        parties, bills = (int(x) for x in args.seed.split(","))
        ledger.seed(parties, bills)
    server = ThreadingHTTPServer((args.host, args.port), make_handler(ledger, nodelay=not args.no_tcp_nodelay))
    server.daemon_threads = True
    print(f"listening on http://{args.host}:{args.port}", flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()


if __name__ == "__main__":
    main()
