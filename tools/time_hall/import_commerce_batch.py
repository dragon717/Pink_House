#!/usr/bin/env python3
"""Import the declared PINK HOUSE current + OUTLET commerce snapshot.

The batch is stored separately from Catalogue exhibits because prices, stock and
product pages are volatile observations. Every item keeps a bundled cover and a
bundled detail image when the official page exposes one, plus the official image
URLs for provenance.
"""

from __future__ import annotations

import argparse
import html as html_lib
import json
import re
import ssl
import sys
import urllib.request
from concurrent.futures import ThreadPoolExecutor, as_completed
from datetime import date
from io import BytesIO
from pathlib import Path
from typing import Dict, List, Optional, Tuple

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
MAX_IMAGE_WIDTH = 900
JPEG_QUALITY = 76
SSL_CONTEXT = ssl._create_unverified_context()


def fetch(url: str) -> bytes:
    request = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    with urllib.request.urlopen(request, timeout=50, context=SSL_CONTEXT) as response:
        return response.read()


def full_url(value: str) -> str:
    return value if value.startswith("https://") else BASE + value


def clean_text(raw: str) -> str:
    value = re.sub(r"<br\s*/?>", "\n", raw, flags=re.I)
    value = re.sub(r"<[^>]+>", " ", value)
    value = html_lib.unescape(value)
    value = value.replace("\r", "")
    value = re.sub(r"[ \t]+", " ", value)
    value = re.sub(r"\n\s*\n+", "\n\n", value)
    return value.strip()


def yen(raw: str) -> int:
    return int(re.sub(r"\D", "", html_lib.unescape(raw)))


def category_for(name: str, official_category: str) -> Tuple[str, str, str]:
    haystack = "%s %s" % (name, official_category)
    dress_rules = [
        ("ジャンパースカート", "JSK 连衣裙"), ("ワンピース", "OP 连衣裙"),
        ("スカート", "半身裙"), ("ドレス", "礼服"),
    ]
    clothing_rules = [
        ("カーディガン", "开衫"), ("ブラウス", "衬衫"), ("シャツ", "衬衫"),
        ("ジャケット", "外套"), ("コート", "大衣"), ("パーカ", "连帽上衣"),
        ("カットソー", "针织上衣"), ("ニット", "针织衫"), ("パンツ", "长裤"),
        ("ベスト", "背心"), ("トップス", "上衣"), ("チュニック", "长上衣"),
    ]
    accessory_rules = [
        ("バッグ", "包"), ("ポーチ", "小包"), ("ソックス", "袜子"),
        ("シューズ", "鞋"), ("ブーツ", "靴子"), ("ハット", "帽子"),
        ("帽子", "帽子"), ("ネックレス", "项链"), ("ブローチ", "胸针"),
        ("コサージュ", "胸花"), ("アクセサリー", "饰品"), ("タオル", "生活小物"),
    ]
    for token, label in dress_rules:
        if token in haystack:
            return "dress", official_category or token, label
    for token, label in clothing_rules:
        if token in haystack:
            return "clothing", official_category or token, label
    for token, label in accessory_rules:
        if token in haystack:
            return "accessory", official_category or token, label
    return "accessory", official_category or "その他", official_category or "其他小物"


def styles_for(name: str, description: str) -> Tuple[List[str], List[str]]:
    text = "%s %s" % (name, description[:1200])
    rules = [
        ("print", "印花", r"プリント|捺染"), ("frill", "荷叶边", r"フリル"),
        ("lace", "蕾丝", r"レース|ラッセル"), ("ribbon", "蝴蝶结", r"リボン"),
        ("embroidery", "刺绣", r"刺繍"), ("rose", "玫瑰", r"ローズ|薔薇|バラ"),
        ("check", "格纹", r"チェック|ギンガム"), ("dot", "圆点", r"ドット|水玉"),
        ("layering", "叠穿", r"レイヤード|重ね"),
    ]
    styles, styles_zh = [], []
    for value, value_zh, pattern in rules:
        if re.search(pattern, text):
            styles.append(value)
            styles_zh.append(value_zh)
    return (styles or ["official-shop"], styles_zh or ["官方商品"])


def maximum_page(text: str) -> int:
    pages = [int(value) for value in re.findall(r"(?:&amp;|&)page=(\d+)", text)]
    return max(pages or [1])


def parse_listing(raw: bytes, source_kind: str) -> List[dict]:
    text = raw.decode("utf-8", errors="ignore")
    entries = []
    for chunk in text.split('<div class="item_archive__list"')[1:]:
        product_match = re.search(r'data-ga_ec_goods_id="([^"]+)"', chunk)
        name_match = re.search(r'data-ga_ec_goods_name="([^"]+)"', chunk)
        category_match = re.search(r'data-ga_ec_goods_category="([^"]*)"', chunk)
        href_match = re.search(r'class="goodsDetailLink" href="([^"]+)"', chunk)
        image_match = re.search(r'<div class="itemImage">.*?<img src="([^"]+)"', chunk, re.S)
        if not all([product_match, name_match, href_match, image_match]):
            continue
        price_html_match = re.search(r'<div class="priceWrapper.*?</div>', chunk, re.S)
        price_html = price_html_match.group(0) if price_html_match else ""
        regular_match = re.search(r'class="nonsale">\s*&yen;([\d,]+)', price_html)
        sale_match = re.search(r'class="sale">\s*&yen;([\d,]+)', price_html)
        plain_match = re.search(r'&yen;([\d,]+)', price_html)
        regular = yen(regular_match.group(1) if regular_match else plain_match.group(1)) \
            if (regular_match or plain_match) else 0
        sale = yen(sale_match.group(1)) if sale_match else None
        entries.append({
            "productCode": product_match.group(1),
            "name": html_lib.unescape(name_match.group(1)).strip(),
            "officialCategory": clean_text(category_match.group(1) if category_match else ""),
            "productPageURL": full_url(href_match.group(1)),
            "coverSourceURL": full_url(image_match.group(1)),
            "regularPriceJPY": regular,
            "salePriceJPY": sale,
            "sourceKind": source_kind,
        })
    return entries


def table_value(text: str, label: str) -> Optional[str]:
    match = re.search(
        r'<p class="item-name table-cell"[^>]*>\s*%s\s*</p>\s*'
        r'<p class="item-value table-cell">(.*?)</p>' % re.escape(label),
        text, re.S,
    )
    return clean_text(match.group(1)) if match else None


def enrich(entry: dict) -> dict:
    text = fetch(entry["productPageURL"]).decode("utf-8", errors="ignore")
    description_match = re.search(
        r'<div id="itemDiscSentence">(.*?)</div>', text, re.S
    )
    description = clean_text(description_match.group(1)) if description_match else ""
    colors = list(dict.fromkeys(re.findall(r'data-color_name="([^"]+)"', text)))
    sizes = []
    for raw_size in re.findall(r'<div class="size_name">(.*?)</div>', text, re.S):
        size = clean_text(raw_size).split("/")[0].strip()
        if size and size not in sizes:
            sizes.append(size)
    image_urls = []
    for value in re.findall(
        r'<img src="((?:https://pinkhouse-webshop\.jp)?/photo/[^\"]+\.jpg(?:\?[^\"]*)?)"',
        text,
    ):
        url = full_url(value)
        if url not in image_urls:
            image_urls.append(url)
    if entry["coverSourceURL"] not in image_urls:
        image_urls.insert(0, entry["coverSourceURL"])
    detail_source = next(
        (url for url in image_urls if "/z-" in url and url != entry["coverSourceURL"]),
        None,
    )
    kind, category, category_zh = category_for(entry["name"], entry["officialCategory"])
    styles, styles_zh = styles_for(entry["name"], description)
    product_code = entry["productCode"]
    stem = re.sub(r"[^a-z0-9_-]+", "-", product_code.lower())
    availability = "sold_out" if "https://schema.org/OutOfStock" in text else "in_stock"
    result = dict(entry)
    result.update({
        "id": "commerce-%s" % stem,
        "kind": kind,
        "category": category,
        "categoryZH": category_zh,
        "nameZH": entry["name"],
        "brand": "PINK HOUSE",
        "listingStatus": availability,
        "description": description,
        "colors": colors,
        "sizes": sizes,
        "material": table_value(text, "素材"),
        "countryOfOrigin": table_value(text, "原産国"),
        "styles": styles,
        "stylesZH": styles_zh,
        "coverImage": "commerce-%s-cover.jpg" % stem,
        "detailImage": "commerce-%s-detail.jpg" % stem if detail_source else None,
        "detailSourceURL": detail_source,
        "imageSourceURLs": image_urls,
        "observedAt": date.today().isoformat(),
    })
    result.pop("officialCategory", None)
    result.pop("coverSourceURL", None)
    return result


def save_image(
    source_url: str,
    destination: Path,
    max_width: int = MAX_IMAGE_WIDTH,
    jpeg_quality: int = JPEG_QUALITY,
) -> None:
    if Image is None:
        raise RuntimeError("Pillow is required to materialize commerce images")
    with Image.open(BytesIO(fetch(source_url))) as opened:
        image = opened.convert("RGB")
        if image.width > max_width:
            height = round(image.height * max_width / image.width)
            image = image.resize((max_width, height), Image.Resampling.LANCZOS)
        destination.parent.mkdir(parents=True, exist_ok=True)
        image.save(destination, "JPEG", quality=jpeg_quality, optimize=True, progressive=True)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--batch-id", default="commerce-current-outlet")
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--skip-images", action="store_true")
    parser.add_argument("--max-workers", type=int, default=10)
    args = parser.parse_args()

    manifest = json.loads(BATCHES_PATH.read_text(encoding="utf-8"))
    batch_config = next(
        (batch for batch in manifest["batches"] if batch["id"] == args.batch_id), None
    )
    if not batch_config or batch_config["kind"] != "commerceSnapshot":
        raise SystemExit("unknown commerceSnapshot batch: %s" % args.batch_id)

    source_specs = [
        ("current", "https://pinkhouse-webshop.jp/item?brand_label_codes=10&display_count=58"),
        ("outlet", "https://pinkhouse-webshop.jp/outlet?brand_label_codes=10&display_count=58"),
    ]
    listing_tasks = []
    with ThreadPoolExecutor(max_workers=args.max_workers) as executor:
        for source_kind, base_url in source_specs:
            first = fetch(base_url)
            listing_tasks.append((source_kind, first))
            for page in range(2, maximum_page(first.decode("utf-8", errors="ignore")) + 1):
                separator = "&" if "?" in base_url else "?"
                listing_tasks.append((source_kind, executor.submit(fetch, "%s%spage=%d" % (base_url, separator, page))))
        listing_pages = []
        for source_kind, value in listing_tasks:
            listing_pages.append((source_kind, value.result() if hasattr(value, "result") else value))

    listed = []
    for source_kind, raw in listing_pages:
        listed.extend(parse_listing(raw, source_kind))
    by_code: Dict[str, dict] = {}
    for source_position, entry in enumerate(listed):
        code = entry["productCode"]
        if code in by_code:
            raise ValueError("product appears more than once in commerce snapshot: %s" % code)
        entry["sourcePosition"] = source_position
        by_code[code] = entry
    print("listing: %d current + %d outlet = %d unique products" % (
        sum(item["sourceKind"] == "current" for item in by_code.values()),
        sum(item["sourceKind"] == "outlet" for item in by_code.values()),
        len(by_code),
    ))

    items = []
    with ThreadPoolExecutor(max_workers=args.max_workers) as executor:
        futures = {executor.submit(enrich, item): code for code, item in by_code.items()}
        completed = 0
        for future in as_completed(futures):
            items.append(future.result())
            completed += 1
            if completed % 50 == 0:
                print("details: %d/%d" % (completed, len(futures)))
    items.sort(key=lambda item: item["sourcePosition"])

    if not args.skip_images and not args.dry_run:
        image_jobs = []
        with ThreadPoolExecutor(max_workers=args.max_workers) as executor:
            for item in items:
                image_jobs.append(executor.submit(
                    save_image, item["imageSourceURLs"][0], IMAGE_DIR / item["coverImage"]
                ))
                if item["detailImage"] and item["detailSourceURL"]:
                    image_jobs.append(executor.submit(
                        save_image, item["detailSourceURL"], IMAGE_DIR / item["detailImage"]
                    ))
            for completed, future in enumerate(as_completed(image_jobs), 1):
                future.result()
                if completed % 100 == 0:
                    print("images: %d/%d" % (completed, len(image_jobs)))

    for item in items:
        item.pop("detailSourceURL", None)
        item.pop("sourcePosition", None)

    observed_at = date.today().isoformat()
    snapshot_id = "commerce-%s" % observed_at
    current_ids = [item["id"] for item in items if item["sourceKind"] == "current"]
    outlet_ids = [item["id"] for item in items if item["sourceKind"] == "outlet"]
    snapshot = {
        "id": snapshot_id,
        "titleZH": "PINK HOUSE 当前商品与 OUTLET",
        "observedAt": observed_at,
        "sourceURLs": batch_config["sourceURLs"],
        "itemIDs": current_ids + outlet_ids,
        "currentItemIDs": current_ids,
        "outletItemIDs": outlet_ids,
    }
    batch_record = {
        "id": batch_config["id"],
        "order": batch_config["order"],
        "kind": batch_config["kind"],
        "titleZH": batch_config["titleZH"],
        "importedAt": observed_at,
        "sourceURLs": batch_config["sourceURLs"],
        "catalogueIDs": [],
        "commerceSnapshotIDs": [snapshot_id],
        "coordinateIDs": [],
        "storyIDs": [],
        "eventIDs": [],
        "historyEntryIDs": [],
        "itemCount": len(items),
    }

    if args.dry_run:
        print("dry-run: %d items, %d with detail images" % (
            len(items), sum(bool(item["detailImage"]) for item in items)
        ))
        return 0

    catalog = json.loads(CATALOG_PATH.read_text(encoding="utf-8"))
    catalog.setdefault("commerceSnapshots", [])
    catalog.setdefault("commerceItems", [])
    for old_batch in catalog.setdefault("importBatches", []):
        old_batch.setdefault("commerceSnapshotIDs", [])
        old_batch.setdefault("coordinateIDs", [])
        old_batch.setdefault("storyIDs", [])
        old_batch.setdefault("eventIDs", [])
        old_batch.setdefault("historyEntryIDs", [])
    old_snapshot_ids = {
        snapshot_id
        for batch in catalog["importBatches"] if batch["id"] == args.batch_id
        for snapshot_id in batch.get("commerceSnapshotIDs", [])
    }
    old_item_ids = {
        item_id
        for snapshot in catalog["commerceSnapshots"] if snapshot["id"] in old_snapshot_ids
        for item_id in snapshot["itemIDs"]
    }
    catalog["commerceSnapshots"] = [
        value for value in catalog["commerceSnapshots"] if value["id"] not in old_snapshot_ids
    ] + [snapshot]
    catalog["commerceItems"] = [
        value for value in catalog["commerceItems"] if value["id"] not in old_item_ids
    ] + items
    catalog["importBatches"] = [
        value for value in catalog["importBatches"] if value["id"] != args.batch_id
    ] + [batch_record]
    catalog["importBatches"].sort(key=lambda value: value["order"])

    temporary = CATALOG_PATH.with_suffix(".json.tmp")
    temporary.write_text(
        json.dumps(catalog, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    temporary.replace(CATALOG_PATH)
    print("wrote %s with %d commerce items" % (CATALOG_PATH, len(items)))
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except KeyboardInterrupt:
        raise SystemExit(130)
    except Exception as error:
        print("error: %s" % error, file=sys.stderr)
        raise
