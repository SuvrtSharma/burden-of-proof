"""The Lean check pipeline accepts honest proofs and rejects every cheat (ADR-0006).

These tests build a real Lake project, so the first run takes a minute or so.
"""

import shutil
from pathlib import Path

import pytest

from burden_of_proof import leancheck, speclock

FIXTURE = Path(__file__).parent / "fixtures" / "lean_project"
ALLOWED_AXIOMS = {"propext", "Classical.choice", "Quot.sound"}


@pytest.fixture(scope="module")
def project(tmp_path_factory: pytest.TempPathFactory) -> Path:
    """One built copy of the fixture, locked by the test acting as owner."""
    dst = tmp_path_factory.mktemp("lean") / "proj"
    shutil.copytree(FIXTURE, dst, ignore=shutil.ignore_patterns(".lake"))
    speclock.write_lock(dst)
    return dst


def check(project: Path, module: str, statement: str, proof: str) -> leancheck.Result:
    return leancheck.check(project, statement=statement, proof=proof, module=module)


@pytest.mark.parametrize("statement,proof", [
    ("Spec.conserve", "Proofs.Honest.conserve"),
    ("Spec.small", "Proofs.Honest.small"),
    ("Spec.refuteFalseClaim", "Proofs.Honest.refute"),
])
def test_honest_proof_is_accepted(project: Path, statement: str, proof: str) -> None:
    result = check(project, "Proofs.Honest", statement, proof)
    assert result.accepted, result.violations
    assert set(result.axioms) <= ALLOWED_AXIOMS
    assert "Proofs.Honest" in result.replayed_modules
    assert len(result.lock_sha256) == 64 and len(result.proof_file_sha256) == 64


def test_witness_is_required_for_statements_with_binders(project: Path) -> None:
    result = check(project, "Proofs.Honest", "Spec.conserve", "Proofs.Honest.conserve")
    assert result.witness == "Proofs.Honest.conserve_witness"
    no_binders = check(project, "Proofs.Honest", "Spec.small", "Proofs.Honest.small")
    assert no_binders.witness is None
    refutation = check(project, "Proofs.Honest", "Spec.refuteFalseClaim", "Proofs.Honest.refute")
    assert refutation.accepted and refutation.witness is None


@pytest.mark.parametrize("module,statement,proof,code,detail", [
    ("Proofs.Sorry", "Spec.falseClaim", "Proofs.Sorry.t", "disallowed_axiom", "sorryAx"),
    ("Proofs.Axiom", "Spec.falseClaim", "Proofs.Axiom.t", "disallowed_axiom", "Proofs.Axiom.cheat"),
    ("Proofs.NativeDecide", "Spec.small", "Proofs.NativeDecide.t", "disallowed_axiom", "native_decide"),
    ("Proofs.ImplementedBy", "Spec.conserve", "Proofs.ImplementedBy.t", "implemented_by", "Proofs.ImplementedBy.f"),
    ("Proofs.Extern", "Spec.conserve", "Proofs.Extern.t", "extern", "Proofs.Extern.g"),
    ("Proofs.OutsideSpec", "Spec.falseClaim", "Proofs.OutsideSpec.t", "proof_statement_mismatch", "Proofs.OutsideSpec.weak"),
    ("Proofs.OutsideSpec", "Proofs.OutsideSpec.weak", "Proofs.OutsideSpec.t", "statement_not_in_spec", "Proofs.OutsideSpec"),
    ("Proofs.OutsideSpec", "Spec.leaky", "Proofs.OutsideSpec.leaky", "statement_uses_outside_spec", "Proofs.Weak.weak"),
    ("Proofs.Honest", "Spec.conserve", "Proofs.Honest.nope", "proof_missing", "Proofs.Honest.nope"),
    ("Proofs.Honest", "Spec.nope", "Proofs.Honest.small", "statement_missing", "Spec.nope"),
    ("Proofs.Honest", "Spec.notProp", "Proofs.Honest.small", "statement_not_prop", "Spec.notProp"),
    ("Proofs.Honest", "Spec.small", "Spec.inSpec", "proof_not_in_proofs", "Spec.inSpec"),
    ("Proofs.NotTheorem", "Spec.small", "Proofs.NotTheorem.t", "proof_not_theorem", "Proofs.NotTheorem.t"),
    ("Proofs.Vacuous", "Spec.vacuous", "Proofs.Vacuous.t", "vacuity_witness_missing", "Proofs.Vacuous.t_witness"),
    ("Proofs.Vacuous", "Spec.vacuous", "Proofs.Vacuous.u", "vacuity_witness_mismatch", "Proofs.Vacuous.u_witness"),
    ("Proofs.Vacuous", "Spec.vacuous", "Proofs.Vacuous.v", "disallowed_axiom", "Proofs.Vacuous.v_witness"),
    ("Proofs.Nope", "Spec.small", "Proofs.Nope.t", "proof_module_missing", "Nope.lean"),
])
def test_cheat_is_rejected(project: Path, module: str, statement: str, proof: str,
                           code: str, detail: str) -> None:
    result = check(project, module, statement, proof)
    assert not result.accepted
    hits = [v for v in result.violations if v.code == code]
    assert hits, result.violations
    assert any(detail in v.detail for v in hits), hits


def test_forged_proof_is_caught_only_by_the_kernels(project: Path) -> None:
    """A false 'theorem' added under debug.skipKernelTC builds, has no axioms,
    and passes every environment check. Each kernel rejects it independently."""
    result = check(project, "Proofs.Forged", "Spec.falseClaim", "Proofs.Forged.t")
    assert not result.accepted
    assert result.codes() == ["kernel_replay_failed", "second_kernel_failed"]
    assert result.axioms == []
    assert all("Proofs.Forged.t" in v.detail for v in result.violations)


@pytest.mark.parametrize("broken,needle", [
    ("Syntax.lean", "Proofs/Syntax.lean"),
    ("Unsafe.lean", "unsafe"),
])
def test_module_that_does_not_build_is_rejected(tmp_path: Path, broken: str, needle: str) -> None:
    """Lean refuses a safe theorem that uses an unsafe definition, so `unsafe`
    can't reach the environment check; it surfaces as a build failure."""
    dst = tmp_path / "proj"
    shutil.copytree(FIXTURE, dst, ignore=shutil.ignore_patterns(".lake"))
    shutil.copy(FIXTURE.parent / "lean_broken" / broken, dst / "Proofs" / broken)
    speclock.write_lock(dst)
    module = "Proofs." + broken.removesuffix(".lean")
    result = check(dst, module, "Spec.small", module + ".t")
    assert result.codes() == ["build_failed"]
    assert needle in result.violations[0].detail


def test_edited_spec_is_rejected_before_building(tmp_path: Path) -> None:
    dst = tmp_path / "proj"
    shutil.copytree(FIXTURE, dst, ignore=shutil.ignore_patterns(".lake"))
    speclock.write_lock(dst)
    spec = dst / "Spec.lean"
    spec.write_text(spec.read_text(encoding="utf-8").replace(
        "a = a + 1", "a + 1 = a + 1"), encoding="utf-8")  # quietly make the false claim true
    result = check(dst, "Proofs.Honest", "Spec.conserve", "Proofs.Honest.conserve")
    assert result.codes() == ["spec_lock_mismatch"]
    assert not (dst / ".lake").exists()  # rejected before any build ran
