"""Verify the actual upload ZIP against the native sizes used in this release."""
import argparse
import hashlib
import io
from collections import defaultdict
from pathlib import Path
from zipfile import ZipFile

from PIL import Image, ImageCms

from frame_screenshot import DEVICES

RELEASE_SCENES = ["01-wardrobe.png", "02-payments.png", "03-stats.png"]
RELEASE_LOCALES = ("zh-Hans", "zh-Hant", "en")
LABELS = {
    "iphone12": "iPhone 12 · Face ID 中屏",
    "iphone17pro": "iPhone 17 Pro · 灵动岛中屏",
    "iphone17promax": "iPhone 17 Pro Max · 灵动岛大屏",
    "ipad13": "13 英寸 iPad Pro",
    "duo-outer": "iPhone Duo 外屏",
    "duo-inner": "iPhone Duo 内屏",
    "duo-inner-landscape": "iPhone Duo 展开内屏（横向）",
}


def verify(root, archive):
    groups = defaultdict(list)
    source = root / "upload"
    names = {p.relative_to(source).as_posix() for p in source.rglob("*.png")}
    with ZipFile(archive) as bundle:
        if not names or sorted(names) != sorted(bundle.namelist()):
            raise ValueError("ZIP entries and upload PNGs differ")
        for name in sorted(names):
            locale, device, filename = Path(name).parts
            payload = bundle.read(name)
            if payload != (source / name).read_bytes():
                raise ValueError(f"ZIP content differs for {name}")
            with Image.open(io.BytesIO(payload)) as photo:
                if (photo.format != "PNG" or photo.size != DEVICES[device]
                        or photo.mode != "RGB" or "transparency" in photo.info):
                    raise ValueError(f"Invalid size, format or alpha channel in {name}")
                profile = ImageCms.ImageCmsProfile(io.BytesIO(photo.info["icc_profile"]))
                if "srgb" not in ImageCms.getProfileDescription(profile).lower():
                    raise ValueError(f"Unexpected color profile in {name}")
                photo.load()
            groups[locale, device].append(filename)
    for group, filenames in groups.items():
        if not 1 <= len(filenames) <= 10:
            raise ValueError(f"{group} needs 1 to 10 screenshots")
    for locale in RELEASE_LOCALES:
        for device in ("iphone12", "iphone17pro", "iphone17promax", "ipad13"):
            if sorted(groups[locale, device]) != RELEASE_SCENES:
                raise ValueError(f"Incomplete release scenes for {locale}/{device}")
        duo_count = sum(len(groups.get((locale, device), ())) for device in LABELS if device.startswith("duo-"))
        if duo_count > 10:
            raise ValueError(f"{locale} exceeds the shared iPhone Duo slot limit")
    return groups


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("archive", type=Path)
    args = parser.parse_args()
    archive = args.archive.resolve()
    groups = verify(archive.parent, archive)
    rows = ["# 商店截图上传尺寸核验", "",
            "逐张解码 ZIP 中的 PNG，并与上传目录的原文件逐字节比对。所有成图均为 RGB、sRGB，无透明通道。",
            "", "| App Store Connect 槽位 | 每张像素（宽 × 高） | 简中 | 繁中 | 英文 |",
            "|---|---:|---:|---:|---:|"]
    for device, label in LABELS.items():
        if not any(groups.get((loc, device)) for loc in RELEASE_LOCALES):
            continue
        w, h = DEVICES[device]
        counts = [str(len(groups[loc, device])) for loc in RELEASE_LOCALES]
        rows.append(" | ".join(["| " + label, f"{w} × {h}", *counts]) + " |")
    rows.extend(["", "每个已使用的设备栏位可上传 1–10 张。iPhone Duo 的内屏与外屏共用一个栏位，按语言合计张数。当前必备组为灵动岛中屏 iPhone 和支持 iPad 的 App 的 13 英寸 iPad。表内另说明，大屏灵动岛没有提交时需要提供大屏 Face ID 截图。本包覆盖中屏和大屏。Duo 从 2027 年 4 月起对使用 iOS 27.1 或更新 SDK 的 App 有截图要求。",
                 "", "核验对象为刻有标题、背景和官方设备框的整张商店图。每个槽位上传其语言目录中的独立 PNG。索引或预览拼图仅供选图。线上保存状态另以版本页为准。",
                 "", f"已核验 {sum(map(len, groups.values()))} 张。ZIP SHA-256 为 `{hashlib.sha256(archive.read_bytes()).hexdigest()}`。",
                 "", "[Apple 截图规格](https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications) · [Apple 上传步骤](https://developer.apple.com/help/app-store-connect/manage-app-information/upload-app-previews-and-screenshots/)", ""])
    (archive.parent / "上传尺寸核验.md").write_text("\n".join(rows), encoding="utf-8")
    print("\n".join(row for row in rows if row.startswith("|")))


if __name__ == "__main__":
    main()
