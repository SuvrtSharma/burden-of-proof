"""The Lean check pipeline (ADR-0006). Any failed step rejects the claim.

1. The spec lock matches (ADR-0004).
2. The target's toolchain matches the checker's.
3. `lake build` succeeds.
4. `leancheck` inspects the environment: the statement is a Prop in the
   spec, built only from core and spec definitions; the proof's type is
   exactly that statement; its axioms are within the allowlist; and no
   declaration of ours that it reaches is unsafe, implemented_by or extern.
   If the statement has binders, `<proof>_witness` must prove that they can
   all be satisfied (the vacuity guard).
5. `leanchecker` replays every Spec/Proofs module through the kernel. This
   catches declarations that were added without kernel checking (for
   example under `debug.skipKernelTC`), which steps 3 and 4 accept.
6. A second, independent kernel: the proof and witness are exported with
   `leanexport` (with everything they depend on, down to core) and
   re-checked from scratch by `con-leche`.
7. The result records the hashes of the lock, the proof file and the
   toolchain.

    python -m burden_of_proof.leancheck --project DIR --statement Spec.X \\
        --proof Proofs.Y.t --module Proofs.Y
"""

from __future__ import annotations

import argparse
import functools
import json
import os
import shutil
import subprocess
import sys
import tempfile
from dataclasses import asdict, dataclass, field
from pathlib import Path

from burden_of_proof import speclock

REPO_ROOT = Path(__file__).resolve().parent.parent
CHECKER_DIR = REPO_ROOT / "tools" / "leancheck"


class ToolError(RuntimeError):
    """The pipeline couldn't run. This is not a verdict on the claim."""


@dataclass
class Violation:
    code: str
    detail: str


@dataclass
class Result:
    accepted: bool
    statement: str
    proof: str
    module: str
    witness: str | None = None
    violations: list[Violation] = field(default_factory=list)
    axioms: list[str] = field(default_factory=list)
    replayed_modules: list[str] = field(default_factory=list)
    replay_reused: list[str] = field(default_factory=list)
    toolchain: str = ""
    lock_sha256: str = ""
    proof_file_sha256: str = ""

    def codes(self) -> list[str]:
        return [v.code for v in self.violations]

    def to_json(self) -> str:
        return json.dumps(asdict(self), indent=2, sort_keys=True)


def lake_exe() -> str:
    for candidate in (shutil.which("lake"), Path.home() / ".elan" / "bin" / "lake.exe"):
        if candidate and Path(candidate).is_file():
            return str(candidate)
    raise ToolError("lake not found; install elan (see CLAUDE.md)")


def run(cmd: list[str], cwd: Path, timeout: int = 1800) -> subprocess.CompletedProcess[str]:
    return subprocess.run(cmd, cwd=cwd, capture_output=True, text=True, encoding="utf-8",
                          errors="replace", timeout=timeout, env=os.environ.copy())


def toolchain_of(project: Path) -> str:
    return (project / "lean-toolchain").read_text(encoding="utf-8").strip()


@functools.cache
def checker_exe() -> Path:
    """Build leancheck if needed and return its path."""
    exe = CHECKER_DIR / ".lake" / "build" / "bin" / ("leancheck.exe" if os.name == "nt" else "leancheck")
    proc = run([lake_exe(), "build"], cwd=CHECKER_DIR)
    if proc.returncode != 0 or not exe.is_file():
        raise ToolError(f"building leancheck failed:\n{proc.stdout[-4000:]}{proc.stderr[-4000:]}")
    return exe


def module_file(project: Path, module: str) -> Path:
    return project.joinpath(*module.split(".")).with_suffix(".lean")


# Modules that replayed cleanly in this process. Replay costs about 5 s per
# module whatever its size (measured 2026-11-07), and most checks share the
# spec modules. The key covers the toolchain and the hash of every Spec and
# Proofs .olean built in the project, so any rebuild invalidates it. In
# memory only: a cache on disk could be forged to skip replay.
_replayed_ok: set[tuple] = set()


def built_oleans(project: Path) -> tuple[tuple[str, str], ...]:
    lib = project / ".lake" / "build" / "lib" / "lean"
    files = [lib / "Spec.olean", lib / "Proofs.olean",
             *lib.glob("Spec/**/*.olean"), *lib.glob("Proofs/**/*.olean")]
    return tuple(sorted((f.relative_to(lib).as_posix(), speclock.sha256_file(f)) for f in files if f.is_file()))


def replay(lake: str, project: Path, modules: list[str], toolchain: str) -> tuple[list[str], list[str]]:
    """Kernel-replay each module. Returns (failure reports, modules reused)."""
    env_key = (toolchain, built_oleans(project))
    failures, reused = [], []
    for m in modules:
        if (env_key, m) in _replayed_ok:
            reused.append(m)
            continue
        proc = run([lake, "env", "leanchecker", m], cwd=project)
        if proc.returncode == 0:
            _replayed_ok.add((env_key, m))
        else:
            failures.append(f"{m}: {(proc.stdout + proc.stderr)[-4000:]}")
    return failures, reused


def check(project: Path, statement: str, proof: str, module: str) -> Result:
    project = project.resolve()
    result = Result(accepted=False, statement=statement, proof=proof, module=module)

    def reject(code: str, detail: str) -> Result:
        result.violations.append(Violation(code, detail))
        return result

    # 1. Spec lock.
    lock = speclock.verify(project)
    if not lock.ok:
        return reject("spec_lock_mismatch", lock.describe())
    result.lock_sha256 = speclock.lock_digest(project)

    # 2. Toolchain.
    result.toolchain = toolchain_of(project)
    if result.toolchain != toolchain_of(CHECKER_DIR):
        raise ToolError(f"target toolchain {result.toolchain!r} differs from checker's "
                        f"{toolchain_of(CHECKER_DIR)!r}")

    source = module_file(project, module)
    if not source.is_file():
        return reject("proof_module_missing", f"{source} not found")
    result.proof_file_sha256 = speclock.sha256_file(source)

    # 3. Build.
    exe = checker_exe()
    lake = lake_exe()
    proc = run([lake, "build"], cwd=project)
    if proc.returncode != 0:
        return reject("build_failed", (proc.stdout + proc.stderr)[-4000:])

    # 4. Inspect the environment.
    proc = run([lake, "env", str(exe), module, statement, proof], cwd=project)
    try:
        report = json.loads(proc.stdout.strip().splitlines()[-1])
    except (IndexError, json.JSONDecodeError) as e:
        raise ToolError(f"leancheck gave no JSON (exit {proc.returncode}):\n{proc.stdout}{proc.stderr}") from e
    if "error" in report:
        raise ToolError(f"leancheck could not run: {report['error']}")
    result.axioms = report["axioms"]
    result.violations += [Violation(v["code"], v["detail"]) for v in report["violations"]]

    # 5. Kernel replay of every module of ours that the proof's environment loads.
    modules = report["our_modules"]
    failures, result.replay_reused = replay(lake, project, modules, result.toolchain)
    result.replayed_modules = modules
    for failure in failures:
        result.violations.append(Violation("kernel_replay_failed", failure))

    # 6. Independent second kernel over the proof, the witness and everything they use.
    codes = result.codes()
    result.witness = report.get("witness")
    decls = [] if "proof_missing" in codes else [proof]
    if result.witness and "vacuity_witness_missing" not in codes:
        decls.append(result.witness)
    if decls:
        failure = second_kernel(lake, project, module, decls)
        if failure:
            result.violations.append(Violation("second_kernel_failed", failure))

    result.accepted = not result.violations
    return result


def second_kernel(lake: str, project: Path, module: str, decls: list[str]) -> str | None:
    """Export `decls` and their dependencies, and check them with con-leche.
    Returns a failure report, or None if accepted."""
    with tempfile.TemporaryDirectory(prefix="burden-of-proof-export-") as tmp:
        export = Path(tmp) / "export.ndjson"
        with export.open("w", encoding="utf-8") as out:
            proc = subprocess.run([lake, "env", "leanexport", module, "--", *decls], cwd=project,
                                  stdout=out, stderr=subprocess.PIPE, text=True, encoding="utf-8",
                                  errors="replace", timeout=1800)
        if proc.returncode != 0:
            return f"leanexport failed: {proc.stderr[-4000:]}"
        proc = run([lake, "env", "con-leche", str(export)], cwd=project)
        if proc.returncode != 0:
            return (proc.stdout + proc.stderr)[-4000:]
    return None


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(prog="python -m burden_of_proof.leancheck")
    ap.add_argument("--project", type=Path, required=True)
    ap.add_argument("--statement", required=True, help="Prop definition in the spec, e.g. Spec.conserve")
    ap.add_argument("--proof", required=True, help="theorem proving it, e.g. Proofs.Attach.t")
    ap.add_argument("--module", required=True, help="module that defines the proof, e.g. Proofs.Attach")
    args = ap.parse_args(argv)
    try:
        result = check(args.project, args.statement, args.proof, args.module)
    except ToolError as e:
        print(f"error: {e}", file=sys.stderr)
        return 2
    print(result.to_json())
    return 0 if result.accepted else 1


if __name__ == "__main__":
    sys.exit(main())
