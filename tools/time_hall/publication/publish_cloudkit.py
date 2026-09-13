#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""发布时光馆产物到公共库（§8.2 / §9.1 / §9.2 / §9.3）。

固定顺序，只在这里定义一次：

    1. 复校验发布产物（等价于 validate_release.py，失败即中止）
    2. 读当前 THRelease 与 changeTag
    3. 上传缺失的 THMedia      —— 不可变，只增不改
    4. 上传缺失的 THDataPack   —— 不可变，只增不改
    5. 回读核对可获取性
    6. 条件更新 THRelease（带第 2 步读到的 changeTag）
    7. 回读确认新发布头生效

只有第 6 步成功，新版本才对用户生效；前面任何一步失败都只留下
未被引用的不可变资源，不改变任何用户看到的版本（§9.1）。

安全约束：

  * 产物带 `localFixture` 标记（未批准来源的本地联调产物）时，
    `--adapter cloudkit` **强制拒绝发布**，不提供覆盖开关（§8.5 / §18.1）。
  * 发布头使用冲突检测；发生 changeTag 冲突**不能**改成无条件覆盖（§9.3）。
  * 凭证只从 Keychain 或环境变量指向的文件读取，绝不明文传参、绝不打印私钥（§8.5）。

演练（不需要任何凭证，不联网）：

    python3 publish_cloudkit.py --release <dir> --adapter filesystem \\
        --filesystem-root /tmp/th_fs --apply
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple

sys.path.insert(0, str(Path(__file__).resolve().parent))

from protocol import ProtocolError, sha256_hex  # noqa: E402
from publish_adapters import (  # noqa: E402
    PublishAdapter,
    env_guard,
    make_adapter,
)
from validate_release import (  # noqa: E402
    check_release_header,
    load_json,
    verify_pack,
)

from protocol import validate_release_references, validate_root_index  # noqa: E402

EXIT_OK = 0
EXIT_USAGE = 2
EXIT_VALIDATION = 3
EXIT_REFUSED = 4
EXIT_CONFLICT = 5


def parse_args(argv: Optional[List[str]] = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="发布时光馆产物到公共库（不可变资源 + 最后切换发布头）"
    )
    parser.add_argument("--release", required=True, type=Path, help="build_release.py 产出的发布产物目录")
    parser.add_argument(
        "--adapter",
        choices=("filesystem", "cloudkit"),
        default="filesystem",
        help="发布适配器。默认 filesystem（本机演练，不需要凭证）",
    )
    parser.add_argument(
        "--environment",
        choices=("development", "production"),
        default="development",
        help="cloudkit 适配器的目标环境。默认 development",
    )
    parser.add_argument(
        "--filesystem-root",
        type=Path,
        help="filesystem 适配器的根目录（演练用目标）",
    )
    parser.add_argument(
        "--apply",
        action="store_true",
        help="真正执行写入。不加此参数只做计划与检查（dry-run）",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="显式声明演练（与不加 --apply 等价）",
    )
    parser.add_argument("--print-requests", action="store_true", help="打印将要发送的请求（签名已脱敏）")
    parser.add_argument("--quiet", action="store_true", help="只输出结论")
    parser.add_argument(
        "--receipt",
        type=Path,
        help="把本次发布回执写到该路径（新增文件，不改动产物目录）",
    )
    return parser.parse_args(argv)


# ------------------------------------------------------------------ 复校验


def revalidate(release_dir: Path) -> Tuple[Dict[str, Any], bytes, Dict[str, Any], List[str]]:
    """发布前再做一次完整校验。返回 (release, root_bytes, root_index, errors)。"""
    errors: List[str] = []
    release_path = release_dir / "release.json"
    root_path = release_dir / "root-index.json"
    if not release_path.exists() or not root_path.exists():
        return {}, b"", {}, ["{} 不是完整的发布产物目录".format(release_dir)]

    release = load_json(release_path)
    root_bytes = root_path.read_bytes()
    root_index = json.loads(root_bytes.decode("utf-8"))

    header_errors, _ = check_release_header(release, root_bytes)
    errors += header_errors
    errors += [
        "[{}] {} {}".format(issue.get("code"), issue.get("entityID") or "", issue.get("message"))
        for issue in validate_root_index(root_index, release.get("releaseSeq"))
    ]

    partitions: List[Dict[str, Any]] = root_index.get("partitions") or []
    packs: List[Tuple[Dict[str, Any], Dict[str, Any]]] = []
    total_records = 0
    for descriptor in partitions:
        payload, pack_issues, pack_errors = verify_pack(release_dir, descriptor)
        errors += ["{}：{}".format(descriptor.get("partitionID"), item) for item in pack_errors]
        errors += [
            "[{}] {} {}".format(
                issue.get("code"), issue.get("entityID") or "", issue.get("message")
            )
            for issue in pack_issues
        ]
        if payload is None:
            continue
        packs.append((descriptor, payload))
        total_records += int(descriptor.get("recordCount", 0))

    errors += [
        "[{}] {} {}".format(issue.get("code"), issue.get("entityID") or "", issue.get("message"))
        for issue in validate_release_references(packs)
    ]

    if release.get("partitionCount") != len(partitions):
        errors.append(
            "release.partitionCount={} 与实际 {} 不一致".format(
                release.get("partitionCount"), len(partitions)
            )
        )
    if release.get("recordCount") != total_records:
        errors.append(
            "release.recordCount={} 与实际 {} 不一致".format(release.get("recordCount"), total_records)
        )
    return release, root_bytes, root_index, errors


# ------------------------------------------------------------------ 发布


def collect_assets(
    release_dir: Path, root_index: Dict[str, Any], release: Dict[str, Any]
) -> Tuple[List[Dict[str, Any]], List[Dict[str, Any]]]:
    """从产物目录收集数据包与媒体清单。"""
    packs: List[Dict[str, Any]] = []
    for descriptor in root_index.get("partitions") or []:
        payload_hash = str(descriptor.get("payloadHash", ""))
        path = release_dir / "packs" / "{}.json.gz".format(payload_hash)
        packs.append(
            {
                "payloadHash": payload_hash,
                "recordName": str(descriptor.get("packRecordName") or "th.pack.{}".format(payload_hash)),
                "filePath": path,
                "meta": {
                    "partitionID": str(descriptor.get("partitionID", "")),
                    "releaseSeq": int(release.get("releaseSeq", 0)),
                    "sha256": payload_hash,
                    "byteCount": path.stat().st_size if path.exists() else 0,
                },
            }
        )

    media: List[Dict[str, Any]] = []
    media_path = release_dir / "media.json"
    if media_path.exists():
        for item in load_json(media_path).get("media") or []:
            content_hash = str(item.get("contentHash", ""))
            media.append(
                {
                    "contentHash": content_hash,
                    "recordName": str(item.get("recordName") or "th.media.{}".format(content_hash)),
                    "filePath": release_dir / "media" / str(item.get("fileName", "")),
                    "meta": {
                        "mediaKey": str(item.get("mediaKey", "")),
                        "mimeType": str(item.get("mimeType", "")),
                        "sha256": content_hash,
                        "byteCount": int(item.get("byteCount", 0)),
                    },
                }
            )
    return packs, media


def publish(args: argparse.Namespace) -> int:
    release_dir: Path = args.release
    apply_changes = bool(args.apply and not args.dry_run)

    release, root_bytes, root_index, errors = revalidate(release_dir)
    if errors:
        print("❌ 发布前复校验未通过，共 {} 条问题：" .format(len(errors)), file=sys.stderr)
        for line in errors[:60]:
            print("   {}".format(line), file=sys.stderr)
        return EXIT_VALIDATION

    if not args.quiet:
        print("发布产物：{}".format(release_dir))
        print("  releaseSeq        {}".format(release.get("releaseSeq")))
        print("  revocationEpoch   {}".format(release.get("revocationEpoch")))
        print("  分片              {}".format(release.get("partitionCount")))
        print("  条目              {}".format(release.get("recordCount")))
        print("  rootIndexHash     {}".format(release.get("rootIndexHash")))
        print("  ✅ 复校验通过")

    if release.get("localFixture") and args.adapter == "cloudkit":
        print(
            "❌ 产物标记为 localFixture（未批准来源的本地联调产物），"
            "拒绝发布到公共库。\n"
            "   请先在 sources.yaml 中把来源置为 approved 并填好 allowedContentTypes / "
            "allowedTerritories，再重新构建。",
            file=sys.stderr,
        )
        return EXIT_REFUSED

    if release.get("localFixture") and args.adapter == "filesystem":
        print("⚠️  产物为 localFixture：只允许写入本机演练目录，不代表已上线。")

    env_guard(args.environment, apply_changes)

    try:
        adapter: PublishAdapter = make_adapter(
            args.adapter,
            args.environment,
            apply_changes,
            args.print_requests,
            args.filesystem_root,
        )
    except ProtocolError as error:
        print("❌ {}".format(error), file=sys.stderr)
        return EXIT_USAGE

    print("目标：{}".format(adapter.describe()))
    print("模式：{}".format("**真实写入**" if apply_changes else "dry-run（不写任何东西）"))
    print("")

    # ---- 第 2 步：读当前发布头
    print("[2/7] 读取当前发布头")
    current = adapter.fetch_current_release()
    expected_change_tag: Optional[str] = None
    if current:
        expected_change_tag = current.get("changeTag")
        print(
            "       当前 releaseSeq={} revocationEpoch={} changeTag={}".format(
                current.get("releaseSeq"), current.get("revocationEpoch"), expected_change_tag
            )
        )
        if int(release["releaseSeq"]) <= int(current.get("releaseSeq") or 0):
            print(
                "❌ 本地 releaseSeq={} 不大于线上 {}，拒绝发布（发布号必须严格递增；"
                "回滚请用 rollback_release.py 递增发布号）。".format(
                    release["releaseSeq"], current.get("releaseSeq")
                ),
                file=sys.stderr,
            )
            return EXIT_CONFLICT
        if int(release.get("revocationEpoch", 0)) < int(current.get("revocationEpoch") or 0):
            print(
                "❌ 本地 revocationEpoch={} 小于线上 {}，撤回只能累加（§11.4）。".format(
                    release.get("revocationEpoch"), current.get("revocationEpoch")
                ),
                file=sys.stderr,
            )
            return EXIT_CONFLICT
        gap = int(release["releaseSeq"]) - int(current.get("releaseSeq") or 0)
        if gap > 1:
            print("       ⚠️ 发布号跳跃 {}，请确认这是有意跳号".format(gap))
    else:
        print("       线上尚无发布头（首次发布）")

    packs, media = collect_assets(release_dir, root_index, release)

    # ---- 第 3 步：媒体
    print("[3/7] 上传缺失媒体（不可变，只增不改）")
    uploaded_media = 0
    for item in media:
        if adapter.media_exists(item["contentHash"]):
            continue
        if not item["filePath"].exists():
            print("❌ 媒体文件缺失：{}".format(item["filePath"]), file=sys.stderr)
            return EXIT_VALIDATION
        adapter.put_media(item["contentHash"], item["filePath"], item["meta"])
        uploaded_media += 1
    print("       新增 {} / 共 {} 个".format(uploaded_media, len(media)))

    # ---- 第 4 步：数据包
    print("[4/7] 上传缺失数据包（不可变，只增不改）")
    uploaded_packs = 0
    for item in packs:
        if adapter.pack_exists(item["payloadHash"]):
            continue
        if not item["filePath"].exists():
            print("❌ 数据包文件缺失：{}".format(item["filePath"]), file=sys.stderr)
            return EXIT_VALIDATION
        if sha256_hex(item["filePath"].read_bytes()) != item["payloadHash"]:
            print("❌ 数据包本地摘要漂移：{}".format(item["filePath"]), file=sys.stderr)
            return EXIT_VALIDATION
        adapter.put_pack(item["payloadHash"], item["filePath"], item["meta"])
        uploaded_packs += 1
    print("       新增 {} / 共 {} 个".format(uploaded_packs, len(packs)))

    # ---- 第 5 步：回读核对
    if not apply_changes:
        print("[5/7] 回读核对（dry-run：未写入，跳过）")
    else:
        print("[5/7] 回读核对可获取性")
        missing: List[str] = []
        for item in packs:
            got = adapter.read_back_pack_hash(item["payloadHash"])
            if got != item["payloadHash"]:
                missing.append(item["recordName"])
        for item in media:
            got = adapter.read_back_media_hash(item["contentHash"])
            if got != item["contentHash"]:
                missing.append(item["recordName"])
        if missing:
            print(
                "❌ 回读发现 {} 个资源不可获取，已中止（发布头未切换）：".format(len(missing)),
                file=sys.stderr,
            )
            for name in missing[:20]:
                print("   - {}".format(name), file=sys.stderr)
            return EXIT_CONFLICT
        print("       {} 个资源均可获取".format(len(packs) + len(media)))

    # ---- 第 6 步：切换发布头（唯一生效点）
    print("[6/7] 条件更新发布头" + ("" if apply_changes else "（dry-run）"))
    try:
        new_change_tag = adapter.put_release(release, root_bytes, expected_change_tag)
    except ProtocolError as error:
        print("❌ {}".format(error), file=sys.stderr)
        return EXIT_CONFLICT
    print("       新 changeTag = {}".format(new_change_tag or "（未返回）"))

    # ---- 第 7 步：回读确认
    print("[7/7] 回读确认发布头")
    confirmed = adapter.fetch_current_release()
    if apply_changes:
        if not confirmed or int(confirmed.get("releaseSeq") or -1) != int(release["releaseSeq"]):
            print("❌ 发布头回读未确认新版本，请人工检查", file=sys.stderr)
            return EXIT_CONFLICT
        print(
            "       已确认 releaseSeq={} changeTag={}".format(
                confirmed.get("releaseSeq"), confirmed.get("changeTag")
            )
        )
    else:
        print("       （dry-run：未写入，跳过确认）")

    print("")
    if apply_changes:
        print("✅ 发布完成：releaseSeq={} 已对全体用户生效".format(release["releaseSeq"]))
    else:
        print("✅ dry-run 完成，未做任何写入。确认无误后加 --apply 真正发布。")

    if args.receipt:
        receipt = {
            "adapter": args.adapter,
            "environment": args.environment,
            "applied": apply_changes,
            "releaseSeq": release.get("releaseSeq"),
            "revocationEpoch": release.get("revocationEpoch"),
            "rootIndexHash": release.get("rootIndexHash"),
            "previousChangeTag": expected_change_tag,
            "newChangeTag": new_change_tag,
            "uploadedPacks": uploaded_packs,
            "uploadedMedia": uploaded_media,
            "totalPacks": len(packs),
            "totalMedia": len(media),
        }
        args.receipt.write_text(
            json.dumps(receipt, ensure_ascii=False, indent=2, sort_keys=True) + "\n", encoding="utf-8"
        )
        print("   发布回执已写入 {}".format(args.receipt))
    return EXIT_OK


def main(argv: Optional[List[str]] = None) -> int:
    args = parse_args(argv)
    try:
        return publish(args)
    except ProtocolError as error:
        print("❌ {}".format(error), file=sys.stderr)
        return EXIT_USAGE


if __name__ == "__main__":
    raise SystemExit(main())
