#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""CloudKit 适配器「读」的**离线回归锁**（不需要凭证、不联网、不需要 cryptography）。

背景（2026-09-27 实测，一次典型的「失败伪装成正常」）：

`CloudKitWebServicesAdapter` 早先把「dry-run 一律不发请求」一刀切地实现在
**传输层**（`_post` 开头 `if not self.apply: return {}`）。可 CloudKit 连
`records/lookup` 这种**读**操作用的也是 POST 动词，于是读被一起挡掉了。后果：

    桥接器的 `--mode baseline`（R07 只读基线核对）恒为 `apply=False`
    → `fetch_current_release()` 恒返回 None
    → App 被告知「线上尚无商店发布头（本次将是首次发布）」

而线上可能已经发过好几个版本。更糟的是**离线抓不到**：
`FilesystemAdapter` 的读不走 `apply` 判定，而 CloudKit 的问题是「读也用 POST 动词」，
两者不在同一条路径上 —— 当时那份离线演练脚本（已于 2026-09-29 连同
`drill_bridge_offline.py` 一起移除）同样是全绿。

本脚本把修好后的**不变量**钉死（双向断言，正反都测）：

  1. `apply=False` 时 `fetch_current_release()` **必须真的发出** lookup 请求，
     并能把发布头解析出来；
  2. `apply=False` 时**写**操作（`put_release` / `put_pack` / `put_media`）请求数必须为 0
     —— 闸门只关写，不能顺手把读也关了，也不能把写漏出去；
  3. 线上**确实没有**发布头时，`fetch_current_release()` 返回 None，
     但请求数必须 ≥ 1（**问过了才知道没有**，这条专门防「没读伪装成没有」回潮）；
  4. 反向断言：把 `_post`（写路径）换成必然抛异常的桩，`fetch_current_release()`
     仍然能正常工作 —— 证明「读走 `_send`、写走 `_post`」没有退化成共用一条路；
  5. 桥接器入口 `ops_publish_bridge.read_head()` 同样必须真发请求
     （App 走的就是这个入口，适配器层修好了不等于入口层也修好了）。

用法：
    python3 selftest_cloudkit_read.py
退出码：0 = 全部通过；1 = 有断言失败。
"""

from __future__ import annotations

import sys
from pathlib import Path
from typing import Any, Dict, List, Tuple

sys.path.insert(0, str(Path(__file__).resolve().parent))

import ops_publish_bridge  # noqa: E402
from protocol import RELEASE_RECORD_NAME  # noqa: E402
from publish_adapters import CloudKitWebServicesAdapter, Credentials  # noqa: E402

PASS = 0
FAIL = 0
DETAILS: List[str] = []

CONTAINER = "iCloud.bugod2.ItemManager"
ENVIRONMENT = "development"

# 一份形状正确的 records/lookup 响应（字段形状照抄真实响应：{key: {"value": ...}}）
HEAD_RESPONSE: Dict[str, Any] = {
    "records": [
        {
            "recordName": RELEASE_RECORD_NAME,
            "recordType": "THRelease",
            "recordChangeTag": "TAG-42",
            "fields": {
                "releaseSeq": {"value": 7},
                "revocationEpoch": {"value": 2},
                "rootIndexHash": {"value": "hash-of-root-index"},
            },
        }
    ]
}

# 记录不存在时 CloudKit **不报 HTTP 错**，而是在 records 里塞一条 serverErrorCode
NOT_FOUND_RESPONSE: Dict[str, Any] = {
    "records": [
        {
            "recordName": RELEASE_RECORD_NAME,
            "serverErrorCode": "NOT_FOUND",
            "reason": "Record not found",
        }
    ]
}


def check(title: str, ok: bool, detail: str = "") -> None:
    global PASS, FAIL
    if ok:
        PASS += 1
        print("  ✅ {}".format(title))
    else:
        FAIL += 1
        print("  ❌ {}{}".format(title, " —— " + detail if detail else ""))
        DETAILS.append(title + (("：" + detail) if detail else ""))


class Transport:
    """可注入的传输层：既记录请求，也决定回什么。"""

    def __init__(self, response: Dict[str, Any]) -> None:
        self.response = response
        self.calls: List[Tuple[str, str]] = []

    def __call__(self, url: str, body: bytes, headers: Dict[str, str]) -> Dict[str, Any]:
        self.calls.append((url, body.decode("utf-8")))
        return self.response

    def paths(self) -> List[str]:
        return [url.rsplit("/public/", 1)[-1] for url, _ in self.calls]


def make_adapter(transport: Transport, apply: bool) -> CloudKitWebServicesAdapter:
    credentials = Credentials(CONTAINER, ENVIRONMENT, "SELFTEST-KEY-ID", "-----PEM-----")
    adapter = CloudKitWebServicesAdapter(credentials, apply=apply, http_post=transport)
    # 绕开真实签名：本脚本锁的是「读要不要发出去」，不是签名（那是 selftest_signing.py 的事）。
    # 这样这条锁**不依赖 cryptography**，缺依赖时也仍然能跑。
    adapter._headers = lambda body, path: {}  # type: ignore[method-assign]
    return adapter


RELEASE_STUB: Dict[str, Any] = {
    "releaseSeq": 8,
    "schemaVersion": 2,
    "revocationEpoch": 2,
    "minimumReaderVersion": 1,
    "previousReleaseSeq": 7,
    "publishedAt": "2026-09-27T00:00:00Z",
    "rootIndexHash": "hash-of-root-index",
}


def main() -> int:
    print("CloudKit 适配器读/写闸门回归锁")
    print("  容器      : {}".format(CONTAINER))
    print("  环境      : {}".format(ENVIRONMENT))
    print("")

    print("① dry-run 必须仍然读到线上发布头")
    transport = Transport(HEAD_RESPONSE)
    adapter = make_adapter(transport, apply=False)
    head = adapter.fetch_current_release()
    check("apply=False 时发出了 lookup 请求", len(transport.calls) == 1,
          "请求数={}".format(len(transport.calls)))
    check("请求打到了 records/lookup", transport.paths() == ["records/lookup"],
          "实际={}".format(transport.paths()))
    check("发布头被解析出来（不再恒为 None）", head is not None)
    check("releaseSeq 解析正确", (head or {}).get("releaseSeq") == 7,
          "实际={}".format((head or {}).get("releaseSeq")))
    check("changeTag 解析正确（R09 冲突检测要用）",
          (head or {}).get("changeTag") == "TAG-42",
          "实际={}".format((head or {}).get("changeTag")))
    check("rootIndexHash 解析正确（R07 基线核对要用）",
          (head or {}).get("rootIndexHash") == "hash-of-root-index")

    print("")
    print("② dry-run 必须仍然拦住**写**（闸门只关写）")
    for name, call in (
        ("put_release", lambda a: a.put_release(dict(RELEASE_STUB), b"{}", "TAG-42")),
        ("put_pack", lambda a: a.put_pack("deadbeef", Path("/dev/null"), {})),
        ("put_media", lambda a: a.put_media("deadbeef", Path("/dev/null"), {})),
    ):
        transport2 = Transport(HEAD_RESPONSE)
        adapter2 = make_adapter(transport2, apply=False)
        try:
            call(adapter2)
            raised = None
        except Exception as error:  # noqa: BLE001 - /dev/null 之类会自然报错，不算失败
            raised = error
        check("apply=False 时 {} 不发任何请求".format(name), len(transport2.calls) == 0,
              "请求数={}（写入异常={}）".format(len(transport2.calls), raised))

    print("")
    print("③ 「线上确实没有」与「根本没读」必须区分得开")
    transport3 = Transport(NOT_FOUND_RESPONSE)
    adapter3 = make_adapter(transport3, apply=False)
    absent = adapter3.fetch_current_release()
    check("NOT_FOUND 时返回 None", absent is None)
    check("但仍然**发过请求**（这些才是「问过了」）", len(transport3.calls) == 1,
          "请求数={}".format(len(transport3.calls)))

    print("")
    print("④ 反向断言：读不走 _post 那条写路径")
    transport4 = Transport(HEAD_RESPONSE)
    adapter4 = make_adapter(transport4, apply=False)

    def forbidden(path: str, payload: Dict[str, Any]) -> Dict[str, Any]:
        raise AssertionError("读操作走到了 _post（写路径）：{}".format(path))

    adapter4._post = forbidden  # type: ignore[method-assign]
    try:
        head4 = adapter4.fetch_current_release()
        check("把 _post 换成必然抛异常的桩后，读仍然成功", head4 is not None)
    except AssertionError as error:
        check("把 _post 换成必然抛异常的桩后，读仍然成功", False, str(error))

    print("")
    print("⑤ 资源存在性检查（pack_exists / media_exists）同样是读")
    transport5 = Transport(HEAD_RESPONSE)
    adapter5 = make_adapter(transport5, apply=False)
    exists = adapter5.pack_exists("deadbeef")
    check("apply=False 时 pack_exists 真发了请求", len(transport5.calls) == 1,
          "请求数={}".format(len(transport5.calls)))
    check("pack_exists 结果来自真实响应（存在）", exists is True)

    print("")
    print("⑥ 桥接器入口 read_head() 也必须真发请求")
    transport6 = Transport(HEAD_RESPONSE)
    bridge_adapter = make_adapter(transport6, apply=False)
    original_make_adapter = ops_publish_bridge.make_adapter
    ops_publish_bridge.make_adapter = lambda *a, **k: bridge_adapter  # type: ignore[assignment]
    try:
        request = {"targetEnvironment": "development"}
        head6 = ops_publish_bridge.read_head(request)
        check("read_head() 发出了请求", len(transport6.calls) == 1,
              "请求数={}".format(len(transport6.calls)))
        check("read_head() 读到了发布头", head6 is not None)
        payload = ops_publish_bridge.head_payload(request, head6)
        check("事件里的 releaseSeq 是线上的 7（不是被伪装成的 0）",
              payload.get("releaseSeq") == 7, "实际={}".format(payload.get("releaseSeq")))
        check("事件里没有「线上尚无…首次发布」这句话",
              "首次发布" not in str(payload.get("message", "")))
    finally:
        ops_publish_bridge.make_adapter = original_make_adapter  # type: ignore[assignment]

    print("")
    print("通过 {} 项，失败 {} 项".format(PASS, FAIL))
    return 1 if FAIL else 0


if __name__ == "__main__":
    sys.exit(main())
