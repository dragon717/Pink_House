#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Audit girl_v1 layered avatar overdraw and render static/motion previews."""
from __future__ import annotations

import argparse
import json
import math
import time
from pathlib import Path
from typing import Any

from PIL import Image


LIVE2D_ROOT = Path("asserts/avatar/girl_v1/live2d")
RIG_MANIFEST = LIVE2D_ROOT / "rig_manifest.json"
HAIRSTYLE_ROOT = LIVE2D_ROOT / "hairstyles"
OUTFIT_MANIFEST = LIVE2D_ROOT / "outfits/default/outfit_manifest.json"

PHASE_SECONDS = [0.0, 0.85, 1.7, 2.55]
QUALITY_PROFILE = {
    "profile": "magicStickerV1",
    "target_fps": {"idle": 24, "gesture": 30, "talkLoop": 24},
    "canvas_scale": 0.72,
    "idle_amplitude_scale": 0.62,
    "snapshot_phase_seconds": 0.0,
    "static_contexts": ["snapshot", "thumbnail", "low_power", "background"],
}
EXPECTED_PREVIEW_LABELS = [
    "hybrid_default_long_pink",
    "hybrid_short_bob",
    "hybrid_default_outfit",
]
DEFAULT_MIN_OVERDRAW = 10
MIN_OVERDRAW_BY_NAME = {
    "body_torso_base": 28,
    "head_face": 20,
    "arm_upper_left": 24,
    "arm_upper_right": 24,
    "arm_lower_left": 24,
    "arm_lower_right": 24,
    "hip_base": 24,
    "thigh_left": 24,
    "thigh_right": 24,
    "lower_leg_left": 24,
    "lower_leg_right": 24,
    "dress_bodice": 20,
    "dress_skirt": 20,
    "sleeve_left": 18,
    "sleeve_right": 18,
    "wrist_cuff_left": 14,
    "wrist_cuff_right": 14,
}


def load_json(path: Path) -> dict[str, Any]:
    return json.loads(path.read_text(encoding="utf-8"))


def layer_path(entry: dict[str, Any]) -> Path:
    raw = Path(str(entry["file"]))
    if raw.is_absolute() or raw.exists():
        return raw
    if str(entry["file"]).startswith("asserts/"):
        return raw
    return LIVE2D_ROOT / raw


def surface_path(entry: dict[str, Any]) -> Path:
    return layer_path(entry)


def minimum_required(entry: dict[str, Any]) -> int:
    return MIN_OVERDRAW_BY_NAME.get(str(entry.get("name")), DEFAULT_MIN_OVERDRAW)


def insets_ok(entry: dict[str, Any]) -> bool:
    insets = entry.get("overdraw_insets_pixels")
    visible = entry.get("visible_bbox_pixels")
    canvas_size = entry.get("canvas_size")
    if not isinstance(insets, list) or len(insets) != 4:
        return False
    if not isinstance(visible, list) or len(visible) != 4:
        return False
    if not isinstance(canvas_size, list) or len(canvas_size) != 2:
        return False

    required = minimum_required(entry)
    width, height = int(canvas_size[0]), int(canvas_size[1])
    vx0, vy0, vx1, vy1 = [int(value) for value in visible]
    canvas_gaps = [vx0, vy0, width - vx1, height - vy1]
    for inset, canvas_gap in zip(insets, canvas_gaps):
        if int(inset) >= required:
            continue
        # If the visible art is genuinely near the canvas edge, clamping is ok.
        if canvas_gap < required and int(inset) >= canvas_gap:
            continue
        return False
    return True


def alpha_edge_contacts(path: Path) -> list[str]:
    image = Image.open(path).convert("RGBA")
    alpha = image.getchannel("A")
    width, height = image.size
    contacts: list[str] = []
    if any(alpha.getpixel((x, 0)) > 8 for x in range(width)):
        contacts.append("top")
    if any(alpha.getpixel((x, height - 1)) > 8 for x in range(width)):
        contacts.append("bottom")
    if any(alpha.getpixel((0, y)) > 8 for y in range(height)):
        contacts.append("left")
    if any(alpha.getpixel((width - 1, y)) > 8 for y in range(height)):
        contacts.append("right")
    return contacts


def audit_entries(label: str, entries: list[dict[str, Any]]) -> dict[str, Any]:
    rows = []
    ok = True
    edge_warnings = []
    for entry in entries:
        path = layer_path(entry)
        placement = entry.get("placement_bbox_pixels") or [0, 0, 0, 0]
        expected_size = (
            max(0, int(placement[2]) - int(placement[0])),
            max(0, int(placement[3]) - int(placement[1])),
        )
        exists = path.exists()
        size_ok = False
        contacts: list[str] = []
        actual_size = None
        if exists:
            with Image.open(path) as image:
                actual_size = image.size
            size_ok = actual_size == expected_size
            contacts = alpha_edge_contacts(path)

        row_ok = exists and size_ok and insets_ok(entry)
        ok = ok and row_ok
        if contacts:
            edge_warnings.append({"name": entry.get("name"), "contacts": contacts})
        rows.append(
            {
                "name": entry.get("name"),
                "file": str(path),
                "exists": exists,
                "expected_size": expected_size,
                "actual_size": actual_size,
                "size_ok": size_ok,
                "min_required_overdraw": minimum_required(entry),
                "overdraw_insets_pixels": entry.get("overdraw_insets_pixels"),
                "visible_bbox_pixels": entry.get("visible_bbox_pixels"),
                "insets_ok": insets_ok(entry),
                "alpha_edge_contacts": contacts,
                "edge_contact_warning": bool(contacts),
                "ok": row_ok,
            }
        )
    return {"label": label, "ok": ok, "edge_contact_warnings": edge_warnings, "layers": rows}


def anchor_unit(entry: dict[str, Any], bones: dict[str, Any]) -> tuple[float, float]:
    placement = [float(value) for value in entry["placement_bbox_pixels"]]
    canvas = [float(value) for value in entry["canvas_size"]]
    if isinstance(entry.get("anchor_pixels"), list) and len(entry["anchor_pixels"]) >= 2:
        anchor_x = float(entry["anchor_pixels"][0])
        anchor_y = float(entry["anchor_pixels"][1])
    else:
        bone = bones.get(str(entry.get("bone")), {})
        normalized = bone.get("anchor") or [
            (placement[0] + placement[2]) / max(canvas[0] * 2, 1),
            (placement[1] + placement[3]) / max(canvas[1] * 2, 1),
        ]
        anchor_x = float(normalized[0]) * canvas[0]
        anchor_y = float(normalized[1]) * canvas[1]
    width = max(placement[2] - placement[0], 1)
    height = max(placement[3] - placement[1], 1)
    return (
        min(max((anchor_x - placement[0]) / width, 0), 1),
        min(max((anchor_y - placement[1]) / height, 0), 1),
    )


def local_transform(bone: str, seconds: float, amplitude: float = QUALITY_PROFILE["idle_amplitude_scale"]) -> tuple[float, float, float]:
    breath = math.sin(seconds * math.pi * 2 / 3.4)
    body_sway = math.sin(seconds * math.pi * 2 / 4.8 + 0.2)
    soft_pulse = math.sin(seconds * math.pi * 2 / 2.6 + 1.4)
    hair_lag = math.sin(seconds * math.pi * 2 / 3.1 + 0.55)
    hair_float = math.sin(seconds * math.pi * 2 / 2.7 + 1.15)
    skirt_lag = math.sin(seconds * math.pi * 2 / 3.8 + 0.85)
    arm_lag = math.sin(seconds * math.pi * 2 / 4.2 + 0.35)

    table = {
        "root": (0, body_sway * 0.7 * amplitude, breath * -0.8 * amplitude),
        "torso": (body_sway * 0.28 * amplitude, body_sway * 0.6 * amplitude, breath * -0.6 * amplitude),
        "hip": (body_sway * -0.18 * amplitude, body_sway * -0.35 * amplitude, breath * 0.35 * amplitude),
        "head": (body_sway * -0.55 * amplitude, body_sway * -0.9 * amplitude, breath * -1.0 * amplitude),
        "hairBack": (hair_lag * 1.25 * amplitude, hair_lag * 1.8 * amplitude, (hair_float * 1.1 + breath * 0.6) * amplitude),
        "hairBackDetail": (hair_lag * 1.25 * amplitude, hair_lag * 1.8 * amplitude, (hair_float * 1.1 + breath * 0.6) * amplitude),
        "hairFront": (hair_lag * -0.65 * amplitude, hair_lag * 0.8 * amplitude, breath * -0.45 * amplitude),
        "hairFrontDetail": (hair_lag * -0.65 * amplitude, hair_lag * 0.8 * amplitude, breath * -0.45 * amplitude),
        "hairSideLeft": (hair_lag * -1.7 * amplitude, hair_lag * -2.1 * amplitude, (hair_float * 1.5 + breath * 0.8) * amplitude),
        "hairSideLeftDetail": (hair_lag * -1.7 * amplitude, hair_lag * -2.1 * amplitude, (hair_float * 1.5 + breath * 0.8) * amplitude),
        "hairSideRight": (hair_lag * 1.7 * amplitude, hair_lag * 2.1 * amplitude, (hair_float * 1.5 + breath * 0.8) * amplitude),
        "hairSideRightDetail": (hair_lag * 1.7 * amplitude, hair_lag * 2.1 * amplitude, (hair_float * 1.5 + breath * 0.8) * amplitude),
        "upperArmLeft": (arm_lag * -0.38 * amplitude, soft_pulse * -0.25 * amplitude, breath * 0.25 * amplitude),
        "upperArmRight": (arm_lag * 0.38 * amplitude, soft_pulse * 0.25 * amplitude, breath * 0.25 * amplitude),
        "lowerArmLeft": (arm_lag * -0.55 * amplitude, soft_pulse * -0.3 * amplitude, breath * 0.35 * amplitude),
        "lowerArmRight": (arm_lag * 0.55 * amplitude, soft_pulse * 0.3 * amplitude, breath * 0.35 * amplitude),
        "handLeft": (arm_lag * -0.75 * amplitude, soft_pulse * -0.25 * amplitude, breath * 0.25 * amplitude),
        "handRight": (arm_lag * 0.75 * amplitude, soft_pulse * 0.25 * amplitude, breath * 0.25 * amplitude),
        "skirt": (skirt_lag * 0.55 * amplitude, skirt_lag * 1.1 * amplitude, breath * 0.65 * amplitude),
        "thighLeft": (body_sway * 0.10 * amplitude, body_sway * 0.18 * amplitude, breath * 0.18 * amplitude),
        "thighRight": (body_sway * -0.10 * amplitude, body_sway * -0.18 * amplitude, breath * 0.18 * amplitude),
        "lowerLegLeft": (body_sway * 0.08 * amplitude, body_sway * 0.12 * amplitude, breath * 0.14 * amplitude),
        "lowerLegRight": (body_sway * -0.08 * amplitude, body_sway * -0.12 * amplitude, breath * 0.14 * amplitude),
        "legLeft": (body_sway * 0.10 * amplitude, body_sway * 0.18 * amplitude, breath * 0.18 * amplitude),
        "legRight": (body_sway * -0.10 * amplitude, body_sway * -0.18 * amplitude, breath * 0.18 * amplitude),
        "footLeft": (body_sway * 0.12 * amplitude, 0, 0),
        "footRight": (body_sway * -0.12 * amplitude, 0, 0),
    }
    return table.get(bone, (0, 0, 0))


def accumulated_transform(bone: str, bones: dict[str, Any], seconds: float, seen: set[str] | None = None) -> tuple[float, float, float]:
    seen = seen or set()
    if bone in seen:
        return (0, 0, 0)
    seen.add(bone)
    parent = (bones.get(bone) or {}).get("parent")
    parent_transform = accumulated_transform(parent, bones, seconds, seen) if parent else (0, 0, 0)
    local = local_transform(bone, seconds)
    return (
        parent_transform[0] + local[0],
        parent_transform[1] + local[1],
        parent_transform[2] + local[2],
    )


def apply_opacity(image: Image.Image, opacity: float | None) -> Image.Image:
    if opacity is None or opacity >= 0.999:
        return image
    result = image.copy()
    alpha = result.getchannel("A")
    alpha = alpha.point(lambda value: round(value * max(0, min(float(opacity), 1))))
    result.putalpha(alpha)
    return result


def compose(entries: list[dict[str, Any]], bones: dict[str, Any], out_path: Path, seconds: float) -> None:
    canvas_size = tuple(int(value) for value in entries[0]["canvas_size"])
    canvas = Image.new("RGBA", canvas_size, (0, 0, 0, 0))
    for entry in sorted(entries, key=lambda row: (int(row["z"]), str(row["name"]))):
        path = layer_path(entry)
        if not path.exists():
            continue
        layer = apply_opacity(Image.open(path).convert("RGBA"), entry.get("opacity"))
        placement = [int(value) for value in entry["placement_bbox_pixels"]]
        anchor = anchor_unit(entry, bones)
        angle, dx, dy = accumulated_transform(str(entry.get("bone")), bones, seconds)
        center = (anchor[0] * layer.size[0], anchor[1] * layer.size[1])
        moved = layer.rotate(
            -angle,
            resample=Image.Resampling.BICUBIC,
            center=center,
            fillcolor=(0, 0, 0, 0),
        )
        canvas.alpha_composite(moved, (round(placement[0] + dx), round(placement[1] + dy)))
    out_path.parent.mkdir(parents=True, exist_ok=True)
    canvas.save(out_path)


def surface_entry_ok(entry: dict[str, Any]) -> bool:
    return (
        isinstance(entry.get("anchor_pixels"), list)
        and len(entry.get("anchor_pixels")) >= 2
        and isinstance(entry.get("motion_role"), str)
        and bool(entry.get("motion_role"))
        and isinstance(entry.get("overdraw_insets_pixels"), list)
        and len(entry.get("overdraw_insets_pixels")) == 4
    )


def audit_surface_plate(label: str, entry: dict[str, Any]) -> dict[str, Any]:
    path = surface_path(entry)
    exists = path.exists()
    size = None
    alpha_extrema = None
    nontransparent_percent = 0.0
    if exists:
        image = Image.open(path).convert("RGBA")
        size = image.size
        alpha = image.getchannel("A")
        alpha_extrema = alpha.getextrema()
        nontransparent = sum(1 for value in alpha.getdata() if value > 0)
        nontransparent_percent = nontransparent / max(image.size[0] * image.size[1], 1) * 100

    overlays = list(entry.get("layers") or [])
    overlay_reports = []
    for overlay in overlays:
        overlay_reports.append({
            "name": overlay.get("name"),
            "file": str(layer_path(overlay)),
            "exists": layer_path(overlay).exists(),
            "metadata_ok": surface_entry_ok(overlay),
            "opacity": overlay.get("opacity"),
            "motion_role": overlay.get("motion_role"),
            "alpha_edge_contacts": alpha_edge_contacts(layer_path(overlay)) if layer_path(overlay).exists() else [],
        })

    return {
        "label": label,
        "file": str(path),
        "exists": exists,
        "size": size,
        "alpha_extrema": alpha_extrema,
        "nontransparent_percent": round(nontransparent_percent, 4),
        "metadata_ok": surface_entry_ok(entry),
        "overlay_count": len(overlays),
        "overlays": overlay_reports,
        "ok": (
            exists
            and size == tuple(int(value) for value in entry.get("canvas_size", []))
            and alpha_extrema is not None
            and alpha_extrema[1] > 0
            and nontransparent_percent >= 2.0
            and surface_entry_ok(entry)
            and all(row["exists"] and row["metadata_ok"] for row in overlay_reports)
        ),
    }


def compose_hybrid_surface(entry: dict[str, Any], bones: dict[str, Any], out_path: Path, seconds: float) -> None:
    canvas_size = tuple(int(value) for value in entry["canvas_size"])
    canvas = Image.new("RGBA", canvas_size, (0, 0, 0, 0))

    base = apply_opacity(Image.open(surface_path(entry)).convert("RGBA"), entry.get("opacity"))
    placement = [int(value) for value in entry["placement_bbox_pixels"]]
    _, dx, dy = accumulated_transform(str(entry.get("bone", "root")), bones, seconds)
    canvas.alpha_composite(base, (round(placement[0] + dx), round(placement[1] + dy)))

    for overlay in sorted(entry.get("layers") or [], key=lambda row: (int(row["z"]), str(row["name"]))):
        path = layer_path(overlay)
        if not path.exists():
            continue
        layer = apply_opacity(Image.open(path).convert("RGBA"), overlay.get("opacity"))
        overlay_placement = [int(value) for value in overlay["placement_bbox_pixels"]]
        anchor = anchor_unit(overlay, bones)
        angle, odx, ody = accumulated_transform(str(overlay.get("bone")), bones, seconds)
        center = (anchor[0] * layer.size[0], anchor[1] * layer.size[1])
        moved = layer.rotate(
            -angle,
            resample=Image.Resampling.BICUBIC,
            center=center,
            fillcolor=(0, 0, 0, 0),
        )
        canvas.alpha_composite(moved, (round(overlay_placement[0] + odx), round(overlay_placement[1] + ody)))

    out_path.parent.mkdir(parents=True, exist_ok=True)
    canvas.save(out_path)


def render_hybrid_previews(
    rig: dict[str, Any],
    outfit: dict[str, Any],
    out_dir: Path,
) -> tuple[list[str], list[dict[str, Any]]]:
    rendered: list[str] = []
    reports: list[dict[str, Any]] = []
    bones = dict(rig.get("bones", {}))
    surfaces = dict(rig.get("surface_plates") or {})
    preview_sets = {
        "hybrid_default_long_pink": surfaces.get("default_long_pink"),
        "hybrid_short_bob": surfaces.get("short_bob"),
    }

    outfit_surface = outfit.get("surface_plate")
    if outfit_surface:
        canvas_size = list(rig.get("source_size", [1086, 1448]))
        preview_sets["hybrid_default_outfit"] = {
            "file": outfit_surface,
            "source_bbox_pixels": [0, 0, canvas_size[0], canvas_size[1]],
            "placement_bbox_pixels": [0, 0, canvas_size[0], canvas_size[1]],
            "visible_bbox_pixels": [0, 0, canvas_size[0], canvas_size[1]],
            "overdraw_insets_pixels": [0, 0, 0, 0],
            "canvas_size": canvas_size,
            "bone": "root",
            "z": 0,
            "anchor_pixels": [canvas_size[0] * 0.5, canvas_size[1] * 0.53],
            "motion_role": "default_outfit_surface",
            "opacity": 1.0,
            "layers": list(outfit.get("surface_motion_overlays") or []),
        }

    for label, entry in preview_sets.items():
        if not entry:
            reports.append({"label": label, "ok": False, "error": "missing surface plate"})
            continue
        reports.append(audit_surface_plate(label, entry))
        if reports[-1]["ok"]:
            for index, seconds in enumerate(PHASE_SECONDS):
                out_path = out_dir / f"{label}_phase_{index}.png"
                compose_hybrid_surface(entry, bones, out_path, seconds)
                rendered.append(str(out_path))
    return rendered, reports


def render_previews(
    rig: dict[str, Any],
    hairstyle_entries: dict[str, list[dict[str, Any]]],
    outfit_entries: list[dict[str, Any]],
    out_dir: Path,
) -> list[str]:
    rendered: list[str] = []
    body_entries = list(rig.get("layers", []))
    bones = dict(rig.get("bones", {}))
    outfit_scope = (
        rig.get("embedded_outfits", {})
        .get("default", {})
        .get("hair_style_scope")
    )

    def outfit_for(hairstyle_id: str) -> list[dict[str, Any]]:
        if outfit_scope not in (None, hairstyle_id):
            return []
        return [
            entry
            for entry in outfit_entries
            if entry.get("hair_style_scope") in (None, hairstyle_id)
        ]

    preview_sets = {
        "default_long_pink": body_entries + hairstyle_entries.get("default_long_pink", []),
        "short_bob": body_entries + hairstyle_entries.get("short_bob", []),
        "default_outfit": body_entries + hairstyle_entries.get("default_long_pink", []) + outfit_for("default_long_pink"),
    }
    for label, entries in preview_sets.items():
        if not entries:
            continue
        for index, seconds in enumerate(PHASE_SECONDS):
            out_path = out_dir / f"{label}_phase_{index}.png"
            compose(entries, bones, out_path, seconds)
            rendered.append(str(out_path))
    return rendered


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--out-dir", default=f"temp/_live2d_avatar_harness/runs/edge_{time.strftime('%Y%m%d_%H%M%S')}")
    parser.add_argument("--no-previews", action="store_true")
    args = parser.parse_args()

    rig = load_json(RIG_MANIFEST)
    outfit = load_json(OUTFIT_MANIFEST)
    hairstyle_entries: dict[str, list[dict[str, Any]]] = {}
    style_reports = []
    for style_dir in sorted(path for path in HAIRSTYLE_ROOT.iterdir() if path.is_dir()):
        manifest = style_dir / "hairstyle_manifest.json"
        if not manifest.exists():
            continue
        data = load_json(manifest)
        entries = list(data.get("layers", []))
        hairstyle_entries[str(data.get("hairstyle_id"))] = entries
        style_reports.append(audit_entries(f"hairstyle:{data.get('hairstyle_id')}", entries))

    body_report = audit_entries("body", list(rig.get("layers", [])))
    outfit_report = audit_entries("default_outfit", list(outfit.get("layers", [])))
    reports = [body_report, *style_reports, outfit_report]
    out_dir = Path(args.out_dir)
    rendered = [] if args.no_previews else render_previews(
        rig,
        hairstyle_entries,
        list(outfit.get("layers", [])),
        out_dir,
    )
    hybrid_rendered, hybrid_reports = ([], []) if args.no_previews else render_hybrid_previews(
        rig,
        outfit,
        out_dir,
    )

    report = {
        "ok": all(row["ok"] for row in reports) and all(row["ok"] for row in hybrid_reports),
        "quality_profile": QUALITY_PROFILE,
        "expected_preview_labels": EXPECTED_PREVIEW_LABELS,
        "rig_manifest": str(RIG_MANIFEST),
        "outfit_manifest": str(OUTFIT_MANIFEST),
        "reports": reports,
        "hybrid_surface_reports": hybrid_reports,
        "rendered_previews": rendered,
        "hybrid_rendered_previews": hybrid_rendered,
    }
    out_dir.mkdir(parents=True, exist_ok=True)
    report_path = out_dir / "REPORT.json"
    report_path.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(report, ensure_ascii=False, indent=2))
    return 0 if report["ok"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
