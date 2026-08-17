#!/usr/bin/env python3
# ABOUTME: Tests localization resource membership validation for project.yml.
# ABOUTME: Covers complete, missing, duplicate, and non-resource declarations.
"""Tests for check_localization_resources.py."""

import tempfile
from pathlib import Path

from check_localization_resources import (
    REQUIRED_LOCALIZATION_RESOURCES,
    check_localization_resources,
)


def manifest_for(paths: list[tuple[str, str]]) -> str:
    source_entries = "\n".join(
        f"      - path: {path}\n        buildPhase: {build_phase}"
        for path, build_phase in paths
    )
    return f"""name: Fixture
targets:
  Dockyard:
    type: application
    sources:
{source_entries}
    settings:
      base:
        PRODUCT_NAME: Dockyard
  DockyardTests:
    type: bundle.unit-test
    sources:
      - path: Tests
"""


def complete_resources() -> list[tuple[str, str]]:
    return [(path, "resources") for path in REQUIRED_LOCALIZATION_RESOURCES]


def check_manifest(contents: str) -> list[str]:
    with tempfile.TemporaryDirectory() as temporary_directory:
        path = Path(temporary_directory) / "project.yml"
        path.write_text(contents, encoding="utf-8")
        return check_localization_resources(path)


def test_complete_supported_locale_resources_pass() -> None:
    assert check_manifest(manifest_for(complete_resources())) == []


def test_missing_locale_declarations_are_reported() -> None:
    resources = [
        entry
        for entry in complete_resources()
        if not entry[0].startswith("Localization/ca.lproj/")
    ]
    assert check_manifest(manifest_for(resources)) == [
        "missing Dockyard resource declaration: "
        "Localization/ca.lproj/InfoPlist.strings",
        "missing Dockyard resource declaration: "
        "Localization/ca.lproj/Localizable.strings",
    ]


def test_missing_resource_declaration_is_reported() -> None:
    missing_path = "Localization/de.lproj/InfoPlist.strings"
    resources = [entry for entry in complete_resources() if entry[0] != missing_path]
    assert check_manifest(manifest_for(resources)) == [
        f"missing Dockyard resource declaration: {missing_path}"
    ]


def test_duplicate_resource_declaration_is_reported() -> None:
    duplicate_path = "Localization/sv.lproj/Localizable.strings"
    resources = complete_resources() + [(duplicate_path, "resources")]
    assert check_manifest(manifest_for(resources)) == [
        f"duplicate Dockyard resource declaration (2 entries): {duplicate_path}"
    ]


def test_non_resource_build_phase_is_reported() -> None:
    wrong_phase_path = "Localization/es.lproj/InfoPlist.strings"
    resources = [
        (path, "sources" if path == wrong_phase_path else build_phase)
        for path, build_phase in complete_resources()
    ]
    assert check_manifest(manifest_for(resources)) == [
        f"Dockyard declaration must use buildPhase: resources: {wrong_phase_path}"
    ]


def test_repository_manifest_has_complete_resource_membership() -> None:
    repository_root = Path(__file__).resolve().parent.parent

    assert check_localization_resources(repository_root / "project.yml") == []


if __name__ == "__main__":
    tests = [
        test_complete_supported_locale_resources_pass,
        test_missing_locale_declarations_are_reported,
        test_missing_resource_declaration_is_reported,
        test_duplicate_resource_declaration_is_reported,
        test_non_resource_build_phase_is_reported,
        test_repository_manifest_has_complete_resource_membership,
    ]
    for test in tests:
        test()
        print(f"PASS: {test.__name__}")
