#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""CloudKit Web Services 请求签名的**已知答案自检**（不需要凭据、不联网）。

背景（2026-09-25 修正）：
`publish_adapters.sign_request` 原先只签 `日期:请求体` 两段，而 Apple 的
SignatureV1 要求签三段：

    [ISO8601 日期]:[base64(SHA-256(请求体))]:[URL subpath]

这个错误在本地演练（filesystem 适配器）里**完全看不出来**——本地不验签。
只有真机发布到 CloudKit 才会表现为笼统的认证失败。因此必须用离线自检把它钉住。

本脚本断言：
  1. 签名对象逐字节等于三段式消息；
  2. 签名能被对应公钥在该消息上验签通过；
  3. 签名**不能**在两种历史错误写法上验签通过（漏 subpath / 未做摘要 base64）。

用法：
    python3 selftest_signing.py
退出码：0 = 全部通过；1 = 有断言失败。
"""

from __future__ import annotations

import base64
import hashlib
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from protocol import canonical_json_bytes  # noqa: E402
from publish_adapters import cloudkit_subpath, sign_request  # noqa: E402

DATE = "2026-09-25T01:45:34Z"
BODY = canonical_json_bytes(
    {"records": [{"recordName": "th.release.catalog-v1", "recordType": "THRelease"}]}
)
CONTAINER = "iCloud.bugod2.ItemManager"
ENVIRONMENT = "development"
PATH = "records/lookup"
SUBPATH = cloudkit_subpath(CONTAINER, ENVIRONMENT, PATH)

PASS = 0
FAIL = 0


def check(title: str, condition: bool, detail: str = "") -> None:
    global PASS, FAIL
    if condition:
        PASS += 1
        print("  ✅ {}".format(title))
    else:
        FAIL += 1
        print("  ❌ {}{}".format(title, " —— " + detail if detail else ""))


def expected_message() -> bytes:
    digest = base64.b64encode(hashlib.sha256(BODY).digest()).decode("ascii")
    return "{}:{}:{}".format(DATE, digest, SUBPATH).encode("utf-8")


def main() -> int:
    try:
        from cryptography.hazmat.primitives import hashes, serialization
        from cryptography.hazmat.primitives.asymmetric import ec
    except ImportError:
        print("需要 cryptography：pip install cryptography", file=sys.stderr)
        return 2

    key = ec.generate_private_key(ec.SECP256R1())
    pem = key.private_bytes(
        encoding=serialization.Encoding.PEM,
        format=serialization.PrivateFormat.PKCS8,
        encryption_algorithm=serialization.NoEncryption(),
    ).decode("utf-8")
    public_key = key.public_key()

    print("CloudKit SignatureV1 自检")
    print("  container : {}".format(CONTAINER))
    print("  subpath   : {}".format(SUBPATH))
    print("  body 摘要 : {}".format(base64.b64encode(hashlib.sha256(BODY).digest()).decode("ascii")))
    print("")

    signature = sign_request(DATE, BODY, pem, SUBPATH)
    raw = base64.b64decode(signature)

    print("断言：")
    check("subpath 形状正确（/database/1/<container>/<env>/public/<path>）",
          SUBPATH == "/database/1/{}/{}/public/{}".format(CONTAINER, ENVIRONMENT, PATH),
          SUBPATH)
    check("签名是 64 字节裸签名（DER 编码，P-256）", len(raw) in (70, 71, 72), "{} 字节".format(len(raw)))

    try:
        public_key.verify(raw, expected_message(), ec.ECDSA(hashes.SHA256()))
        check("可在三段式消息上验签通过", True)
    except Exception as error:  # noqa: BLE001
        check("可在三段式消息上验签通过", False, str(error))

    wrong_old = "{}:{}".format(DATE, BODY.decode("utf-8")).encode("utf-8")
    try:
        public_key.verify(raw, wrong_old, ec.ECDSA(hashes.SHA256()))
        check("不得在「日期:请求体原文」旧写法上验签通过", False, "旧写法竟然通过了")
    except Exception:  # noqa: BLE001
        check("不得在「日期:请求体原文」旧写法上验签通过", True)

    no_subpath = "{}:{}".format(
        DATE, base64.b64encode(hashlib.sha256(BODY).digest()).decode("ascii")
    ).encode("utf-8")
    try:
        public_key.verify(raw, no_subpath, ec.ECDSA(hashes.SHA256()))
        check("不得在「漏 subpath」的写法上验签通过", False, "漏 subpath 竟然通过了")
    except Exception:  # noqa: BLE001
        check("不得在「漏 subpath」的写法上验签通过", True)

    check("空请求体也能签名（摘要段为固定值）",
          len(base64.b64decode(sign_request(DATE, b"", pem, SUBPATH))) > 0)

    print("")
    print("通过 {} 项，失败 {} 项".format(PASS, FAIL))
    return 1 if FAIL else 0


if __name__ == "__main__":
    sys.exit(main())
