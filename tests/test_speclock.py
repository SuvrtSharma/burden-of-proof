"""The spec lock detects every edit to locked files (ADR-0004)."""

import shutil
from pathlib import Path

import pytest

from burden_of_proof import speclock

FIXTURE = Path(__file__).parent / "fixtures" / "lean_project"


@pytest.fixture
def project(tmp_path: Path) -> Path:
    dst = tmp_path / "proj"
    shutil.copytree(FIXTURE, dst, ignore=shutil.ignore_patterns(".lake"))
    speclock.write_lock(dst)
    return dst


def test_fresh_lock_verifies(project: Path) -> None:
    assert speclock.verify(project).ok


def test_lock_covers_spec_lakefile_and_toolchain(project: Path) -> None:
    assert speclock.locked_files(project) == ["Spec.lean", "lakefile.toml", "lean-toolchain"]


def test_missing_lock_fails(project: Path) -> None:
    (project / speclock.LOCK_NAME).unlink()
    report = speclock.verify(project)
    assert not report.ok and report.missing_lock


def test_edited_spec_fails(project: Path) -> None:
    with (project / "Spec.lean").open("a", encoding="utf-8") as f:
        f.write("\n-- harmless-looking comment\n")
    report = speclock.verify(project)
    assert not report.ok and report.changed == ["Spec.lean"]


def test_added_spec_file_fails(project: Path) -> None:
    (project / "Spec").mkdir()
    (project / "Spec" / "Extra.lean").write_text("def Spec.extra : Prop := True\n", encoding="utf-8")
    report = speclock.verify(project)
    assert not report.ok and report.added == ["Spec/Extra.lean"]


def test_removed_locked_file_fails(project: Path) -> None:
    (project / "lean-toolchain").unlink()
    report = speclock.verify(project)
    assert not report.ok and report.removed == ["lean-toolchain"]


def test_edited_lakefile_fails(project: Path) -> None:
    lakefile = project / "lakefile.toml"
    lakefile.write_text(lakefile.read_text(encoding="utf-8") + "\n# moreLeanArgs could go here\n",
                        encoding="utf-8")
    report = speclock.verify(project)
    assert not report.ok and report.changed == ["lakefile.toml"]


def test_crlf_conversion_is_a_change(project: Path) -> None:
    spec = project / "Spec.lean"
    spec.write_bytes(spec.read_bytes().replace(b"\n", b"\r\n"))
    assert speclock.verify(project).changed == ["Spec.lean"]
