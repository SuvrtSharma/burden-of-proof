"""How long does fsync take on this storage? No database involved.
Appends 4 KiB and fsyncs, back to back, for a fixed time, then reports the
latency percentiles and how many syncs completed in each second.

    python -m bench.fsync_probe --path /data/probe --seconds 30
"""
import argparse, json, os, sys, time

ap = argparse.ArgumentParser()
ap.add_argument("--path", required=True)
ap.add_argument("--seconds", type=float, default=30)
args = ap.parse_args()
fd = os.open(args.path, os.O_WRONLY | os.O_CREAT | os.O_APPEND, 0o600)
block = b"x" * 4096
lat, per_sec = [], {}
t0 = time.perf_counter()
while (now := time.perf_counter()) - t0 < args.seconds:
    os.write(fd, block)
    s = time.perf_counter_ns(); os.fsync(fd); ns = time.perf_counter_ns() - s
    lat.append(ns); sec = int(now - t0); per_sec[sec] = per_sec.get(sec, 0) + 1
os.close(fd); os.unlink(args.path)
lat.sort()
pick = lambda q: lat[int(max(1, -(-len(lat) * q // 100))) - 1] / 1e6
json.dump({"fsyncs": len(lat), "p50_ms": round(pick(50), 3), "p99_ms": round(pick(99), 3), "p99_9_ms": round(pick(99.9), 3),
           "max_ms": round(lat[-1] / 1e6, 3), "per_second": [per_sec.get(i, 0) for i in range(int(args.seconds))]}, sys.stdout)
