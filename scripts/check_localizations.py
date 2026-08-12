#!/usr/bin/env python3
# ABOUTME: Verifies app-string and privacy-prompt key parity across supported locales.
# ABOUTME: Parses Apple strings files without dependencies and fails on malformed syntax.
"""Check Dockyard Apple strings resources for deterministic key parity."""

from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Sequence


SUPPORTED_LOCALES = ("en", "ca", "de", "es", "sv")
RESOURCE_FILENAMES = ("Localizable.strings", "InfoPlist.strings")
BASELINE_FILENAME = "key-parity-baseline.json"


class StringsSyntaxError(ValueError):
    """Raised when an Apple strings file cannot be parsed safely."""


class StringsParser:
    def __init__(self, text: str, source: str) -> None:
        self.text = text
        self.source = source
        self.index = 0

    def parse_keys(self) -> set[str]:
        keys: set[str] = set()
        self._skip_ignored()
        while not self._at_end:
            key = self._read_quoted("localization key")
            self._skip_ignored()
            self._expect("=")
            self._skip_ignored()
            self._read_quoted("localized value")
            self._skip_ignored()
            self._expect(";")

            keys.add(key)
            self._skip_ignored()
        return keys

    @property
    def _at_end(self) -> bool:
        return self.index >= len(self.text)

    @property
    def _line(self) -> int:
        return self.text.count("\n", 0, self.index) + 1

    def _fail(self, message: str) -> None:
        raise StringsSyntaxError(f"{self.source}:{self._line}: {message}")

    def _skip_ignored(self) -> None:
        while not self._at_end:
            if self.text[self.index].isspace():
                self.index += 1
                continue
            if self.text.startswith("//", self.index):
                newline = self.text.find("\n", self.index + 2)
                self.index = len(self.text) if newline == -1 else newline + 1
                continue
            if self.text.startswith("/*", self.index):
                comment_end = self.text.find("*/", self.index + 2)
                if comment_end == -1:
                    self._fail("unterminated block comment")
                self.index = comment_end + 2
                continue
            return

    def _expect(self, character: str) -> None:
        if self._at_end or self.text[self.index] != character:
            self._fail(f"expected {character!r}")
        self.index += 1

    def _read_quoted(self, description: str) -> str:
        if self._at_end or self.text[self.index] != '"':
            self._fail(f"expected quoted {description}")
        self.index += 1
        result: list[str] = []

        while not self._at_end:
            character = self.text[self.index]
            self.index += 1
            if character == '"':
                return "".join(result)
            if character != "\\":
                result.append(character)
                continue
            if self._at_end:
                self._fail(f"unterminated escape in {description}")

            escaped = self.text[self.index]
            self.index += 1
            if escaped in ("u", "U"):
                result.append(self._read_unicode_escape(description))
            elif escaped in "01234567":
                result.append(self._read_octal_escape(escaped))
            else:
                result.append(
                    {
                        '"': '"',
                        "\\": "\\",
                        "n": "\n",
                        "r": "\r",
                        "t": "\t",
                    }.get(escaped, escaped)
                )

        self._fail(f"unterminated quoted {description}")
        raise AssertionError("unreachable")

    def _read_unicode_escape(self, description: str) -> str:
        digits = self.text[self.index : self.index + 4]
        if len(digits) != 4 or any(
            character not in "0123456789abcdefABCDEF" for character in digits
        ):
            self._fail(f"invalid Unicode escape in {description}")
        self.index += 4
        return chr(int(digits, 16))

    def _read_octal_escape(self, first_digit: str) -> str:
        digits = first_digit
        while len(digits) < 3 and not self._at_end and self.text[self.index] in "01234567":
            digits += self.text[self.index]
            self.index += 1
        return chr(int(digits, 8))


def parse_strings(text: str, source: str = "<string>") -> set[str]:
    """Return the decoded key set from an Apple strings file."""

    return StringsParser(text, source).parse_keys()


def _locale_path(
    localization_directory: Path,
    locale: str,
    filename: str = "Localizable.strings",
) -> Path:
    return localization_directory / f"{locale}.lproj" / filename


def _display_keys(keys: set[str]) -> str:
    return ", ".join(sorted(keys))


def _load_baseline(
    localization_directory: Path,
) -> tuple[dict[str, dict[str, set[str]]], list[str]]:
    baseline_path = localization_directory / BASELINE_FILENAME
    if not baseline_path.is_file():
        return {}, []

    try:
        raw_baseline = json.loads(baseline_path.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError) as error:
        return {}, [f"baseline: {error}"]

    if not isinstance(raw_baseline, dict):
        return {}, ["baseline: top-level value must be an object"]

    baseline: dict[str, dict[str, set[str]]] = {}
    errors: list[str] = []
    for locale, entry in sorted(raw_baseline.items()):
        if locale not in SUPPORTED_LOCALES[1:]:
            errors.append(f"baseline: unsupported locale {locale!r}")
            continue
        if not isinstance(entry, dict) or set(entry) != {"missing", "extra"}:
            errors.append(
                f"baseline: {locale} must contain only 'missing' and 'extra' arrays"
            )
            continue
        if not all(
            isinstance(entry[kind], list)
            and all(isinstance(key, str) for key in entry[kind])
            for kind in ("missing", "extra")
        ):
            errors.append(f"baseline: {locale} entries must be arrays of strings")
            continue
        baseline[locale] = {
            "missing": set(entry["missing"]),
            "extra": set(entry["extra"]),
        }
    return baseline, errors


def check_localizations(localization_directory: Path) -> list[str]:
    """Return deterministic key-drift errors for every supported locale."""

    baseline, errors = _load_baseline(localization_directory)
    if errors:
        return errors

    for filename in RESOURCE_FILENAMES:
        reference_path = _locale_path(localization_directory, "en", filename)
        if not reference_path.is_file():
            errors.append(f"en: missing Localization/en.lproj/{filename}")
            continue

        reference_label = (
            "en" if filename == "Localizable.strings" else f"en {filename}"
        )
        try:
            reference_keys = parse_strings(
                reference_path.read_text(encoding="utf-8"), str(reference_path)
            )
        except (OSError, UnicodeError, StringsSyntaxError) as error:
            errors.append(f"{reference_label}: {error}")
            continue

        for locale in SUPPORTED_LOCALES[1:]:
            locale_path = _locale_path(localization_directory, locale, filename)
            if not locale_path.is_file():
                errors.append(
                    f"{locale}: missing Localization/{locale}.lproj/{filename}"
                )
                continue
            label = (
                locale
                if filename == "Localizable.strings"
                else f"{locale} {filename}"
            )
            try:
                locale_keys = parse_strings(
                    locale_path.read_text(encoding="utf-8"), str(locale_path)
                )
            except (OSError, UnicodeError, StringsSyntaxError) as error:
                errors.append(f"{label}: {error}")
                continue

            missing = reference_keys - locale_keys
            extra = locale_keys - reference_keys
            resource_baseline = (
                baseline if filename == "Localizable.strings" else {}
            )
            expected_missing = resource_baseline.get(locale, {}).get("missing", set())
            expected_extra = resource_baseline.get(locale, {}).get("extra", set())
            new_missing = missing - expected_missing
            new_extra = extra - expected_extra
            resolved_missing = expected_missing - missing
            resolved_extra = expected_extra - extra
            if new_missing:
                errors.append(f"{label}: missing keys: {_display_keys(new_missing)}")
            if new_extra:
                errors.append(f"{label}: extra keys: {_display_keys(new_extra)}")
            if resolved_missing:
                errors.append(
                    f"{label}: remove resolved missing keys from {BASELINE_FILENAME}: "
                    f"{_display_keys(resolved_missing)}"
                )
            if resolved_extra:
                errors.append(
                    f"{label}: remove resolved extra keys from {BASELINE_FILENAME}: "
                    f"{_display_keys(resolved_extra)}"
                )

    return errors


def main(argv: Sequence[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="Check Dockyard Apple strings resource key drift."
    )
    parser.add_argument(
        "--localization-directory",
        type=Path,
        default=Path(__file__).resolve().parent.parent / "Localization",
    )
    arguments = parser.parse_args(argv)

    errors = check_localizations(arguments.localization_directory)
    if errors:
        for error in errors:
            print(f"ERROR: {error}")
        return 1

    key_counts = []
    for filename in RESOURCE_FILENAMES:
        reference_path = _locale_path(arguments.localization_directory, "en", filename)
        key_counts.append(
            f"{len(parse_strings(reference_path.read_text(encoding='utf-8'), str(reference_path)))} "
            f"{filename} keys"
        )
    print(
        f"Localization key drift verified: {', '.join(key_counts)} across "
        f"{', '.join(SUPPORTED_LOCALES)}; known debt matches {BASELINE_FILENAME}."
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
