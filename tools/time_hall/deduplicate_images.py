#!/usr/bin/env python3
"""Merge duplicate Time Hall images and remove unreferenced files."""

from __future__ import annotations

import argparse
import hashlib
import json
import re
from collections import defaultdict
from pathlib import Path
from typing import Any

try:
    from PIL import Image, ImageChops, ImageOps, ImageStat
except ImportError:  # pragma: no cover - only needed for --visual
    Image = None
    ImageChops = None
    ImageOps = None
    ImageStat = None


PROJ = Path(__file__).resolve().parents[2]
CATALOG_PATH = PROJ / "ItemManager" / "Resources" / "TimeHall" / "catalog.json"
IMAGE_DIR = CATALOG_PATH.parent / "images"
VISUAL_HASH_DISTANCE = 12
VISUAL_RMS_DISTANCE = 5.0


def natural_key(name: str) -> tuple[Any, ...]:
    return tuple(int(part) if part.isdigit() else part for part in re.split(r"(\d+)", name))


def canonical_rank(name: str) -> tuple[int, tuple[Any, ...]]:
    """Prefer stable public-facing names over generated secondary names."""
    priorities = (
        "archive-catalog-",
        "ph-",
        "commerce-",
        "coordinate-",
        "story-",
        "history-",
        "news-",
    )
    prefix_rank = next(
        (index for index, prefix in enumerate(priorities) if name.startswith(prefix)),
        len(priorities),
    )
    detail_penalty = 1 if "-detail." in name else 0
    return prefix_rank * 2 + detail_penalty, natural_key(name)


def replace_image_references(value: Any, replacements: dict[str, str]) -> Any:
    if isinstance(value, dict):
        return {key: replace_image_references(item, replacements) for key, item in value.items()}
    if isinstance(value, list):
        return [replace_image_references(item, replacements) for item in value]
    if isinstance(value, str):
        return replacements.get(value, value)
    return value


def referenced_file_names(value: Any, available: set[str]) -> set[str]:
    found: set[str] = set()

    def visit(item: Any) -> None:
        if isinstance(item, dict):
            for child in item.values():
                visit(child)
        elif isinstance(item, list):
            for child in item:
                visit(child)
        elif isinstance(item, str) and item in available:
            found.add(item)

    visit(value)
    return found


def visual_fingerprint(path: Path) -> tuple[int, Any]:
    """Return a difference hash and small RGB preview for conservative comparison."""
    if Image is None or ImageOps is None:
        raise RuntimeError("Pillow is required for visual duplicate detection")
    with Image.open(path) as opened:
        image = ImageOps.exif_transpose(opened).convert("RGB")
        preview = image.resize((96, 96), Image.Resampling.LANCZOS)
        grayscale = image.resize((17, 16), Image.Resampling.LANCZOS).convert("L")
    pixels = list(grayscale.getdata())
    difference_hash = 0
    for y in range(16):
        for x in range(16):
            difference_hash = (difference_hash << 1) | int(
                pixels[y * 17 + x] > pixels[y * 17 + x + 1]
            )
    return difference_hash, preview


def visual_replacements(names: set[str], files: dict[str, Path]) -> dict[str, str]:
    """Find same-looking encodings without merging merely similar designs."""
    if ImageChops is None or ImageStat is None:
        raise RuntimeError("Pillow is required for visual duplicate detection")
    ordered = sorted(names, key=natural_key)
    fingerprints = [visual_fingerprint(files[name]) for name in ordered]
    parents = list(range(len(ordered)))

    def find(index: int) -> int:
        while parents[index] != index:
            parents[index] = parents[parents[index]]
            index = parents[index]
        return index

    def union(lhs: int, rhs: int) -> None:
        lhs_root = find(lhs)
        rhs_root = find(rhs)
        if lhs_root != rhs_root:
            parents[rhs_root] = lhs_root

    for lhs in range(len(ordered)):
        lhs_hash, lhs_preview = fingerprints[lhs]
        for rhs in range(lhs + 1, len(ordered)):
            rhs_hash, rhs_preview = fingerprints[rhs]
            if bin(lhs_hash ^ rhs_hash).count("1") > VISUAL_HASH_DISTANCE:
                continue
            channel_rms = ImageStat.Stat(ImageChops.difference(lhs_preview, rhs_preview)).rms
            combined_rms = (sum(value * value for value in channel_rms) / 3) ** 0.5
            if combined_rms <= VISUAL_RMS_DISTANCE:
                union(lhs, rhs)

    groups: dict[int, list[str]] = defaultdict(list)
    for index, name in enumerate(ordered):
        groups[find(index)].append(name)

    replacements: dict[str, str] = {}
    for names_in_group in groups.values():
        if len(names_in_group) < 2:
            continue
        canonical = min(
            names_in_group,
            key=lambda name: (files[name].stat().st_size, canonical_rank(name)),
        )
        for name in names_in_group:
            if name != canonical:
                replacements[name] = canonical
    return replacements


def resolved_replacements(replacements: dict[str, str]) -> dict[str, str]:
    def resolve(name: str) -> str:
        seen: set[str] = set()
        while name in replacements and name not in seen:
            seen.add(name)
            name = replacements[name]
        return name

    return {name: resolve(target) for name, target in replacements.items()}


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--apply", action="store_true", help="rewrite catalog and delete redundant files")
    parser.add_argument(
        "--visual",
        action="store_true",
        help="also merge conservatively matched re-encodings of the same visual",
    )
    args = parser.parse_args()

    catalog = json.loads(CATALOG_PATH.read_text(encoding="utf-8"))
    files = {path.name: path for path in IMAGE_DIR.iterdir() if path.is_file()}
    references = referenced_file_names(catalog, set(files))
    by_digest: dict[str, list[str]] = defaultdict(list)
    for name in references:
        by_digest[hashlib.sha256(files[name].read_bytes()).hexdigest()].append(name)

    exact_replacements: dict[str, str] = {}
    for names in by_digest.values():
        canonical = min(names, key=canonical_rank)
        for name in names:
            if name != canonical:
                exact_replacements[name] = canonical

    replacements = dict(exact_replacements)
    visual_merged = 0
    if args.visual:
        exact_canonical_names = references - set(exact_replacements)
        matched = visual_replacements(exact_canonical_names, files)
        visual_merged = len(matched)
        replacements.update(matched)
        replacements = resolved_replacements(replacements)

    rewritten = replace_image_references(catalog, replacements)
    retained = referenced_file_names(rewritten, set(files))
    redundant = sorted(set(files) - retained, key=natural_key)
    saved_bytes = sum(files[name].stat().st_size for name in redundant)

    print(
        "images=%d references=%d canonical=%d exact_merged=%d visual_merged=%d unreferenced=%d saved_bytes=%d"
        % (
            len(files),
            len(references),
            len(retained),
            len(exact_replacements),
            visual_merged,
            len(redundant) - len(replacements),
            saved_bytes,
        )
    )

    if not args.apply:
        return 0

    temporary = CATALOG_PATH.with_suffix(".json.tmp")
    temporary.write_text(
        json.dumps(rewritten, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    temporary.replace(CATALOG_PATH)
    for name in redundant:
        files[name].unlink()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
