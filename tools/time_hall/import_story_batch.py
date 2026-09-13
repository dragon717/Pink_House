#!/usr/bin/env python3
"""Import official PINK HOUSE Feature pages and the Melrose craft archive."""

from __future__ import annotations

import argparse
import html as html_lib
import json
import re
import ssl
import urllib.parse
import urllib.request
from concurrent.futures import ThreadPoolExecutor, as_completed
from datetime import date
from io import BytesIO
from pathlib import Path
from typing import List

from PIL import Image

SHOP = "https://pinkhouse-webshop.jp"
FEATURE_URL = SHOP + "/pinkhouse/contents"
CRAFT_URL = "https://www.melrose.co.jp/50th/melrose_monobooks_pinkhouse/"
PROJ = Path(__file__).resolve().parents[2]
CATALOG_PATH = PROJ / "ItemManager" / "Resources" / "TimeHall" / "catalog.json"
IMAGE_DIR = CATALOG_PATH.parent / "images"
BATCHES_PATH = PROJ / "tools" / "time_hall" / "content_batches.json"
USER_AGENT = "PinkHouseTimeHallImporter/3.0 (+local app catalog)"
# 必须验证证书：证书或抓取失败应中止对应批次，
# 不能以「不验证证书」维持发布成功（docs/Pink_House_TimeHall_Static_CloudKit_Design.md §1.2 G / §17.5）。
SSL_CONTEXT = ssl.create_default_context()


def fetch(url: str) -> bytes:
    request = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    with urllib.request.urlopen(request, timeout=60, context=SSL_CONTEXT) as response:
        return response.read()


def full_url(value: str, base: str = SHOP) -> str:
    return urllib.parse.urljoin(base, html_lib.unescape(value))


def clean_text(raw: str) -> str:
    value = re.sub(r"<(script|style)\b.*?</\1>", " ", raw, flags=re.I | re.S)
    value = re.sub(r"<(br|/p|/h[1-6]|/li|/dt|/dd|/section|/div)\b[^>]*>", "\n", value, flags=re.I)
    value = re.sub(r"<[^>]+>", " ", value)
    value = html_lib.unescape(value).replace("\r", "")
    value = re.sub(r"[ \t\u3000]+", " ", value)
    value = re.sub(r" *\n *", "\n", value)
    value = re.sub(r"\n{3,}", "\n\n", value)
    return value.strip()


def unique(values: List[str]) -> List[str]:
    return list(dict.fromkeys(value for value in values if value))


def parse_feature_listing(raw: bytes) -> List[dict]:
    text = raw.decode("utf-8", errors="ignore")
    pattern = re.compile(
        r'<li>\s*<dt>\s*<a href="([^"]+)" class="feature-item">\s*'
        r'<img src="([^"]+)" alt="[^"]*".*?</dt>\s*<dd>.*?'
        r'<h3 class="contents-title">\s*<a[^>]+>(.*?)</a>\s*</h3>\s*'
        r'<p class="contents-info">\s*<span class="day a-garamond">([^<]+)</span>',
        re.S,
    )
    found = []
    for source_url, image_url, title, published in pattern.findall(text):
        found.append({
            "sourceURL": full_url(source_url),
            "imageSourceURL": full_url(image_url),
            "title": clean_text(title),
            "publishedOn": published.strip().replace("/", "-"),
        })
    return found


def story_region(text: str) -> str:
    marker = text.find('id="goods_quick_view"')
    start = text.find("</div>", marker) + len("</div>") if marker >= 0 else 0
    end = text.find("<!-- footer", start)
    return text[start:end if end >= 0 else None]


def enrich_feature(entry: dict, commerce_id_by_code: dict) -> dict:
    text = fetch(entry["sourceURL"]).decode("utf-8", errors="ignore")
    region = story_region(text)
    images = unique([
        entry["imageSourceURL"],
        *[
            full_url(value)
            for value in re.findall(r'<img\b[^>]+src="([^"]+)"', region, re.I)
            if "/photo/page/" in value
        ],
    ])
    codes = unique([
        re.sub(r"_[13]$", "", value)
        for value in re.findall(r"/item/pinkhouse/1_1_([^/]+?)(?:_[13])?/\d+", region)
    ])
    content = clean_text(region)
    slug = urllib.parse.urlparse(entry["sourceURL"]).path.rstrip("/").split("/")[-1]
    return {
        "id": "story-feature-%s" % slug.lower(),
        "kind": "feature",
        "title": entry["title"],
        "publishedOn": entry["publishedOn"],
        "summary": content[:240].rstrip() + ("…" if len(content) > 240 else ""),
        "content": content,
        "sourceURL": entry["sourceURL"],
        "coverImage": "story-feature-%s.jpg" % slug.lower(),
        "imageSourceURLs": images,
        "productCodes": codes,
        "linkedCommerceItemIDs": [
            commerce_id_by_code[code] for code in codes if code in commerce_id_by_code
        ],
        "observedAt": date.today().isoformat(),
    }


def craft_story(commerce_id_by_code: dict) -> dict:
    text = fetch(CRAFT_URL).decode("utf-8", errors="ignore")
    match = re.search(r'<main class="monobooks-pinkhouse">(.*?)</main>', text, re.S)
    if not match:
        raise ValueError("craft archive main content missing")
    region = match.group(1)
    images = unique([
        full_url(value, CRAFT_URL)
        for value in re.findall(r'<img\b[^>]+src="([^"]+)"', region, re.I)
        if "/monobooks-pinkhouse/" in value and not value.lower().endswith(".svg")
    ])
    codes = unique(re.findall(r"\bA\d{4}[A-Z0-9_]+\b", region))
    content = clean_text(region)
    summary = (
        "从手捺染的 13～15 次套版、写实印花，到以印花为起点统一无地单品色调，"
        "记录 PINK HOUSE 如何延续可跨季叠穿的品牌工艺。"
    )
    return {
        "id": "story-craft-hand-screen-printing",
        "kind": "craft",
        "title": "手捺染で創る永遠のかわいい服",
        "publishedOn": None,
        "summary": summary,
        "content": content,
        "sourceURL": CRAFT_URL,
        "coverImage": "story-craft-hand-screen-printing.jpg",
        "imageSourceURLs": images,
        "productCodes": codes,
        "linkedCommerceItemIDs": [
            commerce_id_by_code[code] for code in codes if code in commerce_id_by_code
        ],
        "observedAt": date.today().isoformat(),
    }


def save_image(url: str, destination: Path) -> None:
    if destination.exists() and destination.stat().st_size > 0:
        return
    with Image.open(BytesIO(fetch(url))) as opened:
        image = opened.convert("RGB")
        if image.width > 1200:
            image = image.resize(
                (1200, round(image.height * 1200 / image.width)), Image.Resampling.LANCZOS
            )
        destination.parent.mkdir(parents=True, exist_ok=True)
        image.save(destination, "JPEG", quality=80, optimize=True, progressive=True)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--batch-id", default="feature-craft")
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--skip-images", action="store_true")
    parser.add_argument("--max-workers", type=int, default=8)
    args = parser.parse_args()

    manifest = json.loads(BATCHES_PATH.read_text(encoding="utf-8"))
    batch = next((value for value in manifest["batches"] if value["id"] == args.batch_id), None)
    if not batch or batch["kind"] != "story":
        raise SystemExit("unknown story batch: %s" % args.batch_id)

    with ThreadPoolExecutor(max_workers=4) as executor:
        pages = list(executor.map(
            lambda page: fetch("%s?page=%d" % (FEATURE_URL, page)), range(1, 5)
        ))
    listings = []
    for raw in pages:
        listings.extend(parse_feature_listing(raw))
    listings = list({value["sourceURL"]: value for value in listings}.values())
    if len(listings) != 35:
        raise ValueError("expected 35 official Feature pages, got %d" % len(listings))
    print("listing: %d Feature pages" % len(listings), flush=True)

    catalog = json.loads(CATALOG_PATH.read_text(encoding="utf-8"))
    commerce_id_by_code = {
        item["productCode"]: item["id"] for item in catalog.get("commerceItems", [])
    }
    stories = []
    with ThreadPoolExecutor(max_workers=args.max_workers) as executor:
        futures = [
            executor.submit(enrich_feature, entry, commerce_id_by_code) for entry in listings
        ]
        for index, future in enumerate(as_completed(futures), 1):
            stories.append(future.result())
            if index % 10 == 0:
                print("details: %d/%d" % (index, len(futures)), flush=True)
    order = {entry["sourceURL"]: index for index, entry in enumerate(listings)}
    stories.sort(key=lambda value: order[value["sourceURL"]])
    stories.append(craft_story(commerce_id_by_code))

    if not args.dry_run and not args.skip_images:
        with ThreadPoolExecutor(max_workers=args.max_workers) as executor:
            futures = [
                executor.submit(save_image, story["imageSourceURLs"][0], IMAGE_DIR / story["coverImage"])
                for story in stories
            ]
            for index, future in enumerate(as_completed(futures), 1):
                future.result()
                if index % 12 == 0:
                    print("images: %d/%d" % (index, len(futures)), flush=True)

    linked = sum(bool(value["linkedCommerceItemIDs"]) for value in stories)
    image_urls = sum(len(value["imageSourceURLs"]) for value in stories)
    if args.dry_run:
        print(
            "dry-run: stories=%d feature=35 craft=1 image_urls=%d linked_stories=%d"
            % (len(stories), image_urls, linked)
        )
        return 0

    old_story_ids = {
        story_id
        for value in catalog.get("importBatches", []) if value["id"] == args.batch_id
        for story_id in value.get("storyIDs", [])
    }
    catalog["stories"] = [
        value for value in catalog.get("stories", []) if value["id"] not in old_story_ids
    ] + stories
    for value in catalog.setdefault("importBatches", []):
        value.setdefault("commerceSnapshotIDs", [])
        value.setdefault("coordinateIDs", [])
        value.setdefault("storyIDs", [])
        value.setdefault("eventIDs", [])
        value.setdefault("historyEntryIDs", [])
    batch_record = {
        "id": batch["id"],
        "order": batch["order"],
        "kind": batch["kind"],
        "titleZH": batch["titleZH"],
        "importedAt": date.today().isoformat(),
        "sourceURLs": batch["sourceURLs"],
        "catalogueIDs": [],
        "commerceSnapshotIDs": [],
        "coordinateIDs": [],
        "storyIDs": [value["id"] for value in stories],
        "eventIDs": [],
        "historyEntryIDs": [],
        "itemCount": len(stories),
    }
    catalog["importBatches"] = [
        value for value in catalog["importBatches"] if value["id"] != args.batch_id
    ] + [batch_record]
    catalog["importBatches"].sort(key=lambda value: value["order"])
    temporary = CATALOG_PATH.with_suffix(".json.tmp")
    temporary.write_text(
        json.dumps(catalog, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    temporary.replace(CATALOG_PATH)
    print("wrote %d stories" % len(stories), flush=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
