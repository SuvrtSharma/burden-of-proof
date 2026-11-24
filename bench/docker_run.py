"""The measured loop, in Docker inside WSL (ADR-0021). Run with the distro's Python:

    python3 bench/docker_run.py before         # new run: tests + the baseline, measured
    python3 bench/docker_run.py check          # meaning verdicts for every claim (no timing)
    python3 bench/docker_run.py after [--each] # the accepted claims, measured and compared
    python3 bench/docker_run.py all            # the three in order
    python3 bench/docker_run.py show           # re-print the latest run's reports from its files

Every phase writes into evidence/<run-id>/ (the newest run is in
evidence/latest.txt). `after` writes benchmark.json and manifest.json, which
hold SHA-256 hashes of every file, the git commit and whether the tree had
uncommitted changes. Server and load generator run in separate containers
on separate CPUs, on a private network. Standard library only.
"""

from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import json
import os
import platform
import random
import statistics
import subprocess
import sys
import tomllib
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
EVIDENCE = Path(os.environ.get("BURDEN_OF_PROOF_EVIDENCE", ROOT / "evidence"))  # override only for smoke tests
LEDGER, CHECKER = "burden-of-proof/ledger:dev", "burden-of-proof/checker:dev"
NETWORK = "burden-of-proof-bench"
SERVER_CPUS, CLIENT_CPUS = "0-3", "4-7"
BASELINE = {"connection_per_request": True, "journal_mode": "DELETE", "synchronous": "EXTRA",
            "index_party": False, "cached_balance": False, "settle_scan_cap": None}
FLOOR_MS = 10.0   # a trivial read slower than this at the median means the harness, not the database (F-016)

TICK, CROSS = "\033[32m✓\033[0m", "\033[31m✕\033[0m"


def sh(*cmd: str, check: bool = True) -> str:
    p = subprocess.run(cmd, capture_output=True, text=True)
    if check and p.returncode != 0:
        raise SystemExit(f"command failed ({p.returncode}): {' '.join(cmd)}\n{p.stdout}\n{p.stderr}")
    return (p.stdout or "").strip()


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def banner(text: str) -> None:
    print(f"\n\033[1m━━ {text} " + "━" * max(3, 90 - len(text)) + "\033[0m", flush=True)


def environment() -> dict:
    cpu = next((l.split(":", 1)[1].strip() for l in Path("/proc/cpuinfo").read_text().splitlines()
                if l.startswith("model name")), "unknown")
    mem_kb = next(int(l.split()[1]) for l in Path("/proc/meminfo").read_text().splitlines() if l.startswith("MemTotal"))
    return {
        "host": "WSL2 " + platform.release(), "cpu_model": cpu, "vm_cpus": int(sh("nproc")), "vm_memory_kib": mem_kb,
        "docker": sh("docker", "version", "--format", "{{.Server.Version}}"),
        "images": {img: sh("docker", "image", "inspect", img, "--format", "{{.Id}}") for img in (LEDGER, CHECKER)},
        "container_python_sqlite": sh("docker", "run", "--rm", LEDGER, "python", "-c",
                                      "import sys,sqlite3;print(sys.version.split()[0], sqlite3.sqlite_version)"),
        "server_cpuset": SERVER_CPUS, "client_cpuset": CLIENT_CPUS,
        "storage": "named Docker volume (ext4 in the WSL2 VM)", "tcp_nodelay": True,
    }


def git_state() -> dict:
    git = ["git", "-c", "safe.directory=*", "-C", str(ROOT)]
    status = sh(*git, "status", "--porcelain")
    return {"commit": sh(*git, "rev-parse", "HEAD"), "dirty": bool(status), "dirty_files": status.splitlines()}


def run_dir(new: bool = False) -> Path:
    latest = EVIDENCE / "latest.txt"
    if new:
        run_id = dt.datetime.now(dt.timezone.utc).strftime("%Y%m%dT%H%M%SZ")
        (EVIDENCE / run_id).mkdir(parents=True)
        latest.write_text(run_id + "\n")
    elif not latest.is_file():
        raise SystemExit("no run yet: start with `python3 bench/docker_run.py before`")
    return EVIDENCE / latest.read_text().strip()


def claims() -> dict:
    return {d["id"]: d for d in (tomllib.loads(p.read_text()) for p in sorted((ROOT / "claims" / "optimisations").glob("*.toml")))}


# ---------------------------------------------------------------- measuring

def measure(label: str, changes: dict, out: Path, args, reps: int | None = None, tag: str = "") -> dict:
    reps = args.reps if reps is None else reps
    name, vol = f"gh-srv-{label.lower()}", f"gh-vol-{label.lower()}"
    sh("docker", "rm", "-f", name, check=False)
    sh("docker", "volume", "rm", "-f", vol, check=False)
    sh("docker", "network", "create", NETWORK, check=False)
    sh("docker", "volume", "create", vol)
    (out / "samples").mkdir(exist_ok=True)
    try:
        sh("docker", "run", "-d", "--name", name, "--network", NETWORK, "--cpuset-cpus", SERVER_CPUS,
           "-v", f"{vol}:/data", LEDGER, "python", "-m", "reference.ledger.server", "--db", "/data/ledger.db",
           "--host", "0.0.0.0", "--port", "8080", "--config", json.dumps(changes),
           "--seed", f"{args.parties},{args.bills}")
        raw = sh("docker", "run", "--rm", "--network", NETWORK, "--cpuset-cpus", CLIENT_CPUS,
                 "-v", f"{out / 'samples'}:/samples", LEDGER, "python", "-m", "bench.loadgen", "--host", name,
                 "--port", "8080", "--parties", str(args.parties), "--threads", str(args.threads),
                 "--seconds", str(args.seconds), "--warmup", str(args.warmup), "--reps", str(reps),
                 "--samples-dir", "/samples", "--label", label + tag)
        result = json.loads(raw)
        result["server_log"] = sh("docker", "logs", name, check=False)[-2000:]
    finally:
        sh("docker", "rm", "-f", name, check=False)
        sh("docker", "volume", "rm", "-f", vol, check=False)
    run = {"label": label, "config_changes": changes, **result}
    floor = min(r["by_op"]["balance"]["p50_ms"] for r in run["reps"])
    run["sanity"] = {"balance_p50_min_ms": floor, "floor_ms": FLOOR_MS, "ok": floor <= FLOOR_MS}
    return run


def print_runs(runs: list[dict], base: dict | None) -> None:
    base_med = statistics.median(r["overall"]["throughput_rps"] for r in base["reps"]) if base else None
    print(f"  {'configuration':22} {'req/s per repetition':28} {'median':>8} {'× baseline':>11} {'p99 ms (median)':>16}  sanity")
    for run in runs:
        tps = [r["overall"]["throughput_rps"] for r in run["reps"]]
        med = statistics.median(tps)
        p99 = statistics.median(r["overall"]["p99_ms"] for r in run["reps"])
        ratio = f"{med / base_med:.2f}" if base_med else "—"
        sanity = TICK if run["sanity"]["ok"] else f"{CROSS} balance p50 {run['sanity']['balance_p50_min_ms']} ms > {FLOOR_MS}"
        print(f"  {run['label'][:22]:22} {', '.join(f'{x:.1f}' for x in tps):28} {med:8.1f} {ratio:>11} {p99:16.3f}  {sanity}")
    print("  (median of the repetitions; spread between repetitions is the noise floor: a smaller difference is no result)")


def load_args(args) -> dict:
    return {"threads": args.threads, "seconds": args.seconds, "reps": args.reps, "warmup_seconds": args.warmup,
            "parties": args.parties, "bills_per_party": args.bills}


# ---------------------------------------------------------------- phases

def phase_before(args) -> None:
    out = run_dir(new=True)
    banner(f"BEFORE  run {out.name}: tests in the checker container")
    tests = subprocess.run(["docker", "run", "--rm", "-v", f"{out}:/out", CHECKER, "python", "-m", "pytest", "-q", "-rs",
                            "-p", "no:cacheprovider", "--junitxml=/out/tests.xml"], capture_output=True, text=True)
    (out / "tests.log").write_text(tests.stdout + tests.stderr)
    summary = (tests.stdout.strip().splitlines() or [""])[-1]
    print(f"  {TICK if tests.returncode == 0 else CROSS} {summary}")
    banner("BEFORE: the baseline, measured over HTTP")
    print(f"  config {json.dumps(BASELINE)}")
    run = measure("baseline", {}, out, args)
    print_runs([run], run)
    (out / "before.json").write_text(json.dumps({
        "run_id": out.name, "started_at": dt.datetime.now(dt.timezone.utc).isoformat(timespec="seconds"),
        "git": git_state(), "environment": environment(), "baseline_config": BASELINE, "load": load_args(args),
        "tests": {"exit_code": tests.returncode, "summary": summary}, "runs": [run]}, indent=2))


def phase_check(args) -> None:
    out = run_dir()
    banner(f"CHECK  run {out.name}: meaning of every optimisation claim (no timing involved)")
    v = subprocess.run(["docker", "run", "--rm", "-v", f"{out}:/out", CHECKER, "python", "-m", "bench.verdicts",
                        "--out", "/out/verdicts.json", "--sequences", str(args.sequences)], capture_output=True, text=True)
    (out / "verdicts.log").write_text(v.stdout + v.stderr)
    if v.returncode != 0:
        raise SystemExit(f"verdicts failed:\n{v.stderr[-4000:]}")
    print_check(json.loads((out / "verdicts.json").read_text()))


def print_check(report: dict) -> None:
    print(f"  spec locked by the owner: {'yes' if report['spec_locked'] else 'NO (Lean evidence about the ledger does not count yet)'}")
    for x in report["verdicts"]:
        mark = TICK if x["verdict"] == "accept" else CROSS
        c = x["evidence"]["conformance"]
        print(f"\n  {mark} {x['id']}  ({x['kind']})  {x['verdict'].upper()}")
        print(f"      agent said: {x['agent_says']}")
        print(f"      conformance: {c['mismatches']} of {c['sequences']} sequences differ from the spec ({c['operations']} operations)")
        obs = x["evidence"]["observed"]["candidate"]
        print(f"      observed: journal_mode={obs['pragmas']['journal_mode']} synchronous={obs['pragmas']['synchronous']} "
              f"durable_commit={obs['held']['sqlite.durable_commit']}")
        for comp in x["evidence"].get("compensations", []):
            print(f"      Lean {comp['statement']}: {'accepted' if comp['accepted'] else 'not accepted ' + str(comp['violations'])}")
        for r in x["reasons"]:
            detail = r["detail"] if isinstance(r["detail"], str) else json.dumps(r["detail"])[:160]
            print(f"      reason {r['code']}: {detail}")
        ce = c.get("shrunk_counterexample")
        if ce:
            print(f"      shrunk counterexample: {len(ce['ops'])} operations; last {json.dumps(ce['ops'][-1])}")
            print(f"        spec : {json.dumps(ce['model'])[:150]}")
            print(f"        store: {json.dumps(ce['store'])[:150]}")


def phase_show(args) -> None:
    """Re-print a saved run's reports from its files; nothing is re-run or re-measured."""
    out = run_dir()
    before = out / "before.json"
    if before.is_file():
        b = json.loads(before.read_text())
        banner(f"BEFORE  run {out.name} (saved {b['started_at']}): tests, then the baseline")
        print(f"  {TICK if b['tests']['exit_code'] == 0 else CROSS} {b['tests']['summary']}")
        print_runs(b["runs"], b["runs"][0])
    verdicts = out / "verdicts.json"
    if verdicts.is_file():
        v = json.loads(verdicts.read_text())
        banner(f"CHECK  run {out.name} (saved {v['generated_at']}): meaning of every optimisation claim")
        print_check(v)
    bench = out / "benchmark.json"
    if bench.is_file():
        bj = json.loads(bench.read_text())
        banner(f"AFTER  run {out.name}: interleaved rounds {bj.get('interleaved_order', [])}")
        print_runs(bj["runs"], bj["runs"][0])


def phase_after(args) -> None:
    out = run_dir()
    before = json.loads((out / "before.json").read_text())
    verdicts = json.loads((out / "verdicts.json").read_text())
    cl = claims()
    accepted = [x["id"] for x in verdicts["verdicts"] if x["verdict"] == "accept"]
    combined: dict = {}
    for cid in accepted:
        combined.update(cl[cid]["config"])
    banner(f"AFTER  run {out.name}: accepted claims applied: {', '.join(accepted) or 'none'}")
    print(f"  config changes {json.dumps(combined)}")
    plan = [("baseline", {})]
    plan += [(x["id"], cl[x["id"]]["config"]) for x in verdicts["verdicts"]] if args.each else []
    plan.append(("ALL-ACCEPTED", combined))
    # Interleaved rounds (F-018): each round measures every configuration once,
    # on a fresh server, in a shuffled order, so storage drift hits all alike.
    order_log, by_label = [], {label: [] for label, _ in plan}
    for rnd in range(args.reps):
        order = plan[:]
        random.Random(rnd).shuffle(order)
        order_log.append([label for label, _ in order])
        print(f"  round {rnd + 1}/{args.reps}: {', '.join(order_log[-1])}", flush=True)
        for label, changes in order:
            by_label[label].append(measure(label, changes, out, args, reps=1, tag=f"-round{rnd + 1}"))
    runs = []
    for label, changes in plan:
        parts = by_label[label]
        reps = [r for part in parts for r in part["reps"]]
        floor = min(r["by_op"]["balance"]["p50_ms"] for r in reps)
        runs.append({"label": label, "config_changes": changes, "reps": reps,
                     "warmup": [part["warmup"] for part in parts], "server_log": parts[-1]["server_log"],
                     "sanity": {"balance_p50_min_ms": floor, "floor_ms": FLOOR_MS, "ok": floor <= FLOOR_MS}})
    banner("BEFORE (earlier, back to back) — for reference")
    print_runs([before["runs"][0]], before["runs"][0])
    banner("AFTER: interleaved rounds, baseline re-measured in the same window")
    print_runs(runs, runs[0])
    if args.each:
        print("  rejected claims were measured only to show what speed was on offer; they are not in ALL-ACCEPTED")
    bench = {**before, "runs": runs, "before_runs": before["runs"], "interleaved_order": order_log, "expires": (dt.date.today() + dt.timedelta(days=90)).isoformat(),
             "git": git_state(), "verdicts_file": "verdicts.json"}
    (out / "benchmark.json").write_text(json.dumps(bench, indent=2))
    files = sorted(p for p in out.rglob("*") if p.is_file() and p.name != "manifest.json")
    (out / "manifest.json").write_text(json.dumps({"run_id": out.name, "git": bench["git"],
                                                    "files": {p.relative_to(out).as_posix(): sha256(p) for p in files}}, indent=2))
    index = EVIDENCE / "index.json"
    entries = json.loads(index.read_text()) if index.is_file() else []
    entries = [e for e in entries if e["run_id"] != out.name]
    entries.append({"run_id": out.name, "started_at": before["started_at"], "commit": bench["git"]["commit"],
                    "dirty": bench["git"]["dirty"], "valid": all(r["sanity"]["ok"] for r in bench["runs"])})
    index.write_text(json.dumps(entries, indent=2))
    print(f"\n  evidence: {out}  (manifest.json lists every file's SHA-256)")


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(prog="python3 bench/docker_run.py")
    ap.add_argument("phase", choices=["before", "check", "after", "all", "show"])
    ap.add_argument("--each", action="store_true", help="after: also measure every claim on its own")
    ap.add_argument("--seconds", type=float, default=20)
    ap.add_argument("--warmup", type=float, default=3)
    ap.add_argument("--reps", type=int, default=3)
    ap.add_argument("--threads", type=int, default=8)
    ap.add_argument("--parties", type=int, default=200)
    ap.add_argument("--bills", type=int, default=100)
    ap.add_argument("--sequences", type=int, default=100)
    args = ap.parse_args(argv)
    if args.phase == "show":
        phase_show(args)
        return 0
    if args.phase in ("before", "all"):
        phase_before(args)
    if args.phase in ("check", "all"):
        phase_check(args)
    if args.phase in ("after", "all"):
        args.each = args.each or args.phase == "all"
        phase_after(args)
    return 0


if __name__ == "__main__":
    sys.exit(main())
