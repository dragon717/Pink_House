#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""以「普通读者视角」回读验证公共库（§8.2 步骤 9 / §20.2）。

与 validate_release.py 的区别：

  * validate_release.py 校验的是**磁盘上的构建产物**，是发布者的自检。
  * verify_publication.py 校验的是**读者实际能拿到的东西**，模拟客户端会走的路径：
        读发布头 → 读根清单 → 按需取分片 → 校验摘要与结构 → 检查撤回与覆盖状态。
    它不读构建产物目录，只看公共库当前对外暴露的状态。

只有它在真实环境通过，才能声称「线上可用」。

用法（演练，目标为 filesystem 适配器写出的目录）：

    python3 verify_publication.py --adapter filesystem --filesystem-root /tmp/th_fs

用法（真实公共库，只读，不写）：

    python3 verify_publication.py --adapter cloudkit --environment development
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
    RELEASE_RECORD_NAME,
    canonical_json_bytes,
    sha256_hex,
    validate_pack_payload,
    validate_partition_descriptor,
    validate_release_references,
    validate_root_index,
)


class VerifyError(Exception):
    pass


# ------------------------------------------------------------------ 读者后端


class PublicReader:
    name = "base"

    def fetch_release(self) -> Optional[Dict[str, Any]]:
        raise NotImplementedError

    def fetch_root_index(self) -> Optional[bytes]:
        raise NotImplementedError

    def fetch_pack(self, payload_hash: str) -> Optional[bytes]:
        raise NotImplementedError

    def fetch_media(self, content_hash: str) -> Optional[bytes]:
        raise NotImplementedError

    def list_pack_hashes(self) -> List[str]:
        return []

    def list_media_hashes(self) -> List[str]:
        return []


class FilesystemReader(PublicReader):
    """读取 filesystem 适配器写出的演练目录。"""

    name = "filesystem"

    def __init__(self, root: Path):
        self.root = root

    def fetch_release(self) -> Optional[Dict[str, Any]]:
        path = self.root / "THRelease.json"
        if not path.exists():
            return None
        return json.loads(path.read_text(encoding="utf-8"))

    def fetch_root_index(self) -> Optional[bytes]:
        path = self.root / "root-index.json"
        return path.read_bytes() if path.exists() else None

    def fetch_pack(self, payload_hash: str) -> Optional[bytes]:
        path = self.root / "THDataPack" / "{}.json.gz".format(payload_hash)
        return path.read_bytes() if path.exists() else None

    def fetch_media(self, content_hash: str) -> Optional[bytes]:
        directory = self.root / "THMedia"
        if not directory.exists():
            return None
        for path in directory.glob("{}.*".format(content_hash)):
            return path.read_bytes()
        return None

    def list_pack_hashes(self) -> List[str]:
        directory = self.root / "THDataPack"
        if not directory.exists():
            return []
        return sorted(
            path.name[: -len(".json.gz")] for path in directory.glob("*.json.gz")
        )

    def list_media_hashes(self) -> List[str]:
        directory = self.root / "THMedia"
        if not directory.exists():
            return []
        return sorted({path.name.split(".")[0] for path in directory.glob("*.*")})


class CloudKitPublicReader(PublicReader):
    """通过 CloudKit Web Services 以读者身份回读。

    ⚠️ 与发布适配器一样，请求构造按 Apple 公开文档实现但**未经真实环境验证**。
    首次运行请配合 `--print-requests` 核对。
    """

    name = "cloudkit"

    def __init__(self, credentials: Any, print_requests: bool = False):
        self.credentials = credentials
        self.print_requests = print_requests

    def _endpoint(self, path: str) -> str:
        return "https://api.apple-cloudkit.com{}".format(self._subpath(path))

    def _subpath(self, path: str) -> str:
        from publish_adapters import cloudkit_subpath

        return cloudkit_subpath(
            self.credentials.container_id, self.credentials.environment, path
        )

    def _post(self, path: str, payload: Dict[str, Any]) -> Dict[str, Any]:
        import urllib.request

        from publish_adapters import sign_request

        body = canonical_json_bytes(payload)
        import datetime as dt

        date_string = dt.datetime.now(dt.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
        headers = {
            "Content-Type": "application/json",
            "X-Apple-CloudKit-Request-KeyID": self.credentials.key_id,
            "X-Apple-CloudKit-Request-ISO8601Date": date_string,
            "X-Apple-CloudKit-Request-SignatureV1": sign_request(
                date_string, body, self.credentials.private_key_pem, self._subpath(path)
            ),
        }
        if self.print_requests:
            print("    POST {} body={}".format(self._endpoint(path), body.decode("utf-8")[:300]))
        request = urllib.request.Request(
            self._endpoint(path), data=body, headers=headers, method="POST"
        )
        with urllib.request.urlopen(request, timeout=60) as response:
            return json.loads(response.read().decode("utf-8"))

    def _lookup(self, record_type: str, record_name: str) -> Optional[Dict[str, Any]]:
        from publish_adapters import first_existing_record

        result = self._post(
            "records/lookup", {"records": [{"recordName": record_name, "recordType": record_type}]}
        )
        # CloudKit 对不存在的记录在 records 数组里返回 serverErrorCode=NOT_FOUND
        # 的条目（不报 HTTP 错），必须过滤，否则空字段条目会被当发布头解析
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
            "revocationEpoch": value("revocationEpoch"),
            "schemaVersion": value("schemaVersion"),
            "minimumReaderVersion": value("minimumReaderVersion"),
            "publishedAt": value("publishedAt"),
            "rootIndexHash": value("rootIndexHash"),
            "changeTag": record.get("recordChangeTag"),
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

    def fetch_media(self, content_hash: str) -> Optional[bytes]:
        record = self._lookup("THMedia", "th.media.{}".format(content_hash))
        if not record:
            return None
        asset = ((record.get("fields") or {}).get("asset") or {}).get("value") or {}
        return self._download(asset)


def make_reader(args: argparse.Namespace) -> PublicReader:
    if args.adapter == "filesystem":
        if args.filesystem_root is None:
            raise VerifyError("filesystem 适配器需要 --filesystem-root")
        return FilesystemReader(args.filesystem_root)
    from publish_adapters import Credentials

    credentials = Credentials.load(args.environment)
    return CloudKitPublicReader(credentials, print_requests=args.print_requests)


# ------------------------------------------------------------------ 验证


def verify(args: argparse.Namespace) -> int:
    try:
        reader = make_reader(args)
    except (VerifyError, Exception) as error:  # noqa: BLE001
        print("❌ {}".format(error), file=sys.stderr)
        return 2

    errors: List[str] = []
    warnings: List[str] = []
    issues: List[Dict[str, str]] = []

    # 1) 发布头
    release = reader.fetch_release()
    if not release:
        print("❌ 公共库中没有发布头（{}）".format(RELEASE_RECORD_NAME), file=sys.stderr)
        return 3
    reader_version = release.get("minimumReaderVersion")
    if not isinstance(reader_version, int):
        errors.append("minimumReaderVersion 缺失或不是整数")
    elif reader_version > READER_VERSION:
        errors.append(
            "minimumReaderVersion={} 高于本读取器协议 {}，读者会被挡住".format(
                reader_version, READER_VERSION
            )
        )
    if release.get("schemaVersion") != PROTOCOL_SCHEMA_VERSION:
        errors.append(
            "发布头 schemaVersion={} 与本读取器支持的 {} 不一致".format(
                release.get("schemaVersion"), PROTOCOL_SCHEMA_VERSION
            )
        )

    # 2) 根清单
    root_bytes = reader.fetch_root_index()
    if root_bytes is None:
        print("❌ 无法获取根清单资产", file=sys.stderr)
        return 3
    declared = str(release.get("rootIndexHash", ""))
    actual = sha256_hex(root_bytes)
    if declared != actual:
        errors.append("根清单摘要不匹配：发布头={} 实际={}".format(declared[:12], actual[:12]))
    try:
        root_index = json.loads(root_bytes.decode("utf-8"))
    except Exception as error:  # noqa: BLE001
        print("❌ 根清单不是合法 JSON：{}".format(error), file=sys.stderr)
        return 3
    if canonical_json_bytes(root_index) != root_bytes:
        errors.append("根清单不是规范化 JSON（重算摘要会漂移）")
    issues += [
        dict(issue, layer="partition") for issue in validate_root_index(root_index, release.get("releaseSeq"))
    ]

    # 3) 逐个分片：读者视角按需取
    partitions: List[Dict[str, Any]] = root_index.get("partitions") or []
    packs: List[Tuple[Dict[str, Any], Dict[str, Any]]] = []
    coverage: Dict[str, int] = {}
    total_records = 0
    for descriptor in partitions:
        pid = str(descriptor.get("partitionID"))
        brand_id = str(descriptor.get("brandID"))
        entity_type = str(descriptor.get("entityType"))
        coverage_status = str(descriptor.get("coverageStatus"))
        coverage[coverage_status] = coverage.get(coverage_status, 0) + 1
        total_records += int(descriptor.get("recordCount", 0))

        # 分片 ID 必须能由 brandID / entityType 推出，防止运维手写漂移
        parts = pid.split("/")
        if len(parts) >= 3 and parts[0] != brand_id:
            errors.append("{} 的品牌前缀与 brandID={} 不一致".format(pid, brand_id))

        payload_hash = str(descriptor.get("payloadHash", ""))
        compressed = reader.fetch_pack(payload_hash)
        if compressed is None:
            errors.append("读者无法获取分片 {}（{}）".format(pid, payload_hash[:12]))
            continue
        if sha256_hex(compressed) != payload_hash:
            errors.append("分片 {} 压缩字节摘要与声明不符".format(pid))
            continue
        if len(compressed) > MAX_PACK_COMPRESSED_BYTES:
            errors.append("分片 {} 压缩后超出上限".format(pid))
        try:
            raw = gzip.decompress(compressed)
        except Exception as error:  # noqa: BLE001
            errors.append("分片 {} 不是合法 gzip：{}".format(pid, error))
            continue
        if len(raw) > MAX_PACK_UNCOMPRESSED_BYTES:
            errors.append("分片 {} 解压后超出上限".format(pid))
        try:
            payload = json.loads(raw.decode("utf-8"))
        except Exception as error:  # noqa: BLE001
            errors.append("分片 {} 解压后不是合法 JSON：{}".format(pid, error))
            continue

        issues += [
            dict(issue, layer="partition")
            for issue in validate_partition_descriptor(descriptor, payload, len(compressed), len(raw))
        ]
        issues += [
            dict(issue, layer="structural")
            for issue in validate_pack_payload(
                payload, brand_id, entity_type, coverage_status
            )
        ]
        packs.append((descriptor, payload))

    # 4) 跨包引用闭合
    issues += [
        dict(issue, layer="structural") for issue in validate_release_references(packs)
    ]

    # 5) 撤回只增不减（读者必须能读到最新撤回清单）
    withdrawals = root_index.get("withdrawals") or []
    rev_epoch = release.get("revocationEpoch")
    if not isinstance(rev_epoch, int):
        errors.append("发布头 revocationEpoch 缺失或不是整数")
    seen_withdrawal_ids: set = set()
    for item in withdrawals:
        entity_id = str(item.get("entityID", ""))
        if entity_id in seen_withdrawal_ids:
            errors.append("撤回清单存在重复 entityID：{}".format(entity_id))
        seen_withdrawal_ids.add(entity_id)

    # 6) 摘要匹配只说明字节一致，不证明来源合法。这里如实提示，不伪装成权限校验。
    warnings.append(
        "本次回读只证明「读者可获取且字节一致」，不等价于来源授权与操作权限校验，"
        "授权状态请查 audit/release-manifest.json（§9.3）"
    )
    if release.get("localFixture"):
        warnings.append("该发布头标记为 localFixture，说明它来自本地演练，不应视为正式上线")

    # 7) 孤儿资源：读者能看到但发布头没引用的资源
    referenced = {"{}".format(item["payloadHash"]) for item in partitions}
    orphans = sorted(set(reader.list_pack_hashes()) - referenced)

    print("公共库回读（{}）".format(reader.name))
    print("  releaseSeq        {}".format(release.get("releaseSeq")))
    print("  revocationEpoch   {}".format(release.get("revocationEpoch")))
    print("  分片              {}（取到 {}）".format(len(partitions), len(packs)))
    print("  条目              {}".format(total_records))
    print("  根清单摘要        {}".format("一致" if declared == actual else "不一致"))
    print("  覆盖状态分布      {}".format(coverage))
    print("  撤回条目          {}".format(len(withdrawals)))
    if orphans:
        print("  ⚠️ 未被引用的数据包 {} 个（读者可取但未被发布头引用，可安全清理）".format(len(orphans)))

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
        for line in errors[:60]:
            print("   {}".format(line), file=sys.stderr)

    if issues or errors:
        return 3
    print("\n✅ 读者视角回读通过：发布头、根清单、全部分片均可获取且自洽。")
    return 0


def parse_args(argv: Optional[List[str]] = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="以读者视角回读验证公共库")
    parser.add_argument(
        "--adapter",
        choices=("filesystem", "cloudkit"),
        default="filesystem",
        help="读者后端。默认 filesystem（演练目录）",
    )
    parser.add_argument(
        "--environment", choices=("development", "production"), default="development"
    )
    parser.add_argument("--filesystem-root", type=Path, help="filesystem 演练目录")
    parser.add_argument("--print-requests", action="store_true", help="打印请求体（脱敏）")
    return parser.parse_args(argv)


def main(argv: Optional[List[str]] = None) -> int:
    return verify(parse_args(argv))


if __name__ == "__main__":
    raise SystemExit(main())
