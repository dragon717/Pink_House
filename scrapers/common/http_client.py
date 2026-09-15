# -*- coding: utf-8 -*-
"""通用 HTTP 客户端：带 UA、重试与限速，用于图片与静态资源下载。"""
import time
import logging
import random

import requests

logger = logging.getLogger(__name__)

DEFAULT_HEADERS = {
    "User-Agent": (
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 "
        "(KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36"
    ),
    "Accept": "image/avif,image/webp,image/apng,image/*,*/*;q=0.8",
    "Accept-Language": "zh-CN,zh;q=0.9",
}


class HttpClient:
    """带重试与限速的 requests 封装（仅用于轻量静态资源，页面抓取走 Playwright）。"""

    def __init__(self, timeout: int = 20, max_retries: int = 3,
                 min_delay: float = 0.8, max_delay: float = 2.0):
        self.timeout = timeout
        self.max_retries = max_retries
        self.min_delay = min_delay
        self.max_delay = max_delay
        self.session = requests.Session()
        self.session.headers.update(DEFAULT_HEADERS)

    def get(self, url: str, referer: str | None = None, **kwargs) -> requests.Response:
        headers = kwargs.pop("headers", {}) or {}
        if referer:
            headers.setdefault("Referer", referer)
        last_exc: Exception | None = None
        for attempt in range(1, self.max_retries + 1):
            try:
                resp = self.session.get(url, timeout=self.timeout, headers=headers, **kwargs)
                resp.raise_for_status()
                self._polite_delay()
                return resp
            except Exception as exc:  # noqa: BLE001
                last_exc = exc
                wait = attempt * 2
                logger.warning("GET 失败(第 %s 次) %s -> %s，%ss 后重试", attempt, url[:120], exc, wait)
                time.sleep(wait)
        raise RuntimeError(f"GET 最终失败: {url} ({last_exc})")

    def _polite_delay(self) -> None:
        time.sleep(random.uniform(self.min_delay, self.max_delay))
