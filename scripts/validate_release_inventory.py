#!/usr/bin/env python3
# Copyright (c) 2026 Dmitry Yarygin
# SPDX-License-Identifier: GPL-3.0-or-later

"""Reject unreviewed SwiftPM dependencies and distributable binary assets."""

import json
import subprocess
import sys
from pathlib import Path


REPOSITORY_ROOT = Path(__file__).resolve().parent.parent
REVIEW_FILE = REPOSITORY_ROOT / "docs" / "release-provenance.json"
RESOURCE_ROOT = REPOSITORY_ROOT / "PulseFiles" / "Resources"
ASSET_SUFFIXES = {
    ".icns", ".png", ".jpg", ".jpeg", ".gif", ".webp", ".pdf", ".svg",
    ".ttf", ".otf", ".woff", ".woff2", ".mp3", ".m4a", ".wav", ".mov",
    ".mp4", ".zip",
}
REQUIRED_COMPONENT_FIELDS = {
    "name", "versionSource", "license", "attributionRequirements",
    "bundleLicenseText",
}
REQUIRED_ASSET_FIELDS = {
    "path", "creatorRightsholder", "versionSource", "license",
    "attributionRequirements", "bundleLicenseText",
}


def fail(message: str) -> None:
    print(f"release inventory: {message}", file=sys.stderr)
    raise SystemExit(1)


def validate_records(records: list[dict], required: set[str], label: str) -> None:
    for record in records:
        missing = required - record.keys()
        if missing:
            fail(f"{label} record is missing fields {sorted(missing)}: {record}")
        for field in required - {"bundleLicenseText"}:
            if not isinstance(record[field], str) or not record[field].strip():
                fail(f"{label} record has an empty {field}: {record}")
        if not isinstance(record["bundleLicenseText"], bool):
            fail(f"{label} record bundleLicenseText must be true or false: {record}")


def swift_dependencies() -> set[str]:
    result = subprocess.run(
        ["swift", "package", "show-dependencies", "--format", "json"],
        cwd=REPOSITORY_ROOT,
        check=True,
        text=True,
        stdout=subprocess.PIPE,
    )
    root = json.loads(result.stdout)
    found: set[str] = set()

    def visit(node: dict) -> None:
        for dependency in node.get("dependencies", []):
            found.add(dependency["identity"])
            visit(dependency)

    visit(root)
    return found


def distributable_assets() -> set[str]:
    return {
        path.relative_to(REPOSITORY_ROOT).as_posix()
        for path in RESOURCE_ROOT.rglob("*")
        if path.is_file() and path.suffix.lower() in ASSET_SUFFIXES
    }


def main() -> None:
    review = json.loads(REVIEW_FILE.read_text(encoding="utf-8"))
    dependencies = review.get("swiftPackageDependencies", [])
    assets = review.get("assets", [])
    validate_records(dependencies, REQUIRED_COMPONENT_FIELDS, "dependency")
    validate_records(assets, REQUIRED_ASSET_FIELDS, "asset")

    reviewed_dependencies = {item["name"] for item in dependencies}
    actual_dependencies = swift_dependencies()
    if actual_dependencies != reviewed_dependencies:
        fail(
            "SwiftPM dependency review differs: "
            f"unreviewed={sorted(actual_dependencies - reviewed_dependencies)}, "
            f"stale={sorted(reviewed_dependencies - actual_dependencies)}"
        )

    reviewed_assets = {item["path"] for item in assets}
    actual_assets = distributable_assets()
    if actual_assets != reviewed_assets:
        fail(
            "asset review differs: "
            f"unreviewed={sorted(actual_assets - reviewed_assets)}, "
            f"stale={sorted(reviewed_assets - actual_assets)}"
        )

    print(
        f"Release inventory reviewed: {len(actual_dependencies)} SwiftPM "
        f"dependencies, {len(actual_assets)} distributable non-source assets."
    )


if __name__ == "__main__":
    main()
