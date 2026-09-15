# -*- coding: utf-8 -*-
"""淘宝 / 天猫商品采集器（Playwright 页面抓取方案）。

思路（参考开源实践：MarketSpider、pachong-cursor、examples-of-web-crawlers）：
1. 带 storage_state 登录态打开 s.taobao.com 搜索页（天猫商品会一起出现在结果里）；
2. 解析结果卡片拿 item_id / 标题 / 价格 / 链接；
3. 详情链接统一规范化为 item.taobao.com/item.htm?id=<商品ID>（天猫商品同样使用该地址，
   旧链接如 detail.tmall.com/item.htm、带 skuId/spm 等跟踪参数的搜索链接一律不再引用）；
4. 图片经 ImageDownloader 全部落成静态文件。

注意：页面结构随平台改版会变，选择器失效时优先更新 _extract_search_cards
与 _extract_detail 内的 CSS 选择器。
"""
import logging
import re
from pathlib import Path
from urllib.parse import parse_qs, urlparse

from playwright.sync_api import sync_playwright, TimeoutError as PWTimeout

from ..common.base import BaseCollector
from ..common.storage import RunStore

logger = logging.getLogger(__name__)

SEARCH_URL = "https://s.taobao.com/search?q={kw}&s={page}"
# 仅用于在搜索结果里"识别"商品链接（天猫商品的链接也长这样），
# 生成的详情链接一律走 canonical_item_url()
ITEM_URL_PATTERNS = ("item.taobao.com/item.htm", "detail.tmall.com/item.htm")
CANONICAL_ITEM_URL = "https://item.taobao.com/item.htm?id={item_id}"


def canonical_item_url(item_id: str) -> str:
    """统一淘宝商品详情页地址：干净、无跟踪参数，天猫商品同样适用。"""
    return CANONICAL_ITEM_URL.format(item_id=item_id)


class TaobaoCollector(BaseCollector):
    """platform 取 'taobao' 或 'tmall'；两者共用淘宝搜索页，详情按域名归档。"""

    def __init__(self, *args, platform: str = "taobao", **kwargs):
        super().__init__(*args, **kwargs)
        self.platform = platform

    # ---------- 搜索 ----------
    def collect(self, keyword: str) -> RunStore:
        store = RunStore(self.root, self.platform, keyword)
        with sync_playwright() as pw:
            browser, ctx, page = self._new_page(pw)
            try:
                cards = self._search(page, keyword)
                logger.info("[%s] 关键词 %r 命中 %s 个结果卡片", self.platform, keyword, len(cards))
                for card in cards[: self.max_items]:
                    item = self._collect_detail(page, card)
                    if not item:
                        continue
                    item["images"] = self.save_images(store, item["item_id"],
                                                      item.pop("image_urls"))
                    item["size_charts"] = self.save_size_charts(
                        store, item["item_id"], item.pop("size_chart_urls", []))
                    store.add_item(item)
                    self._human_delay()
            finally:
                ctx.close()
                browser.close()
        store.save()
        return store

    def _search(self, page, keyword: str) -> list[dict]:
        page.goto(SEARCH_URL.format(kw=keyword, page=0), wait_until="domcontentloaded",
                  timeout=60_000)
        page.wait_for_timeout(4000)
        # 未登录时淘宝跳登录页
        if "login.taobao.com" in page.url:
            raise RuntimeError("淘宝要求登录：请先运行 login_helper.py taobao 生成登录态")
        # headless 无登录态会触发滑块验证码
        if page.query_selector('text=drag the slider') or page.query_selector('text=拖动滑块'):
            raise RuntimeError("触发滑块验证码：请用 --no-headless 有头模式，"
                               "或先用 login_helper.py taobao 生成登录态")
        cards = self._extract_search_cards(page)
        for _ in range(3):
            if cards:
                return cards
            page.mouse.wheel(0, 2000)
            page.wait_for_timeout(3000)
            cards = self._extract_search_cards(page)
        return cards

    @staticmethod
    def _extract_search_cards(page) -> list[dict]:
        cards: dict[str, dict] = {}
        for a in page.query_selector_all("a[href]"):
            href = a.get_attribute("href") or ""
            if not any(p in href for p in ITEM_URL_PATTERNS):
                continue
            item_id = _parse_item_id(href)
            if not item_id or item_id in cards:
                continue
            container = a.evaluate_handle("el => el.closest('div[class]') || el")
            text = " ".join((container.inner_text() or "").split()) if container else ""
            img = a.query_selector("img")
            img_url = ""
            if img:
                img_url = (img.get_attribute("src") or img.get_attribute("data-src") or "")
            title = text
            price_m = re.search(r"[¥￥]\s*([0-9]+(?:\.[0-9]+)?)", text)
            cards[item_id] = {
                "item_id": item_id,
                "title": title[:200],
                "price": price_m.group(1) if price_m else None,
                "detail_url": canonical_item_url(item_id),
                "source_url": href if href.startswith("http") else "https:" + href,
                "image_urls": [img_url] if img_url else [],
            }
        return list(cards.values())

    # ---------- 详情 ----------
    def _collect_detail(self, page, card: dict) -> dict | None:
        item_id = card["item_id"]
        logger.info("抓取详情 %s", item_id)
        try:
            page.goto(card["detail_url"], wait_until="domcontentloaded", timeout=60_000)
            page.wait_for_timeout(3500)
        except PWTimeout:
            logger.warning("详情页超时 %s", item_id)
            return None
        detail = self._extract_detail(page)
        # 尺码表候选：详情描述区的图片（淘宝尺码表基本都在 desc 区）
        detail["size_chart_urls"] = self._extract_size_chart_images(page)
        card.update({k: v for k, v in detail.items() if v})
        return card

    @staticmethod
    def _extract_size_chart_images(page) -> list[str]:
        """尺码表候选图：desc/detail 容器内的 alicdn 图片，去重后最多 8 张。

        只做"候选"判定——是否真是尺码表交给运营者在补录时确认/删除。
        """
        urls: list[str] = []
        seen: set[str] = set()
        containers = page.query_selector_all(
            '[class*="desc" i], [id*="desc" i], [class*="detail" i]')
        for container in containers:
            for img in container.query_selector_all("img"):
                src = img.get_attribute("src") or img.get_attribute("data-src") or ""
                if "alicdn.com" not in src:
                    continue
                src = "https:" + src if src.startswith("//") else src
                if src not in seen and not re.search(r"\.(gif|svg)(\?|$)", src, re.I):
                    seen.add(src)
                    urls.append(src)
        return urls[:8]

    @staticmethod
    def _extract_detail(page) -> dict:
        title = (page.title() or "").split("-")[0].strip()
        desc = ""
        for sel in ('[class*="descText"]', '[class*="detailText"]',
                    '#J_DetailMeta .tb-detail', '[class*="desc"]'):
            el = page.query_selector(sel)
            if el and len((el.inner_text() or "").strip()) > len(desc):
                desc = " ".join(el.inner_text().split())[:2000]
        if len(desc) < 20:
            # 兜底：meta description
            meta = page.query_selector('meta[name="description"]')
            if meta:
                desc = (meta.get_attribute("content") or "").strip()[:2000]
        price = None
        price_el = page.query_selector('[class*="Price"] [class*="text"], .tb-rmb-num')
        if price_el:
            m = re.search(r"([0-9]+(?:\.[0-9]+)?)", price_el.inner_text() or "")
            price = m.group(1) if m else None
        gallery: list[str] = []
        seen: set[str] = set()
        for img in page.query_selector_all("img"):
            src = img.get_attribute("src") or img.get_attribute("data-src") or ""
            if "alicdn.com" not in src:
                continue
            src = "https:" + src if src.startswith("//") else src
            if src in seen or re.search(r"\.(gif|svg)(\?|$)", src, re.I):
                continue
            # 过滤图标类小图
            style = (img.get_attribute("style") or "")
            if any(k in style for k in ("icon", "logo")):
                continue
            seen.add(src)
            gallery.append(src)
        return {"title": title, "description": desc, "price": price, "image_urls": gallery}


def _parse_item_id(url: str) -> str | None:
    try:
        qs = parse_qs(urlparse(url).query)
        return (qs.get("id") or qs.get("itemId") or [None])[0]
    except Exception:  # noqa: BLE001
        return None
