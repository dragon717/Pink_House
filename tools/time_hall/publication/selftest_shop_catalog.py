#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""商店目录发布前处理自测（纯逻辑，不联网）：
   · `strip_archived_shop_catalog`：归档条目连带剔除，且剔除后不得留下悬空引用
   · 未归档内容一个不动；墓碑保留

用法：
    python3 selftest_shop_catalog.py
"""
from __future__ import annotations

import copy
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from protocol import (  # noqa: E402
    COVERAGE_COMPLETE,
    strip_archived_shop_catalog,
    validate_shop_catalog,
)

BRAND = "shaonv-xinyuan"

failures = []


def check(label, condition, detail=""):
    if condition:
        print("  ✓ {}".format(label))
    else:
        print("  ✗ {} {}".format(label, detail))
        failures.append(label)


def make_catalog():
    return {
        "version": 1,
        "shops": [
            {"id": "shop-live", "name": "在售店家", "logo": "asset-live-logo"},
            {"id": "shop-arch", "name": "归档店家", "archivedAt": "2026-09-01T00:00:00Z",
             "logo": "asset-arch-logo"},
        ],
        "series": [
            {"id": "series-live", "shopID": "shop-live", "name": "在售系列"},
            {"id": "series-arch", "shopID": "shop-arch", "name": "归档店家的系列"},
            {"id": "series-arch-self", "shopID": "shop-live", "name": "自己归档的系列",
             "archivedAt": "2026-09-02T00:00:00Z"},
        ],
        "products": [
            {"id": "prod-live", "shopID": "shop-live", "seriesID": "series-live",
             "name": "在售商品", "category": "JSK", "images": ["asset-live-img"]},
            {"id": "prod-arch", "shopID": "shop-live", "seriesID": "series-live",
             "name": "归档商品", "category": "JSK", "images": ["asset-arch-img"],
             "archivedAt": "2026-09-03T00:00:00Z"},
            {"id": "prod-arch-series", "shopID": "shop-live", "seriesID": "series-arch-self",
             "name": "归档系列下的商品", "category": "OP", "images": []},
        ],
        "variants": [
            {"id": "var-live", "productID": "prod-live", "color": "粉", "imageAssetID": "asset-live-img"},
            {"id": "var-arch", "productID": "prod-arch", "color": "蓝"},
        ],
        "sizeCharts": [
            {"id": "chart-live", "productID": "prod-live", "sourceImage": "asset-arch-chart"},
            {"id": "chart-arch", "productID": "prod-arch", "sourceImage": "asset-arch-chart"},
        ],
        "saleEvents": [
            {"id": "ev-live", "productID": "prod-live", "type": "reservation", "price": 328},
            {"id": "ev-arch", "productID": "prod-arch", "type": "reservation", "price": 299},
        ],
        "assets": [
            {"id": "asset-live-logo", "type": "shopCover", "originalURL": "local:a.jpg"},
            {"id": "asset-live-img", "type": "productImage", "originalURL": "local:b.jpg"},
            {"id": "asset-arch-logo", "type": "shopCover", "originalURL": "local:c.jpg"},
            {"id": "asset-arch-img", "type": "productImage", "originalURL": "local:d.jpg"},
            {"id": "asset-arch-chart", "type": "sizeChartImage", "originalURL": "local:e.jpg"},
            {"id": "asset-orphan", "type": "productImage", "originalURL": "local:f.jpg"},
        ],
        "styleProfiles": [
            {"id": "profile-live", "seriesID": "series-live", "category": "JSK", "designName": "在售款"},
            {"id": "profile-arch", "seriesID": "series-arch-self", "category": "OP", "designName": "归档款"},
        ],
        "removedShopIDs": ["shop-gone"],
        "removedSeriesIDs": [],
        "removedProductIDs": [],
    }


print("=== strip_archived_shop_catalog ===")

# 1) 未归档时一个不动（含孤儿图片也必须原样留着）
clean_source = make_catalog()
clean_source["shops"] = [clean_source["shops"][0]]
clean_source["series"] = [clean_source["series"][0]]
clean_source["products"] = [clean_source["products"][0]]
clean_source["variants"] = [clean_source["variants"][0]]
clean_source["sizeCharts"] = [clean_source["sizeCharts"][0]]
clean_source["saleEvents"] = [clean_source["saleEvents"][0]]
clean_source["styleProfiles"] = [clean_source["styleProfiles"][0]]
unchanged, clean_report = strip_archived_shop_catalog(copy.deepcopy(clean_source))
check("未归档目录：一条都不剔除", all(value == 0 for value in clean_report.values()),
      str(clean_report))
check("未归档目录：内容逐字段等价",
      all(unchanged[field] == clean_source[field]
          for field in ("shops", "series", "products", "variants",
                        "sizeCharts", "saleEvents", "styleProfiles", "assets")))

# 2) 归档连带剔除
doc = make_catalog()
cleaned, report = strip_archived_shop_catalog(copy.deepcopy(doc))

check("归档店家被剔除", [s["id"] for s in cleaned["shops"]] == ["shop-live"],
      str([s["id"] for s in cleaned["shops"]]))
check("归档店家的系列连坐剔除",
      [s["id"] for s in cleaned["series"]] == ["series-live"],
      str([s["id"] for s in cleaned["series"]]))
check("自归档系列连坐剔除（其下商品也不留）",
      [p["id"] for p in cleaned["products"]] == ["prod-live"],
      str([p["id"] for p in cleaned["products"]]))
check("归档商品的规格连坐剔除",
      [v["id"] for v in cleaned["variants"]] == ["var-live"])
check("归档商品的尺码表连坐剔除",
      [c["id"] for c in cleaned["sizeCharts"]] == ["chart-live"])
check("归档商品的销售事件连坐剔除",
      [e["id"] for e in cleaned["saleEvents"]] == ["ev-live"])
check("归档系列的款式档案连坐剔除",
      [p["id"] for p in cleaned["styleProfiles"]] == ["profile-live"])
check("剔除数量如实上报（products 少了 2 条）", report["products"] == 2, str(report))

asset_ids = {a["id"] for a in cleaned["assets"]}
check("只被归档实体引用的图片被剔除",
      "asset-arch-logo" not in asset_ids and "asset-arch-img" not in asset_ids,
      str(sorted(asset_ids)))
check("仍被在售实体引用的图片保留", "asset-live-img" in asset_ids and "asset-live-logo" in asset_ids,
      str(sorted(asset_ids)))
check("未被任何实体引用的孤儿图片保持原样（不误删）", "asset-orphan" in asset_ids,
      str(sorted(asset_ids)))
check("墓碑保留（归档与强制删除是两件事）", cleaned["removedShopIDs"] == ["shop-gone"])

# 3) 剔除结果必须过得了客户端同一口径的结构校验
issues = validate_shop_catalog(cleaned, BRAND, COVERAGE_COMPLETE)
check("剔除后无悬空引用（客户端结构校验通过）", not issues, str(issues))

# 4) 反向用例：不连带剔除会被校验拒绝 —— 说明这段裁剪不是可省的
partial = copy.deepcopy(doc)
partial["products"] = [p for p in partial["products"] if p["id"] != "prod-arch"]
partial["variants"] = [v for v in partial["variants"] if v["productID"] != "prod-arch"]
issues_partial = validate_shop_catalog(partial, BRAND, COVERAGE_COMPLETE)
check("反向：只删商品不删尺码表/事件 → 校验必须报悬空引用", bool(issues_partial),
      "期望有 issue，实际 {}".format(issues_partial))

# 5) 裁剪不得掩盖发布端的数据错误：商品指向**本来就不存在**的系列（与归档无关）
broken = copy.deepcopy(doc)
broken["products"].append(
    {"id": "prod-broken", "shopID": "shop-live", "seriesID": "series-missing",
     "name": "指向不存在系列的商品", "category": "JSK"}
)
kept, _ = strip_archived_shop_catalog(broken)
check("非归档的悬空引用不被裁剪抹平（坏数据要留下来报错，不能静默消失）",
      any(p["id"] == "prod-broken" for p in kept["products"]),
      str([p["id"] for p in kept["products"]]))
check("…且会被结构校验如实报出", bool(validate_shop_catalog(kept, BRAND, COVERAGE_COMPLETE)))

print()
print("=== collect_shop_catalog_media（图片随包上传 THMedia） ===")


def media_fixture(tmp: Path):
    images = tmp / "images"
    images.mkdir(parents=True, exist_ok=True)
    (images / "img-ONE.jpg").write_bytes(b"\xff\xd8\xff\xe0-one")
    (images / "img-TWO.png").write_bytes(b"\x89PNG\r\n\x1a\n-two")
    doc = {
        "version": 1,
        "shops": [{"id": "shop-a", "name": "店家", "logo": "local:img-ONE.jpg"}],
        "series": [{"id": "series-a", "shopID": "shop-a", "name": "系列"}],
        "products": [{"id": "p-a", "shopID": "shop-a", "seriesID": "series-a",
                      "name": "商品", "category": "JSK", "images": []}],
        "assets": [
            {"id": "asset-1", "type": "productImage", "originalURL": "local:img-ONE.jpg"},
            {"id": "asset-2", "type": "productImage", "originalURL": "local:img-TWO.png"},
            {"id": "asset-3", "type": "productImage", "originalURL": "bundle:seed.jpg"},
            {"id": "asset-4", "type": "productImage", "originalURL": "https://example.com/a.jpg"},
        ],
        "sizeCharts": [{"id": "chart-a", "productID": "p-a", "sourceImage": "local:img-TWO.png"}],
        "variants": [], "saleEvents": [], "styleProfiles": [],
    }
    return doc, images


import tempfile  # noqa: E402

from build_release import collect_shop_catalog_media  # noqa: E402

with tempfile.TemporaryDirectory() as root_name:
    root = Path(root_name)
    doc, images = media_fixture(root)
    rewritten, records, files = collect_shop_catalog_media(doc, images)

    check("图片被收集成 THMedia 记录（同一张图只传一次）", len(records) == 2,
          "records={}".format(len(records)))
    check("待落盘文件与记录一一对应", len(files) == 2)
    check("记录名符合协议 th.media.<contentHash>",
          all(r["recordName"] == "th.media.{}".format(r["contentHash"]) for r in records))

    def url_of(asset_id):
        return next(a["originalURL"] for a in rewritten["assets"] if a["id"] == asset_id)

    one_hash = next(r["contentHash"] for r in records if r["mediaKey"] == "local:img-ONE.jpg")
    check("引用改写为 thmedia:<contentHash>", url_of("asset-1") == "thmedia:{}".format(one_hash),
          url_of("asset-1"))
    check("同图多处引用共享同一个 hash（logo 与 asset-1）",
          rewritten["shops"][0]["logo"] == url_of("asset-1"))
    check("尺码表原图引用也被改写",
          rewritten["sizeCharts"][0]["sourceImage"].startswith("thmedia:"))
    check("bundle: 引用原样保留", url_of("asset-3") == "bundle:seed.jpg")
    check("http(s) 引用原样保留", url_of("asset-4") == "https://example.com/a.jpg")

    # 缺图必须硬报错（静默跳过会让「图没传」以空白图的形式暴露，难查得多）
    broken = copy.deepcopy(doc)
    broken["assets"].append(
        {"id": "asset-x", "type": "productImage", "originalURL": "local:img-MISSING.jpg"})
    raised = False
    try:
        collect_shop_catalog_media(broken, images)
    except Exception as error:  # noqa: BLE001 - 只关心有没有硬失败
        raised = True
        check("缺图报错信息点名缺失文件", "img-MISSING.jpg" in str(error), str(error)[:80])
    check("引用到的图片缺失 → 构建硬失败（不静默跳过）", raised)

print()
if failures:
    print("❌ {} 项未通过：{}".format(len(failures), "、".join(failures)))
    sys.exit(1)
print("✅ 商店目录归档裁剪自测全部通过")
