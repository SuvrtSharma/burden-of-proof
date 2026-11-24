"""End to end: check every optimisation claim's meaning, then benchmark the
baseline, each claim on its own, and the combination of accepted claims,
over real HTTP against a real server process (ADR-0020).

Rejected claims are measured too, labelled as rejected, to show what speed
was on offer and why it wasn't taken. Only accepted claims go into the
combined configuration.

    python -m bench.run [--seconds 20] [--reps 3] [--threads 8]
"""

from __future__ import annotations

import argparse
import cProfile
import datetime as dt
import io
import json
import os
import platform
import pstats
import random
import shutil
import socket
import sqlite3
import statistics
import subprocess
import sys
import time
import urllib.request
from dataclasses import asdict
from pathlib import Path

from bench import loadgen
from burden_of_proof import optcheck
from reference.ledger.store import Config, Ledger

ROOT = Path(__file__).resolve().parent.parent
CLAIMS = sorted((ROOT / "claims" / "optimisations").glob("*.toml"))
WORK = ROOT / ".local" / "bench"


def free_port() -> int:
    with socket.socket() as s:
        s.bind(("127.0.0.1", 0))
        return s.getsockname()[1]


def environment(args) -> dict:
    now = dt.datetime.now(dt.timezone.utc)
    return {
        "measured_at": now.isoformat(timespec="seconds"),
        "expires": (now + dt.timedelta(days=90)).date().isoformat(),
        "platform": platform.platform(),
        "processor": platform.processor(),
        "cpu_count": os.cpu_count(),
        "python": platform.python_version(),
        "sqlite_library": sqlite3.sqlite_version,
        "disk": str(WORK.resolve().anchor),
        "load": {"threads": args.threads, "seconds": args.seconds, "reps": args.reps,
                 "warmup_seconds": args.warmup, "mix": dict(loadgen.MIX)},
        "data": {"parties": args.parties, "bills_per_party": args.bills},
        "server": "reference.ledger.server (ThreadingHTTPServer, HTTP/1.1 keep-alive), same machine as the client",
    }


def profile_baseline(n_ops: int = 400) -> str:
    """Where the baseline spends its time, in-process (measure before optimising)."""
    path = WORK / "profile" / "p.db"
    shutil.rmtree(path.parent, ignore_errors=True)
    path.parent.mkdir(parents=True)
    ledger = Ledger(path, Config())
    ledger.seed(50, 100)
    rng = random.Random(1)
    prof = cProfile.Profile()
    prof.enable()
    for _ in range(n_ops):
        op, p = rng.choices([m for m, _ in loadgen.MIX], [w for _, w in loadgen.MIX])[0], rng.randint(1, 50)
        if op == "balance":
            ledger.balance(p)
        elif op == "open_bills":
            ledger.open_bills(p)
        elif op == "bill":
            ledger.record_bill(p, rng.randint(100, 5000), rng.randint(0, 364))
        else:
            ledger.record_payment(p, rng.randint(100, 5000))
    prof.disable()
    out = io.StringIO()
    pstats.Stats(prof, stream=out).sort_stats("tottime").print_stats(12)
    return out.getvalue()


def measure(label: str, config: Config, args) -> dict:
    d = WORK / label
    shutil.rmtree(d, ignore_errors=True)
    d.mkdir(parents=True)
    port = free_port()
    changes = {k: v for k, v in asdict(config).items() if asdict(Config())[k] != v}
    log = (d / "server.log").open("w")
    proc = subprocess.Popen([sys.executable, "-m", "reference.ledger.server", "--db", str(d / "ledger.db"),
                             "--port", str(port), "--config", json.dumps(changes),
                             "--seed", f"{args.parties},{args.bills}"], cwd=ROOT, stdout=log, stderr=log)
    try:
        for _ in range(600):
            try:
                urllib.request.urlopen(f"http://127.0.0.1:{port}/health", timeout=1).read()
                break
            except OSError:
                time.sleep(0.1)
        else:
            raise RuntimeError(f"{label}: server did not start; see {d / 'server.log'}")
        loadgen.run("127.0.0.1", port, args.parties, args.threads, args.warmup, seed=0)
        reps = [loadgen.run("127.0.0.1", port, args.parties, args.threads, args.seconds, seed=r + 1)[0]
                for r in range(args.reps)]
    finally:
        proc.terminate()
        proc.wait(timeout=30)
        log.close()

    def med(key, op=None):
        return statistics.median((r["by_op"][op] if op else r["overall"])[key] for r in reps)

    summary = {k: med(k) for k in ("throughput_rps", "p50_ms", "p95_ms", "p99_ms")}
    summary["errors"] = sum(r["overall"]["errors"] for r in reps)
    summary["by_op"] = {op: {k: med(k, op) for k in ("throughput_rps", "p50_ms", "p99_ms")} for op, _ in loadgen.MIX}
    return {"label": label, "config_changes": changes, "summary": summary, "reps": reps}


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(prog="python -m bench.run")
    ap.add_argument("--seconds", type=float, default=20)
    ap.add_argument("--warmup", type=float, default=3)
    ap.add_argument("--reps", type=int, default=3)
    ap.add_argument("--threads", type=int, default=8)
    ap.add_argument("--parties", type=int, default=200)
    ap.add_argument("--bills", type=int, default=100)
    ap.add_argument("--sequences", type=int, default=100)
    ap.add_argument("--out", type=Path, default=ROOT / "bench" / "reports")
    args = ap.parse_args(argv)
    WORK.mkdir(parents=True, exist_ok=True)

    print("profiling baseline", flush=True)
    profile = profile_baseline()

    verdicts = []
    for path in CLAIMS:
        print(f"checking {path.name}", flush=True)
        verdicts.append(optcheck.check(path, args.sequences))
        print(f"  -> {verdicts[-1]['verdict']} {[r['code'] for r in verdicts[-1]['reasons']]}", flush=True)

    combined = Config()
    for v in verdicts:
        if v["verdict"] == "accept":
            claim = __import__("tomllib").loads(next(p for p in CLAIMS if p.stem == v["id"]).read_text("utf-8"))
            combined = combined.with_changes(claim["config"])

    runs = []
    plan = [("baseline", Config())]
    plan += [(v["id"], Config(**v["config"])) for v in verdicts]
    plan += [("ALL-ACCEPTED", combined)]
    for label, cfg in plan:
        print(f"measuring {label}", flush=True)
        runs.append(measure(label, cfg, args))
        s = runs[-1]["summary"]
        print(f"  {s['throughput_rps']} req/s, p50 {s['p50_ms']} ms, p99 {s['p99_ms']} ms, errors {s['errors']}", flush=True)

    base = runs[0]["summary"]["throughput_rps"]
    for r in runs:
        r["summary"]["speedup_vs_baseline"] = round(r["summary"]["throughput_rps"] / base, 2) if base else None

    report = {"environment": environment(args), "profile_baseline": profile, "verdicts": verdicts, "runs": runs}
    args.out.mkdir(parents=True, exist_ok=True)
    stamp = dt.datetime.now().strftime("%Y-%m-%d-%H%M")
    path = args.out / f"{stamp}-ledger.json"
    path.write_text(json.dumps(report, indent=2), encoding="utf-8", newline="\n")
    print(f"wrote {path}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
