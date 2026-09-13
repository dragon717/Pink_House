#!/usr/bin/env python3
"""Import the official PINK HOUSE News archive as dated events."""

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

BASE = "https://pinkhouse-webshop.jp"
NEWS_URL = BASE + "/pinkhouse/news"
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


def full_url(value: str) -> str:
    return urllib.parse.urljoin(BASE, html_lib.unescape(value))


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


def parse_listing(raw: bytes) -> List[dict]:
    text = raw.decode("utf-8", errors="ignore")
    pattern = re.compile(
        r'<a href="/pinkhouse/news/(\d+)\?news_tag_id=1">\s*'
        r'<img src="([^"]+)" alt="([^"]*)" class="news_img"',
        re.S,
    )
    return [
        {
            "officialID": int(official_id),
            "imageSourceURL": full_url(image_url),
            "listingTitle": html_lib.unescape(title).strip(),
        }
        for official_id, image_url, title in pattern.findall(text)
    ]


def enrich(entry: dict, commerce_id_by_code: dict) -> dict:
    official_id = entry["officialID"]
    source_url = "%s/pinkhouse/news/%d" % (BASE, official_id)
    text = fetch(source_url).decode("utf-8", errors="ignore")
    main_start = text.find('<div class="mainContents">')
    pager_start = text.find('<div class="detail-pager">', main_start)
    region = text[main_start:pager_start if pager_start >= 0 else None]
    title_match = re.search(r'<h3 class="ttl">(.*?)</h3>', region, re.S)
    date_match = re.search(r'<span class="day">(\d{4}\.\d{2}\.\d{2})</span>', region)
    kind_match = re.search(r'<div class="blogTitle">([^<]+)</div>', region)
    content_start = region.find('<div class="detail-content">')
    content_region = region[content_start:] if content_start >= 0 else region
    title = clean_text(title_match.group(1)) if title_match else entry["listingTitle"]
    if not date_match:
        raise ValueError("news %d has no official date" % official_id)
    content = clean_text(content_region)
    if not content:
        content = title
    official_kind = clean_text(kind_match.group(1)).upper() if kind_match else ""
    event_terms = re.compile(
        r"イベント|フェア|POP\s*UP|開催|キャンペーン|受注会|展示会|発売|販売|"
        r"コラボ|限定|SALE|セール|MARK\s*DOWN|SPECIAL\s*PRICE",
        re.I,
    )
    kind = "event" if official_kind == "EVENT" or event_terms.search(title + "\n" + content) else "information"
    images = unique([
        entry["imageSourceURL"],
        *[
            full_url(value)
            for value in re.findall(r'<img\b[^>]+src="([^"]+)"', region, re.I)
            if "/photo/news/" in value
        ],
    ])
    codes = unique([
        re.sub(r"_[13]$", "", value)
        for value in re.findall(r"/item/pinkhouse/1_1_([^/]+?)(?:_[13])?/\d+", region)
    ])
    return {
        "id": "news-%d" % official_id,
        "officialID": official_id,
        "kind": kind,
        "title": title,
        "publishedOn": date_match.group(1).replace(".", "-"),
        "summary": content[:220].rstrip() + ("…" if len(content) > 220 else ""),
        "content": content,
        "sourceURL": source_url,
        "coverImage": "news-%d.jpg" % official_id,
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
        if image.width > 900:
            image = image.resize(
                (900, round(image.height * 900 / image.width)), Image.Resampling.LANCZOS
            )
        destination.parent.mkdir(parents=True, exist_ok=True)
        image.save(destination, "JPEG", quality=74, optimize=True, progressive=True)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--batch-id", default="news-timeline")
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--skip-images", action="store_true")
    parser.add_argument("--max-workers", type=int, default=20)
    args = parser.parse_args()

    manifest = json.loads(BATCHES_PATH.read_text(encoding="utf-8"))
    batch = next((value for value in manifest["batches"] if value["id"] == args.batch_id), None)
    if not batch or batch["kind"] != "news":
        raise SystemExit("unknown news batch: %s" % args.batch_id)

    with ThreadPoolExecutor(max_workers=args.max_workers) as executor:
        pages = list(executor.map(
            lambda page: fetch("%s?page=%d" % (NEWS_URL, page)), range(1, 62)
        ))
    listings = []
    for raw in pages:
        listings.extend(parse_listing(raw))
    listings = list({value["officialID"]: value for value in listings}.values())
    if len(listings) != 721:
        raise ValueError("expected 721 official News pages, got %d" % len(listings))
    print("listing: 61 pages / %d News records" % len(listings), flush=True)

    catalog = json.loads(CATALOG_PATH.read_text(encoding="utf-8"))
    commerce_id_by_code = {
        item["productCode"]: item["id"] for item in catalog.get("commerceItems", [])
    }
    events = []
    with ThreadPoolExecutor(max_workers=args.max_workers) as executor:
        futures = [executor.submit(enrich, entry, commerce_id_by_code) for entry in listings]
        for index, future in enumerate(as_completed(futures), 1):
            events.append(future.result())
            if index % 100 == 0:
                print("details: %d/%d" % (index, len(futures)), flush=True)
    order = {entry["officialID"]: index for index, entry in enumerate(listings)}
    events.sort(key=lambda value: order[value["officialID"]])

    if not args.dry_run and not args.skip_images:
        with ThreadPoolExecutor(max_workers=args.max_workers) as executor:
            futures = [
                executor.submit(save_image, event["imageSourceURLs"][0], IMAGE_DIR / event["coverImage"])
                for event in events
            ]
            for index, future in enumerate(as_completed(futures), 1):
                future.result()
                if index % 100 == 0:
                    print("images: %d/%d" % (index, len(futures)), flush=True)

    if args.dry_run:
        print(
            "dry-run: events=%d information=%d event=%d image_urls=%d linked=%d range=%s..%s"
            % (
                len(events),
                sum(value["kind"] == "information" for value in events),
                sum(value["kind"] == "event" for value in events),
                sum(len(value["imageSourceURLs"]) for value in events),
                sum(bool(value["linkedCommerceItemIDs"]) for value in events),
                min(value["publishedOn"] for value in events),
                max(value["publishedOn"] for value in events),
            )
        )
        return 0

    old_event_ids = {
        event_id
        for value in catalog.get("importBatches", []) if value["id"] == args.batch_id
        for event_id in value.get("eventIDs", [])
    }
    catalog["events"] = [
        value for value in catalog.get("events", []) if value["id"] not in old_event_ids
    ] + events
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
        "storyIDs": [],
        "eventIDs": [value["id"] for value in events],
        "historyEntryIDs": [],
        "itemCount": len(events),
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
    print("wrote %d events" % len(events), flush=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
