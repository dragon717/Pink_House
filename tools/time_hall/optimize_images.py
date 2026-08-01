#!/usr/bin/env python3
"""Downsample only oversized Time Hall JPEGs without repeatedly recompressing them."""

from __future__ import annotations

import argparse
import json
from io import BytesIO
from pathlib import Path

from PIL import Image, ImageOps

from deduplicate_images import CATALOG_PATH, IMAGE_DIR, referenced_file_names


def optimized_jpeg(path: Path, max_dimension: int, quality: int) -> bytes | None:
    with Image.open(path) as opened:
        image = ImageOps.exif_transpose(opened).convert("RGB")
        if max(image.size) <= max_dimension:
            return None
        image.thumbnail((max_dimension, max_dimension), Image.Resampling.LANCZOS)
        output = BytesIO()
        image.save(output, "JPEG", quality=quality, optimize=True, progressive=True)
        return output.getvalue()


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--apply", action="store_true", help="replace qualifying oversized files")
    parser.add_argument("--max-dimension", type=int, default=1600)
    parser.add_argument("--quality", type=int, default=84)
    parser.add_argument("--minimum-saving-percent", type=float, default=5.0)
    args = parser.parse_args()
    if args.max_dimension < 800:
        raise SystemExit("max dimension must be at least 800 pixels")
    if not 60 <= args.quality <= 95:
        raise SystemExit("quality must be between 60 and 95")

    catalog = json.loads(CATALOG_PATH.read_text(encoding="utf-8"))
    files = {path.name: path for path in IMAGE_DIR.iterdir() if path.is_file()}
    references = referenced_file_names(catalog, set(files))
    candidates: list[tuple[Path, bytes]] = []
    oversized = 0
    for name in sorted(references):
        path = files[name]
        encoded = optimized_jpeg(path, args.max_dimension, args.quality)
        if encoded is None:
            continue
        oversized += 1
        maximum_size = path.stat().st_size * (1 - args.minimum_saving_percent / 100)
        if len(encoded) <= maximum_size:
            candidates.append((path, encoded))

    saved_bytes = sum(path.stat().st_size - len(encoded) for path, encoded in candidates)
    print(
        "images=%d oversized=%d optimized=%d saved_bytes=%d"
        % (len(references), oversized, len(candidates), saved_bytes)
    )
    if not args.apply:
        return 0

    for path, encoded in candidates:
        temporary = path.with_suffix(path.suffix + ".tmp")
        temporary.write_bytes(encoded)
        temporary.replace(path)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
