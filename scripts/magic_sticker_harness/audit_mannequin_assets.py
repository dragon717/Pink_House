#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Audit Magic Sticker / OOTD mannequin background assets.

This script is intentionally non-mutating. It checks the supplied source PNG and
the catalogued imageset used by SwiftUI so the static mannequin workflow remains
manifest-gated and does not accidentally ship transparent placeholders.
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

try:
    from PIL import Image
except Exception as exc:  # pragma: no cover - local dependency guard
    print(json.dumps({"ok": False, "error": f"Pillow unavailable: {exc}"}, ensure_ascii=False, indent=2))
    sys.exit(2)


def audit_png(path: Path) -> dict:
    if not path.exists():
        return {"path": str(path), "exists": False, "ok": False, "error": "missing"}
    image = Image.open(path).convert("RGBA")
    width, height = image.size
    alpha = image.getchannel("A")
    alpha_min, alpha_max = alpha.getextrema()
    nontransparent = sum(1 for value in alpha.getdata() if value > 0)
    total = width * height
    ratio = width / height if height else 0
    file_bytes = path.stat().st_size
    ok_ratio = abs(ratio - 0.75) <= 0.02
    ok_visible = nontransparent / total >= 0.05 if total else False
    ok_not_tiny = file_bytes >= 8 * 1024
    return {
        "path": str(path),
        "exists": True,
        "width": width,
        "height": height,
        "ratio": round(ratio, 6),
        "expected_ratio": 0.75,
        "ratio_ok": ok_ratio,
        "has_alpha": image.mode == "RGBA",
        "alpha_min": alpha_min,
        "alpha_max": alpha_max,
        "nontransparent_pixels": nontransparent,
        "nontransparent_percent": round(nontransparent / total * 100, 4) if total else 0,
        "file_bytes": file_bytes,
        "not_tiny_placeholder": ok_not_tiny,
        "visible_content_ok": ok_visible,
        "ok": ok_ratio and ok_visible and ok_not_tiny,
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--source", default="temp/人台.png")
    parser.add_argument("--asset", default="ItemManager/Assets.xcassets/OOTD/Mannequin/ootd_mannequin_default.imageset/ootd_mannequin_default.png")
    parser.add_argument("--imageset", default="ItemManager/Assets.xcassets/OOTD/Mannequin/ootd_mannequin_default.imageset")
    parser.add_argument("--out")
    args = parser.parse_args()

    source = audit_png(Path(args.source))
    asset = audit_png(Path(args.asset))
    contents_path = Path(args.imageset) / "Contents.json"
    contents_ok = False
    contents_error = None
    if contents_path.exists():
        try:
            contents = json.loads(contents_path.read_text(encoding="utf-8"))
            names = [row.get("filename") for row in contents.get("images", [])]
            contents_ok = "ootd_mannequin_default.png" in names
        except Exception as exc:
            contents_error = str(exc)
    else:
        contents_error = "Contents.json missing"

    report = {
        "ok": source.get("ok") and asset.get("ok") and contents_ok,
        "source": source,
        "asset": asset,
        "contents_json": str(contents_path),
        "contents_ok": contents_ok,
        "contents_error": contents_error,
    }
    text = json.dumps(report, ensure_ascii=False, indent=2)
    if args.out:
        Path(args.out).parent.mkdir(parents=True, exist_ok=True)
        Path(args.out).write_text(text + "\n", encoding="utf-8")
    print(text)
    return 0 if report["ok"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
