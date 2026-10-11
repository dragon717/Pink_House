#!/usr/bin/env python3
"""冻结并发布从保留草稿恢复的单件商品；沿用商品 ID，不改既有实体与销售历史。"""

import argparse
import copy
import datetime
import gzip
import json
import shutil
import subprocess
import sys
from pathlib import Path

from build_release import collect_shop_catalog_media
from protocol import (ProtocolError, RELEASE_RECORD_NAME, SHOP_CATALOG_ENTITY_TYPE,
                      canonical_json_bytes, gzip_bytes, pack_record_name,
                      sha256_hex, shop_catalog_entity_count)
from publish_adapters import make_adapter
from publish_cloudkit import revalidate


def write_json(path, value):
    path.write_bytes(canonical_json_bytes(value) + b"\n")


def assert_baseline(actual, expected):
    keys = ("releaseSeq", "rootIndexHash", "changeTag")
    if not actual or any(actual.get(k) != expected.get(k) for k in keys):
        raise ProtocolError("线上发布头已变化，请重新读取并生成恢复，不覆盖新版本")


def validate(directory):
    _, _, _, errors = revalidate(directory)
    if errors:
        raise ProtocolError("恢复产物校验失败：" + "; ".join(errors[:10]))


def check_recovery(original, recovered, draft):
    product_id = draft["publishedResult"]["productID"]
    if product_id in original.get("removedProductIDs", []):
        raise ProtocolError("已明确删除的商品不能按丢失商品恢复")
    if any(p["id"] == product_id for p in original.get("products", [])):
        raise ProtocolError("商品已经在线，无需恢复")
    for field in ("saleEvents", "removedShopIDs", "removedSeriesIDs", "removedProductIDs"):
        if recovered.get(field, []) != original.get(field, []):
            raise ProtocolError("恢复不得改变历史或删除记录：" + field)
    for field in ("shops", "series", "products", "variants", "sizeCharts", "assets", "styleProfiles"):
        after = {item["id"]: item for item in recovered.get(field, [])}
        for item in original.get(field, []):
            if after.get(item["id"]) != item:
                raise ProtocolError("恢复不得覆盖或移除原实体：" + field + "." + item["id"])
    new_products = [p for p in recovered.get("products", [])
                    if p["id"] not in {q["id"] for q in original.get("products", [])}]
    if len(new_products) != 1 or new_products[0]["id"] != product_id:
        raise ProtocolError("恢复范围必须恰好为原商品 ID 一件")
    product = new_products[0]
    if product["name"] != draft["name"].strip() or product["category"] != draft["category"]:
        raise ProtocolError("商品名称或分类不匹配保留草稿")
    if product.get("designName", "") != draft.get("designName", "").strip():
        raise ProtocolError("商品款式不匹配保留草稿")
    images = draft.get("images", [])
    if product.get("images", []) != [image["id"] for image in images]:
        raise ProtocolError("商品原图集合不匹配保留草稿")
    assets = {asset["id"]: asset for asset in recovered.get("assets", [])}
    if any(assets.get(image["id"]) != image for image in images):
        raise ProtocolError("商品原图引用不匹配保留草稿")
    variants = [v for v in recovered.get("variants", []) if v["productID"] == product_id]
    if variants != [dict(v, productID=product_id) for v in draft.get("variants", [])]:
        raise ProtocolError("商品规格不匹配保留草稿")
    shop = next(s for s in recovered["shops"] if s["id"] == product["shopID"])
    series = next(s for s in recovered["series"] if s["id"] == product["seriesID"])
    if shop["name"] != draft["newShopName"].strip() or series["name"] != draft["newSeriesName"].strip():
        raise ProtocolError("恢复归属不匹配保留草稿")
    if series["shopID"] != shop["id"]:
        raise ProtocolError("系列与店家归属不一致")
    if draft.get("fabric", "").strip():
        if not any(profile["seriesID"] == series["id"]
                   and profile.get("designName") == product.get("designName")
                   and profile.get("fabric") == draft["fabric"].strip()
                   for profile in recovered.get("styleProfiles", [])):
            raise ProtocolError("商品面料不匹配保留草稿")
    if not any(e["productID"] == product_id for e in original["saleEvents"]):
        raise ProtocolError("没有原商品销售历史，不能猜测恢复")
    allowed_ids = {"shops": {product["shopID"]}, "series": {product["seriesID"]},
                   "assets": set(product.get("images", []))}
    for field in ("shops", "series", "assets", "variants", "sizeCharts", "styleProfiles"):
        old_ids = {item["id"] for item in original.get(field, [])}
        for item in recovered.get(field, []):
            if item["id"] in old_ids:
                continue
            if field in allowed_ids:
                related = item["id"] in allowed_ids[field]
            elif field == "styleProfiles":
                related = item["seriesID"] == product["seriesID"] and item["designName"] == product.get("designName")
            else:
                related = item["productID"] == product_id
            if not related:
                raise ProtocolError("恢复包含无关新增实体：" + field + "." + item["id"])
    return product_id


def prepare(args):
    if args.output.exists():
        raise ProtocolError("输出目录已存在，请保留原审计并使用新目录")
    reader = make_adapter("cloudkit", args.environment, False, False, None)
    head = reader.fetch_current_release()
    root_data = reader.fetch_root_index_bytes()
    if not head or sha256_hex(root_data or b"") != head["rootIndexHash"]:
        raise ProtocolError("线上发布头或根清单无效")
    root = json.loads(root_data)
    descriptor = next(p for p in root["partitions"] if p["entityType"] == SHOP_CATALOG_ENTITY_TYPE)
    compressed = reader.fetch_pack_bytes(descriptor["payloadHash"])
    if sha256_hex(compressed or b"") != descriptor["payloadHash"]:
        raise ProtocolError("线上数据包摘要不符")
    payload = json.loads(gzip.decompress(compressed))
    original = payload["shopCatalog"]
    recovered = json.loads(args.catalog.read_text(encoding="utf-8"))
    drafts = json.loads(args.drafts.read_text(encoding="utf-8"))
    draft = next(d for d in drafts if d["id"] == args.draft_id)
    product_id = check_recovery(original, recovered, draft)
    full_recovery = copy.deepcopy(recovered)
    live_ids = {p["id"] for p in recovered["products"]}
    historical_ids = [e["id"] for e in recovered["saleEvents"] if e["productID"] not in live_ids]
    # 原历史保留于本机恢复快照、旧不可变包与审计；旧客户端拒绝悬空公共事件。
    recovered["saleEvents"] = [e for e in recovered["saleEvents"] if e["productID"] in live_ids]
    recovered, media, files = collect_shop_catalog_media(recovered, args.images)
    directory = args.output / "release"
    (directory / "packs").mkdir(parents=True)
    (args.output / "before").mkdir()
    write_json(args.output / "before" / "head.json", head)
    (args.output / "before" / "root-index.json").write_bytes(root_data)
    write_json(args.output / "before" / "shop-catalog.json", original)
    write_json(args.output / "recovered-full-catalog.json", full_recovery)
    timestamp = datetime.datetime.now(datetime.timezone.utc).isoformat().replace("+00:00", "Z")
    updated = copy.deepcopy(root)
    for part in updated["partitions"]:
        data = reader.fetch_pack_bytes(part["payloadHash"])
        if sha256_hex(data or b"") != part["payloadHash"]:
            raise ProtocolError("原分片摘要无效")
        if part["partitionID"] == descriptor["partitionID"]:
            payload["shopCatalog"] = recovered
            part["partitionRevision"] += 1
            payload["partitionRevision"] = part["partitionRevision"]
            part["coverageStatus"] = payload["coverageStatus"] = "complete"
            part["checkedThrough"] = payload["checkedThrough"] = timestamp
            part["recordCount"] = shop_catalog_entity_count(recovered)
            data = gzip_bytes(canonical_json_bytes(payload))
            part["payloadHash"] = sha256_hex(data)
            part["packRecordName"] = pack_record_name(part["payloadHash"])
        (directory / "packs" / (part["payloadHash"] + ".json.gz")).write_bytes(data)
    updated.update(releaseSeq=head["releaseSeq"] + 1, publishedAt=timestamp)
    root_data = canonical_json_bytes(updated)
    (directory / "root-index.json").write_bytes(root_data)
    release = {"recordName": RELEASE_RECORD_NAME, "releaseSeq": updated["releaseSeq"],
               "schemaVersion": head["schemaVersion"], "publishedAt": timestamp,
               "rootIndexHash": sha256_hex(root_data), "revocationEpoch": head["revocationEpoch"],
               "minimumReaderVersion": head["minimumReaderVersion"], "previousReleaseSeq": head["releaseSeq"],
               "encoding": "json+gzip", "localFixture": False, "brands": updated.get("brands", []),
               "partitionCount": len(updated["partitions"]),
               "recordCount": sum(p["recordCount"] for p in updated["partitions"])}
    write_json(directory / "release.json", release)
    if media:
        (directory / "media").mkdir()
        for name, source in files:
            shutil.copy2(source, directory / "media" / name)
        write_json(directory / "media.json", {"media": media})
    validate(directory)
    assert_baseline(reader.fetch_current_release(), head)
    audit = {"environment": args.environment, "productID": product_id, "draftID": draft["id"],
             "baseline": {k: head.get(k) for k in ("releaseSeq", "rootIndexHash", "changeTag")},
             "newReleaseSeq": release["releaseSeq"], "newRootIndexHash": release["rootIndexHash"],
             "sourceCatalogHash": sha256_hex(args.catalog.read_bytes()),
             "sourceDraftsHash": sha256_hex(args.drafts.read_bytes()),
             "retainedHistoricalSaleEventIDs": historical_ids,
             "mediaHashes": [m["contentHash"] for m in media],
             "artifactHashes": {str(p.relative_to(directory)): sha256_hex(p.read_bytes())
                                for p in sorted(directory.rglob("*")) if p.is_file()}}
    write_json(args.output / "audit.json", audit)
    return audit


def apply(args):
    audit = json.loads((args.output / "audit.json").read_text(encoding="utf-8"))
    if audit["environment"] != args.environment:
        raise ProtocolError("修复目标环境不符")
    directory = args.output / "release"
    actual = {str(p.relative_to(directory)): sha256_hex(p.read_bytes())
              for p in sorted(directory.rglob("*")) if p.is_file()}
    if actual != audit["artifactHashes"]:
        raise ProtocolError("冻结产物已变化，停止发布")
    validate(directory)
    reader = make_adapter("cloudkit", args.environment, False, False, None)
    assert_baseline(reader.fetch_current_release(), audit["baseline"])
    subprocess.run([sys.executable, str(Path(__file__).with_name("publish_cloudkit.py")),
                    "--release", str(directory), "--adapter", "cloudkit", "--environment", args.environment,
                    "--apply", "--receipt", str(args.output / "publish-receipt.json")], check=True)
    head = reader.fetch_current_release()
    if head["releaseSeq"] != audit["newReleaseSeq"] or head["rootIndexHash"] != audit["newRootIndexHash"]:
        raise ProtocolError("回读版本不一致")
    data = reader.fetch_root_index_bytes()
    if data != (directory / "root-index.json").read_bytes():
        raise ProtocolError("回读根清单不一致")
    for part in json.loads(data)["partitions"]:
        if reader.fetch_pack_bytes(part["payloadHash"]) != (directory / "packs" / (part["payloadHash"] + ".json.gz")).read_bytes():
            raise ProtocolError("回读数据包不一致")
    for digest in audit["mediaHashes"]:
        if sha256_hex(reader.fetch_media_bytes(digest) or b"") != digest:
            raise ProtocolError("回读原图摘要不一致")
    write_json(args.output / "verified.json", {"verified": True, "productID": audit["productID"],
                                               "releaseSeq": head["releaseSeq"], "mediaCount": len(audit["mediaHashes"])})
    return audit


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--environment", choices=("development", "production"), required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--apply", action="store_true")
    parser.add_argument("--catalog", type=Path)
    parser.add_argument("--drafts", type=Path)
    parser.add_argument("--draft-id")
    parser.add_argument("--images", type=Path)
    args = parser.parse_args()
    if not args.apply and not all((args.catalog, args.drafts, args.draft_id, args.images)):
        parser.error("准备恢复需要目录、草稿、草稿 ID 和原图目录")
    audit = apply(args) if args.apply else prepare(args)
    print(json.dumps({k: audit[k] for k in ("environment", "productID", "newReleaseSeq")}, ensure_ascii=False))


if __name__ == "__main__":
    main()
