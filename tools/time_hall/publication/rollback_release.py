#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""回滚：把一份历史产物重新发布为**新的更高发布号**（§9.2）。

关键约束（对应设计 §0.3 / §9.2）：

  * **不允许把发布号调小**。回滚不是「改回旧编号」，而是
    「用旧内容 + 新高编号」再发一次，这样已经前进过的客户端才会接受；
  * 撤回（revocationEpoch / withdrawals）**只增不减**，回滚不会让撤回失效；
  * 数据包不可变，因此回滚**复用原分片字节**，只重写根清单与发布头；
    这样回滚本身不会重新引入任何已下线的内容字节。

本脚本只**产出**新的发布产物目录，不直接写线上；
产出后请用 publish_cloudkit.py 发布（可先 --dry-run）：

    python3 rollback_release.py --from-release /tmp/th_old --output /tmp/th_rb \\
        --release-seq 5 --reason "线上 releaseSeq=4 的图片字段大面积错位"
    python3 publish_cloudkit.py --release /tmp/th_rb --adapter cloudkit \\
        --environment production --apply
"""

from __future__ import annotations

import argparse
import datetime as dt
import json
import shutil
import sys
from pathlib import Path
from typing import Any, Dict, List, Optional

sys.path.insert(0, str(Path(__file__).resolve().parent))

from protocol import (  # noqa: E402
    PROTOCOL_SCHEMA_VERSION,
    READER_VERSION,
    RELEASE_RECORD_NAME,
    ProtocolError,
    canonical_json_bytes,
    sha256_hex,
)

EXIT_OK = 0
EXIT_USAGE = 2
EXIT_INVALID = 3
EXIT_REFUSED = 4


def parse_args(argv: Optional[List[str]] = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="把历史产物重新发布为新的更高发布号（回滚）")
    parser.add_argument("--from-release", required=True, type=Path, help="要回滚到的历史产物目录")
    parser.add_argument("--output", required=True, type=Path, help="新的发布产物目录")
    parser.add_argument("--release-seq", required=True, type=int, help="新的发布号，必须严格递增")
    parser.add_argument("--reason", required=True, help="回滚原因（写入审计记录，必填）")
    parser.add_argument(
        "--published-root",
        type=Path,
        help="可选：当前线上演练目录（filesystem 适配器写的），用于校验发布号确实在递增",
    )
    parser.add_argument(
        "--withdrawals",
        type=Path,
        help="可选：回滚同时追加的撤回清单 JSON（撤回只增不减，会与历史撤回合并）",
    )
    parser.add_argument("--apply", action="store_true", help="真正写入 output 目录")
    return parser.parse_args(argv)


def load_json(path: Path) -> Any:
    return json.loads(path.read_text(encoding="utf-8"))


def read_published_seq(root: Path) -> Optional[int]:
    path = root / "THRelease.json"
    if not path.exists():
        return None
    try:
        return int(load_json(path).get("releaseSeq"))
    except (TypeError, ValueError):
        return None


def merge_withdrawals(base: List[Dict[str, Any]], extra: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
    """撤回只增不减：按 entityID 合并，已存在的保留，新的追加。"""
    seen = {str(item.get("entityID")) for item in base}
    merged = list(base)
    for item in extra:
        entity_id = str(item.get("entityID"))
        if entity_id in seen:
            continue
        seen.add(entity_id)
        merged.append(item)
    return merged


def main(argv: Optional[List[str]] = None) -> int:
    args = parse_args(argv)
    source: Path = args.from_release
    output: Path = args.output

    release_path = source / "release.json"
    root_path = source / "root-index.json"
    if not release_path.exists() or not root_path.exists():
        print("❌ {} 不是完整的发布产物目录".format(source), file=sys.stderr)
        return EXIT_INVALID

    source_release = load_json(release_path)
    source_root = load_json(root_path)

    if args.release_seq <= int(source_release.get("releaseSeq") or 0):
        print(
            "❌ --release-seq {} 必须大于历史产物的 {}（回滚也要递增发布号，§9.2）".format(
                args.release_seq, source_release.get("releaseSeq")
            ),
            file=sys.stderr,
        )
        return EXIT_REFUSED

    if args.published_root:
        current = read_published_seq(args.published_root)
        if current is not None and args.release_seq <= current:
            print(
                "❌ --release-seq {} 不大于当前线上 {}，客户端会拒绝接受这次回滚".format(
                    args.release_seq, current
                ),
                file=sys.stderr,
            )
            return EXIT_REFUSED
        if current is None:
            print("⚠️  {} 中没有读到发布头，跳过发布号递增校验".format(args.published_root))

    # 分片字节必须仍在，且摘要与根清单声明一致（回滚不能引入漂移）
    partitions: List[Dict[str, Any]] = source_root.get("partitions") or []
    missing: List[str] = []
    drifted: List[str] = []
    for descriptor in partitions:
        payload_hash = str(descriptor.get("payloadHash", ""))
        pack = source / "packs" / "{}.json.gz".format(payload_hash)
        if not pack.exists():
            missing.append(payload_hash[:12])
            continue
        if sha256_hex(pack.read_bytes()) != payload_hash:
            drifted.append(payload_hash[:12])
    if missing or drifted:
        if missing:
            print("❌ 历史产物缺少 {} 个分片文件，无法回滚".format(len(missing)), file=sys.stderr)
        if drifted:
            print("❌ 历史产物有 {} 个分片字节摘要漂移，拒绝回滚".format(len(drifted)), file=sys.stderr)
        return EXIT_INVALID

    now = dt.datetime.now(dt.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")

    # 只改发布号与时间；分片、品牌、覆盖状态、撤回全部原样沿用
    new_root = dict(source_root)
    new_root["releaseSeq"] = args.release_seq
    new_root["publishedAt"] = now
    if args.withdrawals:
        extra = load_json(args.withdrawals)
        if isinstance(extra, dict):
            extra = extra.get("withdrawals", [])
        if not isinstance(extra, list):
            print("❌ 撤回清单必须是数组", file=sys.stderr)
            return EXIT_USAGE
        before = len(new_root.get("withdrawals") or [])
        new_root["withdrawals"] = merge_withdrawals(new_root.get("withdrawals") or [], extra)
        print(
            "撤回合并：{} → {} 条（只增不减）".format(before, len(new_root["withdrawals"]))
        )

    root_bytes = canonical_json_bytes(new_root)
    root_hash = sha256_hex(root_bytes)

    new_release = {
        "recordName": RELEASE_RECORD_NAME,
        "releaseSeq": args.release_seq,
        "schemaVersion": PROTOCOL_SCHEMA_VERSION,
        "publishedAt": now,
        "rootIndexHash": root_hash,
        "revocationEpoch": new_root.get("revocationEpoch", 0),
        "minimumReaderVersion": READER_VERSION,
        "previousReleaseSeq": int(source_release.get("releaseSeq") or 0),
        "encoding": source_release.get("encoding", "json+gzip"),
        "localFixture": bool(source_release.get("localFixture")),
        "brands": source_release.get("brands") or [],
        "partitionCount": len(partitions),
        "recordCount": sum(int(item.get("recordCount", 0)) for item in partitions),
        "rollbackOf": int(source_release.get("releaseSeq") or 0),
    }

    print("回滚计划：")
    print("  历史产物          {}（releaseSeq={}）".format(source, source_release.get("releaseSeq")))
    print("  新发布号          {}".format(args.release_seq))
    print("  分片              {}（复用原字节，不重打包）".format(len(partitions)))
    print("  条目              {}".format(new_release["recordCount"]))
    print("  新 rootIndexHash  {}".format(root_hash))
    print("  原因              {}".format(args.reason))
    if new_release["localFixture"]:
        print("  ⚠️ 历史产物为 localFixture，回滚产物同样带此标记，publish_cloudkit.py 会拒绝发布到公共库")

    if not args.apply:
        print("\n（未加 --apply：没有写入任何文件）")
        return EXIT_OK

    if output.exists():
        # 只清理看起来就是发布产物或空目录的目标，避免误删运维指定路径
        looks_like_release = (output / "release.json").exists() or (output / "root-index.json").exists()
        if not (looks_like_release or not any(output.iterdir())):
            print(
                "❌ 输出目录 {} 已存在且不像发布产物目录，请换一个目录或先自行清理".format(output),
                file=sys.stderr,
            )
            return EXIT_USAGE
        shutil.rmtree(output)

    packs_dir = output / "packs"
    audits_dir = output / "audit"
    packs_dir.mkdir(parents=True, exist_ok=True)
    audits_dir.mkdir(parents=True, exist_ok=True)
    for descriptor in partitions:
        payload_hash = str(descriptor["payloadHash"])
        shutil.copy2(source / "packs" / "{}.json.gz".format(payload_hash), packs_dir / "{}.json.gz".format(payload_hash))

    # 媒体也原样带过来（不可变，同一批 contentHash）
    media_records: List[Dict[str, Any]] = []
    source_media = source / "media.json"
    if source_media.exists():
        media_records = load_json(source_media).get("media") or []
        media_dir = output / "media"
        media_dir.mkdir(parents=True, exist_ok=True)
        for item in media_records:
            file_name = str(item.get("fileName", ""))
            origin = source / "media" / file_name
            if origin.exists():
                shutil.copy2(origin, media_dir / file_name)
        (output / "media.json").write_text(
            json.dumps({"media": media_records}, ensure_ascii=False, indent=2, sort_keys=True) + "\n",
            encoding="utf-8",
        )

    (output / "root-index.json").write_bytes(root_bytes)
    (output / "release.json").write_text(
        json.dumps(new_release, ensure_ascii=False, indent=2, sort_keys=True) + "\n", encoding="utf-8"
    )

    audit = {
        "kind": "rollback",
        "createdAt": now,
        "reason": args.reason,
        "fromRelease": str(source),
        "fromReleaseSeq": int(source_release.get("releaseSeq") or 0),
        "newReleaseSeq": args.release_seq,
        "rootIndexHash": root_hash,
        "partitionCount": len(partitions),
        "recordCount": new_release["recordCount"],
        "mediaCount": len(media_records),
        "withdrawals": new_root.get("withdrawals") or [],
        "localFixture": new_release["localFixture"],
    }
    (audits_dir / "rollback-manifest.json").write_text(
        json.dumps(audit, ensure_ascii=False, indent=2, sort_keys=True) + "\n", encoding="utf-8"
    )

    checksums = ["{}  root-index.json".format(root_hash)]
    checksums += [
        "{}  packs/{}.json.gz".format(item["payloadHash"], item["payloadHash"]) for item in partitions
    ]
    checksums += [
        "{}  media/{}".format(item["contentHash"], item["fileName"]) for item in media_records
    ]
    (audits_dir / "checksums.txt").write_text("\n".join(checksums) + "\n", encoding="utf-8")

    print("\n✅ 回滚产物已写入 {}".format(output))
    print("   下一步：")
    print("     python3 validate_release.py --release {}".format(output))
    print("     python3 publish_cloudkit.py --release {} --adapter <cloudkit|filesystem> --apply".format(output))
    return EXIT_OK


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except ProtocolError as error:
        print("❌ {}".format(error), file=sys.stderr)
        raise SystemExit(EXIT_USAGE)
