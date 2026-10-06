#!/usr/bin/env python3
"""沙盒剖面运行器 —— 在本机复现「App 沙盒子进程读不到 X」那一类失败。

## 为什么需要它

受控发布桥接器是 Mac App 的**子进程、继承 App 沙盒**。GUI 沙盒子进程**没法在本机
单独拉起**，所以「CLI 直跑全绿、App 里必挂」的差异只能靠等价剖面取证。

实测事故（2026-09-29）：`mimetypes.guess_type()` 首次调用会 `mimetypes.init()` 去读
`/etc/apache2/mime.types`，沙盒里被拒 → `build_release.py` 退出码 1 → 发布 refused，
而终端直跑**永远复现不出来**（终端有读 /etc 的权限）。

## 用法

    .venv/bin/python3 sandbox_profile_run.py --request /path/to/request.json
    .venv/bin/python3 sandbox_profile_run.py --request req.json --mode publish -- --extra-arg

被判为「禁止读取」的前缀（命中即抛 `PermissionError(1, ...)`）：
    /etc/  /private/etc/  /usr/share/  /var/db/  /private/var/db/

跑完会在 stderr 打两行结论之一：
    被拒绝的读取尝试 N 次：…      ← 说明剖面拦到了东西（要么是真缺陷，要么是误报）
    全程未尝试读取系统 mime 库      ← 干净

## 必做的反向对照

    .venv/bin/python3 sandbox_profile_run.py --self-test

同剖面下直接调 `mimetypes.guess_type("a.png")`，**必须**抛同一条 `PermissionError`。
抛不出来 = 剖面是「空过」，绿色毫无意义 —— 别跳过这一步。
"""
from __future__ import annotations

import argparse
import builtins
import io
import os
import runpy
import sys
from typing import List, Sequence

BLOCKED_PREFIXES = (
    "/etc/",
    "/private/etc/",
    "/usr/share/",
    "/var/db/",
    "/private/var/db/",
)

HERE = os.path.dirname(os.path.abspath(__file__))
BRIDGE = os.path.join(HERE, "ops_publish_bridge.py")

_attempts: List[str] = []


def install_profile(blocked: Sequence[str] = BLOCKED_PREFIXES) -> None:
    """把 builtins.open / io.open / os.open 换成命中禁读前缀就抛 PermissionError 的版本。"""
    real_builtin_open = builtins.open
    real_io_open = io.open
    real_os_open = os.open

    def check(target: object) -> None:
        try:
            path = os.fspath(target)  # type: ignore[arg-type]
        except TypeError:
            return
        if not isinstance(path, str):
            return
        abspath = os.path.abspath(path)
        for prefix in blocked:
            if abspath.startswith(prefix):
                _attempts.append(abspath)
                raise PermissionError(1, "Operation not permitted", abspath)

    def guarded_builtin_open(file, *a, **kw):  # type: ignore[no-untyped-def]
        check(file)
        return real_builtin_open(file, *a, **kw)

    def guarded_io_open(file, *a, **kw):  # type: ignore[no-untyped-def]
        check(file)
        return real_io_open(file, *a, **kw)

    def guarded_os_open(path, *a, **kw):  # type: ignore[no-untyped-def]
        check(path)
        return real_os_open(path, *a, **kw)

    builtins.open = guarded_builtin_open
    io.open = guarded_io_open
    os.open = guarded_os_open


def report() -> None:
    if _attempts:
        print(
            "[sandbox-profile] 被拒绝的读取尝试 %d 次：" % len(_attempts),
            file=sys.stderr,
        )
        for path in _attempts[:20]:
            print("  - %s" % path, file=sys.stderr)
    else:
        print("[sandbox-profile] 全程未尝试读取系统文件库（/etc、/usr/share、/var/db）", file=sys.stderr)


def self_test() -> int:
    """反向对照：旧口径在本剖面下必须被拒，新口径必须通过。"""
    install_profile()

    import mimetypes

    print("== 反向对照 · 旧口径 mimetypes.guess_type('a.png') ==")
    try:
        mimetypes.guess_type("a.png")
    except PermissionError as exc:
        print("   ✓ 剖面有效，原样复现：%s: %s" % (type(exc).__name__, exc))
    else:
        print("   ✗ 剖面无效！旧口径竟然通过了 —— 绿色毫无意义", file=sys.stderr)
        return 1

    from protocol import MEDIA_MIME_ALLOWLIST, media_mime_type

    print("== 对照 · 新口径 protocol.media_mime_type() ==")
    failures = 0
    for name in ("a.png", "b.JPG", "c.webp", "d.heic", "e.gif", "f.jpeg"):
        mime = media_mime_type(name)
        ok = mime in MEDIA_MIME_ALLOWLIST
        print("   %-10s -> %-26s %s" % (name, mime, "白名单内" if ok else "✗ 掉出白名单"))
        failures += 0 if ok else 1
    fallback = media_mime_type("g.unknownext")
    print("   %-10s -> %-26s %s" % ("g.unknownext", fallback, "回落 octet-stream"))
    failures += 0 if fallback == "application/octet-stream" else 1

    # 反向对照把 _attempts 塞满了，这里清掉，只看「新口径有没有再碰文件系统」
    _attempts.clear()
    for name in ("h.png", "i.jpg"):
        media_mime_type(name)
    report()

    if failures or _attempts:
        return 1
    print("== 自证通过：剖面能拦旧口径，新口径不触文件系统 ==")
    return 0


def main(argv: Sequence[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="沙盒剖面运行器（选项里的 -- 之后原样透传给桥接器）")
    parser.add_argument("--request", help="冻结请求 JSON 路径")
    parser.add_argument("--mode", default="publish", help="桥接器模式（默认 publish）")
    parser.add_argument("--self-test", action="store_true", help="只做反向对照自证，不跑桥接器")
    parser.add_argument("--no-report", action="store_true", help="不打印剖面结论")
    args, passthrough = parser.parse_known_args(argv)

    if args.self_test:
        return self_test()

    if not args.request:
        parser.error("要么给 --request，要么给 --self-test")
    if not os.path.isfile(BRIDGE):
        print("找不到桥接器：%s" % BRIDGE, file=sys.stderr)
        return 2

    install_profile()
    print("[sandbox-profile] 已装剖面：禁读 %s" % "、".join(BLOCKED_PREFIXES), file=sys.stderr)

    sys.argv = [BRIDGE, "--mode", args.mode, "--request", args.request, *passthrough]
    try:
        runpy.run_path(BRIDGE, run_name="__main__")
    except SystemExit as exc:  # 桥接器用 SystemExit 表达退出码
        code = exc.code if isinstance(exc.code, int) else (0 if exc.code is None else 1)
        if not args.no_report:
            report()
        return code
    if not args.no_report:
        report()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
