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
DEFAULT_LONG_HAIR_REFERENCE = Path("temp/_live2d_avatar_harness/generated/gpt-image-2/avatar_girl_v1_default_long_reference_full.png")
SHORT_BOB_HAIR_REFERENCE = Path("temp/_live2d_avatar_harness/generated/gpt-image-2/avatar_girl_v1_short_bob_reference_full.png")
LIVE2D_ROOT = Path("asserts/avatar/girl_v1/live2d")
OUT_DIR = Path("asserts/avatar/girl_v1/live2d/layers")
OUTFIT_OUT_DIR = Path("asserts/avatar/girl_v1/live2d/outfits/default/layers")
HAIRSTYLE_ROOT = Path("asserts/avatar/girl_v1/live2d/hairstyles")
HARNESS_OUT_DIR = Path("temp/_live2d_avatar_harness/generated/layers")
MANIFEST = Path("asserts/avatar/girl_v1/live2d/rig_manifest.json")
OUTFIT_MANIFEST = Path("asserts/avatar/girl_v1/live2d/outfits/default/outfit_manifest.json")
HAIRSTYLE_INDEX = Path("asserts/avatar/girl_v1/live2d/hairstyles/hairstyle_index.json")
CLOTHING_RULES = Path("asserts/avatar/girl_v1/live2d/clothing_sticker_split_rules.json")


# Coordinates are normalized to the current static source. The source is kept
# front-facing and padded, so these crops remain stable across 3:4 regenerations.
LAYERS: Dict[str, Dict[str, object]] = {
    "body_torso_base": {"bbox": (0.34, 0.24, 0.66, 0.55), "bone": "torso", "z": 30},
    "head_face": {"bbox": (0.34, 0.03, 0.66, 0.29), "bone": "head", "z": 80},
    "arm_upper_left": {"bbox": (0.24, 0.27, 0.40, 0.47), "bone": "upperArmLeft", "z": 42},
    "arm_upper_right": {"bbox": (0.60, 0.27, 0.76, 0.47), "bone": "upperArmRight", "z": 42},
    "arm_lower_left": {"bbox": (0.15, 0.43, 0.35, 0.58), "bone": "lowerArmLeft", "z": 62},
    "arm_lower_right": {"bbox": (0.65, 0.43, 0.85, 0.58), "bone": "lowerArmRight", "z": 62},
    "hand_left": {"bbox": (0.12, 0.47, 0.28, 0.58), "bone": "handLeft", "z": 72},
    "hand_right": {"bbox": (0.72, 0.47, 0.88, 0.58), "bone": "handRight", "z": 72},
    "hip_base": {"bbox": (0.36, 0.45, 0.64, 0.61), "bone": "hip", "z": 24},
    "thigh_left": {"bbox": (0.37, 0.54, 0.51, 0.72), "bone": "thighLeft", "z": 20},
    "thigh_right": {"bbox": (0.49, 0.54, 0.63, 0.72), "bone": "thighRight", "z": 20},
    "lower_leg_left": {"bbox": (0.37, 0.66, 0.51, 0.89), "bone": "lowerLegLeft", "z": 21},
    "lower_leg_right": {"bbox": (0.49, 0.66, 0.63, 0.89), "bone": "lowerLegRight", "z": 21},
    "foot_left": {"bbox": (0.35, 0.84, 0.51, 0.98), "bone": "footLeft", "z": 40},
    "foot_right": {"bbox": (0.49, 0.84, 0.65, 0.98), "bone": "footRight", "z": 40},
}

HAIRSTYLE_LAYERS: Dict[str, Dict[str, object]] = {
    "hair_back_base": {"bbox": (0.17, 0.02, 0.84, 0.50), "slot": "hair.back.base", "bone": "hairBack", "z": 8, "role": "background"},
    "hair_back_detail": {"bbox": (0.20, 0.02, 0.80, 0.50), "slot": "hair.back.detail", "bone": "hairBackDetail", "z": 9, "role": "detail"},
    "hair_side_left_base": {"bbox": (0.12, 0.11, 0.43, 0.53), "slot": "hair.side.left.base", "bone": "hairSideLeft", "z": 18, "role": "background"},
    "hair_side_right_base": {"bbox": (0.57, 0.11, 0.88, 0.53), "slot": "hair.side.right.base", "bone": "hairSideRight", "z": 18, "role": "background"},
    "hair_side_left_detail": {"bbox": (0.10, 0.17, 0.44, 0.56), "slot": "hair.side.left.detail", "bone": "hairSideLeftDetail", "z": 19, "role": "detail"},
    "hair_side_right_detail": {"bbox": (0.56, 0.17, 0.90, 0.56), "slot": "hair.side.right.detail", "bone": "hairSideRightDetail", "z": 19, "role": "detail"},
    "hair_front_bangs": {"bbox": (0.28, 0.01, 0.72, 0.20), "slot": "hair.front.bangs", "bone": "hairFront", "z": 91, "role": "foreground"},
    "hair_front_detail": {"bbox": (0.23, 0.02, 0.77, 0.30), "slot": "hair.front.detail", "bone": "hairFrontDetail", "z": 94, "role": "detail"},
    "hair_highlight_front": {"bbox": (0.30, 0.01, 0.70, 0.22), "slot": "hair.highlight.front", "bone": "hairFrontDetail", "z": 96, "role": "detail"},
    "hair_highlight_back": {"bbox": (0.22, 0.02, 0.78, 0.48), "slot": "hair.highlight.back", "bone": "hairBackDetail", "z": 12, "role": "detail"},
}

SHORT_BOB_VISIBLE_LAYER = "hair_front_detail"
SHORT_BOB_LAYER_OVERRIDES: Dict[str, Dict[str, object]] = {
    SHORT_BOB_VISIBLE_LAYER: {
        "bbox": (0.18, 0.00, 0.82, 0.34),
        "bone": "hairFrontDetail",
        "z": 96,
        "role": "foreground",
    }
}

HAIRSTYLES: Dict[str, Dict[str, object]] = {
    "default_long_pink": {
        "display_name": "粉色长发",
        "source": DEFAULT_LONG_HAIR_REFERENCE,
        "is_default": True,
    },
    "short_bob": {
        "display_name": "短波波头",
        "source": SHORT_BOB_HAIR_REFERENCE,
        "is_default": False,
    },
}


def hairstyle_layer_specs(hairstyle_id: str) -> Dict[str, Dict[str, object]]:
    specs = {name: dict(spec) for name, spec in HAIRSTYLE_LAYERS.items()}
    if hairstyle_id == "short_bob":
        for name, override in SHORT_BOB_LAYER_OVERRIDES.items():
            specs[name].update(override)
    return specs

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

DEFAULT_OVERDRAW = (24, 24, 24, 24)
OVERDRAW_BY_NAME: Dict[str, Tuple[int, int, int, int]] = {
    "body_torso_base": (70, 95, 70, 95),
    "head_face": (70, 45, 70, 95),
    "arm_upper_left": (65, 70, 70, 75),
    "arm_upper_right": (70, 70, 65, 75),
    "arm_lower_left": (70, 75, 65, 65),
    "arm_lower_right": (65, 75, 70, 65),
    "hand_left": (55, 45, 45, 45),
    "hand_right": (45, 45, 55, 45),
    "hip_base": (70, 75, 70, 75),
    "thigh_left": (50, 75, 45, 80),
    "thigh_right": (45, 75, 50, 80),
    "lower_leg_left": (50, 90, 45, 95),
    "lower_leg_right": (45, 90, 50, 95),
    "foot_left": (45, 22, 45, 35),
    "foot_right": (45, 22, 45, 35),
    "hair_back_base": (100, 45, 100, 135),
    "hair_back_detail": (95, 45, 95, 130),
    "hair_side_left_base": (70, 80, 95, 95),
    "hair_side_right_base": (95, 80, 70, 95),
    "hair_side_left_detail": (70, 80, 95, 90),
    "hair_side_right_detail": (95, 80, 70, 90),
    "hair_front_bangs": (70, 35, 70, 85),
    "hair_front_detail": (75, 45, 75, 90),
    "hair_highlight_front": (70, 40, 70, 80),
    "hair_highlight_back": (90, 45, 90, 115),
    "dress_bodice": (55, 70, 55, 60),
    "dress_skirt": (85, 80, 85, 70),
    "sleeve_left": (65, 55, 60, 55),
    "sleeve_right": (60, 55, 65, 55),
    "wrist_cuff_left": (45, 45, 45, 45),
    "wrist_cuff_right": (45, 45, 45, 45),
    "hair_bows": (70, 55, 70, 60),
    "neck_bow": (45, 45, 45, 45),
    "shoe_left": (45, 22, 45, 35),
    "shoe_right": (45, 22, 45, 35),
}

BONES = {
    "root": {"parent": None, "anchor": (0.50, 0.53)},
    "torso": {"parent": "root", "anchor": (0.50, 0.38)},
    "head": {"parent": "torso", "anchor": (0.50, 0.20)},
    "hairBack": {"parent": "head", "anchor": (0.50, 0.16)},
    "hairBackDetail": {"parent": "hairBack", "anchor": (0.50, 0.16)},
    "hairFront": {"parent": "head", "anchor": (0.50, 0.13)},
    "hairFrontDetail": {"parent": "hairFront", "anchor": (0.50, 0.13)},
    "hairSideLeft": {"parent": "head", "anchor": (0.30, 0.24)},
    "hairSideRight": {"parent": "head", "anchor": (0.70, 0.24)},
    "hairSideLeftDetail": {"parent": "hairSideLeft", "anchor": (0.30, 0.25)},
    "hairSideRightDetail": {"parent": "hairSideRight", "anchor": (0.70, 0.25)},
    "upperArmLeft": {"parent": "torso", "anchor": (0.32, 0.34)},
    "upperArmRight": {"parent": "torso", "anchor": (0.68, 0.34)},
    "lowerArmLeft": {"parent": "upperArmLeft", "anchor": (0.25, 0.47)},
    "lowerArmRight": {"parent": "upperArmRight", "anchor": (0.75, 0.47)},
    "handLeft": {"parent": "lowerArmLeft", "anchor": (0.18, 0.54)},
    "handRight": {"parent": "lowerArmRight", "anchor": (0.82, 0.54)},
    "skirt": {"parent": "torso", "anchor": (0.50, 0.52)},
    "hip": {"parent": "root", "anchor": (0.50, 0.53)},
    "thighLeft": {"parent": "root", "anchor": (0.44, 0.61)},
    "thighRight": {"parent": "root", "anchor": (0.56, 0.61)},
    "lowerLegLeft": {"parent": "thighLeft", "anchor": (0.43, 0.71)},
    "lowerLegRight": {"parent": "thighRight", "anchor": (0.57, 0.71)},
    "legLeft": {"parent": "root", "anchor": (0.44, 0.65)},
    "legRight": {"parent": "root", "anchor": (0.56, 0.65)},
    "footLeft": {"parent": "lowerLegLeft", "anchor": (0.43, 0.90)},
    "footRight": {"parent": "lowerLegRight", "anchor": (0.57, 0.90)},
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


def expand_bbox(
    bbox: Tuple[int, int, int, int],
    image_width: int,
    image_height: int,
    overdraw: Tuple[int, int, int, int],
) -> Tuple[int, int, int, int]:
    left, top, right, bottom = overdraw
    x0, y0, x1, y1 = bbox
    return (
        max(0, x0 - left),
        max(0, y0 - top),
        min(image_width, x1 + right),
        min(image_height, y1 + bottom),
    )


def overdraw_insets(
    placement_bbox: Tuple[int, int, int, int],
    visible_bbox: Tuple[int, int, int, int],
) -> list[int]:
    px0, py0, px1, py1 = placement_bbox
    vx0, vy0, vx1, vy1 = visible_bbox
    return [vx0 - px0, vy0 - py0, px1 - vx1, py1 - vy1]


def crop_entry(
    image: Image.Image,
    name: str,
    spec: Dict[str, object],
) -> tuple[Image.Image, Tuple[int, int, int, int], Tuple[int, int, int, int], list[int]]:
    visible_bbox = pixel_bbox(spec["bbox"], image.size[0], image.size[1])
    placement_bbox = expand_bbox(
        visible_bbox,
        image.size[0],
        image.size[1],
        OVERDRAW_BY_NAME.get(name, DEFAULT_OVERDRAW),
    )
    cropped = image.crop(placement_bbox)
    return cropped, placement_bbox, visible_bbox, overdraw_insets(placement_bbox, visible_bbox)


def layer_entry(
    *,
    name: str,
    filename: str,
    spec: Dict[str, object],
    placement_bbox: Tuple[int, int, int, int],
    visible_bbox: Tuple[int, int, int, int],
    insets: list[int],
    canvas_size: Tuple[int, int],
    cropped_size: Tuple[int, int],
    extra: Dict[str, object] | None = None,
) -> Dict[str, object]:
    entry: Dict[str, object] = {
        "name": name,
        "file": filename,
        "source_bbox_normalized": spec["bbox"],
        "source_bbox_pixels": placement_bbox,
        "placement_bbox_pixels": placement_bbox,
        "visible_bbox_pixels": visible_bbox,
        "overdraw_insets_pixels": insets,
        "canvas_size": [canvas_size[0], canvas_size[1]],
        "size": [cropped_size[0], cropped_size[1]],
        "bone": spec["bone"],
        "z": spec["z"],
    }
    if extra:
        entry.update(extra)
    return entry


def compose_preview(entries: list[Dict[str, object]], out_path: Path, canvas_size: Tuple[int, int]) -> None:
    canvas = Image.new("RGBA", canvas_size, (0, 0, 0, 0))
    for entry in sorted(entries, key=lambda row: (int(row["z"]), str(row["name"]))):
        image_path = LIVE2D_ROOT / str(entry["file"])
        if not image_path.exists():
            continue
        layer_image = Image.open(image_path).convert("RGBA")
        x0, y0, x1, y1 = [int(value) for value in entry["placement_bbox_pixels"]]
        expected_size = (max(0, x1 - x0), max(0, y1 - y0))
        if layer_image.size != expected_size and expected_size[0] > 0 and expected_size[1] > 0:
            layer_image = layer_image.resize(expected_size, Image.Resampling.LANCZOS)
        canvas.alpha_composite(layer_image, (x0, y0))
    out_path.parent.mkdir(parents=True, exist_ok=True)
    canvas.save(out_path)


def isolate_hair_pixels(image: Image.Image, hairstyle_id: str) -> Image.Image:
    """Keep pink/lavender hair pixels for bootstrap hairstyle crops.

    This is only an engineering mask. Final Cubism PSDs should use hand-cleaned
    hair-only layers with hidden overdraw.
    """
    source = image.convert("RGBA")
    output = Image.new("RGBA", source.size, (0, 0, 0, 0))
    out_pixels = output.load()
    for y in range(source.height):
        for x in range(source.width):
            nx = x / max(source.width, 1)
            ny = y / max(source.height, 1)
            if hairstyle_id == "default_long_pink":
                in_hair_region = (
                    (0.24 <= nx <= 0.76 and 0.015 <= ny <= 0.22)
                    or (0.20 <= nx <= 0.34 and 0.07 <= ny <= 0.18)
                    or (0.66 <= nx <= 0.80 and 0.07 <= ny <= 0.18)
                )
            elif hairstyle_id == "short_bob":
                in_hair_region = (
                    (0.20 <= nx <= 0.80 and 0.015 <= ny <= 0.285)
                    or (0.16 <= nx <= 0.84 and 0.08 <= ny <= 0.315)
                )
            else:
                in_hair_region = (
                    (0.17 <= nx <= 0.84 and 0.015 <= ny <= 0.54)
                    or (0.09 <= nx <= 0.45 and 0.10 <= ny <= 0.60)
                    or (0.55 <= nx <= 0.91 and 0.10 <= ny <= 0.60)
                )
            if not in_hair_region:
                continue
            r, g, b, a = source.getpixel((x, y))
            if a == 0:
                continue
            if hairstyle_id == "default_long_pink" and 0.34 <= nx <= 0.66 and 0.11 <= ny <= 0.22:
                continue
            if hairstyle_id == "short_bob":
                left_eye = ((nx - 0.445) / 0.045) ** 2 + ((ny - 0.125) / 0.022) ** 2 < 1
                right_eye = ((nx - 0.555) / 0.045) ** 2 + ((ny - 0.125) / 0.022) ** 2 < 1
                mouth = ((nx - 0.50) / 0.030) ** 2 + ((ny - 0.166) / 0.014) ** 2 < 1
                if left_eye or right_eye or mouth:
                    continue
            elif 0.34 <= nx <= 0.66 and 0.11 <= ny <= 0.22:
                continue
            pink_purple_saturation = ((r + b) / 2) - g
            is_purple_eye_or_mouth = (
                0.33 <= nx <= 0.67
                and 0.10 <= ny <= 0.24
                and b > r + 18
                and b > g + 35
            )
            if is_purple_eye_or_mouth:
                continue
            in_eye_band = hairstyle_id != "short_bob" and 0.34 <= nx <= 0.66 and 0.105 <= ny <= 0.195
            if in_eye_band and not (r > b + 14 and r - g > 24):
                continue
            in_face_feature_zone = 0.30 <= nx <= 0.70 and 0.08 <= ny < 0.10
            is_pastel_hair_in_face_zone = (
                r >= 175
                and g >= 100
                and b >= 145
                and pink_purple_saturation >= 18
                and abs(r - b) <= 105
            )
            if in_face_feature_zone and not is_pastel_hair_in_face_zone:
                continue
            is_warm_skin_or_unitard = (
                r >= 210
                and g >= 175
                and b >= 145
                and r - g <= 60
                and g - b <= 55
                and pink_purple_saturation < 24
            )
            if is_warm_skin_or_unitard:
                continue
            is_blue_rig_or_unitard_line = (
                (b > r + 6 and b > g + 2)
                or (b >= 165 and g >= 145 and r <= 220 and pink_purple_saturation < 42)
            )
            if is_blue_rig_or_unitard_line:
                continue
            if hairstyle_id == "short_bob":
                is_pink_lavender = (
                    r >= 120
                    and b >= 105
                    and abs(r - b) <= 160
                    and max(r, b) - g >= 6
                    and (
                        pink_purple_saturation >= 9
                        or r - g >= 14
                        or b - g >= 14
                    )
                )
                is_short_bob_face_detail = (
                    0.36 <= nx <= 0.64
                    and 0.105 <= ny <= 0.175
                    and r < 170
                    and g < 120
                    and b < 165
                )
                if is_short_bob_face_detail:
                    continue
            else:
                is_pink_lavender = (
                    r >= 125
                    and b >= 105
                    and pink_purple_saturation >= 12
                    and abs(r - b) <= 130
                    and max(r, b) - g >= 12
                )
            if is_pink_lavender:
                out_pixels[x, y] = (r, g, b, a)
    return output


def clean_alpha_noise(
    image: Image.Image,
    *,
    alpha_floor: int = 8,
    min_component_pixels: int = 80,
) -> Image.Image:
    """Drop faint alpha and detached specks from bootstrap transparent layers."""
    source = image.convert("RGBA")
    width, height = source.size
    pixels = source.load()
    visited = bytearray(width * height)

    def index(x: int, y: int) -> int:
        return y * width + x

    for y in range(height):
        for x in range(width):
            idx = index(x, y)
            if visited[idx]:
                continue
            r, g, b, a = pixels[x, y]
            if a <= alpha_floor:
                visited[idx] = 1
                if a:
                    pixels[x, y] = (r, g, b, 0)
                continue

            stack = [(x, y)]
            visited[idx] = 1
            component: list[tuple[int, int]] = []
            while stack:
                cx, cy = stack.pop()
                component.append((cx, cy))
                for nx, ny in ((cx - 1, cy), (cx + 1, cy), (cx, cy - 1), (cx, cy + 1)):
                    if nx < 0 or ny < 0 or nx >= width or ny >= height:
                        continue
                    nidx = index(nx, ny)
                    if visited[nidx]:
                        continue
                    nr, ng, nb, na = pixels[nx, ny]
                    if na <= alpha_floor:
                        visited[nidx] = 1
                        if na:
                            pixels[nx, ny] = (nr, ng, nb, 0)
                        continue
                    visited[nidx] = 1
                    stack.append((nx, ny))

            if len(component) < min_component_pixels:
                for cx, cy in component:
                    cr, cg, cb, _ = pixels[cx, cy]
                    pixels[cx, cy] = (cr, cg, cb, 0)

    return source


def trim_short_bob_fragments(image: Image.Image) -> Image.Image:
    """Keep the bootstrap short hair as a stable cap until painted bob layers exist."""
    source = image.convert("RGBA")
    pixels = source.load()
    width, height = source.size
    for y in range(height):
        for x in range(width):
            ny = y / max(height, 1)
            if ny <= 0.135:
                continue
            # The generated reference has disconnected neck-side strands. On the
            # shared body they read as broken hair, so v1 keeps only the cap/fringe.
            r, g, b, a = pixels[x, y]
            if a:
                pixels[x, y] = (r, g, b, 0)
    return source


def hairstyle_source(hairstyle_id: str, reference_path: Path) -> tuple[Path | None, bool]:
    """Return source path and whether it is already hair-only.

    Full-body references live in ignored harness output and are only used when
    regenerating the bootstrap package. The committed hairstyle package keeps
    only a transparent hair-only source so runtime resources never swap in a
    full character image as a hairstyle.
    """
    if reference_path.exists():
        return reference_path, False
    committed_hair_only = HAIRSTYLE_ROOT / hairstyle_id / "source_hair_only.png"
    if committed_hair_only.exists():
        return committed_hair_only, True
    return None, True


def main() -> int:
    image = Image.open(SOURCE).convert("RGBA")
    outfit_image = Image.open(DEFAULT_OUTFIT_SOURCE).convert("RGBA") if DEFAULT_OUTFIT_SOURCE.exists() else None
    width, height = image.size
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    OUTFIT_OUT_DIR.mkdir(parents=True, exist_ok=True)
    HAIRSTYLE_ROOT.mkdir(parents=True, exist_ok=True)
    HARNESS_OUT_DIR.mkdir(parents=True, exist_ok=True)

    layer_entries = []
    for name, spec in LAYERS.items():
        cropped, bbox, visible_bbox, insets = crop_entry(image, name, spec)
        filename = f"{name}.png"
        out_path = OUT_DIR / filename
        harness_path = HARNESS_OUT_DIR / filename
        cropped.save(out_path)
        cropped.save(harness_path)
        layer_entries.append(
            layer_entry(
                name=name,
                filename=f"layers/{filename}",
                spec=spec,
                placement_bbox=bbox,
                visible_bbox=visible_bbox,
                insets=insets,
                canvas_size=(width, height),
                cropped_size=cropped.size,
                extra={
                "notes": "Bootstrap crop from gpt-image-2 full-body source; final Cubism PSD should redraw hidden overdraw behind joints.",
                },
            )
        )

    hairstyle_manifests = []
    hairstyle_entries_by_id: Dict[str, list[Dict[str, object]]] = {}
    for hairstyle_id, hairstyle in HAIRSTYLES.items():
        source_path, is_hair_only_source = hairstyle_source(hairstyle_id, Path(str(hairstyle["source"])))
        if source_path is None:
            continue
        source_image = Image.open(source_path).convert("RGBA")
        hair_only_image = source_image if is_hair_only_source else isolate_hair_pixels(source_image, hairstyle_id)
        hair_only_image = clean_alpha_noise(hair_only_image)
        if hairstyle_id == "short_bob":
            hair_only_image = trim_short_bob_fragments(hair_only_image)
        style_dir = HAIRSTYLE_ROOT / hairstyle_id
        style_layer_dir = style_dir / "layers"
        style_layer_dir.mkdir(parents=True, exist_ok=True)
        hair_only_source_path = style_dir / "source_hair_only.png"
        hair_only_image.save(hair_only_source_path)

        style_entries = []
        style_specs = hairstyle_layer_specs(hairstyle_id)
        for name, spec in style_specs.items():
            cropped, bbox, visible_bbox, insets = crop_entry(hair_only_image, name, spec)
            if hairstyle_id == "default_long_pink" and name.startswith("hair_side_"):
                cropped = Image.new("RGBA", cropped.size, (0, 0, 0, 0))
            if hairstyle_id == "short_bob" and name != SHORT_BOB_VISIBLE_LAYER:
                cropped = Image.new("RGBA", cropped.size, (0, 0, 0, 0))
            filename = f"{name}.png"
            cropped.save(style_layer_dir / filename)
            style_entries.append(
                layer_entry(
                    name=name,
                    filename=f"hairstyles/{hairstyle_id}/layers/{filename}",
                    spec=spec,
                    placement_bbox=bbox,
                    visible_bbox=visible_bbox,
                    insets=insets,
                    canvas_size=source_image.size,
                    cropped_size=cropped.size,
                    extra={
                    "slot": spec["slot"],
                    "role": spec["role"],
                    "replaceable": True,
                    "show_in_sticker_list": False,
                    },
                )
            )
        hairstyle_entries_by_id[hairstyle_id] = style_entries

        style_manifest_path = style_dir / "hairstyle_manifest.json"
        style_manifest = {
            "schema_version": 1,
            "avatar_id": "girl_v1",
            "hairstyle_id": hairstyle_id,
            "display_name": hairstyle["display_name"],
            "source": str(hair_only_source_path),
            "is_default": bool(hairstyle["is_default"]),
            "replaceable": True,
            "show_in_sticker_list": False,
            "layers": sorted(style_entries, key=lambda row: int(row["z"])),
            "notes": [
                "Bootstrap hair-only crops from gpt-image-2 references; runtime package stores transparent hair-only sources only.",
                "Final Cubism PSD should redraw clean strand tips, roots, and hidden overdraw.",
            ],
        }
        style_manifest_path.write_text(json.dumps(style_manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        hairstyle_manifests.append(
            {
                "hairstyle_id": hairstyle_id,
                "display_name": hairstyle["display_name"],
                "manifest": str(style_manifest_path),
                "source": str(hair_only_source_path),
                "is_default": bool(hairstyle["is_default"]),
                "show_in_sticker_list": False,
            }
        )

    hairstyle_index = {
        "schema_version": 1,
        "avatar_id": "girl_v1",
        "default_hairstyle_id": "default_long_pink",
        "layer_contract": list(HAIRSTYLE_LAYERS.keys()),
        "hairstyles": sorted(hairstyle_manifests, key=lambda row: row["hairstyle_id"]),
    }
    HAIRSTYLE_INDEX.write_text(json.dumps(hairstyle_index, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

    outfit_entries = []
    if outfit_image is not None:
        for name, spec in OUTFIT_LAYERS.items():
            cropped, bbox, visible_bbox, insets = crop_entry(outfit_image, name, spec)
            filename = f"{name}.png"
            out_path = OUTFIT_OUT_DIR / filename
            cropped.save(out_path)
            outfit_entries.append(
                layer_entry(
                    name=name,
                    filename=f"outfits/default/layers/{filename}",
                    spec=spec,
                    placement_bbox=bbox,
                    visible_bbox=visible_bbox,
                    insets=insets,
                    canvas_size=outfit_image.size,
                    cropped_size=cropped.size,
                    extra={
                    "slot": spec["slot"],
                    "embedded_in_avatar_outfit": True,
                    "show_in_sticker_list": False,
                    **({"hair_style_scope": "default_long_pink"} if name == "hair_bows" else {}),
                    },
                )
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
                "hair_style_scope": "default_long_pink",
                "show_in_sticker_list": False,
            }
        },
        "replaceable_hairstyles": {
            "index": str(HAIRSTYLE_INDEX),
            "default_hairstyle_id": "default_long_pink",
            "layer_contract": list(HAIRSTYLE_LAYERS.keys()),
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
            "Hair is replaceable through hairstyles/<style_id>/hairstyle_manifest.json packages; body layers should not hard-code one hairstyle.",
            "Keep layer filenames stable so Swift and harness checks remain valid.",
        ],
    }
    MANIFEST.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

    outfit_manifest = {
        "schema_version": 1,
        "avatar_id": "girl_v1",
        "outfit_id": "default",
        "source": str(DEFAULT_OUTFIT_SOURCE),
        "hair_style_scope": "default_long_pink",
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

    default_hair_entries = hairstyle_entries_by_id.get("default_long_pink", [])
    short_hair_entries = hairstyle_entries_by_id.get("short_bob", [])
    compose_preview(
        layer_entries + default_hair_entries,
        HARNESS_OUT_DIR / "avatar_girl_v1_body_hair_preview.png",
        (width, height),
    )
    compose_preview(
        layer_entries + default_hair_entries + outfit_entries,
        HARNESS_OUT_DIR / "avatar_girl_v1_layered_preview.png",
        (width, height),
    )
    compose_preview(
        layer_entries + short_hair_entries,
        HARNESS_OUT_DIR / "avatar_girl_v1_short_bob_preview.png",
        (width, height),
    )

    print(json.dumps({
        "ok": True,
        "base_layers": len(layer_entries),
        "hairstyles": len(hairstyle_manifests),
        "hairstyle_layers_each": len(HAIRSTYLE_LAYERS),
        "outfit_layers": len(outfit_entries),
        "manifest": str(MANIFEST),
        "outfit_manifest": str(OUTFIT_MANIFEST),
        "hairstyle_index": str(HAIRSTYLE_INDEX),
        "clothing_rules": str(CLOTHING_RULES),
    }, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
