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
    result: dict = {"asset_roots": {}, "acceptance": {"static_image": {}}}
    current_list: str | None = None
    in_asset_roots = False
    in_static_acceptance = False
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
            current_list = key if key in {"required_actions", "required_expressions", "render_backends", "layer_outputs"} else None
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

    report = {
        "ok": static_report["ok"]
        and not missing_actions
        and not missing_expressions
        and layers_ok
        and video_ok
        and live2d_ok,
        "manifest": str(manifest_path),
        "avatar_id": manifest.get("avatar_id"),
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
