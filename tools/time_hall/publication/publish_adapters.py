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

✅ `cloudkit` 适配器已于 2026-09-25 在 Development 真实环境全链路验证通过
   （含资产上传现行协议：assets/upload → 字节上传取 singleFile → singleFile 原样写回）。
   上生产环境前仍建议先 `--print-requests` 核对请求形状。详见 publication/README.md。
"""

from __future__ import annotations

import base64
import hashlib
import json
import os
import shutil
import subprocess
import sys
from pathlib import Path
from typing import Any, Dict, List, Optional

from protocol import ProtocolError, RELEASE_RECORD_NAME, canonical_json_bytes, sha256_hex

KEYCHAIN_SERVICE = "PinkHouseTimeHallPublisher"
CREDENTIAL_ENV_VAR = "PINK_HOUSE_TIMEHALL_CREDENTIAL_FILE"


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
        #
        # ⚠️ 环境隔离（2026-09-25 实测）：CloudKit 的 s2s key 是**按环境注册**的，
        # Development 环境创建的 key 打 Production URL 会直接 HTTP 401
        # （Apple 文档："Tokens are specific to a deployment environment"）。
        # 所以 Production 必须使用独立的 key：Keychain 账户名加 `.production`
        # 后缀（keyID.production / privateKey.production / containerID.production），
        # Development 继续用无后缀账户名。
        suffix = ".production" if environment == "production" else ""
        try:
            key_id = subprocess.check_output(
                ["security", "find-generic-password", "-s", KEYCHAIN_SERVICE, "-a", "keyID" + suffix, "-w"],
                stderr=subprocess.DEVNULL,
            ).decode().strip()
            private_key = subprocess.check_output(
                ["security", "find-generic-password", "-s", KEYCHAIN_SERVICE, "-a", "privateKey" + suffix, "-w"],
                stderr=subprocess.DEVNULL,
            ).decode().strip()
            container_id = subprocess.check_output(
                ["security", "find-generic-password", "-s", KEYCHAIN_SERVICE, "-a", "containerID" + suffix, "-w"],
                stderr=subprocess.DEVNULL,
            ).decode().strip()
        except subprocess.CalledProcessError:
            if suffix:
                raise CredentialError(
                    "未找到 Production 发布凭证。CloudKit s2s key 按环境隔离，"
                    "Development 的 key 打 Production URL 会 401，必须单独创建：\n"
                    "  1. CloudKit Console 顶部环境切到 Production；\n"
                    "  2. API Access → Server-to-Server Keys → 新建 key（或复用同一家公私钥，注册出 Production 的 Key ID）；\n"
                    "  3. 写入 Keychain：\n"
                    "     security add-generic-password -s {service} -a keyID.production      -w <PROD_KEY_ID>\n"
                    "     security add-generic-password -s {service} -a privateKey.production -w <PROD_PEM 文件内容>\n"
                    "     security add-generic-password -s {service} -a containerID.production -w iCloud.bugod2.ItemManager\n"
                    "开发环境可改用环境变量 {env} 指向一个 JSON 凭证文件。".format(
                        service=KEYCHAIN_SERVICE, env=CREDENTIAL_ENV_VAR
                    )
                )
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
            private_key_pem=decode_pem_material(private_key),
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


def cloudkit_subpath(container_id: str, environment: str, path: str) -> str:
    """CloudKit Web Services 请求的 URL subpath（签名第三段）。

    形如 `/database/1/<container>/<environment>/public/records/lookup`，
    即完整 URL 去掉 scheme + host、**不含** query string。
    """
    return "/database/1/{}/{}/public/{}".format(container_id, environment, path)


def first_existing_record(result: Dict[str, Any]) -> Optional[Dict[str, Any]]:
    """从 records/lookup 响应里取第一条**真实存在**的记录。

    坑（2026-09-25 实测）：CloudKit 对不存在的记录**不报 HTTP 错**，而是在
    records 数组里返回 `{"recordName":..., "serverErrorCode":"NOT_FOUND",
    "reason":"Record not found"}` 条目。不过滤的话「记录不存在」会被误判成
    「记录存在」——发布端会跳过该包的上传，校验端会把空字段当发布头解析。
    """
    for record in result.get("records") or []:
        if not record.get("serverErrorCode"):
            return record
    return None


def decode_pem_material(raw: str) -> str:
    """把 Keychain 读回的私钥材料还原为 PEM 文本。

    坑（2026-09-25 实测）：macOS `security add-generic-password -w "$(cat key.pem)"`
    会把多行 PEM 按**二进制 data** 存进钥匙串，`-w` 读回来是整个 PEM 的 **hex 编码
    字符串**，直接喂给 load_pem_private_key 会报 MalformedFraming。
    这里按「原文 PEM → hex → base64」三态识别还原。
    """
    text = raw.strip()
    if text.startswith("-----BEGIN"):
        return text
    for decoder in (bytes.fromhex, lambda s: base64.b64decode(s, validate=True)):
        try:
            decoded = decoder(text).decode("utf-8").strip()
        except Exception:
            continue
        if decoded.startswith("-----BEGIN"):
            return decoded
    return raw


def sign_request(date_string: str, body: bytes, private_key_pem: str, subpath: str) -> str:
    """CloudKit Web Services 的 SignatureV1：ECDSA P-256 / SHA-256。

    签名对象按 Apple 规范是**三段**以冒号连接的 UTF-8 字节：

        [ISO8601 日期]:[base64(SHA-256(请求体))]:[URL subpath]

    ⚠️ 这里是历史上最容易写错的地方（2026-09-25 修正）：
      · 第二段是**请求体摘要的 base64**，不是请求体原文；
      · 第三段 `subpath` **必须**参与签名，漏掉会得到「签名无效」；
      · 日期必须是整秒 ISO8601（`%Y-%m-%dT%H:%M:%SZ`，无小数秒）。
    三段任一不符，Apple 侧只会返回笼统的认证失败，排查代价很高。
    """
    try:
        from cryptography.hazmat.primitives import hashes, serialization  # noqa: WPS433
        from cryptography.hazmat.primitives.asymmetric import ec  # noqa: WPS433
    except ImportError as error:  # pragma: no cover
        raise ProtocolError(
            "cloudkit 适配器需要 cryptography 包：python3 -m pip install cryptography\n"
            "（filesystem 适配器不需要任何第三方依赖，可先用于演练）原始错误：{}".format(error)
        )
    body_digest = base64.b64encode(hashlib.sha256(body).digest()).decode("ascii")
    message = "{}:{}:{}".format(date_string, body_digest, subpath).encode("utf-8")
    key = serialization.load_pem_private_key(private_key_pem.encode("utf-8"), password=None)
    signature = key.sign(message, ec.ECDSA(hashes.SHA256()))
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

    2026-09-25 已在 Development 真实环境全链路验证通过
    （发布 releaseSeq=1 + 读者视角回读均通过）。
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
        return "https://api.apple-cloudkit.com{}".format(self._subpath(path))

    def _subpath(self, path: str) -> str:
        return cloudkit_subpath(
            self.credentials.container_id, self.credentials.environment, path
        )

    def _headers(self, body: bytes, path: str) -> Dict[str, str]:
        import datetime as dt

        date_string = dt.datetime.now(dt.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
        signature = sign_request(
            date_string, body, self.credentials.private_key_pem, self._subpath(path)
        )
        return {
            "Content-Type": "application/json",
            "X-Apple-CloudKit-Request-KeyID": self.credentials.key_id,
            "X-Apple-CloudKit-Request-ISO8601Date": date_string,
            "X-Apple-CloudKit-Request-SignatureV1": signature,
        }

    def _post(self, path: str, payload: Dict[str, Any]) -> Dict[str, Any]:
        body = canonical_json_bytes(payload)
        headers = self._headers(body, path)
        if self.print_requests:
            redacted = dict(headers)
            signature = redacted.get("X-Apple-CloudKit-Request-SignatureV1", "")
            redacted["X-Apple-CloudKit-Request-SignatureV1"] = "<{} 字节签名>".format(len(signature))
            print("    POST {}".format(self._endpoint(path)))
            print("      签名对象 subpath: {}".format(self._subpath(path)))
            for key, value in redacted.items():
                print("      {}: {}".format(key, value))
            print("      body: {}".format(body.decode("utf-8")[:400]))
        if not self.apply:
            return {}
        import time
        import urllib.request

        request = urllib.request.Request(
            self._endpoint(path), data=body, headers=headers, method="POST"
        )
        # 连接层重试（2026-09-25 实测）：到 api.apple-cloudkit.com 的 TLS 握手
        # 会间歇性被重置（SSL UNEXPECTED_EOF / SSL_ERROR_SYSCALL），等几十秒又通。
        # 只重试连接类错误，服务端业务错误（4xx/5xx 带 JSON body）不重试。
        last_error: Optional[Exception] = None
        for attempt, wait in enumerate((0, 5, 15, 30), start=1):
            if wait:
                time.sleep(wait)
            try:
                with urllib.request.urlopen(request, timeout=60) as response:
                    return json.loads(response.read().decode("utf-8"))
            except urllib.error.HTTPError as error:
                # 业务错误不重试，但要把响应体带出来（CloudKit 的 400 在 body 里
                # 写 serverErrorCode / reason，只看状态码无法定位）
                detail = ""
                try:
                    detail = error.read().decode("utf-8", errors="replace")[:400]
                except Exception:  # noqa: BLE001
                    pass
                if error.code == 401:
                    # s2s key 按环境隔离：Development 的 key 打 Production URL 必 401
                    raise ProtocolError(
                        "HTTP 401 Unauthorized：s2s key 没有 {} 环境的访问权。"
                        "CloudKit 的 key 按环境注册，Production 需要在 CloudKit Console "
                        "的 Production 环境下单独创建 key 并写入 Keychain"
                        "（keyID.production / privateKey.production）。"
                        "详见 tools/time_hall/publication/README.md 与 "
                        "docs/TIME_HALL_PRODUCTION_PUBLISH_RUNBOOK.md。{}".format(
                            self.credentials.environment, detail
                        )
                    ) from error
                raise ProtocolError(
                    "HTTP {} {}: {}".format(error.code, error.reason, detail)
                ) from error
            except (urllib.error.URLError, ConnectionError, TimeoutError) as error:
                last_error = error
                if self.print_requests:
                    print("      （连接失败，第 {} 次重试：{}）".format(attempt, error))
        raise last_error if last_error else ProtocolError("网络请求失败")

    def fetch_current_release(self) -> Optional[Dict[str, Any]]:
        result = self._post(
            "records/lookup",
            {"records": [{"recordName": RELEASE_RECORD_NAME, "recordType": "THRelease"}]},
        )
        record = first_existing_record(result)
        if not record:
            return None
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
        return first_existing_record(result) is not None

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
        """CloudKit Web Services 的资产上传是三步（见 `_modify_with_asset`）：

        1. `assets/upload` 申请单次上传地址
        2. 把文件 POST 到该地址，取回 `singleFile` 对象
        3. 再 modify 一次，把字段写成上传响应的 `singleFile` **原样**

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
        asset_field: str = "asset",
    ) -> str:
        """资产写入（2026-09-25 真实环境验证通过），返回最终 changeTag。

        现行协议三步（旧「modify 带 ASSET 占位换 uploadURL」已被 Apple 服务端拒绝）：

          1. POST assets/upload，body = {"tokens":[{"recordType","recordName",
             "fieldName","fileChecksum"(SHA-256 base64),"size"}]}
             → tokens[0].url = 单次上传地址
          2. POST 文件**原始字节**到该地址（octet-stream）
             → 响应 JSON {"singleFile":{"size","fileChecksum","receipt":…}}，
             注意 singleFile.fileChecksum 是**服务器自己算的短值**，不是我们
             提交的 SHA-256，receipt 尾部编码了它
          3. records/modify 写记录，asset 字段 = **整个 singleFile 对象原样**
             （与 cloudkit.js 的 consumeUploadReceipt 行为一致：
             `.then(e => e.singleFile)` 后整包写回字段）

        自拼 {"__type":"ASSET","receipt","fileChecksum","size"} 且 fileChecksum
        用自己的 SHA-256 会报 bad upload receipt (did_not_validate)——2026-09-25
        实测三种形状对比：singleFile 原样 / 加 __type / 服务器值三件套**全部成功**
        （权限修好后），此前失败根源是 fileChecksum 与 receipt 内嵌值不一致。
        取「原样整包」为标准形状，不依赖服务器返回字段集合的稳定性假设。

        `expected_change_tag` 非空时，第 3 步带上它做冲突检测（§9.3）。
        任何一步失败都只留下未引用的资源，不改用户可见版本（§9.1）。
        """
        file_checksum = base64.b64encode(hashlib.sha256(file_bytes).digest()).decode("ascii")

        # ---- 第 1 步：申请单次上传地址
        step1 = self._post(
            "assets/upload",
            {
                "tokens": [
                    {
                        "recordType": record_type,
                        "recordName": record_name,
                        "fieldName": asset_field,
                        "fileChecksum": file_checksum,
                        "size": len(file_bytes),
                    }
                ]
            },
        )
        tokens = step1.get("tokens") or []
        upload_url = (tokens[0] or {}).get("url") if tokens else None
        if not upload_url:
            if not self.apply:
                print("      （dry-run：未实际申请上传地址）")
                return ""
            raise ProtocolError(
                "assets/upload 未返回上传地址：{}".format(
                    json.dumps(step1, ensure_ascii=False)[:300]
                )
            )

        # ---- 第 2 步：上传文件字节，回执在响应里
        single_file = self._upload_file(upload_url, file_bytes, file_name)
        if not self.apply:
            print("      （dry-run：未实际上传文件字节）")
            return ""
        if not single_file:
            raise ProtocolError("资产上传成功但未取得 singleFile：{}".format(file_name))

        # ---- 第 3 步：把上传响应的 singleFile 对象**原样**写进记录字段
        write_fields = dict(fields)
        write_fields[asset_field] = {"value": single_file}
        operation: Dict[str, Any] = {
            "operationType": "forceUpdate",
            "record": {
                "recordType": record_type,
                "recordName": record_name,
                "fields": write_fields,
            },
        }
        if expected_change_tag:
            operation["record"]["recordChangeTag"] = expected_change_tag
        step2 = self._post("records/modify", {"operations": [operation]})
        record = first_existing_record(step2)
        if record is None:
            records = step2.get("records") or []
            if records:
                raise ProtocolError(
                    "资产记录写入失败：{}".format(
                        json.dumps(records[0], ensure_ascii=False)[:300]
                    )
                )
        return str((record or {}).get("recordChangeTag") or "")

    def _upload_file(self, upload_url: str, file_bytes: bytes, file_name: str) -> Dict[str, Any]:
        """把文件字节上传到 assets/upload 返回的地址，返回整个 singleFile 对象。

        2026-09-25 实测：地址接受**原始字节**（Content-Type: application/octet-stream），
        响应 JSON = {"singleFile":{"size","fileChecksum","receipt"}}。
        singleFile.fileChecksum 是服务器自己算的短值（非提交的 SHA-256）；
        第 3 步写记录时必须把整个 singleFile **原样**传回，不能重新拼装。
        """
        if not self.apply:
            return {}
        import time
        import urllib.request

        last_error: Optional[Exception] = None
        body = b""
        for attempt, wait in enumerate((0, 5, 15, 30), start=1):
            if wait:
                time.sleep(wait)
            request = urllib.request.Request(
                upload_url,
                data=file_bytes,
                method="POST",
                headers={"Content-Type": "application/octet-stream"},
            )
            try:
                with urllib.request.urlopen(request, timeout=300) as response:
                    body = response.read()
                break
            except urllib.error.HTTPError as error:
                detail = ""
                try:
                    detail = error.read().decode("utf-8", errors="replace")[:300]
                except Exception:  # noqa: BLE001
                    pass
                raise ProtocolError(
                    "资产上传 HTTP {}：{}".format(error.code, detail)
                ) from error
            except (urllib.error.URLError, ConnectionError, TimeoutError) as error:
                last_error = error
        if last_error is not None:
            raise last_error
        try:
            payload = json.loads(body.decode("utf-8"))
        except (ValueError, UnicodeDecodeError):
            return {}  # 非 JSON 响应体：按原始成功处理（无 singleFile 可提取）
        single = payload.get("singleFile") or {}
        if not single:
            raise ProtocolError(
                "资产上传响应缺少 singleFile：{}".format(json.dumps(payload, ensure_ascii=False)[:300])
            )
        return single

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
            asset_field="rootIndexAsset",
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
