"""Meaning verdicts for every optimisation claim, plus a profile of the
baseline, written as one JSON file. Runs inside the checker container, so
conformance uses the same SQLite build the benchmark measures (ADR-0021).

    python -m bench.verdicts --out /out/verdicts.json [--sequences 100]
"""

from __future__ import annotations

import argparse
import datetime as dt
import json
import platform
import sqlite3
import subprocess
import sys
import time
from pathlib import Path

from bench.run import CLAIMS, profile_baseline
from burden_of_proof import optcheck


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(prog="python -m bench.verdicts")
    ap.add_argument("--out", type=Path, required=True)
    ap.add_argument("--sequences", type=int, default=100)
    args = ap.parse_args(argv)
    lean = subprocess.run(["lean", "--version"], capture_output=True, text=True).stdout.strip()
    started = time.perf_counter()
    verdicts = []
    for path in CLAIMS:
        t = time.perf_counter()
        v = optcheck.check(path, args.sequences)
        v["check_seconds"] = round(time.perf_counter() - t, 1)
        verdicts.append(v)
        print(f"{v['id']}: {v['verdict']} {[r['code'] for r in v['reasons']]}", file=sys.stderr, flush=True)
    report = {
        "generated_at": dt.datetime.now(dt.timezone.utc).isoformat(timespec="seconds"),
        "environment": {"python": platform.python_version(), "sqlite_library": sqlite3.sqlite_version,
                        "platform": platform.platform(), "lean": lean, "sequences": args.sequences},
        "spec_locked": (Path(__file__).resolve().parent.parent / "spec.lock.json").is_file(),
        "seconds": round(time.perf_counter() - started, 1),
        "profile_baseline": profile_baseline(),
        "verdicts": verdicts,
    }
    args.out.write_text(json.dumps(report, indent=2), encoding="utf-8")
    print(f"wrote {args.out}", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
