#!/usr/bin/env python3
# ABOUTME: Tests built-app helper verification with complete and unsafe fixtures.
# ABOUTME: Covers missing, non-executable, and symlinked runtime helpers.
"""Tests for check_bundled_helpers.py."""

import tempfile
from pathlib import Path

from check_bundled_helpers import REQUIRED_HELPERS, check_bundled_helpers


def create_app_bundle(root: Path) -> Path:
    app_bundle = root / "Dockyard Debug.app"
    helpers_directory = app_bundle / "Contents" / "Helpers"
    helpers_directory.mkdir(parents=True)
    for helper_name in REQUIRED_HELPERS:
        helper_path = helpers_directory / helper_name
        helper_path.write_bytes(b"fixture")
        helper_path.chmod(0o755)
    return app_bundle


def test_complete_executable_helpers_pass() -> None:
    with tempfile.TemporaryDirectory() as temporary_directory:
        app_bundle = create_app_bundle(Path(temporary_directory))

        assert check_bundled_helpers(app_bundle) == []


def test_missing_helper_is_reported() -> None:
    with tempfile.TemporaryDirectory() as temporary_directory:
        app_bundle = create_app_bundle(Path(temporary_directory))
        helper_path = app_bundle / "Contents" / "Helpers" / "dy-agent-state"
        helper_path.unlink()

        assert check_bundled_helpers(app_bundle) == [
            f"missing bundled helper: {helper_path}"
        ]


def test_non_executable_helper_is_reported() -> None:
    with tempfile.TemporaryDirectory() as temporary_directory:
        app_bundle = create_app_bundle(Path(temporary_directory))
        helper_path = app_bundle / "Contents" / "Helpers" / "dy-run"
        helper_path.chmod(0o644)

        assert check_bundled_helpers(app_bundle) == [
            f"bundled helper is not executable: {helper_path}"
        ]


def test_symlinked_helper_is_rejected() -> None:
    with tempfile.TemporaryDirectory() as temporary_directory:
        app_bundle = create_app_bundle(Path(temporary_directory))
        helper_path = app_bundle / "Contents" / "Helpers" / "dy-run"
        target_path = Path(temporary_directory) / "external-dy-run"
        target_path.write_bytes(b"fixture")
        target_path.chmod(0o755)
        helper_path.unlink()
        helper_path.symlink_to(target_path)

        assert check_bundled_helpers(app_bundle) == [
            f"bundled helper is not a regular file: {helper_path}"
        ]


if __name__ == "__main__":
    tests = [
        test_complete_executable_helpers_pass,
        test_missing_helper_is_reported,
        test_non_executable_helper_is_reported,
        test_symlinked_helper_is_rejected,
    ]
    for test in tests:
        test()
        print(f"PASS: {test.__name__}")
