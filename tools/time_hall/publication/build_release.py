#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""构建不可变发布产物。

对应 docs/Pink_House_TimeHall_Static_CloudKit_Design.md §8.2 / §8.3 / §8.5 / §9.1。

职责边界：
  * 只构建，**不写线上**。发布由 publish_cloudkit.py 负责。
  * 只纳入 sources.yaml 中**已批准**的来源；默认禁止发布。
  * 同一个审核通过的产物可以同时用于 CloudKit 与下一版 Bundle，
    不应分别加工两套内容造成不一致（§8.2）。

产物目录结构：
  <release-dir>/
    release.json            发布头字段（THRelease）
    root-index.json         根清单（THRelease.rootIndexAsset 的内容）
    packs/<sha256>.json.gz  不可变数据包（THDataPack.payloadAsset）
    media/<sha256>.<ext>    已获许可的媒体（THMedia.asset）——可选
    media.json              THMedia 记录元数据——可选
    audit/release-manifest.json  私有审计记录（不进入公共记录）
    audit/checksums.txt     SHA-256 清单
"""

from __future__ import annotations

import argparse
import datetime as dt
import json
import shutil
import sys
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple

sys.path.insert(0, str(Path(__file__).resolve().parent))

from protocol import (  # noqa: E402
    COVERAGE_COMPLETE,
    COVERAGE_EMPTY,
    COVERAGE_PARTIAL,
    COVERAGE_UNKNOWN,
    ENCODING_JSON_GZIP,
    ENTITY_TYPES,
    MAX_PACK_COMPRESSED_BYTES,
    PROTOCOL_SCHEMA_VERSION,
    READER_VERSION,
    RELEASE_RECORD_NAME,
    ProtocolError,
    canonical_json_bytes,
    compute_checked_through,
    entity_count,
    entity_records,
    entity_stable_ids,
    fragment_for,
    gzip_bytes,
    pack_record_name,
    partition_id,
    sha256_hex,
    validate_fragment,
    validate_partition_descriptor,
    validate_root_index,
)
from sources_loader import (  # noqa: E402
    SourcesConfigError,
    approved_brands,
    load_sources,
    rejected_summary,
)

# 只在这些实体类型上附带 timelineYears（年度卡片随归档类内容走）
TIMELINE_CARRYING_TYPES = {"archive-catalogue"}


def parse_args(argv: Optional[List[str]] = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="从已批准的整馆 catalog 构建时光馆不可变发布产物（不写线上）"
    )
    parser.add_argument("--input", required=True, type=Path, help="已审核的输入目录（含 catalog*.json）")
    parser.add_argument("--output", required=True, type=Path, help="发布产物输出目录")
    parser.add_argument(
        "--sources",
        type=Path,
        default=Path(__file__).resolve().parent / "sources.yaml",
        help="来源与授权配置（默认 publication/sources.yaml）",
    )
    parser.add_argument("--release-seq", required=True, type=int, help="运营发布序号，严格递增")
    parser.add_argument("--revocation-epoch", type=int, default=0, help="撤回清单版本")
    parser.add_argument("--previous-release-seq", type=int, default=0, help="上一发布序号（运维追踪用）")
    parser.add_argument("--withdrawals", type=Path, help="撤回清单 JSON")
    parser.add_argument(
        "--coverage-mode",
        choices=("partial", "complete"),
        default="partial",
        help="分片覆盖状态。默认 partial：Bundle 是过去某个时点的快照，不声明完整。",
    )
    parser.add_argument(
        "--checked-through",
        help="覆盖模式为 complete 时必填，ISO 8601，例如 2026-09-14T02:30:00Z",
    )
    parser.add_argument(
        "--day-coverage-days",
        type=int,
        default=0,
        help="为最近 N 个自然日生成 dayCoverage（需要 complete 模式与 --checked-through）",
    )
    parser.add_argument(
        "--scope",
        choices=("legacy", "monthly"),
        default="legacy",
        help="分片范围：legacy 每实体类型一个包；monthly 让资讯按月分包",
    )
    parser.add_argument(
        "--previous",
        type=Path,
        help="上一个发布产物目录，用于输出差异报告",
    )
    parser.add_argument("--dry-run", action="store_true", help="只打印计划，不写任何文件")
    parser.add_argument(
        "--allow-unapproved-local-fixture",
        action="store_true",
        help=(
            "本地联调专用：允许构建未批准来源，产物被标记为 localFixture，"
            "publish_cloudkit.py 会拒绝发布它。"
        ),
    )
    return parser.parse_args(argv)


# ------------------------------------------------------------------ 日期


def parse_iso8601(value: str) -> dt.datetime:
    text = value.strip().replace("Z", "+00:00")
    parsed = dt.datetime.fromisoformat(text)
    if parsed.tzinfo is None:
        raise ProtocolError("时间必须带时区偏移：{}".format(value))
    return parsed


def zone_offset(tz_name: str) -> dt.timedelta:
    """把 IANA 时区名映射为固定偏移。

    ⚠️ 这里**不**实现完整时区数据库，而是显式登记本项目实际使用的来源时区。
    未登记的时区会报错而不是悄悄按 UTC 处理——分片 ID 漂移的代价比报错大。
    """
    known = {
        "Asia/Tokyo": dt.timedelta(hours=9),
        "Asia/Shanghai": dt.timedelta(hours=8),
        "UTC": dt.timedelta(0),
    }
    if tz_name not in known:
        raise ProtocolError(
            "未登记的来源时区 {!r}。请在 build_release.zone_offset 中显式登记后再发布，"
            "避免分片 ID 在不同时区客户端上漂移。".format(tz_name)
        )
    return known[tz_name]


def day_key(moment: dt.datetime, offset: dt.timedelta) -> str:
    return (moment.astimezone(dt.timezone(offset))).strftime("%Y-%m-%d")


# ------------------------------------------------------------------ 构建


def build_pack(
    brand: Dict[str, Any],
    catalog: Dict[str, Any],
    entity_type: str,
    coverage_mode: str,
    checked_through: Optional[str],
    day_coverage: Dict[str, str],
    scope_key: str,
) -> Optional[Tuple[Dict[str, Any], bytes, Dict[str, Any]]]:
    """构建一个数据包。

    返回 (分片描述, 压缩字节, 分片内容)；该实体类型没有任何条目时返回 None。
    """
    count = entity_count(catalog, entity_type)
    if count == 0:
        return None

    brand_id = str(brand["brandID"])
    pid = partition_id(brand_id, entity_type, scope_key)
    fragment = fragment_for(
        catalog, entity_type, include_timeline_years=entity_type in TIMELINE_CARRYING_TYPES
    )

    coverage = COVERAGE_COMPLETE if coverage_mode == "complete" else COVERAGE_PARTIAL
    payload = {
        "schemaVersion": PROTOCOL_SCHEMA_VERSION,
        "partitionID": pid,
        "brandID": brand_id,
        "entityType": entity_type,
        "partitionRevision": 1,
        "coverageStatus": coverage,
        "checkedThrough": checked_through,
        "dayCoverage": day_coverage,
        "records": fragment,
    }

    raw = canonical_json_bytes(payload)
    if len(raw) > MAX_PACK_COMPRESSED_BYTES * 8:
        raise ProtocolError("{} 解压后体积过大，需要先拆分分片".format(pid))
    compressed = gzip_bytes(raw)
    payload_hash = sha256_hex(compressed)

    descriptor = {
        "partitionID": pid,
        "brandID": brand_id,
        "entityType": entity_type,
        "partitionRevision": 1,
        "coverageStatus": coverage,
        "checkedThrough": checked_through,
        "dayCoverage": day_coverage,
        "packRecordName": pack_record_name(payload_hash),
        "payloadHash": payload_hash,
        "recordCount": count,
        "dependencyPackRecordNames": [],
    }
    return descriptor, compressed, payload


def entity_month_scope(catalog: Dict[str, Any], entity_type: str) -> Dict[str, List[Dict[str, Any]]]:
    """按 `yyyy-MM` 归组实体（仅资讯按月分包时使用）"""
    grouped: Dict[str, List[Dict[str, Any]]] = {}
    for record in entity_records(catalog, entity_type):
        published = str(record.get("publishedOn") or record.get("observedAt") or "")
        month = published[:7] if len(published) >= 7 else "unknown"
        grouped.setdefault(month, []).append(record)
    return grouped


def build_for_brand(
    brand: Dict[str, Any],
    catalog: Dict[str, Any],
    args: argparse.Namespace,
) -> Tuple[List[Dict[str, Any]], List[Tuple[str, bytes]], List[Dict[str, str]]]:
    descriptors: List[Dict[str, Any]] = []
    packs: List[Tuple[str, bytes]] = []
    issues: List[Dict[str, str]] = []

    if args.coverage_mode == "complete" and not args.checked_through:
        raise ProtocolError("--coverage-mode complete 必须同时给出 --checked-through")

    offset = zone_offset(str(brand.get("sourceTimeZone") or "Asia/Tokyo"))
    reference_month: Optional[str] = None
    day_coverage: Dict[str, str] = {}

    if args.day_coverage_days > 0:
        if not args.checked_through:
            raise ProtocolError("--day-coverage-days 需要 --checked-through 作为参考时刻")
        reference = parse_iso8601(args.checked_through)
        reference_month = day_key(reference, offset)[:7]
        event_days = {
            day_key(
                dt.datetime.strptime(str(record.get("publishedOn")), "%Y-%m-%d").replace(
                    tzinfo=dt.timezone(offset)
                ),
                offset,
            )
            for record in entity_records(catalog, "event")
            if record.get("publishedOn")
        }
        for index in range(args.day_coverage_days):
            key = day_key(reference - dt.timedelta(days=index), offset)
            # 该业务日**确实被完整枚举过**：有条目是 complete，零条是 empty。
            # 两者都是有效结论，都带版本与检查时间（§5.2）。
            day_coverage[key] = COVERAGE_COMPLETE if key in event_days else COVERAGE_EMPTY

    for entity_type in ENTITY_TYPES:
        if args.scope == "monthly" and entity_type == "event":
            grouped = entity_month_scope(catalog, entity_type)
            for month in sorted(grouped):
                slim = dict(catalog)
                slim["events"] = grouped[month]
                checked = args.checked_through or compute_checked_through(slim, entity_type)
                built = build_pack(
                    brand,
                    slim,
                    entity_type,
                    args.coverage_mode,
                    checked,
                    day_coverage if month == reference_month else {},
                    month,
                )
                if built is None:
                    continue
                descriptors.append(built[0])
                packs.append((built[0]["payloadHash"], built[1]))
                issues += collect_issues(brand, built)
            continue

        checked = args.checked_through or compute_checked_through(catalog, entity_type)
        built = build_pack(
            brand,
            catalog,
            entity_type,
            args.coverage_mode,
            checked,
            day_coverage,
            "all",
        )
        if built is None:
            continue
        descriptors.append(built[0])
        packs.append((built[0]["payloadHash"], built[1]))
        issues += collect_issues(brand, built)

    resolve_dependencies(descriptors)
    return descriptors, packs, issues


# 分片之间的显式依赖：被引用实体不在同包时必须在根清单里声明（§6.7）
PACK_DEPENDENCIES: Dict[str, str] = {
    "item": "catalogue",
    "event": "commerce-product",
    "story": "commerce-product",
    "coordinate": "commerce-product",
    "commerce-snapshot": "commerce-product",
}


def resolve_dependencies(descriptors: List[Dict[str, Any]]) -> None:
    pack_by_type: Dict[str, str] = {}
    for descriptor in descriptors:
        pack_by_type.setdefault(str(descriptor["entityType"]), str(descriptor["packRecordName"]))
    for descriptor in descriptors:
        dependency_type = PACK_DEPENDENCIES.get(str(descriptor["entityType"]))
        if not dependency_type:
            descriptor["dependencyPackRecordNames"] = []
            continue
        dependency = pack_by_type.get(dependency_type)
        if dependency and dependency != descriptor["packRecordName"]:
            descriptor["dependencyPackRecordNames"] = [dependency]
        else:
            descriptor["dependencyPackRecordNames"] = []


def collect_issues(
    brand: Dict[str, Any], built: Tuple[Dict[str, Any], bytes, Dict[str, Any]]
) -> List[Dict[str, str]]:
    descriptor, compressed, payload = built
    structural = validate_fragment(
        payload["records"], str(brand["brandID"]), descriptor["entityType"], descriptor["coverageStatus"]
    )
    partition_level = validate_partition_descriptor(
        descriptor, payload, len(compressed), len(canonical_json_bytes(payload))
    )
    return [dict(issue, layer="structural") for issue in structural] + [
        dict(issue, layer="partition") for issue in partition_level
    ]


def load_withdrawals(path: Optional[Path]) -> List[Dict[str, Any]]:
    if not path:
        return []
    data = json.loads(Path(path).read_text(encoding="utf-8"))
    if isinstance(data, dict):
        data = data.get("withdrawals", [])
    if not isinstance(data, list):
        raise ProtocolError("撤回清单必须是数组")
    return data


def load_media(input_dir: Path) -> Tuple[List[Dict[str, Any]], List[Tuple[str, Path]]]:
    manifest_path = input_dir / "media-manifest.json"
    if not manifest_path.exists():
        return [], []
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    records: List[Dict[str, Any]] = []
    files: List[Tuple[str, Path]] = []
    for entry in manifest.get("media", []):
        source = input_dir / str(entry["fileName"])
        if not source.exists():
            raise ProtocolError("媒体文件缺失：{}".format(source))
        payload = source.read_bytes()
        content_hash = sha256_hex(payload)
        records.append(
            {
                "mediaKey": str(entry["mediaKey"]),
                "contentHash": content_hash,
                "mimeType": str(entry["mimeType"]),
                "byteCount": len(payload),
                "recordName": "th.media.{}".format(content_hash),
                "fileName": "{}.{}".format(content_hash, source.suffix.lstrip(".") or "bin"),
            }
        )
        files.append((records[-1]["fileName"], source))
    return records, files


def diff_summary(previous: Optional[Path], root_index: Dict[str, Any]) -> List[str]:
    if not previous:
        return []
    previous_root = previous / "root-index.json"
    if not previous_root.exists():
        return ["（上一个发布产物缺少 root-index.json，无法比较）"]
    old = json.loads(previous_root.read_text(encoding="utf-8"))
    old_map = {item["partitionID"]: item for item in old.get("partitions", [])}
    new_map = {item["partitionID"]: item for item in root_index.get("partitions", [])}
    lines: List[str] = []
    for pid in sorted(set(new_map) - set(old_map)):
        lines.append("+ 分片新增 {}（{} 条）".format(pid, new_map[pid]["recordCount"]))
    for pid in sorted(set(old_map) - set(new_map)):
        lines.append("- 分片移除 {}（{} 条）".format(pid, old_map[pid]["recordCount"]))
    for pid in sorted(set(old_map) & set(new_map)):
        old_item, new_item = old_map[pid], new_map[pid]
        if old_item["payloadHash"] != new_item["payloadHash"]:
            delta = new_item["recordCount"] - old_item["recordCount"]
            lines.append(
                "~ 分片修订 {}（{} → {} 条）".format(pid, old_item["recordCount"], now_count(new_item))
            )
            if delta < 0:
                lines.append("  ⚠️ 条目数下降 {}，请确认这是有意的删除/撤回".format(-delta))
    return lines


def now_count(item: Dict[str, Any]) -> int:
    return int(item.get("recordCount", 0))


# ------------------------------------------------------------------ 主流程


def main(argv: Optional[List[str]] = None) -> int:
    args = parse_args(argv)
    started = dt.datetime.now(dt.timezone.utc)

    try:
        config = load_sources(args.sources)
    except SourcesConfigError as error:
        print("❌ 来源配置无法解析：{}".format(error), file=sys.stderr)
        return 2

    approved = approved_brands(config)
    if args.allow_unapproved_local_fixture:
        approved = [b for b in (config.get("brands") or []) if isinstance(b, dict)]
        print("⚠️  本地联调模式：已放开未批准来源，产物会被标记为 localFixture，不可发布。")

    print("来源审批状态：")
    for line in rejected_summary(config):
        print("  ✗ {}".format(line))
    for brand in approved:
        print("  ✓ {}（已批准）".format(brand.get("brandID")))

    if not approved:
        print(
            "❌ 没有任何已批准来源，按默认禁止策略不生成产物。\n"
            "   请先在 sources.yaml 中把 permissionStatus 置为 approved，"
            "并填好 allowedContentTypes 与 allowedTerritories。",
            file=sys.stderr,
        )
        return 3

    if args.output.exists():
        # 只清理「看起来就是发布产物」的目录，避免误删运维指定的其它路径
        looks_like_release = (args.output / "release.json").exists() or (
            args.output / "root-index.json"
        ).exists()
        is_empty = not any(args.output.iterdir())
        if not (looks_like_release or is_empty):
            print(
                "❌ 输出目录 {} 已存在且不像发布产物目录，请换一个目录或先自行清理。".format(
                    args.output
                ),
                file=sys.stderr,
            )
            return 6
        print("🧹 清理既有输出目录 {}".format(args.output))
        if not args.dry_run:
            shutil.rmtree(args.output)

    brands: List[Dict[str, Any]] = []
    partitions: List[Dict[str, Any]] = []
    all_packs: List[Tuple[str, bytes]] = []
    all_issues: List[Dict[str, str]] = []
    built_brands: List[str] = []

    for brand in approved:
        catalog_path = args.input / "{}.json".format(brand["resourceName"])
        if not catalog_path.exists():
            print("  · {}：输入缺失 {}，跳过".format(brand["brandID"], catalog_path.name))
            continue
        catalog = json.loads(catalog_path.read_text(encoding="utf-8"))
        descriptors, packs, issues = build_for_brand(brand, catalog, args)
        if not descriptors:
            print("  · {}：没有任何可分片内容，跳过".format(brand["brandID"]))
            continue
        record_total = sum(int(item["recordCount"]) for item in descriptors)
        compressed_total = sum(len(data) for _, data in packs)
        print(
            "  · {}：{} 个分片 / {} 条 / 压缩后 {} 字节".format(
                brand["brandID"], len(descriptors), record_total, compressed_total
            )
        )
        brands.append(
            {
                "brandID": str(brand["brandID"]),
                "displayName": str(brand["displayName"]),
                "sourceTimeZone": str(brand["sourceTimeZone"]),
                "sourceCoverage": str(brand["sourceCoverage"]),
                "coverageDescription": str(brand["coverageDescription"]),
            }
        )
        partitions += descriptors
        all_packs += packs
        all_issues += issues
        built_brands.append(str(brand["brandID"]))

    if not partitions:
        print("❌ 没有生成任何分片，已中止（不会产出空发布）", file=sys.stderr)
        return 4

    media_records, media_files = load_media(args.input)
    withdrawals = load_withdrawals(args.withdrawals)

    root_index = {
        "schemaVersion": PROTOCOL_SCHEMA_VERSION,
        "releaseSeq": args.release_seq,
        "publishedAt": started.strftime("%Y-%m-%dT%H:%M:%SZ"),
        "revocationEpoch": args.revocation_epoch,
        "brands": brands,
        "partitions": partitions,
        "withdrawals": withdrawals,
    }
    all_issues += [
        dict(issue, layer="partition") for issue in validate_root_index(root_index, args.release_seq)
    ]

    if all_issues:
        print("❌ 产物未通过协议校验，共 {} 条问题：".format(len(all_issues)), file=sys.stderr)
        for issue in all_issues[:40]:
            print(
                "   [{}] {} {} {}".format(
                    issue.get("layer", "?"),
                    issue.get("code", "?"),
                    issue.get("entityID", ""),
                    issue.get("message", ""),
                ),
                file=sys.stderr,
            )
        return 5

    root_bytes = canonical_json_bytes(root_index)
    root_hash = sha256_hex(root_bytes)
    release = {
        "recordName": RELEASE_RECORD_NAME,
        "releaseSeq": args.release_seq,
        "schemaVersion": PROTOCOL_SCHEMA_VERSION,
        "publishedAt": root_index["publishedAt"],
        "rootIndexHash": root_hash,
        "revocationEpoch": args.revocation_epoch,
        "minimumReaderVersion": READER_VERSION,
        "previousReleaseSeq": args.previous_release_seq,
        "encoding": ENCODING_JSON_GZIP,
        "localFixture": bool(args.allow_unapproved_local_fixture),
        "brands": built_brands,
        "partitionCount": len(partitions),
        "recordCount": sum(int(item["recordCount"]) for item in partitions),
    }

    print("\n发布计划：")
    print("  releaseSeq        {}".format(args.release_seq))
    print("  revocationEpoch   {}".format(args.revocation_epoch))
    print("  分片              {}".format(len(partitions)))
    print("  数据包            {} 个 / {} 字节".format(len(all_packs), sum(len(d) for _, d in all_packs)))
    print("  媒体              {} 个".format(len(media_records)))
    print("  撤回条目          {}".format(len(withdrawals)))
    print("  rootIndexHash     {}".format(root_hash))
    print("  覆盖模式          {}".format(args.coverage_mode))

    diff_lines = diff_summary(args.previous, root_index)
    if diff_lines:
        print("\n与上一版本的差异：")
        for line in diff_lines:
            print("  {}".format(line))

    if args.dry_run:
        print("\n（--dry-run：未写入任何文件）")
        return 0

    packs_dir = args.output / "packs"
    audits_dir = args.output / "audit"
    packs_dir.mkdir(parents=True, exist_ok=True)
    audits_dir.mkdir(parents=True, exist_ok=True)
    for payload_hash, data in all_packs:
        (packs_dir / "{}.json.gz".format(payload_hash)).write_bytes(data)
    (args.output / "root-index.json").write_bytes(root_bytes)
    (args.output / "release.json").write_text(
        json.dumps(release, ensure_ascii=False, indent=2, sort_keys=True) + "\n", encoding="utf-8"
    )

    if media_records:
        media_dir = args.output / "media"
        media_dir.mkdir(parents=True, exist_ok=True)
        for file_name, source in media_files:
            shutil.copy2(source, media_dir / file_name)
        (args.output / "media.json").write_text(
            json.dumps({"media": media_records}, ensure_ascii=False, indent=2, sort_keys=True) + "\n",
            encoding="utf-8",
        )

    audit = {
        "builtAt": started.strftime("%Y-%m-%dT%H:%M:%SZ"),
        "releaseSeq": args.release_seq,
        "revocationEpoch": args.revocation_epoch,
        "rootIndexHash": root_hash,
        "localFixture": bool(args.allow_unapproved_local_fixture),
        "sourcesFile": str(args.sources),
        "approvedBrands": [
            {
                "brandID": brand["brandID"],
                "sourceID": brand.get("sourceID"),
                "permissionStatus": brand.get("permissionStatus"),
                "allowedContentTypes": brand.get("allowedContentTypes"),
                "allowedTerritories": brand.get("allowedTerritories"),
                "reviewOwner": brand.get("reviewOwner"),
            }
            for brand in approved
        ],
        "partitions": partitions,
        "media": media_records,
        "withdrawals": withdrawals,
    }
    (audits_dir / "release-manifest.json").write_text(
        json.dumps(audit, ensure_ascii=False, indent=2, sort_keys=True) + "\n", encoding="utf-8"
    )
    checksums = ["{}  root-index.json".format(root_hash)]
    checksums += [
        "{}  packs/{}.json.gz".format(payload_hash, payload_hash) for payload_hash, _ in all_packs
    ]
    checksums += [
        "{}  media/{}".format(item["contentHash"], item["fileName"]) for item in media_records
    ]
    (audits_dir / "checksums.txt").write_text("\n".join(checksums) + "\n", encoding="utf-8")

    print("\n✅ 产物已写入 {}".format(args.output))
    print("   下一步：validate_release.py --release {} 校验后再发布。".format(args.output))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
