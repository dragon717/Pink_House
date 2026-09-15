#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""把 scrapers 采集结果（items.json）转换为仲夏物语（Midsummer）可导入的 JSON。

映射规则（对应 docs/上新咨询双方案设计.md §四）：
  title  -> name（款名，投稿校验硬性要求非空）
  价格   -> price/deposit/balance：采集到的是商品页一口价，归"现货价"口径
  kind   -> 按标题关键词猜（JSK/OP/SK/衬衫/小物/套装），猜不出默认 SK
  detail_url -> itemURL（规范化的 item.taobao.com 详情页地址）
  size_charts -> sizeChartImages（尺码表候选图，运营者导入时逐张确认）

用法：
    python export_midsummer.py data/runs/20260915_021855_taobao_JK制服/items.json
输出：同目录下 midsummer_import.json
"""
import json
import sys
from pathlib import Path


def guess_kind(title: str) -> str:
    t = title.upper()
    if "JSK" in t:
        return "JSK"
    if "OP" in t:
        return "OP"
    if "衬衫" in title:
        return "衬衫"
    if any(k in title for k in ("小物", "发夹", "包", "边夹", "领结", "头饰")):
        return "小物"
    if "套装" in title:
        return "套装"
    return "SK"


def main(json_path: str) -> None:
    path = Path(json_path)
    payload = json.loads(path.read_text(encoding="utf-8"))
    out_items = []
    skipped = 0
    for item in payload.get("items", []):
        name = (item.get("title") or "").strip()
        if not name:
            skipped += 1  # 与投稿校验同规则：款名空的单品不导入
            continue
        price = item.get("price")
        try:
            price = int(float(price)) if price is not None else None
        except (TypeError, ValueError):
            price = None
        out_items.append({
            "name": name[:120],
            "kind": guess_kind(name),
            "price": price,
            "deposit": None,
            "balance": None,
            "priceKind": "shop" if price else None,
            "sizes": [],
            "sizeChartImages": item.get("size_charts", []),
            "itemURL": item.get("detail_url"),
            "sourceURL": item.get("detail_url"),
            "note": "来源：淘宝详情页自动采集，价格尺码待运营者核对",
        })
    out = {
        "seriesName": payload.get("keyword", ""),
        "sourceKind": "editorial",
        "note": "由 scrapers 管线自动生成，运营者导入时核对尺码表候选图",
        "items": out_items,
        "skippedUnnamed": skipped,
    }
    out_path = path.parent / "midsummer_import.json"
    out_path.write_text(
        json.dumps(out, ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"已生成 {out_path}：{len(out_items)} 个单品（跳过无款名 {skipped} 个）")


if __name__ == "__main__":
    if len(sys.argv) != 2:
        print(__doc__)
        sys.exit(1)
    main(sys.argv[1])
