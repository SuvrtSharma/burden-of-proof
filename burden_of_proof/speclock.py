"""Hash lock for the reviewed spec of a Lake project (ADR-0004).

Locked files: `Spec.lean`, every `.lean` file under `Spec/`, `lakefile.toml`
and `lean-toolchain`. The lakefile and toolchain are locked too, because
they can change what a proof means (for example, by passing options to every
file).

Hashes are taken over the raw bytes. `.gitattributes` forces LF, so a
Windows checkout doesn't change them.

Only the owner runs `update`. Agents run `verify`.

    python -m burden_of_proof.speclock verify [--project DIR]
    python -m burden_of_proof.speclock update [--project DIR]
"""

from __future__ import annotations

import argparse
import hashlib
import json
import sys
from dataclasses import dataclass, field
from pathlib import Path

LOCK_NAME = "spec.lock.json"
LOCK_VERSION = 1


def locked_files(project: Path) -> list[str]:
    """Relative POSIX paths of every file the lock covers, sorted."""
    paths: set[Path] = set()
    for name in ("Spec.lean", "lakefile.toml", "lean-toolchain"):
        if (project / name).is_file():
            paths.add(project / name)
    spec_dir = project / "Spec"
    if spec_dir.is_dir():
        paths.update(p for p in spec_dir.rglob("*.lean") if p.is_file())
    return sorted(p.relative_to(project).as_posix() for p in paths)


def sha256_file(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def current_hashes(project: Path) -> dict[str, str]:
    return {rel: sha256_file(project / rel) for rel in locked_files(project)}


def write_lock(project: Path) -> Path:
    lock = {"version": LOCK_VERSION, "files": current_hashes(project)}
    path = project / LOCK_NAME
    path.write_text(json.dumps(lock, indent=2, sort_keys=True) + "\n", encoding="utf-8", newline="\n")
    return path


@dataclass
class LockReport:
    ok: bool
    missing_lock: bool = False
    changed: list[str] = field(default_factory=list)
    added: list[str] = field(default_factory=list)
    removed: list[str] = field(default_factory=list)

    def describe(self) -> str:
        if self.missing_lock:
            return f"no {LOCK_NAME}"
        parts = []
        for label, items in (("changed", self.changed), ("added", self.added), ("removed", self.removed)):
            if items:
                parts.append(f"{label}: {', '.join(items)}")
        return "; ".join(parts) or "ok"


def verify(project: Path) -> LockReport:
    path = project / LOCK_NAME
    if not path.is_file():
        return LockReport(ok=False, missing_lock=True)
    locked = json.loads(path.read_text(encoding="utf-8"))["files"]
    current = current_hashes(project)
    changed = sorted(k for k in locked.keys() & current.keys() if locked[k] != current[k])
    added = sorted(current.keys() - locked.keys())
    removed = sorted(locked.keys() - current.keys())
    return LockReport(ok=not (changed or added or removed), changed=changed, added=added, removed=removed)


def lock_digest(project: Path) -> str:
    """Hash of the lock file itself, recorded with every result."""
    return sha256_file(project / LOCK_NAME)


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(prog="python -m burden_of_proof.speclock")
    ap.add_argument("action", choices=["verify", "update"])
    ap.add_argument("--project", type=Path, default=Path.cwd())
    args = ap.parse_args(argv)
    if args.action == "update":
        print(f"wrote {write_lock(args.project)}")
        return 0
    report = verify(args.project)
    print(report.describe())
    return 0 if report.ok else 1


if __name__ == "__main__":
    sys.exit(main())
