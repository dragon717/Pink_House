#!/usr/bin/env python3
"""Import one declared official Catalogue batch into the Time Hall V3 catalog.

The importer is intentionally idempotent: rerunning a batch replaces only the deep
catalogue and items owned by that batch while preserving every other batch.
"""

from __future__ import annotations

import argparse
import hashlib
import html as html_lib
import json
import re
import ssl
import sys
import urllib.request
from datetime import date
from io import BytesIO
from pathlib import Path
from typing import Dict, Iterable, List, Optional, Tuple

try:
    from PIL import Image
except ImportError:
    Image = None

BASE = "https://pinkhouse-webshop.jp"
PROJ = Path(__file__).resolve().parents[2]
OUT_DIR = PROJ / "ItemManager" / "Resources" / "TimeHall"
IMAGE_DIR = OUT_DIR / "images"
CATALOG_PATH = OUT_DIR / "catalog.json"
BATCHES_PATH = PROJ / "tools" / "time_hall" / "content_batches.json"
USER_AGENT = "PinkHouseTimeHallImporter/3.0 (+local app catalog)"
MAX_IMAGE_WIDTH = 1200
JPEG_QUALITY = 80


def fetch(url: str) -> bytes:
    request = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    context = ssl.create_default_context()
    try:
        with urllib.request.urlopen(request, timeout=45, context=context) as response:
            return response.read()
    except Exception:
        # The local Python installation can lack the macOS trust-chain bridge.
        with urllib.request.urlopen(
            request, timeout=45, context=ssl._create_unverified_context()
        ) as response:
            return response.read()


def clean_text(raw: str) -> str:
    value = re.sub(r"<br\s*/?>", " ", raw, flags=re.I)
    value = re.sub(r"<[^>]+>", " ", value)
    value = html_lib.unescape(value)
    return re.sub(r"\s+", " ", value).strip()


def full_url(value: str) -> str:
    return value if value.startswith("https://") else BASE + value


def category_for(name: str) -> Tuple[str, str, str]:
    dress_rules = [
        ("ジャンパースカート", "JSK 连衣裙"),
        ("ミディワンピース", "中长 OP"),
        ("ワンピース", "OP 连衣裙"),
        ("チュニック", "长上衣"),
        ("スカート", "半身裙"),
        ("ドレス", "礼服"),
    ]
    clothing_rules = [
        ("カーディガン", "开衫"),
        ("ブラウス", "衬衫"),
        ("キャミソール", "吊带上衣"),
        ("ボレロ", "短外套"),
        ("ジャケット", "外套"),
        ("パーカ", "连帽上衣"),
        ("カットソー", "针织上衣"),
        ("ドロワーズ", "灯笼裤"),
        ("パンツ", "长裤"),
        ("ベスト", "背心"),
        ("ケープ", "披肩"),
        ("ニット", "针织衫"),
        ("シャツ", "衬衫"),
    ]
    accessory_rules = [
        ("ソックス", "袜子"),
        ("コサージュ", "胸花"),
        ("ブローチ", "胸针"),
        ("ネックレス", "项链"),
        ("ブレスレット", "手链"),
        ("ポシェット", "斜挎包"),
        ("バッグ", "包"),
        ("カチューシャ", "发箍"),
        ("シューズ", "鞋"),
        ("ブーツ", "靴子"),
        ("ストール", "披巾"),
        ("リボン", "蝴蝶结小物"),
        ("ワッペン", "布贴"),
    ]
    for token, label in dress_rules:
        if token in name:
            return "dress", token, label
    for token, label in clothing_rules:
        if token in name:
            return "clothing", token, label
    for token, label in accessory_rules:
        if token in name:
            return "accessory", token, label
    return "accessory", "その他", "其他小物"


def styles_for(name: str) -> Tuple[List[str], List[str]]:
    rules = [
        ("print", "印花", r"プリント"),
        ("frill", "荷叶边", r"フリル"),
        ("lace", "蕾丝", r"レース|ラッセル"),
        ("ribbon", "蝴蝶结", r"リボン"),
        ("embroidery", "刺绣", r"刺繍"),
        ("rose", "玫瑰", r"ローズ|薔薇|バラ"),
        ("lily-of-the-valley", "铃兰", r"鈴蘭"),
        ("dot", "圆点", r"ドット"),
        ("sprinkle-posy", "Sprinkle Posy", r"スプリンクルポジー"),
        ("creperie", "Crêperie", r"クレープリー"),
        ("rococo-ribbon", "洛可可蝴蝶结", r"ロココリボン"),
    ]
    styles = []
    styles_zh = []
    for value, value_zh, pattern in rules:
        if re.search(pattern, name):
            styles.append(value)
            styles_zh.append(value_zh)
    if not styles:
        return ["catalogue-look"], ["目录造型"]
    return styles[:5], styles_zh[:5]


def parse_product_code(href: Optional[str]) -> Optional[str]:
    if not href:
        return None
    match = re.search(r"/item/pinkhouse/1_1_([^/]+)/", href)
    return match.group(1) if match else None


def parse_catalogue(raw: bytes, config: dict) -> Tuple[dict, List[dict], Dict[int, str]]:
    text = raw.decode("utf-8", errors="ignore")
    title_match = re.search(r'<div class="catalog_title">(.*?)</div>', text, re.S)
    total_match = re.search(r'<span class="all_slide">(\d+)</span>', text)
    cover_match = re.search(
        r'href="([^"]*?/photo/catalog/\d+/[^"?]+\.jpg)"[^>]*>\s*'
        r'<img[^>]+data-index="00"',
        text,
        re.S | re.I,
    )
    if not title_match or not total_match or not cover_match:
        raise ValueError("catalogue title, page count, or cover image is missing")

    source_url = "%s/pinkhouse/catalog/detail/%s" % (BASE, config["officialID"])
    title = clean_text(title_match.group(1))
    page_count = int(total_match.group(1))
    page_source_urls = {}
    mentions = []

    for chunk in text.split('<div class="item_wrap">')[1:]:
        page_match = re.search(
            r'href="([^"]*?/photo/catalog/\d+/[^"?]+\.jpg)".*?data-index="(\d+)"',
            chunk,
            re.S | re.I,
        )
        items_match = re.search(r'<div class="text_items">(.*?)</div>', chunk, re.S)
        if not page_match or not items_match:
            continue
        page = int(page_match.group(2))
        if page <= 0:
            continue
        page_source_urls[page] = full_url(page_match.group(1))
        for paragraph in re.findall(r"<p>(.*?)</p>", items_match.group(1), re.S):
            value = clean_text(paragraph)
            item_match = re.match(r"(.+?)\s*¥([\d,]+)", value)
            if not item_match:
                continue
            name = item_match.group(1).strip()
            price = int(item_match.group(2).replace(",", ""))
            href_match = re.search(r'href="([^"]*?/item/pinkhouse/[^"]+)"', paragraph)
            href = full_url(href_match.group(1)) if href_match else None
            mentions.append(
                {"name": name, "price": price, "page": page, "productPageURL": href}
            )

    if not mentions or not page_source_urls:
        raise ValueError("catalogue contains no priced item mentions")

    by_name = {}
    for mention in mentions:
        entry = by_name.setdefault(
            mention["name"],
            {
                "name": mention["name"],
                "price": mention["price"],
                "pages": [],
                "productPageURL": mention["productPageURL"],
            },
        )
        if mention["page"] not in entry["pages"]:
            entry["pages"].append(mention["page"])
        if not entry["productPageURL"] and mention["productPageURL"]:
            entry["productPageURL"] = mention["productPageURL"]

    image_prefix = "ph-%s-%s" % (config["year"], config["season"])
    items = []
    for entry in by_name.values():
        pages = sorted(entry["pages"])
        kind, category, category_zh = category_for(entry["name"])
        styles, styles_zh = styles_for(entry["name"])
        product_code = parse_product_code(entry["productPageURL"])
        stable_suffix = product_code or hashlib.sha1(entry["name"].encode("utf-8")).hexdigest()[:12]
        item_id = "catalog-%s-%s" % (config["officialID"], stable_suffix.lower())
        page_images = ["%s-p%02d.jpg" % (image_prefix, page) for page in pages]
        canonical_key = "pink-house|%s-%s|%s" % (
            config["year"],
            config["season"],
            entry["name"],
        )
        note = "官方 %s 目录第 %s 页；价格为采集时页面展示的含税价格。官方商品名暂保留日文原文。" % (
            title,
            "、".join(str(page) for page in pages),
        )
        items.append(
            {
                "id": item_id,
                "canonicalKey": canonical_key,
                "kind": kind,
                "category": category,
                "categoryZH": category_zh,
                "name": entry["name"],
                "nameZH": entry["name"],
                "brand": "PINK HOUSE",
                "year": config["year"],
                "season": config["season"],
                "catalogueID": config["catalogueID"],
                "cataloguePage": pages[0],
                "priceJPY": entry["price"],
                "listingStatus": "catalogue_as_observed",
                "styles": styles,
                "stylesZH": styles_zh,
                "coverImage": page_images[0],
                "gallery": page_images,
                "imageSourceURL": page_source_urls[pages[0]],
                "sourceURL": source_url,
                "observedAt": date.today().isoformat(),
                "datePrecision": "season",
                "noteZH": note,
                "productCode": product_code,
                "productPageURL": entry["productPageURL"],
                "cataloguePages": pages,
            }
        )

    items.sort(key=lambda item: (item["cataloguePage"], item["name"]))
    catalogue = {
        "id": config["catalogueID"],
        "year": config["year"],
        "season": config["season"],
        "seasonLabel": config["seasonLabel"],
        "title": title,
        "titleZH": "%s 完整目录" % title,
        "summaryZH": config["summaryZH"],
        "sourceURL": source_url,
        "coverImage": config["coverImage"],
        "imageSourceURL": full_url(cover_match.group(1)),
        "pageCount": page_count,
        "itemIds": [item["id"] for item in items],
    }
    return catalogue, items, page_source_urls


def save_image(url: str, destination: Path) -> None:
    if destination.exists() and destination.stat().st_size > 0:
        return
    data = fetch(url)
    destination.parent.mkdir(parents=True, exist_ok=True)
    temporary = destination.with_suffix(".tmp")
    if Image is None:
        temporary.write_bytes(data)
    else:
        image = Image.open(BytesIO(data)).convert("RGB")
        if image.width > MAX_IMAGE_WIDTH:
            height = round(image.height * MAX_IMAGE_WIDTH / image.width)
            image = image.resize((MAX_IMAGE_WIDTH, height), Image.Resampling.LANCZOS)
        image.save(temporary, format="JPEG", quality=JPEG_QUALITY, optimize=True)
    temporary.replace(destination)


def validate_merge(catalog: dict) -> None:
    catalogue_ids = [value["id"] for value in catalog["catalogues"]]
    item_ids = [value["id"] for value in catalog["items"]]
    canonical_keys = [value["canonicalKey"] for value in catalog["items"]]
    if len(catalogue_ids) != len(set(catalogue_ids)):
        raise ValueError("duplicate deep catalogue IDs after merge")
    if len(item_ids) != len(set(item_ids)):
        raise ValueError("duplicate item IDs after merge")
    if len(canonical_keys) != len(set(canonical_keys)):
        raise ValueError("duplicate canonical item keys after merge")
    existing = set(item_ids)
    referenced = set()
    for catalogue in catalog["catalogues"]:
        referenced.update(catalogue["itemIds"])
    if referenced != existing:
        raise ValueError("catalogue item references do not match merged items")
    batch_ids = [value["id"] for value in catalog["importBatches"]]
    if len(batch_ids) != len(set(batch_ids)):
        raise ValueError("duplicate import batch IDs after merge")


def merge_batch(catalog: dict, batch: dict, catalogue_payloads: Iterable[Tuple[dict, List[dict]]]) -> dict:
    merged = json.loads(json.dumps(catalog, ensure_ascii=False))
    new_catalogues = []
    new_items = []
    for catalogue, items in catalogue_payloads:
        new_catalogues.append(catalogue)
        new_items.extend(items)

    owned_catalogue_ids = {value["id"] for value in new_catalogues}
    merged["catalogues"] = [
        value for value in merged.get("catalogues", []) if value["id"] not in owned_catalogue_ids
    ] + new_catalogues
    merged["items"] = [
        value
        for value in merged.get("items", [])
        if value.get("catalogueID") not in owned_catalogue_ids
    ] + new_items
    merged["catalogues"].sort(key=lambda value: (-value["year"], value["season"], value["id"]))
    merged["items"].sort(
        key=lambda value: (-value["year"], value["season"], value["cataloguePage"], value["id"])
    )
    merged.setdefault("scope", {})["sampleYears"] = sorted(
        {value["year"] for value in merged["catalogues"]}
    )

    batch_record = {
        "id": batch["id"],
        "order": batch["order"],
        "kind": batch["kind"],
        "titleZH": batch["titleZH"],
        "importedAt": date.today().isoformat(),
        "sourceURLs": batch["sourceURLs"],
        "catalogueIDs": [value["id"] for value in new_catalogues],
        "commerceSnapshotIDs": [],
        "coordinateIDs": [],
        "storyIDs": [],
        "eventIDs": [],
        "historyEntryIDs": [],
        "itemCount": len(new_items),
    }
    merged["importBatches"] = [
        value for value in merged.get("importBatches", []) if value["id"] != batch["id"]
    ] + [batch_record]
    merged["importBatches"].sort(key=lambda value: value["order"])

    latest = max(new_catalogues, key=lambda value: (value["year"], value["season"]))
    merged["heroImage"] = latest["coverImage"]
    merged["heroCaption"] = "%s 正式入馆" % latest["title"]
    merged["heroBody"] = "%s，共归档 %d 件官方定价商品。" % (
        batch["titleZH"],
        len(new_items),
    )
    validate_merge(merged)
    return merged


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--batch", required=True, help="Batch id from content_batches.json")
    parser.add_argument("--dry-run", action="store_true", help="Fetch and parse without writing")
    args = parser.parse_args()

    manifest = json.loads(BATCHES_PATH.read_text(encoding="utf-8"))
    batch = next((value for value in manifest["batches"] if value["id"] == args.batch), None)
    if not batch:
        raise SystemExit("unknown batch: %s" % args.batch)
    if batch["kind"] != "catalogue" or not batch.get("catalogues"):
        raise SystemExit("batch is not supported by the Catalogue importer: %s" % args.batch)

    catalog = json.loads(CATALOG_PATH.read_text(encoding="utf-8"))
    payloads = []
    images = []
    for config in batch["catalogues"]:
        source_url = "%s/pinkhouse/catalog/detail/%s" % (BASE, config["officialID"])
        print("[fetch] %s" % source_url, flush=True)
        catalogue, items, page_sources = parse_catalogue(fetch(source_url), config)
        payloads.append((catalogue, items))
        prefix = "ph-%s-%s" % (config["year"], config["season"])
        images.extend(
            (url, IMAGE_DIR / ("%s-p%02d.jpg" % (prefix, page)))
            for page, url in sorted(page_sources.items())
        )
        print(
            "[parsed] %s pages=%d unique_items=%d image_pages=%d"
            % (catalogue["title"], catalogue["pageCount"], len(items), len(page_sources)),
            flush=True,
        )

    merged = merge_batch(catalog, batch, payloads)
    if args.dry_run:
        print(
            "[dry-run] catalogues=%d items=%d batches=%d"
            % (len(merged["catalogues"]), len(merged["items"]), len(merged["importBatches"])),
            flush=True,
        )
        return 0

    for index, (url, destination) in enumerate(images, start=1):
        save_image(url, destination)
        print("[image] %d/%d %s" % (index, len(images), destination.name), flush=True)

    temporary = CATALOG_PATH.with_suffix(".json.tmp")
    temporary.write_text(
        json.dumps(merged, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    temporary.replace(CATALOG_PATH)
    print(
        "[done] catalogues=%d items=%d batches=%d -> %s"
        % (len(merged["catalogues"]), len(merged["items"]), len(merged["importBatches"]), CATALOG_PATH),
        flush=True,
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
