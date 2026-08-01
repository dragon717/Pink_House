#!/usr/bin/env python3
"""Import the official PINK HOUSE Coordinate archive as relationship records."""

from __future__ import annotations

import argparse
import html as html_lib
import json
import re
import ssl
import urllib.request
from concurrent.futures import ThreadPoolExecutor, as_completed
from datetime import date
from io import BytesIO
from pathlib import Path
from typing import Dict, List, Optional

from PIL import Image

BASE = "https://pinkhouse-webshop.jp"
PROJ = Path(__file__).resolve().parents[2]
CATALOG_PATH = PROJ / "ItemManager" / "Resources" / "TimeHall" / "catalog.json"
IMAGE_DIR = CATALOG_PATH.parent / "images"
BATCHES_PATH = PROJ / "tools" / "time_hall" / "content_batches.json"
USER_AGENT = "PinkHouseTimeHallImporter/3.0 (+local app catalog)"
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
    value = html_lib.unescape(value).replace("\r", "")
    value = re.sub(r"[ \t]+", " ", value)
    value = re.sub(r"\n\s*\n+", "\n", value)
    return value.strip()


def parse_listing(raw: bytes) -> List[dict]:
    text = raw.decode("utf-8", errors="ignore")
    found = []
    for official_id, image_url, title in re.findall(
        r'<a href="/pinkhouse/coordinate/detail/(\d+)">\s*'
        r'<img src="([^"]+)" alt="([^"]+)"',
        text,
        re.S,
    ):
        if any(value["officialID"] == int(official_id) for value in found):
            continue
        found.append({
            "officialID": int(official_id),
            "title": html_lib.unescape(title).strip(),
            "thumbnailSourceURL": full_url(image_url),
        })
    return found


def published_on(title: str) -> Optional[str]:
    match = re.match(r"(\d{2})(\d{2})(\d{2})", title)
    if not match:
        return None
    year, month, day = map(int, match.groups())
    try:
        return date(2000 + year, month, day).isoformat()
    except ValueError:
        return None


def enrich(entry: dict, commerce_id_by_code: Dict[str, str]) -> dict:
    official_id = entry["officialID"]
    source_url = "%s/pinkhouse/coordinate/detail/%d" % (BASE, official_id)
    text = fetch(source_url).decode("utf-8", errors="ignore")
    core = text.split('<div class="recommendArea">', 1)[0]
    point_match = re.search(
        r'<div class="product_info__text"[^>]*>(.*?)</div>', core, re.S
    )
    point = clean_text(point_match.group(1)) if point_match else entry["title"]
    product_codes = list(dict.fromkeys(
        re.findall(r'/item/pinkhouse/1_1_([^/]+?)(?:_[13])?/\d+', core)
    ))
    # The display-manage suffix is sometimes captured with the product code; normalize it.
    product_codes = [re.sub(r"_[13]$", "", value) for value in product_codes]
    product_codes = list(dict.fromkeys(product_codes))
    linked_ids = [commerce_id_by_code[code] for code in product_codes if code in commerce_id_by_code]
    item_names = []
    for line in point.splitlines():
        value = re.sub(r"^［[^］]+］\s*", "", line).strip()
        match = re.match(r"(.+?)\s+¥[\d,]+", value)
        if match and match.group(1).strip() not in item_names:
            item_names.append(match.group(1).strip())
    image_match = re.search(
        r'coordinate-detail__top-pic.*?<img src="([^"]+)"', core, re.S
    )
    image_source_url = full_url(image_match.group(1)) if image_match else entry["thumbnailSourceURL"]
    return {
        "id": "coordinate-%d" % official_id,
        "officialID": official_id,
        "title": entry["title"],
        "publishedOn": published_on(entry["title"]),
        "coordinatePoint": point,
        "sourceURL": source_url,
        "coverImage": "coordinate-%d.jpg" % official_id,
        "imageSourceURL": image_source_url,
        "productCodes": product_codes,
        "linkedCommerceItemIDs": linked_ids,
        "unlinkedItemNames": item_names,
        "observedAt": date.today().isoformat(),
    }


def save_image(url: str, destination: Path) -> None:
    if destination.exists() and destination.stat().st_size > 0:
        return
    with Image.open(BytesIO(fetch(url))) as opened:
        image = opened.convert("RGB")
        if image.width > 1000:
            image = image.resize(
                (1000, round(image.height * 1000 / image.width)), Image.Resampling.LANCZOS
            )
        destination.parent.mkdir(parents=True, exist_ok=True)
        image.save(destination, "JPEG", quality=78, optimize=True, progressive=True)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--batch-id", default="coordinate-current")
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--skip-images", action="store_true")
    parser.add_argument("--max-workers", type=int, default=10)
    args = parser.parse_args()

    manifest = json.loads(BATCHES_PATH.read_text(encoding="utf-8"))
    batch = next((value for value in manifest["batches"] if value["id"] == args.batch_id), None)
    if not batch or batch["kind"] != "coordinate":
        raise SystemExit("unknown coordinate batch: %s" % args.batch_id)

    with ThreadPoolExecutor(max_workers=args.max_workers) as executor:
        pages = list(executor.map(
            lambda page: fetch("%s/pinkhouse/coordinate?page=%d" % (BASE, page)),
            range(1, 10),
        ))
    listings = []
    for raw in pages:
        listings.extend(parse_listing(raw))
    unique = {value["officialID"]: value for value in listings}
    listings = list(unique.values())
    if len(listings) != 150:
        raise ValueError("expected 150 official coordinates, got %d" % len(listings))
    print("listing: %d coordinates" % len(listings), flush=True)

    catalog = json.loads(CATALOG_PATH.read_text(encoding="utf-8"))
    commerce_id_by_code = {
        item["productCode"]: item["id"] for item in catalog.get("commerceItems", [])
    }
    coordinates = []
    with ThreadPoolExecutor(max_workers=args.max_workers) as executor:
        futures = {
            executor.submit(enrich, entry, commerce_id_by_code): entry["officialID"]
            for entry in listings
        }
        for index, future in enumerate(as_completed(futures), 1):
            coordinates.append(future.result())
            if index % 50 == 0:
                print("details: %d/%d" % (index, len(futures)), flush=True)
    order = {entry["officialID"]: index for index, entry in enumerate(listings)}
    coordinates.sort(key=lambda value: order[value["officialID"]])

    if not args.dry_run and not args.skip_images:
        with ThreadPoolExecutor(max_workers=args.max_workers) as executor:
            futures = [
                executor.submit(save_image, value["imageSourceURL"], IMAGE_DIR / value["coverImage"])
                for value in coordinates
            ]
            for index, future in enumerate(as_completed(futures), 1):
                future.result()
                if index % 50 == 0:
                    print("images: %d/%d" % (index, len(futures)), flush=True)

    linked = sum(bool(value["linkedCommerceItemIDs"]) for value in coordinates)
    products = sum(len(value["productCodes"]) for value in coordinates)
    if args.dry_run:
        print("dry-run: coordinates=%d product_refs=%d linked_looks=%d" % (
            len(coordinates), products, linked
        ))
        return 0

    old_coordinate_ids = {
        coordinate_id
        for value in catalog.get("importBatches", []) if value["id"] == args.batch_id
        for coordinate_id in value.get("coordinateIDs", [])
    }
    catalog["coordinates"] = [
        value for value in catalog.get("coordinates", []) if value["id"] not in old_coordinate_ids
    ] + coordinates
    for value in catalog.setdefault("importBatches", []):
        value.setdefault("commerceSnapshotIDs", [])
        value.setdefault("coordinateIDs", [])
        value.setdefault("storyIDs", [])
        value.setdefault("eventIDs", [])
        value.setdefault("historyEntryIDs", [])
    batch_record = {
        "id": batch["id"], "order": batch["order"], "kind": batch["kind"],
        "titleZH": batch["titleZH"], "importedAt": date.today().isoformat(),
        "sourceURLs": batch["sourceURLs"], "catalogueIDs": [],
        "commerceSnapshotIDs": [], "coordinateIDs": [value["id"] for value in coordinates],
        "storyIDs": [],
        "eventIDs": [],
        "historyEntryIDs": [],
        "itemCount": len(coordinates),
    }
    catalog["importBatches"] = [
        value for value in catalog["importBatches"] if value["id"] != args.batch_id
    ] + [batch_record]
    catalog["importBatches"].sort(key=lambda value: value["order"])
    temporary = CATALOG_PATH.with_suffix(".json.tmp")
    temporary.write_text(json.dumps(catalog, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    temporary.replace(CATALOG_PATH)
    print("wrote %d coordinates" % len(coordinates), flush=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
