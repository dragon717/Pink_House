#!/usr/bin/env python3
"""Scrape https://pinkhouse-webshop.jp/pinkhouse/news into TimeHall local catalog.

ponytail: gallery capped at MAX_IMAGES_PER_ARTICLE + JPEG resize to keep app bundle sane.
Re-run anytime; images are skipped if already on disk.
"""

from __future__ import annotations

import html as html_lib
import json
import re
import sys
import time
import urllib.error
import urllib.request
from concurrent.futures import ThreadPoolExecutor, as_completed
from html.parser import HTMLParser
from io import BytesIO
from pathlib import Path

try:
    from PIL import Image
except ImportError:
    Image = None  # type: ignore

BASE = "https://pinkhouse-webshop.jp"
LIST_URL = f"{BASE}/pinkhouse/news"
PROJ = Path(__file__).resolve().parents[2]
OUT_DIR = PROJ / "ItemManager" / "Resources" / "TimeHall"
IMG_DIR = OUT_DIR / "images"
CATALOG_PATH = OUT_DIR / "catalog.json"
RAW_DIR = PROJ / "tools" / "time_hall" / "_artifacts"
CURATED_PATH = OUT_DIR / "catalog.curated.json"

MAX_IMAGES_PER_ARTICLE = 3
MAX_IMAGE_WIDTH = 800
JPEG_QUALITY = 70
REQUEST_PAUSE = 0.03
ARTICLE_WORKERS = 8
UA = "PinkHouseTimeHallScraper/1.0 (+local catalog seed)"

ARTICLE_HREF_RE = re.compile(r'href="(/pinkhouse/news/(\d+)\?news_tag_id=1)"')
PHOTO_RE = re.compile(r'(/photo/news/[^"\'\s>]+\.(?:jpg|jpeg|png|webp))', re.I)
TITLE_RE = re.compile(r'<h3 class="ttl">([^<]+)</h3>')
DATE_RE = re.compile(r'<span class="day">(\d{4})\.(\d{2})\.(\d{2})</span>')
NEXT_RE = re.compile(r'rel="next"\s+href="([^"]+)"')
BODY_RE = re.compile(
    r'<div class="detail-wrap">([\s\S]*?)(?:<div class="back-number">|BACK NUMBER)',
    re.I,
)


def fetch(url: str, retries: int = 3) -> bytes:
    req = urllib.request.Request(url, headers={"User-Agent": UA})
    last_err: Exception | None = None
    for i in range(retries):
        try:
            with urllib.request.urlopen(req, timeout=45) as resp:
                return resp.read()
        except Exception as exc:  # noqa: BLE001
            last_err = exc
            time.sleep(0.6 * (i + 1))
    raise RuntimeError(f"fetch failed {url}: {last_err}")


def fetch_text(url: str) -> str:
    return fetch(url).decode("utf-8", errors="ignore")


def season_for_month(month: int) -> tuple[str, str]:
    if month in (3, 4, 5):
        return "spring", "春"
    if month in (6, 7, 8):
        return "summer", "夏"
    if month in (9, 10, 11):
        return "autumn", "秋"
    return "winter", "冬"


def strip_tags(raw: str) -> str:
    text = re.sub(r"<br\s*/?>", "\n", raw, flags=re.I)
    text = re.sub(r"</(?:p|div|li|h\d)>", "\n", text, flags=re.I)
    text = re.sub(r"<[^>]+>", "", text)
    text = html_lib.unescape(text)
    text = re.sub(r"[ \t]+\n", "\n", text)
    text = re.sub(r"\n{3,}", "\n\n", text)
    return text.strip()


def infer_styles(title: str, body: str) -> tuple[list[str], list[str]]:
    blob = f"{title}\n{body}"
    rules = [
        ("Sale", "特卖", r"SALE|％OFF|%OFF|OUTLET"),
        ("Event", "活动", r"EVENT|イベント|ご招待|フェア"),
        ("Open", "开业", r"オープン|OPEN"),
        ("Campaign", "活动企划", r"campaign|キャンペーン|POINT"),
        ("Limited", "限定", r"限定|LIMITED"),
        ("Archive", "档案", r"アーカイブ|ARCHIVE"),
        ("Coordinate", "搭配", r"コーディネート|COORDINATE"),
        ("Catalogue", "图册", r"カタログ|CATALOGUE|LOOK"),
        ("Store", "店铺", r"店|SHOP|タカシマヤ|東武|銀座|横浜|名古屋"),
        ("Print", "印花", r"プリント|ローズ|ネコ|ベア|トランプ"),
    ]
    styles: list[str] = []
    styles_zh: list[str] = []
    for en, zh, pat in rules:
        if re.search(pat, blob, re.I):
            styles.append(en)
            styles_zh.append(zh)
    if not styles:
        styles, styles_zh = ["News"], ["资讯"]
    return styles[:5], styles_zh[:5]


def collect_article_ids() -> list[int]:
    cache = RAW_DIR / "article_ids.json"
    if cache.exists():
        ids = json.loads(cache.read_text(encoding="utf-8"))
        if isinstance(ids, list) and len(ids) > 100:
            print(f"[list] cached unique articles={len(ids)}", flush=True)
            return [int(x) for x in ids]

    ids: list[int] = []
    seen: set[int] = set()
    page = 1
    while True:
        url = f"{LIST_URL}?page={page}&news_tag_id=1"
        print(f"[list] page {page}", flush=True)
        text = fetch_text(url)
        found = [int(m.group(2)) for m in ARTICLE_HREF_RE.finditer(text)]
        new = 0
        for aid in found:
            if aid not in seen:
                seen.add(aid)
                ids.append(aid)
                new += 1
        if new == 0 and page > 1:
            break
        if not NEXT_RE.search(text):
            break
        page += 1
        time.sleep(REQUEST_PAUSE)
        if page > 300:
            break
    ids.sort(reverse=True)
    print(f"[list] unique articles={len(ids)}", flush=True)
    return ids


def save_image(url_path: str, dest: Path) -> bool:
    if dest.exists() and dest.stat().st_size > 0:
        return True
    url = url_path if url_path.startswith("http") else f"{BASE}{url_path}"
    try:
        data = fetch(url)
    except Exception as exc:  # noqa: BLE001
        print(f"  ! image fail {url}: {exc}", flush=True)
        return False

    dest.parent.mkdir(parents=True, exist_ok=True)
    if Image is None:
        dest.write_bytes(data)
        return True

    try:
        im = Image.open(BytesIO(data))
        im = im.convert("RGB")
        w, h = im.size
        if w > MAX_IMAGE_WIDTH:
            nh = int(h * (MAX_IMAGE_WIDTH / w))
            im = im.resize((MAX_IMAGE_WIDTH, nh), Image.Resampling.LANCZOS)
        dest = dest.with_suffix(".jpg")
        im.save(dest, format="JPEG", quality=JPEG_QUALITY, optimize=True)
        return True
    except Exception:
        dest.write_bytes(data)
        return True


def parse_article(article_id: int) -> dict | None:
    url = f"{BASE}/pinkhouse/news/{article_id}?news_tag_id=1"
    try:
        text = fetch_text(url)
    except Exception as exc:  # noqa: BLE001
        print(f"[skip] {article_id}: {exc}", flush=True)
        return None

    RAW_DIR.mkdir(parents=True, exist_ok=True)
    # ponytail: only keep HTML on parse failure; 700 full pages is needless disk

    title_m = TITLE_RE.search(text)
    date_m = DATE_RE.search(text)
    if not title_m or not date_m:
        (RAW_DIR / f"{article_id}.html").write_text(text, encoding="utf-8")
        print(f"[skip] {article_id}: missing title/date", flush=True)
        return None

    title = html_lib.unescape(title_m.group(1)).strip()
    year, month, day = map(int, date_m.groups())
    season, season_label = season_for_month(month)

    body_m = BODY_RE.search(text)
    body_html = body_m.group(1) if body_m else ""
    # Prefer article body photos; fall back to any /photo/news
    photos = []
    seen_p = set()
    for src in PHOTO_RE.findall(body_html) + PHOTO_RE.findall(text):
        if src in seen_p:
            continue
        # skip tiny icons / brand marks if any slip in
        if "brand_icon" in src or "assets/front" in src:
            continue
        seen_p.add(src)
        photos.append(src)

    photos = photos[:MAX_IMAGES_PER_ARTICLE]
    if not photos:
        print(f"[skip] {article_id}: no photos", flush=True)
        return None

    local_names: list[str] = []
    for idx, src in enumerate(photos):
        ext = Path(src).suffix.lower() or ".jpg"
        if ext not in {".jpg", ".jpeg", ".png", ".webp"}:
            ext = ".jpg"
        # normalized jpg after resize
        name = f"news_{article_id}_{idx}.jpg"
        ok = save_image(src, IMG_DIR / name)
        if ok and (IMG_DIR / name).exists():
            local_names.append(name)
        time.sleep(REQUEST_PAUSE)

    if not local_names:
        return None

    body_text = strip_tags(body_html)
    # trim very long store notices
    if len(body_text) > 1200:
        body_text = body_text[:1200].rstrip() + "…"

    styles, styles_zh = infer_styles(title, body_text)
    return {
        "id": f"news_{article_id}",
        "name": title,
        "nameZH": title,  # ponytail: JP source; ZH translation later
        "brand": "PINK HOUSE",
        "year": year,
        "season": season,
        "storeLimit": f"{year}.{month:02d}.{day:02d}",
        "storeLimitZH": f"{year}.{month:02d}.{day:02d}",
        "styles": styles,
        "stylesZH": styles_zh,
        "coverImage": local_names[0],
        "gallery": local_names,
        "note": body_text,
        "noteZH": body_text,
        "sourceURL": url,
        "_month": month,
        "_day": day,
        "_season_label": season_label,
    }


def build_catalog(dresses: list[dict]) -> dict:
    # Keep curated archive-print dresses if still present on disk
    curated_path = OUT_DIR / "catalog.curated.json"
    curated_dresses: list[dict] = []
    if curated_path.exists():
        curated_dresses = json.loads(curated_path.read_text(encoding="utf-8")).get("dresses", [])

    # Dedup: news entries win by id; curated ids that aren't news_* stay
    by_id = {d["id"]: d for d in curated_dresses}
    for d in dresses:
        clean = {k: v for k, v in d.items() if not k.startswith("_") and k != "sourceURL"}
        by_id[d["id"]] = clean

    all_dresses = list(by_id.values())
    all_dresses.sort(
        key=lambda d: (
            -int(d.get("year", 0)),
            d.get("storeLimitZH", ""),
            d.get("id", ""),
        )
    )

    # Collections: one per year-season that has news
    collections_map: dict[str, dict] = {}
    for d in dresses:
        key = f"{d['year']}_{d['season']}"
        if key not in collections_map:
            collections_map[key] = {
                "id": f"ph_news_{key}",
                "year": d["year"],
                "season": d["season"],
                "seasonLabel": d.get("_season_label", ""),
                "title": f"PINK HOUSE News {d['year']} {d.get('_season_label', '')}",
                "titleZH": f"PINK HOUSE 资讯 · {d['year']}{d.get('_season_label', '')}",
                "summary": "Official Pink House news lookbook archive.",
                "summaryZH": "PINK HOUSE 官方新闻馆藏。",
                "heroImage": d["coverImage"],
                "dressIds": [],
            }
        collections_map[key]["dressIds"].append(d["id"])

    # Also attach curated archive collection if present
    collections = sorted(collections_map.values(), key=lambda c: (-c["year"], c["season"]))
    if curated_path.exists():
        for c in json.loads(curated_path.read_text(encoding="utf-8")).get("collections", []):
            if c["id"] not in {x["id"] for x in collections}:
                collections.append(c)

    hero = dresses[0] if dresses else all_dresses[0]
    return {
        "version": 2,
        "source": "https://pinkhouse-webshop.jp/pinkhouse/news",
        "title": "梦裙时光馆",
        "subtitle": "PINK HOUSE 档案馆藏",
        "heroImage": hero["coverImage"],
        "heroCaption": hero["name"],
        "heroBody": (hero.get("noteZH") or hero.get("note") or "")[:160],
        "collections": collections,
        "dresses": all_dresses,
    }


def main() -> int:
    if "--allow-legacy-v2" not in sys.argv:
        print(
            "[blocked] This historical scraper emits destructive Time Hall V2 data. "
            "Use the V3 batch importers documented in tools/time_hall/README.md.",
            file=sys.stderr,
        )
        return 2
    sys.argv.remove("--allow-legacy-v2")
    IMG_DIR.mkdir(parents=True, exist_ok=True)
    OUT_DIR.mkdir(parents=True, exist_ok=True)

    # Snapshot current hand-curated catalog once
    curated_path = OUT_DIR / "catalog.curated.json"
    if CATALOG_PATH.exists() and not curated_path.exists():
        old = json.loads(CATALOG_PATH.read_text(encoding="utf-8"))
        curated = {
            "collections": [c for c in old.get("collections", []) if not str(c.get("id", "")).startswith("ph_news_")],
            "dresses": [d for d in old.get("dresses", []) if not str(d.get("id", "")).startswith("news_")],
        }
        curated_path.write_text(json.dumps(curated, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        print(f"[curated] saved {len(curated['dresses'])} dresses → {curated_path}", flush=True)

    if Image is None:
        print("[warn] Pillow not installed; images saved without resize", flush=True)
    else:
        print("[ok] Pillow resize enabled", flush=True)

    ids = collect_article_ids()
    RAW_DIR.mkdir(parents=True, exist_ok=True)
    (RAW_DIR / "article_ids.json").write_text(json.dumps(ids), encoding="utf-8")

    dresses: list[dict] = []
    done = 0
    ok = 0
    with ThreadPoolExecutor(max_workers=ARTICLE_WORKERS) as pool:
        futures = {pool.submit(parse_article, aid): aid for aid in ids}
        for fut in as_completed(futures):
            aid = futures[fut]
            done += 1
            try:
                item = fut.result()
            except Exception as exc:  # noqa: BLE001
                print(f"[err] {aid}: {exc}", flush=True)
                item = None
            if item:
                dresses.append(item)
                ok += 1
            if done % 10 == 0 or done == len(ids):
                print(f"[progress] {done}/{len(ids)} ok={ok}", flush=True)

    catalog = build_catalog(dresses)
    CATALOG_PATH.write_text(json.dumps(catalog, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(
        f"[done] dresses={len(catalog['dresses'])} collections={len(catalog['collections'])} → {CATALOG_PATH}",
        flush=True,
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
