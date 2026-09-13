#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""校验发布产物（§8.2 步骤 6–8 / §18.1）。

只读磁盘，不联网、不写线上。
任何一条不通过都以非零退出码结束，避免「校验失败但继续发布」。

覆盖的验收点（对应设计 §18.1）：
  D09  重复 ID、悬空关系、错误品牌范围
  D10  partial 包少记录不当作删除
  D11  complete 新快照的移除是有意行为（差异报告提示）
  D12  schema 不受支持时明确拒绝
"""

from __future__ import annotations

import argparse
import gzip
import json
import sys
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple

sys.path.insert(0, str(Path(__file__).resolve().parent))

from protocol import (  # noqa: E402
    MAX_PACK_COMPRESSED_BYTES,
    MAX_PACK_UNCOMPRESSED_BYTES,
    PROTOCOL_SCHEMA_VERSION,
    READER_VERSION,
    ProtocolError,
    canonical_json_bytes,
    entity_records,
    is_safe_partition_id,
    pack_record_name,
    sha256_hex,
    validate_fragment,
    validate_partition_descriptor,
    validate_release_references,
    validate_root_index,
)


def parse_args(argv: Optional[List[str]] = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="校验时光馆发布产物")
    parser.add_argument("--release", required=True, type=Path, help="发布产物目录")
    parser.add_argument(
        "--previous", type=Path, help="上一版产物目录，用于输出条目数下降提示"
    )
    parser.add_argument("--quiet", action="store_true", help="只输出结论与问题")
    return parser.parse_args(argv)


def load_json(path: Path) -> Any:
    return json.loads(path.read_text(encoding="utf-8"))


def check_release_header(
    release: Dict[str, Any], root_bytes: bytes
) -> Tuple[List[str], List[str]]:
    """返回 (errors, warnings)。

    `localFixture` 只是警告：本地联调产物必须能被完整校验，
    但它由 publish_cloudkit.py 强制拒绝发布，不能只靠这里拦。
    """
    errors: List[str] = []
    warnings: List[str] = []
    declared = str(release.get("rootIndexHash", ""))
    actual = sha256_hex(root_bytes)
    if declared != actual:
        errors.append("rootIndexHash 不匹配：release.json={} 实际={}".format(declared[:12], actual[:12]))
    reader_version = release.get("minimumReaderVersion")
    if not isinstance(reader_version, int):
        errors.append("minimumReaderVersion 缺失或不是整数")
    elif reader_version > READER_VERSION:
        errors.append(
            "minimumReaderVersion={} 高于当前读取协议 {}，会挡住现有客户端".format(
                reader_version, READER_VERSION
            )
        )
    if release.get("schemaVersion") != PROTOCOL_SCHEMA_VERSION:
        errors.append("release.schemaVersion 与协议版本不一致")
    if release.get("localFixture"):
        warnings.append(
            "产物被标记为 localFixture（未批准来源的本地联调产物），publish_cloudkit.py 会拒绝发布"
        )
    return errors, warnings


def verify_pack(
    release_dir: Path, descriptor: Dict[str, Any]
) -> Tuple[Optional[Dict[str, Any]], List[Dict[str, str]], List[str]]:
    errors: List[str] = []
    payload_hash = str(descriptor.get("payloadHash", ""))
    if not payload_hash:
        return None, [], ["分片缺少 payloadHash：{}".format(descriptor.get("partitionID"))]
    pack_path = release_dir / "packs" / "{}.json.gz".format(payload_hash)
    if not pack_path.exists():
        return None, [], ["数据包文件缺失：{}".format(pack_path.name)]

    compressed = pack_path.read_bytes()
    if sha256_hex(compressed) != payload_hash:
        errors.append("{} 压缩字节摘要与声明不符".format(pack_path.name))
    if len(compressed) > MAX_PACK_COMPRESSED_BYTES:
        errors.append("{} 压缩后超出上限".format(pack_path.name))
    if pack_record_name(payload_hash) != descriptor.get("packRecordName"):
        errors.append("{} 记录名与 payloadHash 不一致".format(pack_path.name))

    try:
        raw = gzip.decompress(compressed)
    except Exception as error:  # noqa: BLE001
        return None, [], ["{} 不是合法的 gzip：{}".format(pack_path.name, error)]
    if len(raw) > MAX_PACK_UNCOMPRESSED_BYTES:
        errors.append("{} 解压后超出上限".format(pack_path.name))

    try:
        payload = json.loads(raw.decode("utf-8"))
    except Exception as error:  # noqa: BLE001
        return None, [], ["{} 解压后不是合法 JSON：{}".format(pack_path.name, error)]

    issues = [
        dict(issue, layer="partition")
        for issue in validate_partition_descriptor(descriptor, payload, len(compressed), len(raw))
    ]
    issues += [
        dict(issue, layer="structural")
        for issue in validate_fragment(
            payload.get("records") or {},
            str(descriptor.get("brandID", "")),
            str(descriptor.get("entityType", "")),
            str(descriptor.get("coverageStatus", "")),
        )
    ]
    return payload, issues, errors


def main(argv: Optional[List[str]] = None) -> int:
    args = parse_args(argv)
    release_dir: Path = args.release
    release_path = release_dir / "release.json"
    root_path = release_dir / "root-index.json"
    if not release_path.exists() or not root_path.exists():
        print("❌ {} 不是完整的发布产物目录".format(release_dir), file=sys.stderr)
        return 2

    release = load_json(release_path)
    root_bytes = root_path.read_bytes()
    root_index = json.loads(root_bytes.decode("utf-8"))

    errors: List[str] = []
    warnings: List[str] = []
    issues: List[Dict[str, str]] = []

    header_errors, header_warnings = check_release_header(release, root_bytes)
    errors += header_errors
    warnings += header_warnings
    issues += [
        dict(issue, layer="partition") for issue in validate_root_index(root_index, release.get("releaseSeq"))
    ]
    if canonical_json_bytes(root_index) != root_bytes:
        errors.append("root-index.json 不是规范化 JSON，重算摘要会漂移")

    partitions: List[Dict[str, Any]] = root_index.get("partitions") or []
    packs: List[Tuple[Dict[str, Any], Dict[str, Any]]] = []
    total_records = 0
    total_compressed = 0

    for descriptor in partitions:
        payload, pack_issues, pack_errors = verify_pack(release_dir, descriptor)
        issues += pack_issues
        errors += pack_errors
        if payload is None:
            continue
        packs.append((descriptor, payload))
        total_records += int(descriptor.get("recordCount", 0))
        total_compressed += (release_dir / "packs" / "{}.json.gz".format(descriptor["payloadHash"])).stat().st_size

    issues += [dict(issue, layer="structural") for issue in validate_release_references(packs)]

    if release.get("partitionCount") != len(partitions):
        errors.append(
            "release.partitionCount={} 与实际 {} 不一致".format(release.get("partitionCount"), len(partitions))
        )
    if release.get("recordCount") != total_records:
        errors.append(
            "release.recordCount={} 与实际 {} 不一致".format(release.get("recordCount"), total_records)
        )

    # 未引用的孤儿包：不是错误，但必须报告，避免悄然堆积
    referenced = {"{}.json.gz".format(item["payloadHash"]) for item in partitions}
    packs_dir = release_dir / "packs"
    orphans: List[str] = []
    if packs_dir.exists():
        orphans = sorted(
            path.name for path in packs_dir.iterdir() if path.is_file() and path.name not in referenced
        )

    if not args.quiet:
        print("发布产物：{}".format(release_dir))
        print("  releaseSeq        {}".format(release.get("releaseSeq")))
        print("  revocationEpoch   {}".format(release.get("revocationEpoch")))
        print("  分片              {}".format(len(partitions)))
        print("  条目              {}".format(total_records))
        print("  压缩体积          {} 字节".format(total_compressed))
        media_path = release_dir / "media.json"
        media_count = len(load_json(media_path).get("media", [])) if media_path.exists() else 0
        print("  媒体              {} 个".format(media_count))
        print("  rootIndexHash     {}".format(release.get("rootIndexHash")))
        coverage: Dict[str, int] = {}
        for descriptor in partitions:
            key = str(descriptor.get("coverageStatus"))
            coverage[key] = coverage.get(key, 0) + 1
        print("  覆盖状态分布      {}".format(coverage))
        by_brand: Dict[str, int] = {}
        for descriptor in partitions:
            by_brand[str(descriptor.get("brandID"))] = by_brand.get(str(descriptor.get("brandID")), 0) + int(
                descriptor.get("recordCount", 0)
            )
        print("  各品牌条目数      {}".format(by_brand))
        if orphans:
            print("  ⚠️ 未被引用的数据包 {} 个（发布前请确认是否需要保留）".format(len(orphans)))
            for name in orphans[:10]:
                print("     - {}".format(name))

    if args.previous:
        previous_root = args.previous / "root-index.json"
        if previous_root.exists():
            old = json.loads(previous_root.read_text(encoding="utf-8"))
            old_map = {item["partitionID"]: item for item in old.get("partitions", [])}
            print("\n与上一版本对比：")
            for descriptor in partitions:
                old_item = old_map.get(descriptor["partitionID"])
                if not old_item:
                    print("  + {} 新增（{} 条）".format(descriptor["partitionID"], descriptor["recordCount"]))
                elif old_item["payloadHash"] != descriptor["payloadHash"]:
                    delta = int(descriptor["recordCount"]) - int(old_item["recordCount"])
                    flag = "  ⚠️ 条目数下降" if delta < 0 else ""
                    print(
                        "  ~ {} 修订（{} → {} 条）{}".format(
                            descriptor["partitionID"], old_item["recordCount"], descriptor["recordCount"], flag
                        )
                    )
            for partition_id in sorted(set(old_map) - {item["partitionID"] for item in partitions}):
                print("  - {} 移除".format(partition_id))

    if warnings:
        print("")
        for warning in warnings:
            print("⚠️  {}".format(warning), file=sys.stderr)

    if issues:
        print("\n❌ 协议问题 {} 条：".format(len(issues)), file=sys.stderr)
        for issue in issues[:60]:
            print(
                "   [{}] {} {} {}".format(
                    issue.get("layer", "?"),
                    issue.get("code", "?"),
                    issue.get("entityID", ""),
                    issue.get("message", ""),
                ),
                file=sys.stderr,
            )
    if errors:
        print("\n❌ 完整性问题 {} 条：".format(len(errors)), file=sys.stderr)
        for error in errors[:60]:
            print("   {}".format(error), file=sys.stderr)

    if issues or errors:
        return 3
    print("\n✅ 校验通过，可以进入 publish_cloudkit.py --dry-run")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
