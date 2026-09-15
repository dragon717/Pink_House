# -*- coding: utf-8 -*-
"""一次性登录助手：弹出真实浏览器，人工扫码，自动检测登录成功并保存登录态。

用法：
    python login_helper.py taobao [超时秒数=300]
    python login_helper.py xianyu [超时秒数=300]

检测逻辑：轮询 cookies，出现登录凭证（unb / lid / havana 系列）即认为成功。
生成的文件：scrapers/cookies/<platform>_state.json
"""
import sys
import time
from pathlib import Path

from playwright.sync_api import sync_playwright

ROOT = Path(__file__).resolve().parent
START_URLS = {
    "taobao": "https://login.taobao.com/member/login.jhtml?redirectURL=https%3A%2F%2Fwww.taobao.com%2F",
    "xianyu": "https://www.goofish.com/",
}
# 登录成功后域名下会出现的凭证 cookie 名片段
LOGIN_COOKIE_HINTS = ("unb", "lid", "havana", "lgc", "dnk")


def is_logged_in(cookies: list[dict]) -> bool:
    for c in cookies:
        name = c.get("name", "").lower()
        if any(h in name for h in LOGIN_COOKIE_HINTS) and c.get("value"):
            return True
    return False


def main(platform: str, timeout_s: int = 300) -> None:
    if platform not in START_URLS:
        print(f"不支持的平台: {platform}，可选 {list(START_URLS)}")
        sys.exit(1)
    out_dir = ROOT / "cookies"
    if not out_dir.exists():
        out_dir.mkdir(parents=True, exist_ok=True)
    out_path = out_dir / f"{platform}_state.json"

    with sync_playwright() as pw:
        browser = pw.chromium.launch(headless=False)  # 必须有头：headless 会触发滑块风控
        ctx = browser.new_context(viewport={"width": 1440, "height": 900})
        page = ctx.new_page()
        page.goto(START_URLS[platform])
        print(f"PLAYER_LOGIN_START {platform}", flush=True)
        deadline = time.time() + timeout_s
        ok = False
        while time.time() < deadline:
            time.sleep(2)
            try:
                if is_logged_in(ctx.cookies()):
                    ok = True
                    break
            except Exception:  # noqa: BLE001
                pass
        if ok:
            # 多等几秒让登录态 cookie 写全
            time.sleep(4)
            ctx.storage_state(path=str(out_path))
            print(f"PLAYER_LOGIN_OK {out_path}", flush=True)
        else:
            print(f"PLAYER_LOGIN_TIMEOUT {timeout_s}s", flush=True)
        browser.close()
    sys.exit(0 if ok else 2)


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print(__doc__)
        sys.exit(1)
    main(sys.argv[1].strip().lower(),
         int(sys.argv[2]) if len(sys.argv) > 2 else 300)
