#!/usr/bin/env python3
"""按运营确认把已发布商店目录的未明确币种补为 CNY。

默认只读取线上、冻结修复产物与审计；--apply 发布之前已冻结的产物。
复用原发布器，不改写不可变旧包，不换算金额，不修改明确币种。
"""

from __future__ import annotations

import argparse
import copy
import datetime
import gzip
import json
import subprocess
import sys
from pathlib import Path

from protocol import (ProtocolError, RELEASE_RECORD_NAME, SHOP_CATALOG_ENTITY_TYPE,
                      _shop_media_references, canonical_json_bytes, gzip_bytes,
                      pack_record_name, sha256_hex)
from publish_adapters import CredentialError, make_adapter
from publish_cloudkit import revalidate

UNSPECIFIED = (None, "", "UNKNOWN")


def repair_catalog(catalog):
    """返回复制后的目录与逐字段审计；nil 修正继承已明确外币时保持继承。"""
    fixed = copy.deepcopy(catalog)
    changes = []
    for event in fixed.get("saleEvents", []):
        if event.get("currency") in UNSPECIFIED:
            changes.append({"field": "saleEvents.currency", "id": event["id"],
                            "productID": event["productID"],
                            "before": event.get("currency"), "after": "CNY"})
            event["currency"] = "CNY"
    currencies = {}
    for event in fixed.get("saleEvents", []):
        currencies.setdefault(event["productID"], set()).add(event.get("currency"))
    for product in fixed.get("products", []):
        correction = product.get("priceCorrection")
        if not correction or correction.get("currency") not in UNSPECIFIED:
            continue
        # nil 表示继承销售记录；有明确外币来源时不得改标人民币。
        if correction.get("currency") in (None, "") and (
                currencies.get(product["id"], set()) - {"CNY"}):
            continue
        changes.append({"field": "products.priceCorrection.currency", "id": product["id"],
                        "productID": product["id"],
                        "before": correction.get("currency"), "after": "CNY"})
        correction["currency"] = "CNY"
    return fixed, changes


def write_json(path, value):
    path.write_bytes(canonical_json_bytes(value) + b"\n")


def assert_baseline(actual, expected):
    keys = ("releaseSeq", "rootIndexHash", "changeTag")
    if not actual or any(actual.get(k) != expected.get(k) for k in keys):
        raise ProtocolError("线上发布头已变化，请重新读取并生成修复，不覆盖新版本")


def validate(directory):
    _, _, _, errors = revalidate(directory)
    if errors:
        raise ProtocolError("修复产物校验失败：" + "; ".join(errors[:10]))


def prepare(environment, output):
    if output.exists():
        raise ProtocolError("输出目录已存在；请使用新目录，保留原冻结证据")
    reader = make_adapter("cloudkit", environment, False, False, None)
    head = reader.fetch_current_release()
    if not head:
        raise ProtocolError("线上没有发布头，没有可修复的商品")
    if not isinstance(head.get("schemaVersion"), int) or not isinstance(
            head.get("minimumReaderVersion"), int):
        raise ProtocolError("线上发布头缺少协议版本字段，不能猜测兼容设置")
    root_bytes = reader.fetch_root_index_bytes()
    if not root_bytes or sha256_hex(root_bytes) != head["rootIndexHash"]:
        raise ProtocolError("根清单摘要不匹配")
    root = json.loads(root_bytes)
    output.mkdir(parents=True)
    before = output / "before"
    release_dir = output / "release"
    for directory in (before / "packs", release_dir / "packs"):
        directory.mkdir(parents=True)
    write_json(before / "head.json", head)
    (before / "root-index.json").write_bytes(root_bytes)
    changes = []
    replacements = {}
    media_hashes = set()
    timestamp = datetime.datetime.now(datetime.timezone.utc).isoformat().replace("+00:00", "Z")
    for descriptor in root["partitions"]:
        old_hash = descriptor["payloadHash"]
        compressed = reader.fetch_pack_bytes(old_hash)
        if not compressed or sha256_hex(compressed) != old_hash:
            raise ProtocolError("数据包摘要不匹配：" + old_hash)
        (before / "packs" / (old_hash + ".json.gz")).write_bytes(compressed)
        payload = json.loads(gzip.decompress(compressed))
        if descriptor.get("entityType") == SHOP_CATALOG_ENTITY_TYPE:
            original = payload["shopCatalog"]
            fixed, edits = repair_catalog(original)
            for field, reference, _ in _shop_media_references(original):
                digest = reference if field.endswith(".mediaKey") else reference.removeprefix("thmedia:")
                if len(digest) == 64 and all(c in "0123456789abcdef" for c in digest):
                    media_hashes.add(digest)
            write_json(before / "shop-catalog.json", original)
            write_json(output / "repaired-shop-catalog.json", fixed)
            if edits:
                changes.extend(edits)
                payload["shopCatalog"] = fixed
                revision = int(descriptor["partitionRevision"]) + 1
                payload["partitionRevision"] = descriptor["partitionRevision"] = revision
                compressed = gzip_bytes(canonical_json_bytes(payload))
                digest = sha256_hex(compressed)
                replacements[descriptor["packRecordName"]] = pack_record_name(digest)
                descriptor["payloadHash"] = digest
                descriptor["packRecordName"] = pack_record_name(digest)
        (release_dir / "packs" / (descriptor["payloadHash"] + ".json.gz")).write_bytes(compressed)
    for descriptor in root["partitions"]:
        descriptor["dependencyPackRecordNames"] = [
            replacements.get(name, name) for name in descriptor.get("dependencyPackRecordNames", [])]
    assert_baseline(reader.fetch_current_release(), head)
    audit = {"environment": environment, "baseline": {k: head.get(k) for k in
             ("releaseSeq", "rootIndexHash", "changeTag")}, "changes": changes,
             "changedSaleEvents": sum(c["field"] == "saleEvents.currency" for c in changes),
             "changedCorrections": sum(c["field"] == "products.priceCorrection.currency" for c in changes),
             "affectedProducts": len({c["productID"] for c in changes}),
             "mediaHashes": sorted(media_hashes), "preparedAt": timestamp}
    if not changes:
        write_json(output / "audit.json", audit)
        return audit
    root.update(releaseSeq=int(head["releaseSeq"]) + 1, publishedAt=timestamp)
    root_bytes = canonical_json_bytes(root)
    (release_dir / "root-index.json").write_bytes(root_bytes)
    release = {"recordName": RELEASE_RECORD_NAME, "releaseSeq": root["releaseSeq"],
               "schemaVersion": head["schemaVersion"], "publishedAt": timestamp,
               "rootIndexHash": sha256_hex(root_bytes),
               "revocationEpoch": head["revocationEpoch"],
               "minimumReaderVersion": head["minimumReaderVersion"],
               "previousReleaseSeq": head["releaseSeq"], "encoding": "json+gzip",
               "localFixture": False, "brands": root["brands"],
               "partitionCount": len(root["partitions"]),
               "recordCount": sum(p["recordCount"] for p in root["partitions"])}
    write_json(release_dir / "release.json", release)
    validate(release_dir)
    audit["newReleaseSeq"] = release["releaseSeq"]
    audit["newRootIndexHash"] = release["rootIndexHash"]
    # apply 前要锁住整个发布目录，不能只核对清单而漏掉被修改的数据包。
    audit["artifactHashes"] = {str(p.relative_to(release_dir)): sha256_hex(p.read_bytes())
                               for p in sorted(release_dir.rglob("*")) if p.is_file()}
    write_json(output / "audit.json", audit)
    return audit


def apply(environment, output):
    audit = json.loads((output / "audit.json").read_text(encoding="utf-8"))
    if audit["environment"] != environment:
        raise ProtocolError("冻结产物的环境与目标不一致")
    if not audit["changes"]:
        return audit
    directory = output / "release"
    actual = {str(p.relative_to(directory)): sha256_hex(p.read_bytes())
              for p in sorted(directory.rglob("*")) if p.is_file()}
    if actual != audit["artifactHashes"]:
        raise ProtocolError("冻结产物被修改，请重新准备修复")
    validate(directory)
    reader = make_adapter("cloudkit", environment, False, False, None)
    assert_baseline(reader.fetch_current_release(), audit["baseline"])
    available = reader.media_exists_many(audit["mediaHashes"])
    if set(audit["mediaHashes"]) - available:
        raise ProtocolError("原目录引用的云端图片不可获取，停止发布")
    result = subprocess.run([sys.executable, str(Path(__file__).with_name("publish_cloudkit.py")),
                             "--release", str(directory), "--adapter", "cloudkit",
                             "--environment", environment, "--apply",
                             "--receipt", str(output / "publish-receipt.json")], check=False)
    if result.returncode:
        raise ProtocolError("发布器未确认成功，保留产物与回执供核对")
    head = reader.fetch_current_release()
    if not head or head["releaseSeq"] != audit["newReleaseSeq"] or (
            head["rootIndexHash"] != audit["newRootIndexHash"]):
        raise ProtocolError("发布后回读版本或摘要不一致")
    root_bytes = reader.fetch_root_index_bytes()
    if sha256_hex(root_bytes or b"") != audit["newRootIndexHash"]:
        raise ProtocolError("发布后根清单回读摘要不一致")
    for part in json.loads(root_bytes)["partitions"]:
        expected = (directory / "packs" / (part["payloadHash"] + ".json.gz")).read_bytes()
        if reader.fetch_pack_bytes(part["payloadHash"]) != expected:
            raise ProtocolError("发布后数据包字节与冻结产物不一致")
    write_json(output / "verified.json", {"releaseSeq": head["releaseSeq"],
               "rootIndexHash": head["rootIndexHash"], "verified": True,
               "changedFields": len(audit["changes"]), "mediaVerified": len(available)})
    return audit


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--environment", choices=("development", "production"), required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--apply", action="store_true", help="发布已经准备并审核的修复")
    args = parser.parse_args()
    try:
        audit = apply(args.environment, args.output) if args.apply else prepare(args.environment, args.output)
        print(json.dumps({k: audit.get(k) for k in ("environment", "changedSaleEvents",
                         "changedCorrections", "affectedProducts", "newReleaseSeq")}, ensure_ascii=False))
        return 0
    except (ProtocolError, CredentialError, OSError, ValueError) as error:
        print("币种修复失败：" + str(error), file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
