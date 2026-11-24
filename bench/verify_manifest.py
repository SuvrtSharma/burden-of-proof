"""Re-hash every evidence file of a run and compare with its manifest.

    python3 bench/verify_manifest.py [evidence/<run-id>]   (default: the latest run)
"""

from __future__ import annotations

import hashlib
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def main(argv: list[str]) -> int:
    run = Path(argv[0]) if argv else ROOT / "evidence" / (ROOT / "evidence" / "latest.txt").read_text().strip()
    manifest = json.loads((run / "manifest.json").read_text())
    bad = 0
    for rel, want in manifest["files"].items():
        got = hashlib.sha256((run / rel).read_bytes()).hexdigest() if (run / rel).is_file() else "missing"
        same = got == want
        bad += not same
        print(f"{'✓' if same else '✕'} {want[:16]}…  {rel}" + ("" if same else f"   now {got[:16]}…"))
    print(f"\nrun {manifest['run_id']} at commit {manifest['git']['commit'][:12]}"
          f"{' (with uncommitted changes)' if manifest['git']['dirty'] else ''}: "
          f"{len(manifest['files']) - bad} of {len(manifest['files'])} files match")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
