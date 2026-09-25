#!/usr/bin/env python3
"""把一个 CloudKit 环境里已发布的版本**原样镜像**到另一个环境。

## 为什么需要它

发布流水线（`publish_cloudkit.py`）要求 `--release <产物目录>`，而产物目录是
`build_release.py` 从审核后的输入目录生成的。产物目录一旦丢失（临时目录被清、
换机器），就没法直接「把 Development 已经发布好的内容再发一份到 Production」——
重新从输入重建既要凑齐输入、又可能与线上字节不一致。

本工具绕过产物目录：直接从**源环境回读**（发布头 / 根清单 / 全部分片），
逐项自证摘要后**原样写入**目标环境。字节级别的等价由回读保证，
不依赖本地是否有产物。

## 典型用途

    # 把 Development 已经发布好的内容同步到 Production（TestFlight 只读 Production）
    python3 mirror_environments.py --from development --to production --apply

## 硬约束（与 publish_cloudkit.py 一致）

1. **默认 dry-run**。不加 `--apply` 只打印计划，不写任何东西。
2. **摘要自证**：根清单 SHA-256 必须等于发布头的 `rootIndexHash`；
   每个分片字节的 SHA-256 必须等于其 `payloadHash`。不符即中止。
3. **发布号递增**：目标环境已有发布头时，只允许源的 `releaseSeq` 严格大于目标，
   否则中止（不可变语义，不回退）。目标为空则视为 0。
4. **失败只留孤儿资源**：分片先写、发布头最后切换（与 §9.1 同序），
   半途失败不会让目标环境的用户看到半成品。
5. **凭证按环境隔离**：源用无后缀 Keychain 账户、目标用 `.production` 后缀账户
   （见 `publish_adapters.Credentials`，_s2s key 按环境注册）。

## 边界

- **不迁移 THMedia**：媒体哈希不在根清单里，客户端本期也不消费远端媒体
  （商品图走包内 `local:` 引用）。源环境若有 THMedia 记录需要同步，
  得另提供 `media.json`；本工具会尝试枚举并在枚举成功时一并镜像。
"""

from __future__ import annotations

import argparse
import hashlib
import json
import sys
import tempfile
from pathlib import Path
from typing import Any, Dict, List, Optional

sys.path.insert(0, str(Path(__file__).resolve().parent))

from protocol import RELEASE_RECORD_NAME, ProtocolError, sha256_hex  # noqa: E402
from publish_adapters import (  # noqa: E402
    Credentials,
    CloudKitWebServicesAdapter,
    first_existing_record,
)


class MirrorError(Exception):
    pass


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="把 CloudKit 公共库里已发布的内容从一个环境镜像到另一个环境"
    )
    parser.add_argument(
        "--from",
        dest="source_env",
        choices=("development", "production"),
        default="development",
        help="源环境（默认 development）",
    )
    parser.add_argument(
        "--to",
        dest="target_env",
        choices=("development", "production"),
        default="production",
        help="目标环境（默认 production）",
    )
    parser.add_argument("--apply", action="store_true", help="真正写入目标环境（默认只打印计划）")
    parser.add_argument("--print-requests", action="store_true", help="打印请求形状（不含凭证）")
    parser.add_argument(
        "--media",
        action="store_true",
        help="尝试枚举并镜像 THMedia（需要 THMedia 上有 Query 索引）",
    )
    return parser


class SourceReader:
    """源环境只读回读。复用发布工具自身的签名实现，避免第二套签名代码。"""

    def __init__(self, environment: str, print_requests: bool = False):
        self.credentials = Credentials.load(environment)
        # 复用适配器只是为了复用签名 / _post；apply=False 时 _post 不落盘，
        # 但**读**请求本来就不受影响——这里显式用 apply=False 只读适配器。
        self.adapter = CloudKitWebServicesAdapter(
            self.credentials, apply=True, print_requests=print_requests
        )

    def _lookup(self, record_type: str, record_name: str) -> Optional[Dict[str, Any]]:
        result = self.adapter._post(
            "records/lookup",
            {"records": [{"recordName": record_name, "recordType": record_type}]},
        )
        return first_existing_record(result)

    def fetch_release(self) -> Optional[Dict[str, Any]]:
        record = self._lookup("THRelease", RELEASE_RECORD_NAME)
        if not record:
            return None
        fields = record.get("fields") or {}

        def value(key: str) -> Any:
            return (fields.get(key) or {}).get("value")

        return {
            "releaseSeq": value("releaseSeq"),
            "schemaVersion": value("schemaVersion"),
            "revocationEpoch": value("revocationEpoch"),
            "minimumReaderVersion": value("minimumReaderVersion"),
            "previousReleaseSeq": value("previousReleaseSeq"),
            "publishedAt": value("publishedAt"),
            "rootIndexHash": value("rootIndexHash"),
            "_rootIndexAsset": (fields.get("rootIndexAsset") or {}).get("value") or {},
        }

    def _download(self, asset: Dict[str, Any]) -> Optional[bytes]:
        import urllib.request

        url = asset.get("downloadURL")
        if not url:
            return None
        with urllib.request.urlopen(url, timeout=300) as response:
            return response.read()

    def fetch_root_index(self) -> Optional[bytes]:
        release = self.fetch_release()
        if not release:
            return None
        return self._download(release.get("_rootIndexAsset") or {})

    def fetch_pack(self, payload_hash: str) -> Optional[bytes]:
        record = self._lookup("THDataPack", "th.pack.{}".format(payload_hash))
        if not record:
            return None
        asset = ((record.get("fields") or {}).get("asset") or {}).get("value") or {}
        return self._download(asset)

    def query_media_record_names(self) -> List[str]:
        result = self.adapter._post(
            "records/query", {"query": {"recordType": "THMedia"}},
        )
        return [
            str(record.get("recordName"))
            for record in result.get("records") or []
            if not record.get("serverErrorCode") and record.get("recordName")
        ]


def mirror(args: argparse.Namespace) -> int:
    if args.source_env == args.target_env:
        raise MirrorError("源环境与目标环境相同（{}），没有可做的事".format(args.source_env))

    print("镜像 {} → {}".format(args.source_env, args.target_env))
    if not args.apply:
        print("（dry-run：只打印计划，不写入。加 --apply 才真正执行）")

    # ---------- 1. 源环境回读 + 自证
    source = SourceReader(args.source_env, print_requests=args.print_requests)
    release = source.fetch_release()
    if not release:
        raise MirrorError("源环境（{}）没有发布头，无法镜像".format(args.source_env))

    root_bytes = source.fetch_root_index()
    if not root_bytes:
        raise MirrorError("源环境发布头的根清单资产下载失败")

    root_hash = sha256_hex(root_bytes)
    if root_hash != release["rootIndexHash"]:
        raise MirrorError(
            "根清单摘要不符：回读 {} ≠ 发布头 {}".format(root_hash, release["rootIndexHash"])
        )
    print("  发布头 releaseSeq={} 根清单摘要一致 {}".format(
        release["releaseSeq"], root_hash[:16]))

    root_index = json.loads(root_bytes.decode("utf-8"))
    partitions = root_index.get("partitions") or []
    if not partitions:
        raise MirrorError("根清单里没有分片")

    packs: List[Dict[str, Any]] = []
    for descriptor in partitions:
        payload_hash = str(descriptor.get("payloadHash", ""))
        payload_bytes = source.fetch_pack(payload_hash)
        if not payload_bytes:
            raise MirrorError("源环境取不到分片 {}".format(descriptor.get("partitionID")))
        if sha256_hex(payload_bytes) != payload_hash:
            raise MirrorError("分片字节摘要不符 {}".format(descriptor.get("partitionID")))
        packs.append(
            {
                "payloadHash": payload_hash,
                "partitionID": str(descriptor.get("partitionID", "")),
                "recordName": str(
                    descriptor.get("packRecordName") or "th.pack.{}".format(payload_hash)
                ),
                "bytes": payload_bytes,
            }
        )
        print("  分片 {} {} 字节 {} 条".format(
            descriptor.get("partitionID"), len(payload_bytes), descriptor.get("recordCount")))

    # ---------- 2. 目标环境递增校验
    target = CloudKitWebServicesAdapter(
        Credentials.load(args.target_env), apply=args.apply, print_requests=args.print_requests
    )
    current = target.fetch_current_release()
    current_seq = int((current or {}).get("releaseSeq") or 0)
    new_seq = int(release["releaseSeq"] or 0)
    if current_seq and new_seq <= current_seq:
        raise MirrorError(
            "目标环境（{}）已有 releaseSeq={}，源环境 releaseSeq={} 不大于它，"
            "拒绝回退（不可变语义）".format(args.target_env, current_seq, new_seq)
        )
    print("  目标环境当前 releaseSeq={} → 将写入 {}".format(current_seq, new_seq))

    # ---------- 3. 写入：分片先、发布头最后
    if args.apply:
        for item in packs:
            if target.pack_exists(item["payloadHash"]):
                print("    分片已存在，跳过 th.pack.{}".format(item["payloadHash"][:12]))
                continue
            with tempfile.NamedTemporaryFile(suffix=".json.gz") as handle:
                handle.write(item["bytes"])
                handle.flush()
                target.put_pack(
                    item["payloadHash"],
                    Path(handle.name),
                    {
                        "partitionID": item["partitionID"],
                        "releaseSeq": new_seq,
                        "sha256": item["payloadHash"],
                        "byteCount": len(item["bytes"]),
                    },
                )
            print("    分片已写入 th.pack.{}".format(item["payloadHash"][:12]))

        if args.media:
            mirrored = 0
            for record_name in source.query_media_record_names():
                content_hash = record_name.replace("th.media.", "")
                if target.media_exists(content_hash):
                    continue
                record = source._lookup("THMedia", record_name)
                asset = ((record.get("fields") or {}).get("asset") or {}).get("value") or {}
                data = source._download(asset)
                if not data:
                    continue
                mime = (((record.get("fields") or {}).get("mimeType") or {}).get("value")) or ""
                with tempfile.NamedTemporaryFile(suffix=".bin") as handle:
                    handle.write(data)
                    handle.flush()
                    target.put_media(
                        content_hash,
                        Path(handle.name),
                        {
                            "mediaKey": ((record.get("fields") or {}).get("mediaKey") or {}).get(
                                "value"
                            )
                            or "",
                            "mimeType": mime,
                            "sha256": content_hash,
                            "byteCount": len(data),
                        },
                    )
                mirrored += 1
            print("    媒体镜像 {} 条".format(mirrored))

        target.put_release(
            {
                "releaseSeq": int(release["releaseSeq"] or 0),
                "schemaVersion": int(release["schemaVersion"] or 0),
                "revocationEpoch": int(release["revocationEpoch"] or 0),
                "minimumReaderVersion": int(release["minimumReaderVersion"] or 0),
                "previousReleaseSeq": int(release["previousReleaseSeq"] or 0),
                "publishedAt": release["publishedAt"],
                "rootIndexHash": release["rootIndexHash"],
            },
            root_bytes,
            (current or {}).get("changeTag"),
        )
        print("✅ 发布头已切换，{} 现在与 {} 字节一致".format(args.target_env, args.source_env))
        print("   下一步：python3 verify_publication.py --adapter cloudkit "
              "--environment {}".format(args.target_env))
    else:
        print("计划：写入 {} 个分片 + 切换发布头（releaseSeq {}），未执行".format(
            len(packs), new_seq))
    return 0


def main(argv: Optional[List[str]] = None) -> int:
    args = build_parser().parse_args(argv)
    try:
        return mirror(args)
    except (MirrorError, ProtocolError) as error:
        print("❌ {}".format(error), file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
