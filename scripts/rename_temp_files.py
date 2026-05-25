#!/usr/bin/env python3
"""Legacy/manual-only temp file renamer.

This tool used to scan the repository temp directory and rename matching files
immediately. It is now intentionally explicit and dry-run by default. Pass a
target directory and use --apply only after reviewing the planned renames.
"""

from __future__ import annotations

import argparse
from pathlib import Path


RULES = [
    ("启动 (Start)", "cat_rush_start_loop"),
    ("基础待机 (Idle Loop)", "cat_idle_loop"),
    ("打完工累瘫", "cat_work_exhausted"),
    ("登基仪式系列", "cat_coronation"),
    ("打工成功", "cat_work_success"),
]


def target_name(filename: str) -> str | None:
    new_base_name = None
    for keyword, name in RULES:
        if keyword in filename:
            new_base_name = name
            break

    if not new_base_name:
        return None

    path = Path(filename)
    name_body = path.stem
    suffix = ""
    if name_body.endswith("_video"):
        suffix = "_video"
    elif name_body.endswith("_audio"):
        suffix = "_audio"
    elif "_clean" in name_body:
        suffix = "_clean"

    return f"{new_base_name}{suffix}{path.suffix}"


def iter_files(target_dir: Path) -> list[Path]:
    return sorted(path for path in target_dir.iterdir() if path.is_file())


def rename_files(target_dir: Path, apply: bool) -> int:
    if not target_dir.exists():
        print(f"ERROR: target directory does not exist: {target_dir}")
        return 2
    if not target_dir.is_dir():
        print(f"ERROR: target path is not a directory: {target_dir}")
        return 2

    planned: list[tuple[Path, Path]] = []
    skipped = 0

    for file_path in iter_files(target_dir):
        new_filename = target_name(file_path.name)
        if not new_filename:
            continue

        new_path = file_path.with_name(new_filename)
        if file_path == new_path:
            skipped += 1
            continue
        if new_path.exists():
            print(f"SKIP collision: {file_path.name} -> {new_filename}")
            skipped += 1
            continue
        planned.append((file_path, new_path))

    mode = "APPLY" if apply else "DRY-RUN"
    print(f"{mode}: {target_dir}")
    print(f"Planned renames: {len(planned)}")
    if skipped:
        print(f"Skipped: {skipped}")

    for old_path, new_path in planned:
        print(f"  {old_path.name} -> {new_path.name}")
        if apply:
            old_path.rename(new_path)

    if not planned:
        print("No matching files found.")
    elif not apply:
        print("No files changed. Re-run with --apply to rename.")

    return 0


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Legacy/manual-only renamer for selected temp media filenames. "
            "Requires an explicit target directory and defaults to dry-run."
        )
    )
    parser.add_argument(
        "target_dir",
        type=Path,
        help="Directory whose immediate child files should be inspected.",
    )
    parser.add_argument(
        "--apply",
        action="store_true",
        help="Actually rename files. Omit this flag for dry-run.",
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    return rename_files(args.target_dir.expanduser(), args.apply)


if __name__ == "__main__":
    raise SystemExit(main())
