#!/usr/bin/env python3
"""Audit Swift source files for user-facing string literal candidates.

The tool is intentionally conservative. It reports string literals that contain
CJK characters and leaves final ownership decisions to the caller because this
codebase also contains comments, logs, AI prompts, and user-data examples.
"""

from __future__ import annotations

import argparse
import csv
import re
from pathlib import Path


DEFAULT_SCOPES = ("ItemManager/Views", "ItemManager/Components")
HAN_RE = re.compile(r"[\u3400-\u4dbf\u4e00-\u9fff\uf900-\ufaff]")
SWIFT_STRING_RE = re.compile(r'"(?:\\.|[^"\\])*"')
LOCALIZED_MARKERS = (
    ".appLocalized",
    "String(localized:",
    "NSLocalizedString(",
    "LocalizedStringResource(",
)
NON_UI_MARKERS = (
    "print(",
    "AppLogger.",
    "logger.",
    "//",
)


def iter_swift_files(scopes: list[Path]) -> list[Path]:
    files: list[Path] = []
    for scope in scopes:
        if scope.is_file() and scope.suffix == ".swift":
            files.append(scope)
        elif scope.is_dir():
            files.extend(path for path in scope.rglob("*.swift") if path.is_file())
    return sorted(set(files))


def classify_line(line: str) -> str:
    if any(marker in line for marker in LOCALIZED_MARKERS):
        return "localized"
    if any(marker in line.lstrip() for marker in NON_UI_MARKERS):
        return "low-priority"
    return "candidate"


def audit_file(path: Path) -> list[dict[str, str]]:
    rows: list[dict[str, str]] = []
    try:
        lines = path.read_text(encoding="utf-8").splitlines()
    except UnicodeDecodeError:
        lines = path.read_text(encoding="utf-8", errors="replace").splitlines()

    for index, line in enumerate(lines, start=1):
        literals = [match.group(0) for match in SWIFT_STRING_RE.finditer(line)]
        if not any(HAN_RE.search(literal) for literal in literals):
            continue

        rows.append(
            {
                "file": str(path),
                "line": str(index),
                "status": classify_line(line),
                "snippet": line.strip(),
            }
        )
    return rows


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Find Swift string literal lines containing CJK characters."
    )
    parser.add_argument(
        "scopes",
        nargs="*",
        default=list(DEFAULT_SCOPES),
        help="Swift files or directories to scan.",
    )
    parser.add_argument(
        "--csv",
        dest="csv_path",
        help="Write detailed rows to a CSV file.",
    )
    parser.add_argument(
        "--show",
        choices=("all", "candidate", "localized", "low-priority"),
        default="candidate",
        help="Which rows to print to stdout.",
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    scopes = [Path(scope) for scope in args.scopes]
    files = iter_swift_files(scopes)

    rows: list[dict[str, str]] = []
    for file_path in files:
        rows.extend(audit_file(file_path))

    counts: dict[str, int] = {"candidate": 0, "localized": 0, "low-priority": 0}
    for row in rows:
        counts[row["status"]] = counts.get(row["status"], 0) + 1

    print(f"files_scanned={len(files)}")
    print(f"literal_lines={len(rows)}")
    for status in ("candidate", "localized", "low-priority"):
        print(f"{status}={counts.get(status, 0)}")

    visible_rows = rows if args.show == "all" else [row for row in rows if row["status"] == args.show]
    for row in visible_rows:
        print(f"{row['file']}:{row['line']} [{row['status']}] {row['snippet']}")

    if args.csv_path:
        csv_path = Path(args.csv_path)
        csv_path.parent.mkdir(parents=True, exist_ok=True)
        with csv_path.open("w", newline="", encoding="utf-8") as handle:
            writer = csv.DictWriter(handle, fieldnames=("file", "line", "status", "snippet"))
            writer.writeheader()
            writer.writerows(rows)
        print(f"csv={csv_path}")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
