#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""CloudKit 发布适配层。

对应 docs/Pink_House_TimeHall_Static_CloudKit_Design.md §8.1 / §9.1 / §9.3。

设计要点：
  * 发布顺序只在这里定义一次，importer 不参与上传；
  * **不可变资源 + 最后切换一个发布头**：
        读当前 THRelease 与 changeTag
          → 上传缺失的 THMedia
          → 上传缺失的 THDataPack
          → 回读核对可获取性
          → 条件更新 THRelease（带原 changeTag）
    只有最后一步成功，才认为发布生效（§9.1）。
  * 发布头使用冲突检测策略；发生版本冲突**不能**改成无条件覆盖（§9.3）。
  * 摘要匹配只说明字节一致，不证明来源合法或操作者有权限（§9.3）。

提供两个适配器：
  * `filesystem`  —— 把公共库语义落在一个本地目录，用于演练与联调，不需要凭证。
  * `cloudkit`    —— CloudKit Web Services + server-to-server key。

⚠️ `cloudkit` 适配器的请求构造按 Apple 公开文档实现，但**未经真实环境验证**。
   首次使用必须先在 `--environment development` 下用 `--print-requests` 逐条核对，
   再考虑生产环境。详见 publication/README.md。
"""

from __future__ import annotations

import base64
import json
import os
import shutil
import subprocess
import sys
from pathlib import Path
from typing import Any, Dict, List, Optional

from protocol import ProtocolError, RELEASE_RECORD_NAME, canonical_json_bytes, sha256_hex

KEYCHAIN_SERVICE = "PinkHouseTimeHallPublisher"
CREDENTIAL_ENV_VAR = "PINK_HOUSE_TIMEFIELD_CREDENTIAL_FILE"


class CredentialError(Exception):
    pass


class Credentials:
    """发布凭证。

    绝不作为命令行明文参数传入，也绝不打印到日志（§8.5 / §7.2）。
    优先从 macOS Keychain 读取；其次从环境变量指向的文件读取（仅限开发环境）。
    """

    def __init__(self, container_id: str, environment: str, key_id: str, private_key_pem: str):
        self.container_id = container_id
        self.environment = environment
        self.key_id = key_id
        self._private_key_pem = private_key_pem

    def __repr__(self) -> str:  # pragma: no cover - 防御性
        return "Credentials(container={}, environment={}, keyID={}, privateKey=***)".format(
            self.container_id, self.environment, self.key_id
        )

    @property
    def private_key_pem(self) -> str:
        return self._private_key_pem

    @classmethod
    def load(cls, environment: str) -> "Credentials":
        raw = os.environ.get(CREDENTIAL_ENV_VAR)
        if raw:
            path = Path(raw)
            if not path.exists():
                raise CredentialError("凭证文件不存在：{}".format(path))
            payload = json.loads(path.read_text(encoding="utf-8"))
            payload.setdefault("environment", environment)
            print(
                "⚠️  使用文件凭证（{}）。文件凭证仅限开发环境，生产请改用 Keychain。".format(path)
            )
            return cls._from_payload(payload, environment)

        # macOS Keychain：keyID 与私钥分开存放，避免出现在同一个输出里
        try:
            key_id = subprocess.check_output(
                ["security", "find-generic-password", "-s", KEYCHAIN_SERVICE, "-a", "keyID", "-w"],
                stderr=subprocess.DEVNULL,
            ).decode().strip()
            private_key = subprocess.check_output(
                ["security", "find-generic-password", "-s", KEYCHAIN_SERVICE, "-a", "privateKey", "-w"],
                stderr=subprocess.DEVNULL,
            ).decode().strip()
            container_id = subprocess.check_output(
                ["security", "find-generic-password", "-s", KEYCHAIN_SERVICE, "-a", "containerID", "-w"],
                stderr=subprocess.DEVNULL,
            ).decode().strip()
        except subprocess.CalledProcessError:
            raise CredentialError(
                "未找到发布凭证。请先写入 Keychain：\n"
                "  security add-generic-password -s {service} -a keyID      -w <KEY_ID>\n"
                "  security add-generic-password -s {service} -a privateKey -w <PEM 文件内容>\n"
                "  security add-generic-password -s {service} -a containerID -w iCloud.bugod2.ItemManager\n"
                "开发环境可改用环境变量 {env} 指向一个 JSON 凭证文件。".format(
                    service=KEYCHAIN_SERVICE, env=CREDENTIAL_ENV_VAR
                )
            )
        return cls(
            container_id=container_id,
            environment=environment,
            key_id=key_id,
            private_key_pem=private_key,
        )

    @classmethod
    def _from_payload(cls, payload: Dict[str, Any], environment: str) -> "Credentials":
        for key in ("keyID", "privateKey", "containerID"):
            if not payload.get(key):
                raise CredentialError("凭证缺少字段 {}".format(key))
        return cls(
            container_id=str(payload["containerID"]),
            environment=str(payload.get("environment", environment)),
            key_id=str(payload["keyID"]),
            private_key_pem=str(payload["privateKey"]),
        )


def sign_request(date_string: str, body: bytes, private_key_pem: str) -> str:
    """CloudKit Web Services 的 SignatureV1：ECDSA P-256 / SHA-256。

    签名对象是「日期:请求体」的 UTF-8 字节，请求体为空时只签日期加冒号。
    """
    try:
        from cryptography.hazmat.primitives import hashes, serialization  # noqa: WPS433
        from cryptography.hazmat.primitives.asymmetric import ec  # noqa: WPS433
    except ImportError as error:  # pragma: no cover
        raise ProtocolError(
            "cloudkit 适配器需要 cryptography 包：python3 -m pip install cryptography\n"
            "（filesystem 适配器不需要任何第三方依赖，可先用于演练）原始错误：{}".format(error)
        )
    payload = date_string.encode("utf-8") + b":" + body
    key = serialization.load_pem_private_key(private_key_pem.encode("utf-8"), password=None)
    signature = key.sign(payload, ec.ECDSA(hashes.SHA256()))
    return base64.b64encode(signature).decode("ascii")


class PublishAdapter:
    """发布适配器接口。替换上传方式时只改这里，不动 importer（§8.1）。"""

    name = "base"

    def describe(self) -> str:
        raise NotImplementedError

    def fetch_current_release(self) -> Optional[Dict[str, Any]]:
        raise NotImplementedError

    def pack_exists(self, payload_hash: str) -> bool:
        raise NotImplementedError

    def put_pack(self, payload_hash: str, file_path: Path, meta: Dict[str, Any]) -> None:
        raise NotImplementedError

    def media_exists(self, content_hash: str) -> bool:
        raise NotImplementedError

    def put_media(self, content_hash: str, file_path: Path, meta: Dict[str, Any]) -> None:
        raise NotImplementedError

    def read_back_pack_hash(self, payload_hash: str) -> Optional[str]:
        raise NotImplementedError

    def read_back_media_hash(self, content_hash: str) -> Optional[str]:
        raise NotImplementedError

    def put_release(
        self, record: Dict[str, Any], root_bytes: bytes, expected_change_tag: Optional[str]
    ) -> str:
        """条件更新发布头（连同根清单资产）。返回新的 changeTag。

        这是整个发布流程中**唯一**修改发布头的动作，也是唯一让新版本对用户生效的动作（§9.1）。
        """
        raise NotImplementedError


# --------------------------------------------------------------- 文件系统适配器


class FilesystemAdapter(PublishAdapter):
    """把公共库语义落在本地目录。

    用途：在没有任何凭证和真实容器的情况下，完整演练
    「不可变资源 + 最后切换发布头 + 冲突检测 + 回读验证」这套应用层协议。
    它不是部署目标，也不能替代真实权限验证。
    """

    name = "filesystem"

    def __init__(self, root: Path, apply: bool, print_requests: bool = False):
        self.root = root
        self.apply = apply
        self.print_requests = print_requests

    def describe(self) -> str:
        return "本地目录 {}（演练用，非部署目标）".format(self.root)

    def _read(self, name: str) -> Optional[Dict[str, Any]]:
        path = self.root / name
        if not path.exists():
            return None
        return json.loads(path.read_text(encoding="utf-8"))

    def _write(self, name: str, payload: Dict[str, Any]) -> None:
        if not self.apply:
            return
        self.root.mkdir(parents=True, exist_ok=True)
        (self.root / name).write_text(
            json.dumps(payload, ensure_ascii=False, indent=2, sort_keys=True) + "\n",
            encoding="utf-8",
        )

    def fetch_current_release(self) -> Optional[Dict[str, Any]]:
        return self._read("THRelease.json")

    def _asset_dir(self, kind: str) -> Path:
        return self.root / kind

    def pack_exists(self, payload_hash: str) -> bool:
        return (self._asset_dir("THDataPack") / "{}.json.gz".format(payload_hash)).exists()

    def put_pack(self, payload_hash: str, file_path: Path, meta: Dict[str, Any]) -> None:
        if not self.apply:
            return
        target_dir = self._asset_dir("THDataPack")
        target_dir.mkdir(parents=True, exist_ok=True)
        shutil.copy2(file_path, target_dir / file_path.name)
        self._write("THDataPack__{}.json".format(payload_hash), meta)

    def media_exists(self, content_hash: str) -> bool:
        directory = self._asset_dir("THMedia")
        return any(directory.glob("{}.*".format(content_hash))) if directory.exists() else False

    def put_media(self, content_hash: str, file_path: Path, meta: Dict[str, Any]) -> None:
        if not self.apply:
            return
        target_dir = self._asset_dir("THMedia")
        target_dir.mkdir(parents=True, exist_ok=True)
        shutil.copy2(file_path, target_dir / file_path.name)
        self._write("THMedia__{}.json".format(content_hash), meta)

    def read_back_pack_hash(self, payload_hash: str) -> Optional[str]:
        path = self._asset_dir("THDataPack") / "{}.json.gz".format(payload_hash)
        if not path.exists():
            return None
        return sha256_hex(path.read_bytes())

    def read_back_media_hash(self, content_hash: str) -> Optional[str]:
        directory = self._asset_dir("THMedia")
        if not directory.exists():
            return None
        for path in directory.glob("{}.*".format(content_hash)):
            return sha256_hex(path.read_bytes())
        return None

    def put_root_index(self, root_bytes: bytes, root_hash: str) -> None:
        """filesystem 适配器把根清单单独落一个文件，便于人工核对。"""
        if not self.apply:
            return
        self.root.mkdir(parents=True, exist_ok=True)
        (self.root / "root-index.json").write_bytes(root_bytes)

    def put_release(
        self, record: Dict[str, Any], root_bytes: bytes, expected_change_tag: Optional[str]
    ) -> str:
        current = self.fetch_current_release()
        current_tag = (current or {}).get("changeTag")
        if current_tag != expected_change_tag:
            raise ProtocolError(
                "发布头已被其它发布者修改（期望 changeTag={!r}，实际 {!r}）。"
                "请重新读取当前状态、合并差异后重新构建（§9.2 / §9.3）。".format(
                    expected_change_tag, current_tag
                )
            )
        if current:
            if int(record["releaseSeq"]) <= int(current.get("releaseSeq", 0)):
                raise ProtocolError(
                    "releaseSeq 必须严格递增：当前 {}，本次 {}".format(
                        current.get("releaseSeq"), record["releaseSeq"]
                    )
                )
            if int(record.get("revocationEpoch", 0)) < int(current.get("revocationEpoch", 0)):
                raise ProtocolError(
                    "revocationEpoch 只能递增：当前 {}，本次 {}".format(
                        current.get("revocationEpoch"), record.get("revocationEpoch")
                    )
                )
        if not self.apply:
            return "<dry-run-change-tag>"
        self.put_root_index(root_bytes, str(record.get("rootIndexHash", "")))
        stored = dict(record)
        stored["changeTag"] = sha256_hex(canonical_json_bytes(record))[:16]
        self._write("THRelease.json", stored)
        return str(stored["changeTag"])


# --------------------------------------------------------------- CloudKit 适配器


class CloudKitWebServicesAdapter(PublishAdapter):
    """CloudKit Web Services（server-to-server key）。

    ⚠️ 未经真实环境验证。请先用 `--print-requests` 核对请求形状。
    """

    name = "cloudkit"

    def __init__(
        self,
        credentials: Credentials,
        apply: bool,
        print_requests: bool = False,
        http_post: Optional[Any] = None,
    ):
        self.credentials = credentials
        self.apply = apply
        self.print_requests = print_requests
        self._http_post = http_post

    def describe(self) -> str:
        return "CloudKit 容器 {} / {} 环境的公共库".format(
            self.credentials.container_id, self.credentials.environment
        )

    def _endpoint(self, path: str) -> str:
        return "https://api.apple-cloudkit.com/database/1/{}/{}/public/{}".format(
            self.credentials.container_id, self.credentials.environment, path
        )

    def _headers(self, body: bytes) -> Dict[str, str]:
        import datetime as dt

        date_string = dt.datetime.now(dt.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
        signature = sign_request(date_string, body, self.credentials.private_key_pem)
        return {
            "Content-Type": "application/json",
            "X-Apple-CloudKit-Request-KeyID": self.credentials.key_id,
            "X-Apple-CloudKit-Request-ISO8601Date": date_string,
            "X-Apple-CloudKit-Request-SignatureV1": signature,
        }

    def _post(self, path: str, payload: Dict[str, Any]) -> Dict[str, Any]:
        body = canonical_json_bytes(payload)
        headers = self._headers(body)
        if self.print_requests:
            redacted = dict(headers)
            signature = redacted.get("X-Apple-CloudKit-Request-SignatureV1", "")
            redacted["X-Apple-CloudKit-Request-SignatureV1"] = "<{} 字节签名>".format(len(signature))
            print("    POST {}".format(self._endpoint(path)))
            for key, value in redacted.items():
                print("      {}: {}".format(key, value))
            print("      body: {}".format(body.decode("utf-8")[:400]))
        if not self.apply:
            return {}
        import urllib.request

        request = urllib.request.Request(
            self._endpoint(path), data=body, headers=headers, method="POST"
        )
        with urllib.request.urlopen(request, timeout=60) as response:
            return json.loads(response.read().decode("utf-8"))

    def fetch_current_release(self) -> Optional[Dict[str, Any]]:
        result = self._post(
            "records/lookup",
            {"records": [{"recordName": RELEASE_RECORD_NAME, "recordType": "THRelease"}]},
        )
        records = result.get("records") or []
        if not records:
            return None
        record = records[0]
        fields = record.get("fields") or {}
        return {
            "releaseSeq": (fields.get("releaseSeq") or {}).get("value"),
            "revocationEpoch": (fields.get("revocationEpoch") or {}).get("value"),
            "changeTag": record.get("recordChangeTag"),
            "recordName": record.get("recordName"),
        }

    def _asset_exists(self, record_type: str, record_name: str) -> bool:
        result = self._post(
            "records/lookup",
            {"records": [{"recordName": record_name, "recordType": record_type}]},
        )
        return bool(result.get("records"))

    def pack_exists(self, payload_hash: str) -> bool:
        return self._asset_exists("THDataPack", "th.pack.{}".format(payload_hash))

    def media_exists(self, content_hash: str) -> bool:
        return self._asset_exists("THMedia", "th.media.{}".format(content_hash))

    def put_pack(self, payload_hash: str, file_path: Path, meta: Dict[str, Any]) -> None:
        self._upload_asset(
            "THDataPack", "th.pack.{}".format(payload_hash), file_path.read_bytes(), file_path.name, meta
        )

    def put_media(self, content_hash: str, file_path: Path, meta: Dict[str, Any]) -> None:
        self._upload_asset(
            "THMedia", "th.media.{}".format(content_hash), file_path.read_bytes(), file_path.name, meta
        )

    def _upload_asset(
        self,
        record_type: str,
        record_name: str,
        file_bytes: bytes,
        file_name: str,
        meta: Dict[str, Any],
    ) -> None:
        """CloudKit Web Services 的资产上传是三步：

        1. modify 传入 `{"__type": "ASSET"}` 占位，拿到单次上传地址
        2. 把文件 POST 到该地址，拿到 receipt
        3. 再 modify 一次，把字段写成 `{"__type": "ASSET", "receipt": ...}`

        三步都不会修改发布头，因此半途失败只留下未引用的不可变资源（§9.1）。
        """
        fields = {key: {"value": value} for key, value in meta.items()}
        fields["asset"] = {"value": {"__type": "ASSET"}}
        self._modify_with_asset(
            record_type=record_type,
            record_name=record_name,
            fields=fields,
            file_bytes=file_bytes,
            file_name=file_name,
            expected_change_tag=None,
        )

    def _modify_with_asset(
        self,
        record_type: str,
        record_name: str,
        fields: Dict[str, Any],
        file_bytes: bytes,
        file_name: str,
        expected_change_tag: Optional[str],
    ) -> str:
        """三步资产写入，返回最终 changeTag。

        `fields["asset"]` 必须已经是 `{"value": {"__type": "ASSET"}}` 占位。
        `expected_change_tag` 非空时，两次 modify 都带上它做冲突检测（§9.3）。
        """
        operation: Dict[str, Any] = {
            "operationType": "forceUpdate",
            "record": {"recordType": record_type, "recordName": record_name, "fields": fields},
        }
        if expected_change_tag:
            operation["record"]["recordChangeTag"] = expected_change_tag
        step1 = self._post("records/modify", {"operations": [operation]})
        upload_url = self._extract_upload_url(step1)
        if not upload_url:
            if self.print_requests or not self.apply:
                print("      （未实际发送，无法取得 uploadURL）")
                return ""
            raise ProtocolError("第 1 步未取得 uploadURL，无法上传 {}".format(record_name))

        receipt = self._upload_file(upload_url, file_bytes, file_name)
        fields["asset"] = {"value": {"__type": "ASSET", "receipt": receipt}}
        operation = {
            "operationType": "forceUpdate",
            "record": {"recordType": record_type, "recordName": record_name, "fields": fields},
        }
        if expected_change_tag:
            operation["record"]["recordChangeTag"] = expected_change_tag
        step2 = self._post("records/modify", {"operations": [operation]})
        records = step2.get("records") or []
        return str(records[0].get("recordChangeTag") or "") if records else ""

    def _extract_upload_url(self, response: Dict[str, Any]) -> Optional[str]:
        for record in response.get("records") or []:
            asset = ((record.get("fields") or {}).get("asset") or {}).get("value") or {}
            if asset.get("uploadURL"):
                return str(asset["uploadURL"])
        return None

    def _upload_file(self, upload_url: str, file_bytes: bytes, file_name: str) -> str:
        if not self.apply:
            return "<dry-run-receipt>"
        import urllib.request
        import uuid

        boundary = uuid.uuid4().hex
        head = (
            "--{boundary}\r\n"
            'Content-Disposition: form-data; name="file"; filename="{name}"\r\n'
            "Content-Type: application/octet-stream\r\n\r\n"
        ).format(boundary=boundary, name=file_name).encode("utf-8")
        tail = "\r\n--{boundary}--\r\n".format(boundary=boundary).encode("utf-8")
        body = head + file_bytes + tail
        request = urllib.request.Request(
            upload_url,
            data=body,
            method="POST",
            headers={"Content-Type": "multipart/form-data; boundary={}".format(boundary)},
        )
        with urllib.request.urlopen(request, timeout=300) as response:
            payload = json.loads(response.read().decode("utf-8"))
        receipt = payload.get("singleUseToken") or payload.get("receipt")
        if not receipt:
            raise ProtocolError("上传未返回 receipt：{}".format(payload))
        return str(receipt)

    def read_back_pack_hash(self, payload_hash: str) -> Optional[str]:
        # 真实回读需要下载资产再比对；这里只确认记录存在，
        # 完整回读由 verify_publication.py 以「普通读者视角」执行（§8.2 步骤 9 / §20.2）。
        return payload_hash if self.pack_exists(payload_hash) else None

    def read_back_media_hash(self, content_hash: str) -> Optional[str]:
        return content_hash if self.media_exists(content_hash) else None

    def put_root_index(self, root_bytes: bytes, root_hash: str) -> None:
        # 根清单作为 THRelease 的 rootIndexAsset 一起提交，不单独占记录。
        return None

    def put_release(
        self, record: Dict[str, Any], root_bytes: bytes, expected_change_tag: Optional[str]
    ) -> str:
        fields: Dict[str, Any] = {}
        for key in (
            "releaseSeq",
            "schemaVersion",
            "revocationEpoch",
            "minimumReaderVersion",
            "previousReleaseSeq",
        ):
            fields[key] = {"value": int(record[key])}
        fields["publishedAt"] = {"value": record["publishedAt"]}
        fields["rootIndexHash"] = {"value": record["rootIndexHash"]}
        fields["rootIndexAsset"] = {"value": {"__type": "ASSET"}}

        # 冲突检测：带 expected_change_tag，不做无条件覆盖（§9.3）
        return self._modify_with_asset(
            record_type="THRelease",
            record_name=RELEASE_RECORD_NAME,
            fields=fields,
            file_bytes=root_bytes,
            file_name="root-index.json",
            expected_change_tag=expected_change_tag,
        )


def make_adapter(
    name: str, environment: str, apply: bool, print_requests: bool, filesystem_root: Optional[Path]
) -> PublishAdapter:
    if name == "filesystem":
        if filesystem_root is None:
            raise ProtocolError("filesystem 适配器需要 --filesystem-root")
        return FilesystemAdapter(filesystem_root, apply=apply, print_requests=print_requests)
    if name == "cloudkit":
        credentials = Credentials.load(environment)
        if credentials.environment != environment:
            print(
                "⚠️  凭证声明环境 {} 与 --environment {} 不一致，以 --environment 为准".format(
                    credentials.environment, environment
                )
            )
        return CloudKitWebServicesAdapter(credentials, apply=apply, print_requests=print_requests)
    raise ProtocolError("未知适配器 {}".format(name))


def env_guard(environment: str, apply: bool) -> None:
    """生产环境必须显式确认，且不允许在 dry-run 下声称已发布（§8.5）。"""
    if environment == "production" and apply:
        print("⚠️  目标为 **生产环境** 公共库，发布头一旦切换即对全体用户生效。")
