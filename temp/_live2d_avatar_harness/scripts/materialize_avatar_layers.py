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
DEFAULT_OUTFIT_SOURCE = Path("asserts/avatar/girl_v1/live2d/outfits/default/default_outfit_full.png")
OUT_DIR = Path("asserts/avatar/girl_v1/live2d/layers")
OUTFIT_OUT_DIR = Path("asserts/avatar/girl_v1/live2d/outfits/default/layers")
HARNESS_OUT_DIR = Path("temp/_live2d_avatar_harness/generated/layers")
MANIFEST = Path("asserts/avatar/girl_v1/live2d/rig_manifest.json")
OUTFIT_MANIFEST = Path("asserts/avatar/girl_v1/live2d/outfits/default/outfit_manifest.json")
CLOTHING_RULES = Path("asserts/avatar/girl_v1/live2d/clothing_sticker_split_rules.json")


# Coordinates are normalized to the current static source. The source is kept
# front-facing and padded, so these crops remain stable across 3:4 regenerations.
LAYERS: Dict[str, Dict[str, object]] = {
    "hair_back": {"bbox": (0.17, 0.02, 0.84, 0.49), "bone": "hairBack", "z": 10},
    "body_torso_base": {"bbox": (0.34, 0.24, 0.66, 0.55), "bone": "torso", "z": 30},
    "head_face": {"bbox": (0.34, 0.03, 0.66, 0.29), "bone": "head", "z": 80},
    "hair_front": {"bbox": (0.29, 0.01, 0.72, 0.29), "bone": "hairFront", "z": 90},
    "hair_side_left": {"bbox": (0.17, 0.15, 0.42, 0.49), "bone": "hairSideLeft", "z": 70},
    "hair_side_right": {"bbox": (0.58, 0.15, 0.84, 0.49), "bone": "hairSideRight", "z": 70},
    "arm_upper_left": {"bbox": (0.24, 0.27, 0.40, 0.47), "bone": "upperArmLeft", "z": 42},
    "arm_upper_right": {"bbox": (0.60, 0.27, 0.76, 0.47), "bone": "upperArmRight", "z": 42},
    "arm_lower_left": {"bbox": (0.15, 0.43, 0.35, 0.58), "bone": "lowerArmLeft", "z": 62},
    "arm_lower_right": {"bbox": (0.65, 0.43, 0.85, 0.58), "bone": "lowerArmRight", "z": 62},
    "hand_left": {"bbox": (0.12, 0.47, 0.28, 0.58), "bone": "handLeft", "z": 72},
    "hand_right": {"bbox": (0.72, 0.47, 0.88, 0.58), "bone": "handRight", "z": 72},
    "hip_base": {"bbox": (0.36, 0.45, 0.64, 0.61), "bone": "hip", "z": 24},
    "leg_left": {"bbox": (0.38, 0.55, 0.50, 0.88), "bone": "legLeft", "z": 20},
    "leg_right": {"bbox": (0.50, 0.55, 0.62, 0.88), "bone": "legRight", "z": 20},
    "foot_left": {"bbox": (0.35, 0.84, 0.51, 0.98), "bone": "footLeft", "z": 40},
    "foot_right": {"bbox": (0.49, 0.84, 0.65, 0.98), "bone": "footRight", "z": 40},
}

OUTFIT_LAYERS: Dict[str, Dict[str, object]] = {
    "dress_bodice": {"bbox": (0.30, 0.26, 0.70, 0.49), "slot": "dress.bodice", "bone": "torso", "z": 110},
    "dress_skirt": {"bbox": (0.16, 0.43, 0.84, 0.68), "slot": "dress.skirt", "bone": "skirt", "z": 115},
    "sleeve_left": {"bbox": (0.19, 0.28, 0.39, 0.46), "slot": "dress.sleeve.left", "bone": "upperArmLeft", "z": 112},
    "sleeve_right": {"bbox": (0.61, 0.28, 0.81, 0.46), "slot": "dress.sleeve.right", "bone": "upperArmRight", "z": 112},
    "wrist_cuff_left": {"bbox": (0.19, 0.41, 0.35, 0.52), "slot": "dress.wrist.left", "bone": "lowerArmLeft", "z": 118},
    "wrist_cuff_right": {"bbox": (0.65, 0.41, 0.81, 0.52), "slot": "dress.wrist.right", "bone": "lowerArmRight", "z": 118},
    "hair_bows": {"bbox": (0.23, 0.03, 0.77, 0.25), "slot": "accessory.hair", "bone": "head", "z": 130},
    "neck_bow": {"bbox": (0.38, 0.21, 0.62, 0.33), "slot": "accessory.neck", "bone": "head", "z": 125},
    "shoe_left": {"bbox": (0.34, 0.82, 0.51, 0.98), "slot": "shoe.left", "bone": "footLeft", "z": 118},
    "shoe_right": {"bbox": (0.49, 0.82, 0.66, 0.98), "slot": "shoe.right", "bone": "footRight", "z": 118},
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
    "hip": {"parent": "root", "anchor": (0.50, 0.53)},
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
    outfit_image = Image.open(DEFAULT_OUTFIT_SOURCE).convert("RGBA") if DEFAULT_OUTFIT_SOURCE.exists() else None
    width, height = image.size
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    OUTFIT_OUT_DIR.mkdir(parents=True, exist_ok=True)
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

    outfit_entries = []
    if outfit_image is not None:
        for name, spec in OUTFIT_LAYERS.items():
            bbox = pixel_bbox(spec["bbox"], outfit_image.size[0], outfit_image.size[1])
            cropped = trim_transparent(outfit_image.crop(bbox))
            filename = f"{name}.png"
            out_path = OUTFIT_OUT_DIR / filename
            cropped.save(out_path)
            outfit_entries.append(
                {
                    "name": name,
                    "file": f"outfits/default/layers/{filename}",
                    "slot": spec["slot"],
                    "source_bbox_normalized": spec["bbox"],
                    "source_bbox_pixels": bbox,
                    "size": cropped.size,
                    "bone": spec["bone"],
                    "z": spec["z"],
                    "embedded_in_avatar_outfit": True,
                    "show_in_sticker_list": False,
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
        "embedded_outfits": {
            "default": {
                "manifest": str(OUTFIT_MANIFEST),
                "full_preview": str(DEFAULT_OUTFIT_SOURCE),
                "show_in_sticker_list": False,
            }
        },
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

    outfit_manifest = {
        "schema_version": 1,
        "avatar_id": "girl_v1",
        "outfit_id": "default",
        "source": str(DEFAULT_OUTFIT_SOURCE),
        "show_in_sticker_list": False,
        "embedded_in_avatar_outfit": True,
        "layers": sorted(outfit_entries, key=lambda row: int(row["z"])),
    }
    OUTFIT_MANIFEST.write_text(json.dumps(outfit_manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

    clothing_rules = {
        "schema_version": 1,
        "avatar_id": "girl_v1",
        "purpose": "Split future clothing stickers into bone-bound outfit layers instead of adding the avatar's own outfit to the normal sticker list.",
        "normal_sticker_list_policy": {
            "embedded_avatar_outfit_layers": "hidden",
            "user_added_clothing_cutouts": "visible",
        },
        "slots": [
            {"slot": "dress.bodice", "bone": "torso", "recommended_bbox": [0.30, 0.25, 0.70, 0.48]},
            {"slot": "dress.skirt", "bone": "skirt", "recommended_bbox": [0.16, 0.42, 0.84, 0.70]},
            {"slot": "dress.sleeve.left", "bone": "upperArmLeft", "recommended_bbox": [0.18, 0.28, 0.40, 0.47]},
            {"slot": "dress.sleeve.right", "bone": "upperArmRight", "recommended_bbox": [0.60, 0.28, 0.82, 0.47]},
            {"slot": "shoe.left", "bone": "footLeft", "recommended_bbox": [0.34, 0.82, 0.51, 0.98]},
            {"slot": "shoe.right", "bone": "footRight", "recommended_bbox": [0.49, 0.82, 0.66, 0.98]},
            {"slot": "accessory.hair", "bone": "head", "recommended_bbox": [0.23, 0.03, 0.77, 0.25]},
            {"slot": "accessory.neck", "bone": "head", "recommended_bbox": [0.38, 0.21, 0.62, 0.33]},
        ],
        "live2d_notes": [
            "Each clothing slot should keep hidden overdraw near joints and hems.",
            "Sleeves and wrist cuffs should be separate from arm skin so arm rotation does not smear textures.",
            "Skirts should be split into front panels if stronger sway is needed.",
        ],
    }
    CLOTHING_RULES.write_text(json.dumps(clothing_rules, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

    print(json.dumps({
        "ok": True,
        "base_layers": len(layer_entries),
        "outfit_layers": len(outfit_entries),
        "manifest": str(MANIFEST),
        "outfit_manifest": str(OUTFIT_MANIFEST),
        "clothing_rules": str(CLOTHING_RULES),
    }, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
