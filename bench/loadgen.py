"""Closed-loop HTTP load against the ledger API.

Each worker thread keeps one HTTP/1.1 connection open and sends requests
back to back for the duration. Every request is recorded (operation, status,
start offset, latency). Percentiles are computed from all of them (nearest
rank), never estimated, and the raw samples can be written out for audit.

    python -m bench.loadgen --host srv --port 8080 --parties 200 --threads 8 \\
        --seconds 20 --reps 3 --warmup 3 [--samples-dir DIR]
"""

from __future__ import annotations

import argparse
import gzip
import hashlib
import http.client
import json
import random
import sys
import threading
import time
from collections import Counter
from dataclasses import dataclass
from pathlib import Path

# Operation mix: (name, weight). Reads dominate, as in most SaaS APIs.
MIX = [("balance", 45), ("open_bills", 15), ("bill", 20), ("payment", 15), ("reverse", 5)]


@dataclass
class Sample:
    op: str
    status: int
    start_ns: int   # from the start of the run
    ns: int         # latency


def percentile(sorted_ns: list[int], q: float) -> int:
    """Nearest-rank percentile of already-sorted values."""
    if not sorted_ns:
        return 0
    rank = max(1, -(-len(sorted_ns) * q // 100))  # ceil(n*q/100), at least 1
    return sorted_ns[int(rank) - 1]


def worker(host: str, port: int, parties: int, seed: int, t0: int, stop_at: float, out: list[Sample]) -> None:
    rng = random.Random(seed)
    names, weights = zip(*MIX)
    conn = http.client.HTTPConnection(host, port, timeout=60)
    headers = {"Content-Type": "application/json"}
    mine: list[int] = []   # payments this worker made, for reversals
    while time.perf_counter() < stop_at:
        op = rng.choices(names, weights)[0]
        if op == "reverse" and not mine:
            op = "payment"
        party = rng.randint(1, parties)
        if op == "balance":
            method, path, body = "GET", f"/parties/{party}/balance", None
        elif op == "open_bills":
            method, path, body = "GET", f"/parties/{party}/open-bills", None
        elif op == "bill":
            method, path, body = "POST", f"/parties/{party}/bills", json.dumps(
                {"amount": rng.randint(100, 5000), "date": rng.randint(0, 364)})
        elif op == "payment":
            method, path, body = "POST", f"/parties/{party}/payments", json.dumps({"amount": rng.randint(100, 5000)})
        else:
            method, path, body = "POST", f"/payments/{mine.pop(rng.randrange(len(mine)))}/reverse", None
        start = time.perf_counter_ns()
        try:
            conn.request(method, path, body=body, headers=headers)
            resp = conn.getresponse()
            data = resp.read()
            status = resp.status
            if op == "payment" and status == 201:
                mine.append(json.loads(data)["payment"])
        except (OSError, http.client.HTTPException):
            status = 0
            conn.close()
            conn = http.client.HTTPConnection(host, port, timeout=60)
        out.append(Sample(op, status, start - t0, time.perf_counter_ns() - start))
    conn.close()


def histogram(ns: list[int]) -> dict[str, int]:
    """Counts per power-of-two microsecond bucket: key "k" covers [2^k, 2^(k+1)) µs."""
    counts = Counter(max(0, (n // 1000).bit_length() - 1) for n in ns)
    return {str(k): counts[k] for k in sorted(counts)}


def summarise(samples: list[Sample], seconds: float) -> dict:
    def stats(group: list[Sample]) -> dict:
        ok = sorted(s.ns for s in group if 200 <= s.status < 300)
        return {
            "requests": len(group),
            "ok": len(ok),
            "errors": len(group) - len(ok),
            "throughput_rps": round(len(ok) / seconds, 1),
            "p50_ms": round(percentile(ok, 50) / 1e6, 3),
            "p95_ms": round(percentile(ok, 95) / 1e6, 3),
            "p99_ms": round(percentile(ok, 99) / 1e6, 3),
            "max_ms": round(ok[-1] / 1e6, 3) if ok else 0,
            "latency_histogram_log2_us": histogram(ok),
        }
    per_second = Counter(s.start_ns // 1_000_000_000 for s in samples if 200 <= s.status < 300)
    return {
        "overall": stats(samples),
        "by_op": {name: stats([s for s in samples if s.op == name]) for name, _ in MIX},
        "status_counts": {str(k): v for k, v in sorted(Counter(s.status for s in samples).items())},
        "ok_per_second": [per_second[i] for i in range(int(seconds) + 1)],
        "seconds": seconds,
    }


def run(host: str, port: int, parties: int, threads: int, seconds: float, seed: int) -> tuple[dict, list[Sample]]:
    stop_at = time.perf_counter() + seconds
    buckets: list[list[Sample]] = [[] for _ in range(threads)]
    t0 = time.perf_counter_ns()
    ts = [threading.Thread(target=worker, args=(host, port, parties, seed * 1000 + i, t0, stop_at, buckets[i]))
          for i in range(threads)]
    started = time.perf_counter()
    for t in ts:
        t.start()
    for t in ts:
        t.join()
    elapsed = time.perf_counter() - started
    samples = sorted((s for b in buckets for s in b), key=lambda s: s.start_ns)
    return summarise(samples, elapsed), samples


def write_samples(path: Path, samples: list[Sample]) -> str:
    """Every request as gzipped CSV; returns the file's SHA-256."""
    with gzip.open(path, "wt", encoding="utf-8", newline="\n") as f:
        f.write("op,status,start_ns,latency_ns\n")
        for s in samples:
            f.write(f"{s.op},{s.status},{s.start_ns},{s.ns}\n")
    return hashlib.sha256(path.read_bytes()).hexdigest()


def wait_healthy(host: str, port: int, timeout: float = 120) -> None:
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        try:
            conn = http.client.HTTPConnection(host, port, timeout=2)
            conn.request("GET", "/health")
            if conn.getresponse().status == 200:
                return
        except OSError:
            pass
        time.sleep(0.2)
    raise SystemExit(f"{host}:{port} not healthy after {timeout}s")


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(prog="python -m bench.loadgen")
    ap.add_argument("--host", default="127.0.0.1")
    ap.add_argument("--port", type=int, default=8080)
    ap.add_argument("--parties", type=int, required=True)
    ap.add_argument("--threads", type=int, default=8)
    ap.add_argument("--seconds", type=float, default=20)
    ap.add_argument("--warmup", type=float, default=3)
    ap.add_argument("--reps", type=int, default=3)
    ap.add_argument("--samples-dir", type=Path)
    ap.add_argument("--label", default="run")
    args = ap.parse_args(argv)
    wait_healthy(args.host, args.port)
    warm, _ = run(args.host, args.port, args.parties, args.threads, args.warmup, seed=0)
    reps = []
    for r in range(args.reps):
        summary, samples = run(args.host, args.port, args.parties, args.threads, args.seconds, seed=r + 1)
        if args.samples_dir:
            name = f"{args.label}-rep{r + 1}.csv.gz"
            summary["samples_file"] = name
            summary["samples_sha256"] = write_samples(args.samples_dir / name, samples)
        reps.append(summary)
    json.dump({"warmup": {"seconds": warm["seconds"], "ok": warm["overall"]["ok"]}, "reps": reps}, sys.stdout)
    return 0


if __name__ == "__main__":
    sys.exit(main())
