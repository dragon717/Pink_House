# -*- coding: utf-8 -*-
"""图片下载器：把商品图片落成静态文件，按 md5 去重。"""
import hashlib
import logging
import re
from pathlib import Path
from urllib.parse import urlparse, unquote

from .http_client import HttpClient

logger = logging.getLogger(__name__)

# 各平台图片 CDN 的 Referer（alicdn 一般不需要，但带上更稳）
REFERER_MAP = {
    "img.alicdn.com": "https://www.taobao.com/",
    "cbu01.alicdn.com": "https://www.1688.com/",
    "img.goofish.com": "https://www.goofish.com/",
    "gw.alipayobjects.com": "https://www.goofish.com/",
}


def _referer_for(url: str) -> str | None:
    host = urlparse(url).netloc
    for key, ref in REFERER_MAP.items():
        if host.endswith(key):
            return ref
    return None


def safe_ext(url: str, default: str = ".jpg") -> str:
    path = unquote(urlparse(url).path)
    m = re.search(r"\.(jpe?g|png|webp|gif|bmp)$", path, re.I)
    return ("." + m.group(1).lower()) if m else default


def slugify(text: str, max_len: int = 40) -> str:
    text = re.sub(r"[^\w\u4e00-\u9fff-]+", "_", text.strip())
    return text.strip("_")[:max_len] or "untitled"


class ImageDownloader:
    """把图片 URL 下载为静态文件，返回相对路径。文件名基于内容 md5 去重。"""

    def __init__(self, root: Path, client: HttpClient | None = None):
        self.root = Path(root)
        self.client = client or HttpClient()
        self._seen_md5: dict[str, str] = {}

    def download(self, url: str, rel_dir: str | Path, base_name: str) -> str | None:
        """下载单张图片，成功返回相对 root 的路径，失败返回 None。"""
        url = self._normalize(url)
        if not url or not url.startswith(("http://", "https://")):
            return None
        try:
            resp = self.client.get(url, referer=_referer_for(url))
        except Exception as exc:  # noqa: BLE001
            logger.error("图片下载失败 %s: %s", url[:120], exc)
            return None

        content = resp.content
        if len(content) < 1024:
            logger.warning("图片过小，疑似占位图，跳过 %s", url[:120])
            return None
        md5 = hashlib.md5(content).hexdigest()
        if md5 in self._seen_md5:
            return self._seen_md5[md5]

        dest_dir = self.root / rel_dir
        dest_dir.mkdir(parents=True, exist_ok=True)
        dest = dest_dir / f"{base_name}{safe_ext(url)}"
        # 内容去重：同 md5 已存在直接复用
        existing = self._find_by_md5(dest_dir, md5)
        if existing:
            self._seen_md5[md5] = existing
            return existing
        dest.write_bytes(content)
        rel_path = str(dest.relative_to(self.root))
        self._seen_md5[md5] = rel_path
        logger.info("已保存 %s (%.1f KB)", rel_path, len(content) / 1024)
        return rel_path

    @staticmethod
    def _normalize(url: str) -> str:
        url = url.strip()
        if url.startswith("//"):
            url = "https:" + url
        # 淘宝系缩略图转原图：去掉尺寸后缀 _S / _400x400 等
        url = re.sub(r"_(\d+x\d+|S|b|sum)\.(jpg|png|webp)$", r".\2", url, flags=re.I)
        return url

    @staticmethod
    def _find_by_md5(dest_dir: Path, md5: str) -> str | None:
        return None  # 跨运行去重交给调用方用 items.json 的 url 字段判断
