#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Create first-pass Live2D layer PNGs from the gpt-image-2 character source.

This is a bootstrap layer kit, not a replacement for a Cubism artist's PSD.
It produces transparent cropped parts plus a rig manifest so engineers can
wire motion/backends while the final overdraw PSD is being prepared.
"""
from __future__ import annotations

import json
from pathlib import Path
from typing import Dict, Tuple

from PIL import Image


SOURCE = Path("ItemManager/Assets.xcassets/AvatarCharacter/girl_v1/avatar_girl_v1_static.imageset/avatar_girl_v1_static.png")
OUT_DIR = Path("asserts/avatar/girl_v1/live2d/layers")
HARNESS_OUT_DIR = Path("temp/_live2d_avatar_harness/generated/layers")
MANIFEST = Path("asserts/avatar/girl_v1/live2d/rig_manifest.json")


# Coordinates are normalized to the current static source. The source is kept
# front-facing and padded, so these crops remain stable across 3:4 regenerations.
LAYERS: Dict[str, Dict[str, object]] = {
    "hair_back": {"bbox": (0.16, 0.04, 0.84, 0.47), "bone": "hairBack", "z": 10},
    "body_torso": {"bbox": (0.31, 0.27, 0.69, 0.57), "bone": "torso", "z": 30},
    "skirt_front": {"bbox": (0.16, 0.44, 0.84, 0.70), "bone": "skirt", "z": 50},
    "head_face": {"bbox": (0.34, 0.07, 0.66, 0.34), "bone": "head", "z": 80},
    "hair_front": {"bbox": (0.25, 0.03, 0.75, 0.33), "bone": "hairFront", "z": 90},
    "hair_side_left": {"bbox": (0.11, 0.15, 0.40, 0.48), "bone": "hairSideLeft", "z": 70},
    "hair_side_right": {"bbox": (0.60, 0.15, 0.89, 0.48), "bone": "hairSideRight", "z": 70},
    "arm_upper_left": {"bbox": (0.18, 0.31, 0.36, 0.48), "bone": "upperArmLeft", "z": 42},
    "arm_upper_right": {"bbox": (0.64, 0.31, 0.82, 0.48), "bone": "upperArmRight", "z": 42},
    "arm_lower_left": {"bbox": (0.09, 0.43, 0.32, 0.62), "bone": "lowerArmLeft", "z": 62},
    "arm_lower_right": {"bbox": (0.68, 0.43, 0.91, 0.62), "bone": "lowerArmRight", "z": 62},
    "hand_left": {"bbox": (0.07, 0.47, 0.25, 0.58), "bone": "handLeft", "z": 72},
    "hand_right": {"bbox": (0.75, 0.47, 0.93, 0.58), "bone": "handRight", "z": 72},
    "leg_left": {"bbox": (0.38, 0.61, 0.50, 0.88), "bone": "legLeft", "z": 20},
    "leg_right": {"bbox": (0.50, 0.61, 0.62, 0.88), "bone": "legRight", "z": 20},
    "foot_left": {"bbox": (0.34, 0.84, 0.51, 0.98), "bone": "footLeft", "z": 40},
    "foot_right": {"bbox": (0.49, 0.84, 0.66, 0.98), "bone": "footRight", "z": 40},
    "accessory_bows": {"bbox": (0.23, 0.02, 0.78, 0.55), "bone": "accessories", "z": 100},
}

BONES = {
    "root": {"parent": None, "anchor": (0.50, 0.53)},
    "torso": {"parent": "root", "anchor": (0.50, 0.38)},
    "head": {"parent": "torso", "anchor": (0.50, 0.20)},
    "hairBack": {"parent": "head", "anchor": (0.50, 0.16)},
    "hairFront": {"parent": "head", "anchor": (0.50, 0.13)},
    "hairSideLeft": {"parent": "head", "anchor": (0.30, 0.24)},
    "hairSideRight": {"parent": "head", "anchor": (0.70, 0.24)},
    "upperArmLeft": {"parent": "torso", "anchor": (0.32, 0.34)},
    "upperArmRight": {"parent": "torso", "anchor": (0.68, 0.34)},
    "lowerArmLeft": {"parent": "upperArmLeft", "anchor": (0.25, 0.47)},
    "lowerArmRight": {"parent": "upperArmRight", "anchor": (0.75, 0.47)},
    "handLeft": {"parent": "lowerArmLeft", "anchor": (0.18, 0.54)},
    "handRight": {"parent": "lowerArmRight", "anchor": (0.82, 0.54)},
    "skirt": {"parent": "torso", "anchor": (0.50, 0.52)},
    "legLeft": {"parent": "root", "anchor": (0.44, 0.65)},
    "legRight": {"parent": "root", "anchor": (0.56, 0.65)},
    "footLeft": {"parent": "legLeft", "anchor": (0.43, 0.90)},
    "footRight": {"parent": "legRight", "anchor": (0.57, 0.90)},
    "accessories": {"parent": "torso", "anchor": (0.50, 0.34)},
}


def pixel_bbox(norm: Tuple[float, float, float, float], width: int, height: int) -> Tuple[int, int, int, int]:
    x0, y0, x1, y1 = norm
    return (
        max(0, round(x0 * width)),
        max(0, round(y0 * height)),
        min(width, round(x1 * width)),
        min(height, round(y1 * height)),
    )


def trim_transparent(image: Image.Image) -> Image.Image:
    bbox = image.getbbox()
    if bbox is None:
        return image
    return image.crop(bbox)


def main() -> int:
    image = Image.open(SOURCE).convert("RGBA")
    width, height = image.size
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    HARNESS_OUT_DIR.mkdir(parents=True, exist_ok=True)

    layer_entries = []
    for name, spec in LAYERS.items():
        bbox = pixel_bbox(spec["bbox"], width, height)
        cropped = trim_transparent(image.crop(bbox))
        filename = f"{name}.png"
        out_path = OUT_DIR / filename
        harness_path = HARNESS_OUT_DIR / filename
        cropped.save(out_path)
        cropped.save(harness_path)
        layer_entries.append(
            {
                "name": name,
                "file": f"layers/{filename}",
                "source_bbox_normalized": spec["bbox"],
                "source_bbox_pixels": bbox,
                "size": cropped.size,
                "bone": spec["bone"],
                "z": spec["z"],
                "notes": "Bootstrap crop from gpt-image-2 full-body source; final Cubism PSD should redraw hidden overdraw behind joints.",
            }
        )

    manifest = {
        "schema_version": 1,
        "avatar_id": "girl_v1",
        "source": str(SOURCE),
        "source_size": [width, height],
        "coordinate_space": "normalized_static_image",
        "layers": sorted(layer_entries, key=lambda row: int(row["z"])),
        "bones": BONES,
        "actions": [
            "idle",
            "greet",
            "wave",
            "thinking",
            "happy",
            "shy",
            "stickerPresent",
            "touchHead",
            "touchBody",
            "sleep",
            "talkLoop",
        ],
        "expressions": ["neutral", "smile", "surprised", "sad", "angry", "sleepy"],
        "live2d_notes": [
            "Use this as an engineering bootstrap layer kit.",
            "Before final Cubism binding, repaint hidden overdraw for shoulders, elbows, wrists, hips, knees, neck, skirt hem, and hair roots.",
            "Keep layer filenames stable so Swift and harness checks remain valid.",
        ],
    }
    MANIFEST.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"ok": True, "layers": len(layer_entries), "manifest": str(MANIFEST)}, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
