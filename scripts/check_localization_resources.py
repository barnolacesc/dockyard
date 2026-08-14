#!/usr/bin/env python3
# ABOUTME: Verifies project.yml bundles every supported Dockyard localization resource.
# ABOUTME: Fails on missing, duplicate, or incorrectly phased strings declarations.
"""Check deterministic localization resource membership in project.yml."""

from __future__ import annotations

import argparse
from pathlib import Path
from typing import Sequence


SUPPORTED_LOCALES = ("en", "ca", "de", "es", "sv")
LOCALIZATION_FILENAMES = ("InfoPlist.strings", "Localizable.strings")
REQUIRED_LOCALIZATION_RESOURCES = tuple(
    f"Localization/{locale}.lproj/{filename}"
    for locale in SUPPORTED_LOCALES
    for filename in LOCALIZATION_FILENAMES
)


def _decode_scalar(value: str) -> str:
    value = value.strip()
    if len(value) >= 2 and value[0] == value[-1] and value[0] in ("'", '"'):
        return value[1:-1]
    return value


def _dockyard_source_declarations(
    manifest: str,
) -> tuple[list[tuple[str, str | None]], bool]:
    declarations: list[tuple[str, str | None]] = []
    in_targets = False
    in_dockyard = False
    in_sources = False
    sources_found = False
    current_index: int | None = None

    for raw_line in manifest.splitlines():
        stripped = raw_line.strip()
        if not stripped or stripped.startswith("#"):
            continue
        indentation = len(raw_line) - len(raw_line.lstrip(" "))

        if indentation == 0:
            in_targets = stripped == "targets:"
            in_dockyard = False
            in_sources = False
            current_index = None
            continue

        if not in_targets:
            continue

        if indentation == 2 and stripped.endswith(":"):
            in_dockyard = stripped == "Dockyard:"
            in_sources = False
            current_index = None
            continue

        if not in_dockyard:
            continue

        if indentation == 4:
            in_sources = stripped == "sources:"
            sources_found = sources_found or in_sources
            current_index = None
            continue

        if not in_sources:
            continue

        if indentation == 6 and stripped.startswith("- path:"):
            path = _decode_scalar(stripped.removeprefix("- path:"))
            declarations.append((path, None))
            current_index = len(declarations) - 1
            continue

        if (
            current_index is not None
            and indentation >= 8
            and stripped.startswith("buildPhase:")
        ):
            path, _ = declarations[current_index]
            build_phase = _decode_scalar(stripped.removeprefix("buildPhase:"))
            declarations[current_index] = (path, build_phase)

    return declarations, sources_found


def check_localization_resources(project_manifest: Path) -> list[str]:
    """Return deterministic errors for Dockyard localization bundle membership."""

    try:
        manifest = project_manifest.read_text(encoding="utf-8")
    except (OSError, UnicodeError) as error:
        return [f"project.yml: {error}"]

    declarations, sources_found = _dockyard_source_declarations(manifest)
    if not sources_found:
        return ["project.yml: missing targets.Dockyard.sources"]

    errors: list[str] = []
    for required_path in REQUIRED_LOCALIZATION_RESOURCES:
        matches = [
            build_phase
            for path, build_phase in declarations
            if path == required_path
        ]
        if not matches:
            errors.append(f"missing Dockyard resource declaration: {required_path}")
        elif len(matches) > 1:
            errors.append(
                "duplicate Dockyard resource declaration "
                f"({len(matches)} entries): {required_path}"
            )
        elif matches[0] != "resources":
            errors.append(
                f"Dockyard declaration must use buildPhase: resources: {required_path}"
            )

    return errors


def main(argv: Sequence[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="Check Dockyard localization resource membership in project.yml."
    )
    parser.add_argument(
        "--project-manifest",
        type=Path,
        default=Path(__file__).resolve().parent.parent / "project.yml",
    )
    arguments = parser.parse_args(argv)

    errors = check_localization_resources(arguments.project_manifest)
    if errors:
        for error in errors:
            print(f"ERROR: {error}")
        return 1

    print(
        "Localization resource membership verified: "
        f"{len(REQUIRED_LOCALIZATION_RESOURCES)} entries across "
        f"{', '.join(SUPPORTED_LOCALES)}."
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
