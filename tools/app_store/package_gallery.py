"""Package approved upload PNGs, validating the actual archive before replacing it."""
import argparse
import json
from pathlib import Path
from tempfile import TemporaryDirectory
from zipfile import ZIP_STORED, ZipFile

from PIL import Image, ImageDraw, ImageFont

from frame_screenshot import DEVICES
from verify_gallery import verify


def package(root):
    paths = sorted((root / "upload").glob("*/*/*.png"))
    archive = root / "少女心愿-4.4-商店截图.zip"
    with TemporaryDirectory(dir=root) as work:
        candidate = Path(work) / archive.name
        with ZipFile(candidate, "w", compression=ZIP_STORED) as bundle:
            for path in paths:
                bundle.write(path, path.relative_to(root / "upload"))
        verify(root, candidate)
        candidate.replace(archive)
    rows = []
    for path in paths:
        locale, device, scene = path.relative_to(root / "upload").parts
        rows.append({"device": device, "locale": locale, "scene": scene,
                     "dimensions": DEVICES[device], "file": str(path.relative_to(root))})
    (root / "screenshots.json").write_text(json.dumps(rows, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    preview(root)
    print(f"Packaged and verified {len(rows)} screenshots: {archive}")


def preview(root):
    board = Image.new("RGB", (1320, 700), "#fcf4e9")
    draw = ImageDraw.Draw(board)
    font = "/System/Library/Fonts/Supplemental/Songti.ttc"
    draw.text((660, 46), "少女心愿  ·  4.4 商店截图", anchor="mm",
              font=ImageFont.truetype(font, 32), fill="#62434c")
    examples = [("iphone12", "01-wardrobe", "iPhone 12"),
                ("iphone17pro", "02-payments", "iPhone 17 Pro"),
                ("iphone17promax", "03-stats", "iPhone 17 Pro Max"),
                ("ipad13", "01-wardrobe", "iPad Pro 13″")]
    for column, (device, scene, label) in enumerate(examples):
        with Image.open(root / "upload" / "zh-Hans" / device / f"{scene}.png") as photo:
            photo.thumbnail((300, 530))
            center = 165 + 330 * column
            board.paste(photo, (center - photo.width // 2, 92 + (530 - photo.height) // 2))
        draw.text((center, 654), label, anchor="mm", font=ImageFont.truetype(font, 23), fill="#6f5359")
    board.save(root / "商店图预览.jpg", quality=91)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("root", type=Path)
    package(parser.parse_args().root)
