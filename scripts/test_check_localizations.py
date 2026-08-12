#!/usr/bin/env python3
# ABOUTME: Tests deterministic key parity for Dockyard's Apple strings resources.
# ABOUTME: Covers app strings, privacy prompts, malformed input, and repository locales.
"""Tests for check_localizations.py."""

import os
import json
import tempfile
from pathlib import Path

from check_localizations import check_localizations, parse_strings


def write_locale(
    root: Path,
    locale: str,
    contents: str,
    filename: str = "Localizable.strings",
) -> None:
    locale_directory = root / f"{locale}.lproj"
    locale_directory.mkdir(parents=True, exist_ok=True)
    (locale_directory / filename).write_text(contents, encoding="utf-8")


def write_supported_locales(root: Path, contents: str) -> None:
    for locale in ("en", "ca", "de", "es", "sv"):
        write_locale(root, locale, contents)
        write_locale(root, locale, contents, "InfoPlist.strings")


def test_parser_handles_comments_and_escaped_strings() -> None:
    contents = r'''
        /* A block comment containing "ignored" = "ignored"; */
        "Plain" = "Value"; // A line comment
        "Quote: \" and slash: \\" = "Translated \"value\"";
        "Unicode: \U00E9" = "Unicode value";
    '''

    assert parse_strings(contents, "fixture") == {
        "Plain",
        'Quote: " and slash: \\',
        "Unicode: é",
    }


def test_matching_locale_keys_pass() -> None:
    with tempfile.TemporaryDirectory() as temporary_directory:
        root = Path(temporary_directory)
        write_supported_locales(root, '"First" = "Value";\n"Second" = "Value";\n')

        assert check_localizations(root) == []


def test_missing_and_extra_keys_are_reported() -> None:
    with tempfile.TemporaryDirectory() as temporary_directory:
        root = Path(temporary_directory)
        write_supported_locales(root, '"Shared" = "Value";\n')
        write_locale(root, "ca", '"Extra" = "Valor";\n')
        write_locale(root, "de", '"Shared" = "Wert";\n"Extra" = "Wert";\n')

        errors = check_localizations(root)

        assert errors == [
            "ca: missing keys: Shared",
            "ca: extra keys: Extra",
            "de: extra keys: Extra",
        ]


def test_missing_supported_locale_is_reported() -> None:
    with tempfile.TemporaryDirectory() as temporary_directory:
        root = Path(temporary_directory)
        write_supported_locales(root, '"Shared" = "Value";\n')
        os.remove(root / "sv.lproj" / "Localizable.strings")

        assert check_localizations(root) == [
            "sv: missing Localization/sv.lproj/Localizable.strings"
        ]


def test_missing_privacy_prompt_file_is_reported() -> None:
    with tempfile.TemporaryDirectory() as temporary_directory:
        root = Path(temporary_directory)
        write_supported_locales(root, '"NSCameraUsageDescription" = "Value";\n')
        os.remove(root / "de.lproj" / "InfoPlist.strings")

        assert check_localizations(root) == [
            "de: missing Localization/de.lproj/InfoPlist.strings"
        ]


def test_privacy_prompt_key_drift_is_reported() -> None:
    with tempfile.TemporaryDirectory() as temporary_directory:
        root = Path(temporary_directory)
        write_supported_locales(root, '"Shared" = "Value";\n')
        write_locale(
            root,
            "sv",
            '"ExtraPrivacyKey" = "Varde";\n',
            "InfoPlist.strings",
        )

        assert check_localizations(root) == [
            "sv InfoPlist.strings: missing keys: Shared",
            "sv InfoPlist.strings: extra keys: ExtraPrivacyKey",
        ]


def test_known_baseline_debt_passes_and_must_be_removed_when_resolved() -> None:
    with tempfile.TemporaryDirectory() as temporary_directory:
        root = Path(temporary_directory)
        write_supported_locales(root, '"Shared" = "Value";\n')
        write_locale(root, "de", "")
        baseline_path = root / "key-parity-baseline.json"
        baseline_path.write_text(
            json.dumps({"de": {"missing": ["Shared"], "extra": []}}),
            encoding="utf-8",
        )

        assert check_localizations(root) == []

        write_locale(root, "de", '"Shared" = "Wert";\n')
        assert check_localizations(root) == [
            "de: remove resolved missing keys from key-parity-baseline.json: Shared"
        ]


def test_malformed_strings_are_reported() -> None:
    with tempfile.TemporaryDirectory() as temporary_directory:
        root = Path(temporary_directory)
        write_supported_locales(root, '"Shared" = "Value";\n')
        write_locale(root, "es", '"Broken" = "Missing semicolon"\n')

        errors = check_localizations(root)

        assert len(errors) == 1
        assert errors[0].startswith("es: ")
        assert "expected ';'" in errors[0]


def test_malformed_privacy_prompt_strings_are_reported() -> None:
    with tempfile.TemporaryDirectory() as temporary_directory:
        root = Path(temporary_directory)
        write_supported_locales(root, '"Shared" = "Value";\n')
        write_locale(
            root,
            "ca",
            '"Broken" = "Missing semicolon"\n',
            "InfoPlist.strings",
        )

        errors = check_localizations(root)

        assert len(errors) == 1
        assert errors[0].startswith("ca InfoPlist.strings: ")
        assert "expected ';'" in errors[0]


def test_repository_locales_match_the_debt_baseline() -> None:
    repository_root = Path(__file__).resolve().parent.parent

    assert check_localizations(repository_root / "Localization") == []


if __name__ == "__main__":
    tests = [
        test_parser_handles_comments_and_escaped_strings,
        test_matching_locale_keys_pass,
        test_missing_and_extra_keys_are_reported,
        test_missing_supported_locale_is_reported,
        test_missing_privacy_prompt_file_is_reported,
        test_privacy_prompt_key_drift_is_reported,
        test_known_baseline_debt_passes_and_must_be_removed_when_resolved,
        test_malformed_strings_are_reported,
        test_malformed_privacy_prompt_strings_are_reported,
        test_repository_locales_match_the_debt_baseline,
    ]
    for test in tests:
        test()
        print(f"PASS: {test.__name__}")
