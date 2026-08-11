#!/usr/bin/env python3
"""Import every product still publicly enumerable on four official storefronts."""

from __future__ import annotations

import argparse
import html as html_lib
import json
import re
import time
import urllib.parse
import urllib.request
from concurrent.futures import ThreadPoolExecutor, as_completed
from datetime import date
from decimal import Decimal
from pathlib import Path

from import_commerce_batch import (
    SSL_CONTEXT,
    category_for,
    clean_text,
    save_image,
    styles_for,
)


PROJ = Path(__file__).resolve().parents[2]
CATALOG_DIR = PROJ / "ItemManager" / "Resources" / "TimeHall"
IMAGE_DIR = CATALOG_DIR / "images"
USER_AGENT = "PinkHouseTimeHallImporter/4.0 (+local app catalog)"
OBSERVED_AT = date.today().isoformat()

SHOPS = {
    "baby": {
        "catalog": "catalog-baby-stars-shine-bright.json",
        "base": "https://store.babyssb.co.jp",
        "feed": "https://store.babyssb.co.jp/products.json",
        "title": "BABY / ALICE and the PIRATES 官网公开商品",
        "sources": [
            "https://www.babyssb.co.jp/brand/",
            "https://store.babyssb.co.jp/collections/all",
        ],
    },
    "juliette": {
        "catalog": "catalog-juliette-et-justine.json",
        "base": "https://juliette-et-justine.com",
        "feed": "https://juliette-et-justine.com/products.json",
        "title": "Juliette et Justine 官网公开商品",
        "sources": [
            "https://juliette-et-justine.com/zh-cn/pages/about",
            "https://juliette-et-justine.com/collections/all",
        ],
    },
    "wunderwelt": {
        "catalog": "catalog-wunderwelt-fleur.json",
        "base": "https://www.wunderwelt.jp",
        "feed": "https://www.wunderwelt.jp/collections/fleur/products.json",
        "title": "Wunderwelt FLEUR 官方授权新品",
        "sources": [
            "https://libre.wunderwelt.jp/zh/9183/",
            "https://www.wunderwelt.jp/collections/fleur",
        ],
    },
}

AP_LIST = (
    "https://angelicpretty.com/Form/Product/ProductList.aspx"
    "?cat=&dpcnt=-1&fpfl=0&img=2&pno={page}&sfl=0&shop=0&sort=13&udns=0"
)
AP_CONFIG = {
    "catalog": "catalog-angelic-pretty.json",
    "base": "https://angelicpretty.com",
    "title": "Angelic Pretty 官网公开商品",
    "sources": [
        "https://angelicpretty.com/",
        "https://angelicpretty.com/Page/collection2026spring.aspx",
        AP_LIST.format(page=1),
    ],
}


def fetch(url: str) -> bytes:
    request = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    for attempt in range(4):
        try:
            with urllib.request.urlopen(request, timeout=60, context=SSL_CONTEXT) as response:
                return response.read()
        except Exception:
            if attempt == 3:
                raise
            time.sleep(1 << attempt)
    raise AssertionError("unreachable")


def money(value: object) -> int:
    return int(Decimal(str(value or "0")))


def unique(values: list[str]) -> list[str]:
    return list(dict.fromkeys(value.strip() for value in values if value and value.strip()))


def shopify_products(feed: str) -> list[dict]:
    products: list[dict] = []
    for page in range(1, 1000):
        separator = "&" if "?" in feed else "?"
        batch = json.loads(fetch(f"{feed}{separator}limit=250&page={page}"))["products"]
        products.extend(batch)
        if len(batch) < 250:
            return products
    raise RuntimeError(f"pagination limit reached: {feed}")


def shopify_item(product: dict, shop: dict, key: str) -> dict:
    variants = product.get("variants") or []
    prices = [money(value.get("price")) for value in variants if money(value.get("price")) > 0]
    sale_pairs = [
        (money(value.get("compare_at_price")), money(value.get("price")))
        for value in variants
        if money(value.get("compare_at_price")) > money(value.get("price")) > 0
    ]
    regular_price = min(pair[0] for pair in sale_pairs) if sale_pairs else min(prices or [0])
    sale_price = min(pair[1] for pair in sale_pairs) if sale_pairs else None
    description = clean_text(product.get("body_html") or "")
    kind, category, category_zh = category_for(
        product["title"], product.get("product_type") or "その他"
    )
    styles, styles_zh = styles_for(product["title"], description)
    option_values: dict[str, list[str]] = {}
    for option in product.get("options") or []:
        option_values[str(option.get("name", "")).lower()] = unique(option.get("values") or [])
    sizes = unique([
        value
        for name, values in option_values.items()
        if "size" in name or "サイズ" in name
        for value in values
    ])
    colors = unique([
        value
        for name, values in option_values.items()
        if "size" not in name and "サイズ" not in name
        for value in values
        if value != "Default Title"
    ])
    product_code = next(
        (str(value.get("sku")).strip() for value in variants if value.get("sku")),
        product["handle"],
    )
    image_urls = unique([value.get("src", "") for value in product.get("images") or []])
    return {
        "id": f"commerce-{key}-{product['id']}",
        "productCode": product_code,
        "kind": kind,
        "category": category,
        "categoryZH": category_zh,
        "name": product["title"].strip(),
        "nameZH": product["title"].strip(),
        "brand": (product.get("vendor") or shop["title"]).strip(),
        "sourceKind": "current",
        "regularPriceJPY": regular_price,
        "salePriceJPY": sale_price,
        "listingStatus": "in_stock" if any(value.get("available") for value in variants) else "sold_out",
        "description": description,
        "colors": colors,
        "sizes": sizes,
        "material": None,
        "countryOfOrigin": None,
        "styles": styles,
        "stylesZH": styles_zh,
        "coverImage": f"commerce-{key}-{product['id']}-cover.jpg",
        "detailImage": None,
        "imageSourceURLs": image_urls,
        "productPageURL": f"{shop['base']}/products/{product['handle']}",
        "observedAt": OBSERVED_AT,
    }


def ap_listing(text: str) -> list[dict]:
    items = []
    for block in text.split('<div class="product-list__item">')[1:]:
        href = re.search(r"href=['\"]([^'\"]*ProductDetail[^'\"]+)['\"]", block)
        name = re.search(r'<p class="detail__name">\s*<a[^>]*>(.*?)</a>', block, re.S)
        price = re.search(r'<p class="detail__price--normal">\s*(?:&yen;|&#165;)([\d,]+)', block)
        image = re.search(r'<img[^>]+src="([^"]*ProductImages[^"]+_LL\.jpg)"', block)
        if not all((href, name, price, image)):
            continue
        url = urllib.parse.urljoin(AP_CONFIG["base"], html_lib.unescape(href.group(1)))
        items.append({
            "name": clean_text(name.group(1)),
            "price": int(price.group(1).replace(",", "")),
            "url": url,
            "image": urllib.parse.urljoin(AP_CONFIG["base"], image.group(1)),
        })
    return items


def ap_item(entry: dict) -> dict:
    text = fetch(entry["url"]).decode("utf-8", errors="ignore")
    code_match = re.search(r"商品コード：\s*([^<\s]+)", text)
    detail_match = re.search(r'<div class="tab01">(.*?)</div>', text, re.S)
    description = clean_text(detail_match.group(1)) if detail_match else ""
    code = code_match.group(1) if code_match else urllib.parse.parse_qs(
        urllib.parse.urlparse(entry["url"]).query
    )["pid"][0]
    colors = unique(re.findall(r'<div class="multiVariation__color(?: imgBottm)?">(.*?)</div>', text, re.S))
    sizes = unique(re.findall(r'<p class="multiVariation__size">(.*?)</p>', text, re.S))
    image_urls = unique([
        urllib.parse.urljoin(AP_CONFIG["base"], value)
        for value in re.findall(r'(/Contents/ProductImages/[^" ]+_LL\.jpg)', text)
        if "NowPrinting" not in value
    ])
    if entry["image"] not in image_urls:
        image_urls.insert(0, entry["image"])
    material_match = re.search(r"\[素材\](.*?)(?:\[|★|☆|$)", description, re.S)
    material = clean_text(material_match.group(1)) if material_match else None
    kind, category, category_zh = category_for(entry["name"], "その他")
    styles, styles_zh = styles_for(entry["name"], description)
    return {
        "id": "commerce-ap-" + re.sub(r"[^a-z0-9_-]+", "-", code.lower()),
        "productCode": code,
        "kind": kind,
        "category": category,
        "categoryZH": category_zh,
        "name": entry["name"],
        "nameZH": entry["name"],
        "brand": "Angelic Pretty",
        "sourceKind": "current",
        "regularPriceJPY": entry["price"],
        "salePriceJPY": None,
        "listingStatus": "in_stock" if "productAddCartBtn" in text else "sold_out",
        "description": description,
        "colors": colors,
        "sizes": sizes,
        "material": material,
        "countryOfOrigin": None,
        "styles": styles,
        "stylesZH": styles_zh,
        "coverImage": "commerce-ap-" + re.sub(r"[^a-z0-9_-]+", "-", code.lower()) + "-cover.jpg",
        "detailImage": None,
        "imageSourceURLs": image_urls,
        "productPageURL": entry["url"],
        "observedAt": OBSERVED_AT,
    }


def angelic_pretty_products(max_workers: int) -> list[dict]:
    first = fetch(AP_LIST.format(page=1)).decode("utf-8", errors="ignore")
    pages = max([int(value) for value in re.findall(r"pno=(\d+)", first)] or [1])
    listings = ap_listing(first)
    with ThreadPoolExecutor(max_workers=max_workers) as executor:
        futures = [
            executor.submit(fetch, AP_LIST.format(page=page)) for page in range(2, pages + 1)
        ]
        for future in futures:
            listings.extend(ap_listing(future.result().decode("utf-8", errors="ignore")))
    by_url = {item["url"]: item for item in listings}
    items = []
    with ThreadPoolExecutor(max_workers=max_workers) as executor:
        futures = {executor.submit(ap_item, item): item["url"] for item in by_url.values()}
        for completed, future in enumerate(as_completed(futures), 1):
            items.append(future.result())
            if completed % 50 == 0:
                print(f"angelic-pretty details: {completed}/{len(futures)}")
    return sorted(items, key=lambda item: item["productCode"])


def materialize_covers(key: str, items: list[dict], max_workers: int) -> None:
    missing = [
        item for item in items
        if item["imageSourceURLs"] and not (IMAGE_DIR / item["coverImage"]).exists()
    ]
    print(f"{key} covers: {len(items) - len(missing)} cached, {len(missing)} to download")

    def download(item: dict) -> None:
        destination = IMAGE_DIR / item["coverImage"]
        temporary = destination.with_suffix(".tmp.jpg")
        last_error = None
        for source_url in item["imageSourceURLs"][:3]:
            for attempt in range(4):
                try:
                    save_image(source_url, temporary, max_width=600, jpeg_quality=72)
                    temporary.replace(destination)
                    return
                except Exception as error:
                    last_error = error
                    if temporary.exists():
                        temporary.unlink()
                    if attempt < 3:
                        time.sleep(1 << attempt)
        raise last_error or RuntimeError(f"no cover image: {item['id']}")

    with ThreadPoolExecutor(max_workers=max_workers) as executor:
        futures = [executor.submit(download, item) for item in missing]
        for completed, future in enumerate(as_completed(futures), 1):
            future.result()
            if completed % 100 == 0 or completed == len(futures):
                print(f"{key} covers: {completed}/{len(futures)} downloaded", flush=True)


def materialize_existing_catalog(key: str, config: dict, max_workers: int) -> None:
    path = CATALOG_DIR / config["catalog"]
    catalog = json.loads(path.read_text(encoding="utf-8"))
    items = catalog["commerceItems"]
    for item in items:
        item["coverImage"] = f"{item['id']}-cover.jpg"
    materialize_covers(key, items, max_workers)
    temporary = path.with_suffix(".json.tmp")
    temporary.write_text(json.dumps(catalog, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    temporary.replace(path)


def write_catalog(key: str, config: dict, items: list[dict], dry_run: bool) -> None:
    if not items:
        raise ValueError(f"{key}: official feed returned no products")
    ids = [item["id"] for item in items]
    if len(ids) != len(set(ids)):
        raise ValueError(f"{key}: duplicate product ids")
    snapshot_id = f"commerce-{key}-{OBSERVED_AT}"
    snapshot = {
        "id": snapshot_id,
        "titleZH": config["title"],
        "observedAt": OBSERVED_AT,
        "sourceURLs": config["sources"],
        "itemIDs": ids,
        "currentItemIDs": ids,
        "outletItemIDs": [],
    }
    batch = {
        "id": f"commerce-{key}-official",
        "order": 100,
        "kind": "commerceSnapshot",
        "titleZH": config["title"],
        "importedAt": OBSERVED_AT,
        "sourceURLs": config["sources"],
        "catalogueIDs": [],
        "commerceSnapshotIDs": [snapshot_id],
        "coordinateIDs": [],
        "storyIDs": [],
        "eventIDs": [],
        "historyEntryIDs": [],
        "itemCount": len(items),
    }
    print(f"{key}: {len(items)} products ({sum(i['listingStatus'] == 'in_stock' for i in items)} in stock)")
    if dry_run:
        return
    path = CATALOG_DIR / config["catalog"]
    catalog = json.loads(path.read_text(encoding="utf-8"))
    previous_items = {item["id"]: item for item in catalog.get("commerceItems", [])}
    for item in items:
        previous = previous_items.get(item["id"], {})
        item["descriptionZH"] = (
            previous.get("descriptionZH", "")
            if previous.get("description") == item["description"]
            else ""
        )
    old_snapshots = {value["id"] for value in catalog.get("commerceSnapshots", [])}
    old_ids = {
        value
        for snapshot in catalog.get("commerceSnapshots", [])
        for value in snapshot.get("itemIDs", [])
        if snapshot["id"] in old_snapshots
    }
    catalog["commerceItems"] = [
        item for item in catalog.get("commerceItems", []) if item["id"] not in old_ids
    ] + items
    catalog["commerceSnapshots"] = [snapshot]
    catalog["importBatches"] = [
        value for value in catalog.get("importBatches", []) if value["id"] != batch["id"]
    ] + [batch]
    temporary = path.with_suffix(".json.tmp")
    temporary.write_text(json.dumps(catalog, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    temporary.replace(path)


def self_check() -> None:
    sample = {
        "id": 7, "title": "Ribbonジャンパースカート", "handle": "ribbon-jsk",
        "vendor": "Test", "product_type": "ジャンパースカート", "body_html": "<p>レース</p>",
        "images": [{"src": "https://cdn.shopify.com/test.jpg"}],
        "options": [{"name": "Color", "values": ["Pink"]}],
        "variants": [{"sku": "T-7", "price": "12000", "compare_at_price": "15000", "available": False}],
    }
    item = shopify_item(sample, {"base": "https://example.com", "title": "Test"}, "test")
    assert item["kind"] == "dress" and item["salePriceJPY"] == 12000
    assert item["regularPriceJPY"] == 15000 and item["colors"] == ["Pink"]


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--brand", choices=["all", "angelic-pretty", *SHOPS], default="all")
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--images-only", action="store_true")
    parser.add_argument("--skip-images", action="store_true")
    parser.add_argument("--max-items", type=int)
    parser.add_argument("--max-workers", type=int, default=8)
    parser.add_argument("--self-check", action="store_true")
    args = parser.parse_args()
    self_check()
    if args.self_check:
        print("self-check: PASS")
        return 0
    if args.max_items and not args.dry_run:
        raise SystemExit("--max-items is only allowed with --dry-run")
    if args.images_only and (args.dry_run or args.skip_images or args.max_items):
        raise SystemExit("--images-only cannot be combined with dry-run/skip/max-items")

    keys = ["angelic-pretty", *SHOPS] if args.brand == "all" else [args.brand]
    for key in keys:
        config = AP_CONFIG if key == "angelic-pretty" else SHOPS[key]
        if args.images_only:
            materialize_existing_catalog(key, config, args.max_workers)
            continue
        if key == "angelic-pretty":
            items = angelic_pretty_products(args.max_workers)
        else:
            products = shopify_products(config["feed"])
            items = [shopify_item(product, config, key) for product in products]
        if not args.dry_run and not args.skip_images:
            materialize_covers(key, items, args.max_workers)
        write_catalog(key, config, items[:args.max_items] if args.max_items else items, args.dry_run)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
