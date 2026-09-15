# -*- coding: utf-8 -*-
"""采集器基类：Playwright 登录态管理、限速、通用图片落盘逻辑。"""
import json
import logging
import random
import time
from pathlib import Path

from .http_client import HttpClient
from .image_downloader import ImageDownloader
from .storage import RunStore

logger = logging.getLogger(__name__)

# 反自动化检测：闲鱼/淘宝会检查 navigator.webdriver 等指纹，
# 不加这段会被提示"非法访问，请使用正常浏览器访问"
STEALTH_JS = """
Object.defineProperty(navigator, 'webdriver', {get: () => undefined});
window.chrome = window.chrome || { runtime: {} };
Object.defineProperty(navigator, 'languages', {get: () => ['zh-CN','zh','en']});
Object.defineProperty(navigator, 'plugins', {get: () => [1,2,3,4,5]});
const origQuery = window.navigator.permissions && window.navigator.permissions.query;
if (origQuery) { window.navigator.permissions.query = (p) => p && p.name === 'notifications'
  ? Promise.resolve({state: Notification.permission}) : origQuery(p); }
"""

UA = ("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 "
      "(KHTML, like Gecko) Chrome/151.0.0.0 Safari/537.36")


class BaseCollector:
    """所有平台采集器的公共骨架。

    登录态：通过 Playwright storage_state JSON 文件注入（首次用
    `python -m scrapers.login_helper <platform>` 人工扫码生成）。
    """

    platform = "base"

    def __init__(self, scrapers_root: Path, storage_state: Path | None = None,
                 headless: bool = True, max_items: int = 20):
        self.root = Path(scrapers_root)
        self.storage_state = storage_state
        self.headless = headless
        self.max_items = max_items
        self.client = HttpClient()
        self.downloader = ImageDownloader(self.root / "assets" / "images")

    # ---------- 登录态 ----------
    def has_login_state(self) -> bool:
        return bool(self.storage_state and Path(self.storage_state).exists())

    # ---------- Playwright ----------
    def _new_page(self, pw):
        # channel="chromium" 走完整版 Chromium 的新无头模式；
        # 默认的 chrome-headless-shell 会被闲鱼/淘宝识别为"非法访问"直接拒绝
        browser = pw.chromium.launch(headless=self.headless, channel="chromium")
        kwargs = {"viewport": {"width": 1440, "height": 900}, "user_agent": UA}
        if self.has_login_state():
            ctx = browser.new_context(storage_state=str(self.storage_state), **kwargs)
        else:
            logger.warning("[%s] 未提供登录态文件，将尝试免登录抓取（很可能被风控拦截）",
                           self.platform)
            ctx = browser.new_context(**kwargs)
        ctx.add_init_script(STEALTH_JS)
        return browser, ctx, ctx.new_page()

    def _human_delay(self, lo: float = 2.0, hi: float = 5.0) -> None:
        time.sleep(random.uniform(lo, hi))

    # ---------- 图片 ----------
    def save_images(self, store: RunStore, item_id: str, urls: list[str],
                    max_images: int = 12) -> list[str]:
        rel_dir = store.item_image_dir(item_id)
        saved: list[str] = []
        for i, url in enumerate(urls[:max_images], 1):
            rel = self.downloader.download(url, rel_dir, f"{i:03d}")
            if rel:
                saved.append(rel)
        return saved

    def save_size_charts(self, store: RunStore, item_id: str, urls: list[str],
                         max_images: int = 4) -> list[str]:
        """尺码表候选图：与商品图同目录、sizechart_ 前缀，供运营者补录时挑选确认。"""
        rel_dir = store.item_image_dir(item_id)
        saved: list[str] = []
        for i, url in enumerate(urls[:max_images], 1):
            rel = self.downloader.download(url, rel_dir, f"sizechart_{i:02d}")
            if rel:
                saved.append(rel)
        return saved

    # ---------- 子类实现 ----------
    def collect(self, keyword: str) -> RunStore:  # pragma: no cover
        raise NotImplementedError


def load_storage_state_map(config_path: Path) -> dict:
    """config.json 里 cookies 段：{"taobao": "path/to/state.json", ...}"""
    if not Path(config_path).exists():
        return {}
    data = json.loads(Path(config_path).read_text(encoding="utf-8"))
    return data.get("storage_state", {})
