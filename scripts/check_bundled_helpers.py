#!/usr/bin/env python3
# ABOUTME: Verifies Dockyard's runtime helpers are regular executable bundle files.
# ABOUTME: Fails macOS CI when dy-run or dy-agent-state is missing or unusable.
"""Check required helper executables in a built Dockyard app bundle."""

from __future__ import annotations

import argparse
import stat
from pathlib import Path
from typing import Sequence


REQUIRED_HELPERS = ("dy-run", "dy-agent-state")


def check_bundled_helpers(app_bundle: Path) -> list[str]:
    """Return deterministic errors for missing or unusable bundled helpers."""

    if not app_bundle.is_dir():
        return [f"app bundle is not a directory: {app_bundle}"]

    errors: list[str] = []
    helpers_directory = app_bundle / "Contents" / "Helpers"
    for helper_name in REQUIRED_HELPERS:
        helper_path = helpers_directory / helper_name
        try:
            mode = helper_path.lstat().st_mode
        except OSError:
            errors.append(f"missing bundled helper: {helper_path}")
            continue

        if not stat.S_ISREG(mode):
            errors.append(f"bundled helper is not a regular file: {helper_path}")
            continue

        if mode & 0o111 == 0:
            errors.append(f"bundled helper is not executable: {helper_path}")

    return errors


def main(argv: Sequence[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="Check Dockyard's required bundled helper executables."
    )
    parser.add_argument(
        "--app-bundle",
        type=Path,
        required=True,
        help="Path to the built Dockyard .app bundle.",
    )
    arguments = parser.parse_args(argv)

    errors = check_bundled_helpers(arguments.app_bundle)
    if errors:
        for error in errors:
            print(f"ERROR: {error}")
        return 1

    print(
        "Bundled helpers verified: "
        + ", ".join(REQUIRED_HELPERS)
        + "."
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
