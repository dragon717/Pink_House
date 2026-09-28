#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""出网回退的**离线回归锁**（不联网、不需要凭证、不需要 cryptography）。

## 锁住的那个真实事故（2026-09-29）

App 面板点「拉回目录」，拿到的是：

    refused · 桥接器内部错误：URLError: <urlopen error [Errno 54] Connection reset by peer>

看着像桥接器有 bug。实际是：

`api.apple-cloudkit.com` 会解析出**多个边缘 IP**，其中个别 IP 是
「**TCP 连得上、TLS 握手被立刻 RST**」（实测连续 3 轮 3/3，用时 0.01s）：

    17.248.216.28    TCP ✓ [0.06s]  TLS ✗ [0.01s] ConnectionResetError: [Errno 54]
    17.248.216.42    TCP ✓ [0.09s]  TLS ✓ [0.08s] TLSv1.2

而 `socket.create_connection()`（urllib 内部走的那条）**只在 TCP connect 失败时**
才换下一个地址 —— TLS 阶段炸掉**不回退**，于是整次请求判死，其余健康地址
一个都没试过。DNS 答案顺序是轮换的：坏 IP 排第一就失败，排后面就正常。
**这就是「同一份请求，一会儿行一会儿不行」的机制**，而 4 次外层重试每次都重新
解析、拿到同一份顺序 → 全部撞同一个坏 IP（耗时正好 = 重试等待之和
`0+5+15+30=50` 秒），最后吐一个「内部错误」。

修法：把「就绪」定义成 **TLS 握手完成之后**，回退也做到那一层（`connect_first_ready`），
并且**全项目只留一个出网入口** `open_https`，免得下次有人新写一处 `urlopen` 又绕过去。

用法：
    python3 selftest_network_failover.py
退出码：0 = 全部通过；1 = 有断言失败。
"""

from __future__ import annotations

import http.client
import re
import ssl
import sys
from pathlib import Path
from typing import Any, List, Optional

sys.path.insert(0, str(Path(__file__).resolve().parent))

import publish_adapters as pa  # noqa: E402

PASS = 0
FAIL = 0
DETAILS: List[str] = []

ADAPTER_SOURCE = Path(pa.__file__)


def check(title: str, ok: bool, detail: str = "") -> None:
    global PASS, FAIL
    if ok:
        PASS += 1
        print("  ✅ {}".format(title))
    else:
        FAIL += 1
        print("  ❌ {}{}".format(title, " —— " + detail if detail else ""))
        DETAILS.append(title + (("：" + detail) if detail else ""))


# ------------------------------------------------------------------ 替身

class FakeSocket:
    """只记录「连的是哪个地址」「有没有被关掉」。"""

    def __init__(self, address: str) -> None:
        self.address = address
        self.closed = False

    def close(self) -> None:
        self.closed = True


def candidates(*addresses: str):
    return [
        (2, 1, 6, (address, 443))  # AF_INET, SOCK_STREAM, IPPROTO_TCP
        for address in addresses
    ]


def open_socket_on(opened: List[FakeSocket]):
    def open_socket(family: int, sockaddr: Any) -> FakeSocket:
        sock = FakeSocket(sockaddr[0])
        opened.append(sock)
        return sock

    return open_socket


def ready_that_fail_on(bad: List[str], log: Optional[List[str]] = None):
    """`bad` 里的地址在「TLS 阶段」抛 ConnectionResetError（TCP 已经连上了）。"""

    def ready(sock: FakeSocket) -> FakeSocket:
        if log is not None:
            log.append(sock.address)
        if sock.address in bad:
            raise ConnectionResetError(54, "Connection reset by peer")
        return sock

    return ready


# ------------------------------------------------------------------ 断言

def main() -> int:
    print("出网回退（TLS 之后仍换地址）回归锁")
    print()

    # ---- 1. 候选地址的来源与顺序
    print("① 候选地址：按 getaddrinfo 顺序、去重")
    real_getaddrinfo = pa.socket.getaddrinfo
    try:
        pa.socket.getaddrinfo = lambda host, port, *a, **k: [
            (2, 1, 6, "", ("10.0.0.1", port)),
            (2, 1, 6, "", ("10.0.0.2", port)),
            (2, 1, 6, "", ("10.0.0.1", port)),  # 重复，应被去掉
        ]
        ordered = pa.resolved_tcp_addresses("example.invalid", 443)
        check("顺序保持 + 去重", [c[3][0] for c in ordered] == ["10.0.0.1", "10.0.0.2"],
              str([c[3][0] for c in ordered]))
    finally:
        pa.socket.getaddrinfo = real_getaddrinfo

    # ---- 2. 核心：TLS 阶段失败必须换下一个地址
    print()
    print("② TLS 握手失败 → 换下一个地址（这条就是 09-29 那个 bug）")
    opened: List[FakeSocket] = []
    ready = ready_that_fail_on(["17.248.216.28"])
    sock = pa.connect_first_ready(candidates("17.248.216.28", "17.248.216.42"),
                                 open_socket_on(opened), ready)
    check("第一个地址 TLS 被重置后，拿到的是第二个地址的连接",
          sock.address == "17.248.216.42", "拿到 " + sock.address)
    check("试过的地址顺序正确（先坏后好）",
          [s.address for s in opened] == ["17.248.216.28", "17.248.216.42"],
          str([s.address for s in opened]))
    check("失败的那个连接被关掉（不泄漏 socket）", opened[0].closed is True)

    # ---- 3. 坏 IP 排第一、后面 4 个健康：必须成功
    print()
    print("③ 真实 DNS 形状：1 坏 + 4 好，坏的排第一")
    opened = []
    ready = ready_that_fail_on(["17.248.216.28"])
    sock = pa.connect_first_ready(
        candidates("17.248.216.28", "17.248.216.42", "17.248.216.20",
                   "17.248.216.66", "17.248.216.67"),
        open_socket_on(opened), ready)
    check("自动落到第一个健康地址（只试了 2 个）",
          sock.address == "17.248.216.42" and len(opened) == 2,
          "用了 {} 个: {}".format(len(opened), [s.address for s in opened]))

    # ---- 4. 全部失败 → NetworkError，点名所有试过的地址
    print()
    print("④ 全部地址都失败 → NetworkError（不是「内部错误」）")
    opened = []
    try:
        pa.connect_first_ready(
            candidates("10.0.0.1", "10.0.0.2"),
            open_socket_on(opened), ready_that_fail_on(["10.0.0.1", "10.0.0.2"]))
    except pa.NetworkError as error:
        text = str(error)
        check("抛的是 NetworkError", True)
        check("点名了两个试过的地址", "10.0.0.1" in text and "10.0.0.2" in text, text)
        check("保留了底层错误类型（ConnectionResetError）",
              "ConnectionResetError" in text, text)
    except Exception as error:  # noqa: BLE001
        check("抛的是 NetworkError", False, "{}: {}".format(type(error).__name__, error))
    else:
        check("抛的是 NetworkError", False, "竟然没有抛错")
    check("两个坏连接都被关掉", all(s.closed for s in opened))

    # ---- 5. 证书校验失败**不换地址**（换也没用，且会把确定的错误说成「网络不可达」）
    print()
    print("⑤ 证书校验失败**不**参与地址回退")
    opened = []
    try:
        pa.connect_first_ready(
            candidates("10.0.0.1", "10.0.0.2"),
            open_socket_on(opened),
            lambda sock: (_ for _ in ()).throw(
                ssl.SSLCertVerificationError("certificate verify failed")))
    except ssl.SSLCertVerificationError:
        check("直接抛证书错误", True)
    except Exception as error:  # noqa: BLE001
        check("直接抛证书错误", False, "{}: {}".format(type(error).__name__, error))
    else:
        check("直接抛证书错误", False, "竟然没有抛错")
    check("只试了第一个地址就停（没有把确定的证书错误说成「网络不可达」）",
          [s.address for s in opened] == ["10.0.0.1"], str([s.address for s in opened]))

    # ---- 6. 一个候选都没有
    print()
    print("⑥ 解析不到任何地址")
    try:
        pa.connect_first_ready([], open_socket_on([]), ready_that_fail_on([]))
    except pa.NetworkError as error:
        check("抛 NetworkError 且说明候选为 0", "0 个" in str(error), str(error))
    else:
        check("抛 NetworkError 且说明候选为 0", False, "竟然没有抛错")

    # ---- 7. 结构约束：这些是「改坏了眼睛看不出来」的部分
    print()
    print("⑦ 结构约束（防下次重构悄悄退化）")
    check("_FailoverHTTPSConnection 仍是 http.client.HTTPSConnection 的子类",
          issubclass(pa._FailoverHTTPSConnection, http.client.HTTPSConnection))
    check("出网 opener 装的是我们的 handler",
          any(isinstance(h, pa._FailoverHTTPSHandler) for h in pa._HTTPS_OPENER.handlers),
          str([type(h).__name__ for h in pa._HTTPS_OPENER.handlers]))
    check("整份适配层**没有**裸 urlopen 调用（新写一处就会绕过回退）",
          re.search(r"(?<!\.)\burlopen\s*\(", ADAPTER_SOURCE.read_text(encoding="utf-8")) is None,
          "publish_adapters.py 里又出现了 urlopen(")
    check("NetworkError 没有继承 ProtocolError（否则会被降级成「被拒绝」并丢掉可重试）",
          not issubclass(pa.NetworkError, pa.ProtocolError))

    print()
    print("通过 {} 项，失败 {} 项".format(PASS, FAIL))
    for detail in DETAILS:
        print("  - {}".format(detail))
    return 1 if FAIL else 0


if __name__ == "__main__":
    raise SystemExit(main())
