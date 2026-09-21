#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""批量绑定种子数据中的配色记录与商品图片（图文绑定）。

用途
----
读取 ShopCatalog 种子 JSON（默认 ``ItemManager/Resources/ShopCatalog/shop-catalog.json``），
对每条带配色的 variant（配色记录），在其所属商品 images 引用的 CatalogAsset
（图片文件，originalURL）中按名称自动匹配，匹配成功则写入
``variant.imageAssetID``，即 App 内「系列页点菜式选购」的图文绑定。

匹配规则
--------
* 只在**同一商品的 images** 内匹配（图文绑定语义：配色图必须是该商品自己的照片）。
* 名称归一化后做全等比较：
  - 忽略大小写（casefold）
  - 去掉文件后缀（最后一个 .xxx）
  - 去掉所有空白（含全角空格）、``_ - （）() 【】[] · .`` 等分隔符
* 无法匹配 → 警告日志 + 计入失败；同名多图（归一化后重名）→ 歧义警告 + 计入失败。

幂等性
------
* 已绑定且指向正确 asset → 跳过，不重复写。
* 已绑定但指向其他 asset → 视为名称冲突，默认保留现绑定并警告（``--force`` 才覆盖）。
* 重复执行不产生重复绑定（绑定目标是 asset id 单值字段，写入即覆盖同值）。

统计摘要
--------
结束输出 总数 / 成功 / 跳过 / 失败 / 警告 数量，失败明细按商品×配色归组，便于人工核查。

用法示例
--------
    # 预览（不改文件）
    python3 scripts/bind_seed_variant_images.py --dry-run

    # 实际写入
    python3 scripts/bind_seed_variant_images.py

    # 只处理某个系列 + 警告落盘
    python3 scripts/bind_seed_variant_images.py --series series-ag-xueguo-2026 \
        --log-file /tmp/bind_warnings.log

    # 已有绑定时强制按名称匹配结果覆盖
    python3 scripts/bind_seed_variant_images.py --force
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from collections import Counter, defaultdict
from pathlib import Path

# 默认种子路径（相对仓库根）
DEFAULT_SEED = Path(__file__).resolve().parent.parent / "ItemManager" / "Resources" / "ShopCatalog" / "shop-catalog.json"

# 归一化时剔除的分隔符：半角/全角空格、下划线、连字符、各类括号、间隔点、点
_STRIP_RE = re.compile(r"[\s_\-‐－（）()【】\[\]｛｝{}「」『』·．.*+]+")


def normalize(name: str) -> str:
    """名称归一化：去后缀、忽略大小写、去空白与常见分隔符。"""
    s = name.strip()
    s = re.sub(r"\.[A-Za-z0-9]{1,5}$", "", s)  # 去文件后缀
    s = _STRIP_RE.sub("", s)
    return s.casefold()


class Binder:
    def __init__(self, args: argparse.Namespace) -> None:
        self.args = args
        self.seed_path: Path = args.seed
        self.data: dict = {}
        self.warnings: list[str] = []
        # 统计：成功 / 跳过 / 失败
        self.ok = 0
        self.skipped = 0
        self.failed = 0
        self.fail_detail: Counter[str] = Counter()  # (商品|配色) -> 次数

    # ---------- 日志 ----------
    def warn(self, msg: str) -> None:
        self.warnings.append(msg)
        print(f"⚠️  {msg}")

    # ---------- 加载 ----------
    def load(self) -> None:
        with open(self.seed_path, encoding="utf-8") as f:
            self.data = json.load(f)
        self.assets: dict[str, dict] = {a["id"]: a for a in self.data.get("assets", [])}
        self.products: dict[str, dict] = {p["id"]: p for p in self.data.get("products", [])}
        self.variants: list[dict] = self.data.get("variants", [])

    def product_image_assets(self, product: dict) -> list[dict]:
        """商品 images 引用的 asset 列表（只保留真实存在的 asset）。"""
        out = []
        for aid in product.get("images", []):
            asset = self.assets.get(aid)
            if asset is None:
                self.warn(f"[孤儿引用] 商品 {product['id']} 引用了不存在的 asset：{aid}")
                continue
            out.append(asset)
        return out

    # ---------- 核心流程 ----------
    def run(self) -> bool:
        self.load()
        series_filter = set(self.args.series) if self.args.series else None
        changed = 0

        for v in self.variants:
            color = (v.get("color") or "").strip()
            if not color:
                # 纯尺码规格不是配色记录，直接跳过
                self.skipped += 1
                continue

            product = self.products.get(v.get("productID", ""))
            if product is None:
                self.failed += 1
                self.fail_detail[f"{v.get('productID', '?')}|{color}"] += 1
                self.warn(f"[无法匹配] variant {v['id']} 的商品不存在：{v.get('productID')}")
                continue

            if series_filter and product.get("seriesID") not in series_filter:
                self.skipped += 1
                continue

            candidates = self.product_image_assets(product)
            key = normalize(color)
            if not key:
                self.skipped += 1
                continue

            matched = [a for a in candidates if normalize(a.get("originalURL", "")) == key]

            if len(matched) == 0:
                self.failed += 1
                self.fail_detail[f"{product.get('name', product['id'])}|{color}"] += 1
                self.warn(
                    f"[无法匹配] 商品「{product.get('name', product['id'])}」配色「{color}」"
                    f"在其 {len(candidates)} 张图片中找不到同名文件"
                    f"（图片：{[a.get('originalURL') for a in candidates]}）"
                )
                continue

            if len(matched) > 1:
                # 同名多图 → 歧义
                self.failed += 1
                self.fail_detail[f"{product.get('name', product['id'])}|{color}"] += 1
                self.warn(
                    f"[歧义] 商品「{product.get('name', product['id'])}」配色「{color}」"
                    f"匹配到 {len(matched)} 张同名图片，需人工指定："
                    f"{[a['id'] + ' -> ' + a.get('originalURL', '') for a in matched]}"
                )
                continue

            target = matched[0]["id"]
            current = v.get("imageAssetID")
            if current == target:
                self.skipped += 1  # 幂等：已绑定且正确
            elif current:
                # 已绑定其他图片 → 名称冲突，默认保留
                self.skipped += 1
                self.warn(
                    f"[冲突] 商品「{product.get('name', product['id'])}」配色「{color}」"
                    f"已绑定 {current}（{self.assets.get(current, {}).get('originalURL', '?')}），"
                    f"按名称应绑定 {target}（{matched[0].get('originalURL')}）；"
                    f"默认保留现绑定，使用 --force 覆盖"
                )
                if self.args.force:
                    v["imageAssetID"] = target
                    changed += 1
                    self.ok += 1
                    self.skipped -= 1
            else:
                v["imageAssetID"] = target
                changed += 1
                self.ok += 1
                print(f"✅ 绑定：{product.get('name', product['id'])}「{color}」→ {target}（{matched[0].get('originalURL')}）")

        # 同名配色冲突检测：同一商品内两个不同配色名归一化后相同（名称冲突）
        by_product: dict[str, set[str]] = defaultdict(set)
        for v in self.variants:
            color = (v.get("color") or "").strip()
            if color and v.get("productID") in self.products:
                by_product[v["productID"]].add(color)
        for pid, colors in by_product.items():
            seen: dict[str, str] = {}
            for color in sorted(colors):
                k = normalize(color)
                if k in seen and seen[k] != color:
                    self.warn(
                        f"[名称冲突] 商品 {self.products[pid].get('name', pid)} "
                        f"内配色「{seen[k]}」与「{color}」归一化后同名，绑定会互相覆盖，请人工区分"
                    )
                seen[k] = color

        if changed and not self.args.dry_run:
            self.write()

        self.summary(changed)
        return changed

    # ---------- 写回 ----------
    def write(self) -> None:
        backup = self.seed_path.with_suffix(self.seed_path.suffix + ".bak")
        backup.write_text(self.seed_path.read_text(encoding="utf-8"), encoding="utf-8")
        tmp = self.seed_path.with_suffix(self.seed_path.suffix + ".tmp")
        with open(tmp, "w", encoding="utf-8") as f:
            json.dump(self.data, f, ensure_ascii=False, indent=2)
            f.write("\n")
        tmp.replace(self.seed_path)
        print(f"💾 已写回 {self.seed_path}（备份：{backup}）")

    # ---------- 摘要 ----------
    def summary(self, changed: int) -> None:
        total = len(self.variants)
        no_color = sum(1 for v in self.variants if not (v.get("color") or "").strip())
        print("\n" + "=" * 56)
        print("📊 统计摘要")
        print(f"   variant 总数  : {total}（其中 {no_color} 条为纯尺码规格，计入跳过）")
        print(f"   ✅ 成功绑定   : {self.ok}")
        print(f"   ⏭️  跳过       : {self.skipped}（已绑定/无配色/未选中系列）")
        print(f"   ❌ 失败       : {self.failed}（无法匹配 / 歧义）")
        print(f"   ⚠️  警告条数   : {len(self.warnings)}")
        if self.fail_detail:
            print("   失败明细（商品|配色）：")
            for k, n in sorted(self.fail_detail.items()):
                print(f"      - {k} ×{n}")
        if self.args.dry_run:
            print("   （--dry-run：未写入任何文件）")
        elif changed == 0:
            print("   （无变更，文件未改动）")
        print("=" * 56)


def parse_args(argv: list[str]) -> argparse.Namespace:
    p = argparse.ArgumentParser(description="种子数据配色记录 × 商品图片 按名称批量图文绑定")
    p.add_argument("--seed", type=Path, default=DEFAULT_SEED, help=f"种子 JSON 路径（默认 {DEFAULT_SEED}）")
    p.add_argument("--series", action="append", help="只处理指定 seriesID（可多次传入）")
    p.add_argument("--dry-run", action="store_true", help="只预览匹配结果，不写文件")
    p.add_argument("--force", action="store_true", help="已绑定的配色也按名称匹配结果覆盖")
    p.add_argument("--log-file", type=Path, help="警告日志追加写入该文件")
    return p.parse_args(argv)


def main(argv: list[str]) -> int:
    args = parse_args(argv)
    if not args.seed.exists():
        print(f"❌ 种子文件不存在：{args.seed}", file=sys.stderr)
        return 2
    binder = Binder(args)
    binder.run()
    if args.log_file and binder.warnings:
        args.log_file.parent.mkdir(parents=True, exist_ok=True)
        with open(args.log_file, "a", encoding="utf-8") as f:
            f.write("\n".join(binder.warnings) + "\n")
        print(f"📝 警告日志已追加：{args.log_file}")
    # 有失败时返回 1，便于脚本化流水线感知
    return 1 if binder.failed else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
