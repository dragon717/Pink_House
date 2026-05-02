#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Audit AvatarCharacterKit assets.

The script is intentionally non-mutating. It validates the manifest, the static
PNG, and optional video/Live2D resource presence so the feature can ship with a
static fallback before Cubism assets are legally available.
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

try:
    from PIL import Image
except Exception as exc:
    print(json.dumps({"ok": False, "error": f"Pillow unavailable: {exc}"}, ensure_ascii=False, indent=2))
    sys.exit(2)

try:
    import yaml
except Exception:
    yaml = None


REQUIRED_ACTIONS = {
    "idle", "greet", "wave", "thinking", "happy", "shy",
    "stickerPresent", "touchHead", "touchBody", "sleep", "talkLoop",
}
REQUIRED_EXPRESSIONS = {"neutral", "smile", "surprised", "sad", "angry", "sleepy"}


def load_manifest(path: Path) -> dict:
    text = path.read_text(encoding="utf-8")
    if yaml is not None:
        return yaml.safe_load(text)

    # Minimal parser for this harness manifest. It keeps the script usable on a
    # clean macOS install where PyYAML is not present.
    result: dict = {"asset_roots": {}, "acceptance": {"static_image": {}, "magic_sticker_v1": {}}}
    current_list: str | None = None
    current_magic_list: str | None = None
    in_asset_roots = False
    in_static_acceptance = False
    in_magic_acceptance = False
    for raw_line in text.splitlines():
        line = raw_line.rstrip()
        stripped = line.strip()
        if not stripped or stripped.startswith("#"):
            continue
        if not line.startswith(" ") and ":" in stripped:
            key, value = stripped.split(":", 1)
            value = value.strip()
            in_asset_roots = key == "asset_roots"
            in_static_acceptance = False
            in_magic_acceptance = False
            current_magic_list = None
            current_list = key if key in {
                "required_actions",
                "required_expressions",
                "render_backends",
                "layer_outputs",
                "hairstyle_layer_outputs",
                "default_outfit_layer_outputs",
            } else None
            if current_list:
                result[current_list] = []
            elif value:
                result[key] = value
            continue
        if current_list and stripped.startswith("- "):
            result[current_list].append(stripped[2:].strip())
            continue
        if in_asset_roots and line.startswith("  ") and ":" in stripped:
            key, value = stripped.split(":", 1)
            result["asset_roots"][key.strip()] = value.strip()
            continue
        if stripped == "static_image:":
            in_static_acceptance = True
            in_magic_acceptance = False
            current_magic_list = None
            continue
        if stripped == "magic_sticker_v1:":
            in_static_acceptance = False
            in_magic_acceptance = True
            current_magic_list = None
            continue
        if in_magic_acceptance and line.startswith("  ") and not line.startswith("    ") and stripped.endswith(":"):
            in_magic_acceptance = False
            current_magic_list = None
            continue
        if in_static_acceptance and line.startswith("    ") and ":" in stripped:
            key, value = stripped.split(":", 1)
            value = value.strip()
            try:
                parsed_value: float | int = float(value) if "." in value else int(value)
            except ValueError:
                parsed_value = value
            result["acceptance"]["static_image"][key.strip()] = parsed_value
            continue
        if in_magic_acceptance and line.startswith("    "):
            if current_magic_list and stripped.startswith("- "):
                result["acceptance"]["magic_sticker_v1"][current_magic_list].append(stripped[2:].strip())
                continue
            if stripped.endswith(":"):
                key = stripped[:-1].strip()
                current_magic_list = key
                result["acceptance"]["magic_sticker_v1"][key] = []
                continue
            if ":" in stripped:
                key, value = stripped.split(":", 1)
                value = value.strip()
                try:
                    parsed_value: float | int = float(value) if "." in value else int(value)
                except ValueError:
                    parsed_value = value
                result["acceptance"]["magic_sticker_v1"][key.strip()] = parsed_value
                current_magic_list = None
                continue
    return result


def audit_png(path: Path, expected_ratio: float, tolerance: float, min_visible_percent: float, min_file_bytes: int) -> dict:
    if not path.exists():
        return {"path": str(path), "exists": False, "ok": False, "error": "missing"}
    image = Image.open(path).convert("RGBA")
    width, height = image.size
    alpha = image.getchannel("A")
    alpha_min, alpha_max = alpha.getextrema()
    nontransparent = sum(1 for value in alpha.getdata() if value > 0)
    total = max(width * height, 1)
    ratio = width / height if height else 0
    file_bytes = path.stat().st_size
    visible_percent = nontransparent / total * 100
    return {
        "path": str(path),
        "exists": True,
        "width": width,
        "height": height,
        "ratio": round(ratio, 6),
        "expected_ratio": expected_ratio,
        "ratio_ok": abs(ratio - expected_ratio) <= tolerance,
        "alpha_min": alpha_min,
        "alpha_max": alpha_max,
        "nontransparent_percent": round(visible_percent, 4),
        "visible_content_ok": visible_percent >= min_visible_percent,
        "file_bytes": file_bytes,
        "not_tiny_placeholder": file_bytes >= min_file_bytes,
        "ok": abs(ratio - expected_ratio) <= tolerance
        and visible_percent >= min_visible_percent
        and file_bytes >= min_file_bytes
        and alpha_max > 0,
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--manifest", default="temp/_live2d_avatar_harness/MANIFEST.yaml")
    parser.add_argument("--allow-missing-video", action="store_true")
    parser.add_argument("--allow-missing-live2d", action="store_true")
    parser.add_argument("--out")
    args = parser.parse_args()

    manifest_path = Path(args.manifest)
    manifest = load_manifest(manifest_path)

    actions = set(manifest.get("required_actions") or [])
    expressions = set(manifest.get("required_expressions") or [])
    missing_actions = sorted(REQUIRED_ACTIONS - actions)
    missing_expressions = sorted(REQUIRED_EXPRESSIONS - expressions)

    acceptance = manifest.get("acceptance", {}).get("static_image", {})
    static_path = Path(manifest["asset_roots"]["static_image"])
    static_report = audit_png(
        static_path,
        expected_ratio=float(acceptance.get("ratio", 0.75)),
        tolerance=float(acceptance.get("ratio_tolerance", 0.03)),
        min_visible_percent=float(acceptance.get("min_nontransparent_percent", 2.0)),
        min_file_bytes=int(acceptance.get("min_file_bytes", 8192)),
    )

    video_dir = Path(manifest["asset_roots"]["video"])
    video_files = sorted(str(path) for path in video_dir.glob("*.mov")) if video_dir.exists() else []
    video_ok = bool(video_files) or args.allow_missing_video

    live2d_dir = Path(manifest["asset_roots"]["live2d"])
    live2d_files = sorted(path.name for path in live2d_dir.glob("*")) if live2d_dir.exists() else []
    has_model3 = any(name.endswith(".model3.json") or name == "model3.json" for name in live2d_files)
    has_moc3 = any(name.endswith(".moc3") for name in live2d_files)
    live2d_ok = (has_model3 and has_moc3) or args.allow_missing_live2d

    layer_manifest_path = Path(manifest.get("asset_roots", {}).get("layer_manifest", ""))
    layer_dir = Path(manifest.get("asset_roots", {}).get("layers", ""))
    expected_layers = list(manifest.get("layer_outputs") or [])
    layer_manifest_ok = layer_manifest_path.exists()
    layer_manifest_error = None
    manifest_layer_names = []
    if layer_manifest_ok:
        try:
            layer_manifest = json.loads(layer_manifest_path.read_text(encoding="utf-8"))
            manifest_layer_names = [row.get("name") for row in layer_manifest.get("layers", [])]
        except Exception as exc:
            layer_manifest_ok = False
            layer_manifest_error = str(exc)
    missing_layer_files = [
        name for name in expected_layers
        if not (layer_dir / f"{name}.png").exists()
    ]
    missing_manifest_layers = sorted(set(expected_layers) - set(manifest_layer_names))
    layers_ok = layer_manifest_ok and not missing_layer_files and not missing_manifest_layers

    hairstyle_index_path = Path(manifest.get("asset_roots", {}).get("hairstyle_index", ""))
    hairstyle_root = Path(manifest.get("asset_roots", {}).get("hairstyles", ""))
    expected_hairstyle_layers = list(manifest.get("hairstyle_layer_outputs") or [])
    hairstyle_index_ok = hairstyle_index_path.exists()
    hairstyle_index_error = None
    hairstyle_entries = []
    hairstyle_reports = []
    if hairstyle_index_ok:
        try:
            hairstyle_index = json.loads(hairstyle_index_path.read_text(encoding="utf-8"))
            hairstyle_entries = list(hairstyle_index.get("hairstyles", []))
        except Exception as exc:
            hairstyle_index_ok = False
            hairstyle_index_error = str(exc)
    for style in hairstyle_entries:
        style_id = style.get("hairstyle_id")
        style_manifest_path = Path(style.get("manifest", ""))
        if not style_manifest_path.is_absolute() and not style_manifest_path.exists():
            style_manifest_path = hairstyle_root / str(style_id) / "hairstyle_manifest.json"
        style_report = {
            "hairstyle_id": style_id,
            "manifest": str(style_manifest_path),
            "manifest_ok": style_manifest_path.exists(),
            "source": None,
            "source_exists": False,
            "source_full_present": False,
            "source_is_hair_only": False,
            "missing_layer_files": expected_hairstyle_layers[:],
            "missing_manifest_layers": expected_hairstyle_layers[:],
            "show_in_sticker_list": None,
            "replaceable": None,
            "ok": False,
        }
        if style_manifest_path.exists():
            try:
                style_manifest = json.loads(style_manifest_path.read_text(encoding="utf-8"))
                style_layer_names = [row.get("name") for row in style_manifest.get("layers", [])]
                style_layer_dir = style_manifest_path.parent / "layers"
                source_value = str(style_manifest.get("source") or "")
                source_path = Path(source_value)
                if not source_path.is_absolute() and not source_path.exists():
                    source_path = style_manifest_path.parent / source_path.name
                source_full_present = (style_manifest_path.parent / "source_full.png").exists() or "source_full" in source_value
                missing_style_files = [
                    name for name in expected_hairstyle_layers
                    if not (style_layer_dir / f"{name}.png").exists()
                ]
                missing_style_manifest_layers = sorted(set(expected_hairstyle_layers) - set(style_layer_names))
                style_report.update({
                    "source": source_value,
                    "source_exists": source_path.exists(),
                    "source_full_present": source_full_present,
                    "source_is_hair_only": source_path.name == "source_hair_only.png",
                    "missing_layer_files": missing_style_files,
                    "missing_manifest_layers": missing_style_manifest_layers,
                    "show_in_sticker_list": style_manifest.get("show_in_sticker_list"),
                    "replaceable": style_manifest.get("replaceable"),
                    "ok": (
                        not missing_style_files
                        and not missing_style_manifest_layers
                        and source_path.exists()
                        and source_path.name == "source_hair_only.png"
                        and not source_full_present
                        and style_manifest.get("show_in_sticker_list") is False
                        and style_manifest.get("replaceable") is True
                    ),
                })
            except Exception as exc:
                style_report["manifest_error"] = str(exc)
        hairstyle_reports.append(style_report)
    hairstyles_ok = (
        hairstyle_index_ok
        and len(hairstyle_reports) >= 2
        and all(row.get("ok") for row in hairstyle_reports)
    )

    outfit_manifest_path = Path(manifest.get("asset_roots", {}).get("default_outfit_manifest", ""))
    outfit_layer_dir = Path(manifest.get("asset_roots", {}).get("default_outfit_layers", ""))
    expected_outfit_layers = list(manifest.get("default_outfit_layer_outputs") or [])
    outfit_manifest_ok = outfit_manifest_path.exists()
    outfit_manifest_error = None
    outfit_layer_names = []
    outfit_show_in_sticker_list = None
    if outfit_manifest_ok:
        try:
            outfit_manifest = json.loads(outfit_manifest_path.read_text(encoding="utf-8"))
            outfit_layer_names = [row.get("name") for row in outfit_manifest.get("layers", [])]
            outfit_show_in_sticker_list = outfit_manifest.get("show_in_sticker_list")
        except Exception as exc:
            outfit_manifest_ok = False
            outfit_manifest_error = str(exc)
    missing_outfit_layer_files = [
        name for name in expected_outfit_layers
        if not (outfit_layer_dir / f"{name}.png").exists()
    ]
    missing_outfit_manifest_layers = sorted(set(expected_outfit_layers) - set(outfit_layer_names))
    clothing_rules_path = Path(manifest.get("asset_roots", {}).get("clothing_split_rules", ""))
    outfit_layers_ok = (
        outfit_manifest_ok
        and outfit_show_in_sticker_list is False
        and not missing_outfit_layer_files
        and not missing_outfit_manifest_layers
        and clothing_rules_path.exists()
    )

    report = {
        "ok": static_report["ok"]
        and not missing_actions
        and not missing_expressions
        and layers_ok
        and hairstyles_ok
        and outfit_layers_ok
        and video_ok
        and live2d_ok,
        "manifest": str(manifest_path),
        "avatar_id": manifest.get("avatar_id"),
        "magic_sticker_v1_acceptance": manifest.get("acceptance", {}).get("magic_sticker_v1", {}),
        "actions_ok": not missing_actions,
        "missing_actions": missing_actions,
        "expressions_ok": not missing_expressions,
        "missing_expressions": missing_expressions,
        "static_image": static_report,
        "layers": {
            "dir": str(layer_dir),
            "manifest": str(layer_manifest_path),
            "manifest_ok": layer_manifest_ok,
            "manifest_error": layer_manifest_error,
            "expected_count": len(expected_layers),
            "missing_layer_files": missing_layer_files,
            "missing_manifest_layers": missing_manifest_layers,
            "ok": layers_ok,
        },
        "hairstyles": {
            "root": str(hairstyle_root),
            "index": str(hairstyle_index_path),
            "index_ok": hairstyle_index_ok,
            "index_error": hairstyle_index_error,
            "expected_layer_count": len(expected_hairstyle_layers),
            "styles": hairstyle_reports,
            "ok": hairstyles_ok,
        },
        "default_outfit_layers": {
            "dir": str(outfit_layer_dir),
            "manifest": str(outfit_manifest_path),
            "manifest_ok": outfit_manifest_ok,
            "manifest_error": outfit_manifest_error,
            "expected_count": len(expected_outfit_layers),
            "missing_layer_files": missing_outfit_layer_files,
            "missing_manifest_layers": missing_outfit_manifest_layers,
            "show_in_sticker_list": outfit_show_in_sticker_list,
            "clothing_split_rules": str(clothing_rules_path),
            "clothing_split_rules_exists": clothing_rules_path.exists(),
            "ok": outfit_layers_ok,
        },
        "video": {
            "dir": str(video_dir),
            "files": video_files,
            "ok": video_ok,
            "warning": None if video_files else "missing video pack; transparentVideo backend will fallback",
        },
        "live2d": {
            "dir": str(live2d_dir),
            "files": live2d_files,
            "has_model3_json": has_model3,
            "has_moc3": has_moc3,
            "ok": live2d_ok,
            "warning": None if has_model3 and has_moc3 else "missing Cubism package; live2d backend is spike shell only",
        },
    }

    text = json.dumps(report, ensure_ascii=False, indent=2)
    if args.out:
        out_path = Path(args.out)
        out_path.parent.mkdir(parents=True, exist_ok=True)
        out_path.write_text(text + "\n", encoding="utf-8")
    print(text)
    return 0 if report["ok"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
