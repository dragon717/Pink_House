"""Render the three product-page scenes from visually approved native captures."""
import argparse
from pathlib import Path
from types import SimpleNamespace

from frame_screenshot import DEVICES, render

SCENES = ("wardrobe", "payments", "stats")
COPY = {
    "zh-Hans": (
        ("把喜欢的裙子收进衣橱", "用照片记下每一件，也记下每一种喜欢"),
        ("每笔尾款，心中有数", "按月查看待付金额和截止日期"),
        ("细数衣橱里的收藏", "从裙装件数到收藏价值，一页看清"),
    ),
    "zh-Hant": (
        ("把喜歡的裙子收進衣櫥", "用照片記下每一件，也記下每一種喜歡"),
        ("每筆尾款，心中有數", "按月查看待付金額和截止日期"),
        ("細數衣櫥裡的收藏", "從洋裝件數到收藏價值，一頁看清"),
    ),
    "en": (
        ("A wardrobe in pictures", "Keep a photo of every dress you love"),
        ("See what's due next", "View upcoming balances and due dates by month"),
        ("Your collection at a glance", "Explore dress counts and wardrobe value"),
    ),
}

OPEN_WARDROBE = {
    "zh-Hans": ("展开衣橱，看清裙装细节", "左侧浏览收藏，右侧查看喜欢的每一处细节"),
    "zh-Hant": ("展開衣櫥，看清洋裝細節", "左側瀏覽收藏，右側查看喜歡的每一處細節"),
    "en": ("A closer look at each dress", "Browse your wardrobe alongside every dress detail"),
}

DETAIL_COPY = {
    "zh-Hans": ("每件喜欢，都值得记下", "照片、价格与购入信息，随时回看"),
    "zh-Hant": ("每件喜歡，都值得記下", "照片、價格與購入資訊，隨時回看"),
    "en": ("Remember every favorite", "Keep photos, prices and purchase details together"),
}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("root", type=Path, help="Release folder with raw/ and frames/")
    parser.add_argument("devices", nargs="+", choices=DEVICES)
    parser.add_argument("--scenes", nargs="+", choices=(*SCENES, "detail"), default=SCENES)
    parser.add_argument("--locales", nargs="+", choices=COPY, default=list(COPY))
    args = parser.parse_args()
    for device in args.devices:
        for locale in args.locales:
            entries = COPY[locale]
            scenes = [*zip(SCENES, entries), ("detail", DETAIL_COPY[locale])]
            for number, (scene, (title, caption)) in enumerate(scenes, 1):
                if scene not in args.scenes:
                    continue
                stem = f"{number:02d}-{scene}.png"
                if scene == "detail":
                    number = 3
                    stem = "03-dress-details.png"
                if device == "duo-inner-landscape" and scene == "wardrobe":
                    stem = "02-open-wardrobe.png"
                    number = 2
                    title, caption = OPEN_WARDROBE[locale]
                render(SimpleNamespace(
                    device=device, locale=locale, frame=args.root / "frames" / f"{device}.png",
                    screen=args.root / "raw" / locale / device / f"{scene}.png",
                    output=args.root / "upload" / locale / device / stem,
                    kicker=f"WARDROBE NOTES   /   {number:02d}",
                    title=title, caption=caption, template=False,
                ))


if __name__ == "__main__":
    main()
