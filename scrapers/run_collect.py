#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Pink House 时光馆 · 商品素材采集入口。

用法示例：
    # 淘宝搜索并抓详情（含天猫商品）
    python scrapers/run_collect.py --platforms taobao --keywords "JK制服" --max-items 20

    # 同时抓三个平台
    python scrapers/run_collect.py -p taobao -p tmall -p xianyu -k "洛丽塔 女装"

    # 从已有 items.json 批量补下载图片（不重新抓页面）
    python scrapers/run_collect.py --only-images-from data/runs/xxx/items.json

输出结构：
    scrapers/data/runs/<时间戳>_<平台>_<关键词>/items.json   # 结构化数据
    scrapers/assets/images/<平台>/<关键词>/<商品ID>/NNN.jpg  # 静态图片
    scrapers/data/index.json                                 # 所有 run 的索引
"""
import argparse
import json
import logging
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent
sys.path.insert(0, str(ROOT.parent))  # 让 `scrapers` 可作为包导入

from scrapers.collectors.taobao import TaobaoCollector  # noqa: E402
from scrapers.collectors.xianyu import XianyuCollector  # noqa: E402
from scrapers.common.http_client import HttpClient  # noqa: E402
from scrapers.common.image_downloader import ImageDownloader  # noqa: E402

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(name)s: %(message)s")
log = logging.getLogger("run_collect")


def build_collector(platform: str, args):
    state_map = {}
    cfg = ROOT / "config.json"
    if cfg.exists():
        state_map = json.loads(cfg.read_text(encoding="utf-8")).get("storage_state", {})
    common = dict(scrapers_root=ROOT, headless=not args.no_headless, max_items=args.max_items)
    if platform in ("taobao", "tmall"):
        return TaobaoCollector(platform=platform,
                               storage_state=state_map.get("taobao"), **common)
    if platform == "xianyu":
        return XianyuCollector(storage_state=state_map.get("xianyu"), **common)
    raise ValueError(f"未知平台: {platform}")


def download_images_from_json(json_path: str) -> None:
    """把已有 items.json 里的 image_urls 补下载为静态文件（图片兜底通道）。"""
    path = Path(json_path)
    payload = json.loads(path.read_text(encoding="utf-8"))
    store_root = ROOT / "assets" / "images"
    dl = ImageDownloader(store_root, HttpClient())
    ok = fail = 0
    for item in payload.get("items", []):
        rel_dir = f"{payload.get('platform', 'unknown')}/{item.get('item_id', 'no_id')}"
        saved = []
        for i, url in enumerate(item.get("image_urls", []), 1):
            rel = dl.download(url, rel_dir, f"{i:03d}")
            if rel:
                saved.append(rel)
                ok += 1
            else:
                fail += 1
        item["images"] = saved
    out = path.with_name(path.stem + "_with_images.json")
    out.write_text(json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8")
    log.info("补图完成：成功 %s，失败 %s -> %s", ok, fail, out)


def main() -> None:
    ap = argparse.ArgumentParser(description="Pink House 商品素材采集")
    ap.add_argument("-p", "--platforms", nargs="+",
                    default=["taobao"], choices=["taobao", "tmall", "xianyu"])
    ap.add_argument("-k", "--keywords", nargs="+", required=False)
    ap.add_argument("--max-items", type=int, default=20, help="每个关键词最多抓取商品数")
    ap.add_argument("--no-headless", action="store_true", help="显示浏览器窗口便于过验证码")
    ap.add_argument("--only-images-from", metavar="ITEMS_JSON",
                    help="跳过抓取，仅从已有 items.json 补下载图片")
    args = ap.parse_args()

    if args.only_images_from:
        download_images_from_json(args.only_images_from)
        return
    if not args.keywords:
        ap.error("必须提供 --keywords（或使用 --only-images-from）")

    for kw in args.keywords:
        for platform in args.platforms:
            log.info("=== 开始采集 [%s] %r ===", platform, kw)
            try:
                collector = build_collector(platform, args)
                store = collector.collect(kw)
                log.info("=== 完成 [%s] %r：%s 个商品，输出 %s ===",
                         platform, kw, len(store.items), store.run_dir)
            except Exception as exc:  # noqa: BLE001
                log.error("采集失败 [%s] %r: %s", platform, kw, exc)


if __name__ == "__main__":
    main()
