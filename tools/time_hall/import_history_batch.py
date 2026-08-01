#!/usr/bin/env python3
"""Import PINK HOUSE-related evidence from the official Melrose company history."""

from __future__ import annotations

import argparse
import html as html_lib
import json
import re
import ssl
import urllib.request
from datetime import date
from io import BytesIO
from pathlib import Path

from PIL import Image

SOURCE_URL = "https://www.melrose.co.jp/about-history/"
PROJ = Path(__file__).resolve().parents[2]
CATALOG_PATH = PROJ / "ItemManager" / "Resources" / "TimeHall" / "catalog.json"
IMAGE_DIR = CATALOG_PATH.parent / "images"
BATCHES_PATH = PROJ / "tools" / "time_hall" / "content_batches.json"
USER_AGENT = "PinkHouseTimeHallImporter/3.0 (+local app catalog)"
SSL_CONTEXT = ssl._create_unverified_context()
TARGET_YEARS = {1972, 1982, 1983, 1985, 2004, 2011}


def fetch(url: str) -> bytes:
    request = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    with urllib.request.urlopen(request, timeout=60, context=SSL_CONTEXT) as response:
        return response.read()


def clean_text(raw: str) -> str:
    value = re.sub(r"<br\s*/?>", "\n", raw, flags=re.I)
    value = re.sub(r"<[^>]+>", " ", value)
    value = html_lib.unescape(value).replace("\r", "")
    value = re.sub(r"[ \t\u3000]+", " ", value)
    value = re.sub(r" *\n *", "\n", value)
    return value.strip()


def parse_entries(raw: bytes) -> list[dict]:
    text = raw.decode("utf-8", errors="ignore")
    starts = list(re.finditer(
        r'<li class="corporate_history">\s*<div class="year"><span[^>]*>(\d{4})</span></div>',
        text,
        re.S,
    ))
    entries = []
    for index, match in enumerate(starts):
        year = int(match.group(1))
        if year not in TARGET_YEARS:
            continue
        end = starts[index + 1].start() if index + 1 < len(starts) else len(text)
        region = text[match.end():end]
        titles = list(re.finditer(r'<p class="history_detail_title">(.*?)</p>', region, re.S))
        candidates = []
        for title_index, title_match in enumerate(titles):
            block_end = titles[title_index + 1].start() if title_index + 1 < len(titles) else len(region)
            block = region[title_match.start():block_end]
            text_match = re.search(r'<p class="history_detail_text">(.*?)</p>', block, re.S)
            image_match = re.search(r'<img class="history_detail_image" src="([^"]+)"', block)
            if text_match:
                candidates.append({
                    "title": clean_text(title_match.group(1)),
                    "content": clean_text(text_match.group(1)),
                    "imageSourceURL": image_match.group(1) if image_match else None,
                })
        if year == 2011:
            selected = next(value for value in candidates if "PINK HOUSE" in value["content"])
        else:
            terms = {
                1972: "PINK HOUSE",
                1982: "ピンクハウス",
                1983: "INGEBORG",
                1985: "Karl Helmut",
                2004: "ピンクハウス",
            }
            selected = next(value for value in candidates if terms[year] in value["title"])
        slug = {
            1972: "pink-house-born",
            1982: "pink-house-company",
            1983: "ingeborg-born",
            1985: "karl-helmut-born",
            2004: "company-merger",
            2011: "melrose-return",
        }[year]
        image_source_url = selected["imageSourceURL"]
        entries.append({
            "id": "history-%d-%s" % (year, slug),
            "year": year,
            "title": selected["title"],
            "content": selected["content"],
            "sourceURL": SOURCE_URL,
            "coverImage": "history-%d-%s.jpg" % (year, slug) if image_source_url else None,
            "imageSourceURL": image_source_url,
            "observedAt": date.today().isoformat(),
        })
    entries.sort(key=lambda value: value["year"])
    if len(entries) != 6:
        raise ValueError("expected 6 PINK HOUSE history entries, got %d" % len(entries))
    return entries


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
        image.save(destination, "JPEG", quality=82, optimize=True, progressive=True)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--batch-id", default="history-evidence")
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--skip-images", action="store_true")
    args = parser.parse_args()

    manifest = json.loads(BATCHES_PATH.read_text(encoding="utf-8"))
    batch = next((value for value in manifest["batches"] if value["id"] == args.batch_id), None)
    if not batch or batch["kind"] != "history":
        raise SystemExit("unknown history batch: %s" % args.batch_id)

    entries = parse_entries(fetch(SOURCE_URL))
    print("history: %d PINK HOUSE evidence records" % len(entries), flush=True)
    if args.dry_run:
        print("dry-run: years=%s images=%d" % (
            ",".join(str(value["year"]) for value in entries),
            sum(value["coverImage"] is not None for value in entries),
        ))
        return 0

    if not args.skip_images:
        for entry in entries:
            if entry["imageSourceURL"]:
                save_image(entry["imageSourceURL"], IMAGE_DIR / entry["coverImage"])

    catalog = json.loads(CATALOG_PATH.read_text(encoding="utf-8"))
    old_entry_ids = {
        entry_id
        for value in catalog.get("importBatches", []) if value["id"] == args.batch_id
        for entry_id in value.get("historyEntryIDs", [])
    }
    catalog["historyEntries"] = [
        value for value in catalog.get("historyEntries", []) if value["id"] not in old_entry_ids
    ] + entries
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
        "eventIDs": [],
        "historyEntryIDs": [value["id"] for value in entries],
        "itemCount": len(entries),
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
    print("wrote %d history entries" % len(entries), flush=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
