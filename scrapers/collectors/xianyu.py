# -*- coding: utf-8 -*-
"""闲鱼（Goofish）商品采集器 —— PC Web 端页面抓取方案。

参考实践：browser-act goofish-item-detail、floatin/xianyu_spider（App 端备选）。
- 搜索页：https://www.goofish.com/search?q=<kw>（需登录态）
- 详情页：https://www.goofish.com/item?id=<item_id>
- 图片 CDN：img.alicdn.com / img.goofish.com，可直接静态化
若页面抓取被风控，可退化用 mtop 接口 mtop.taobao.idle.pc.search（需自行带 cookie 签名）。
"""
import logging
import re
from urllib.parse import parse_qs, urlparse

from playwright.sync_api import sync_playwright, TimeoutError as PWTimeout

from ..common.base import BaseCollector
from ..common.storage import RunStore

logger = logging.getLogger(__name__)

SEARCH_URL = "https://www.goofish.com/search?q={kw}"
DETAIL_URL = "https://www.goofish.com/item?id={item_id}"


SITE_TITLE_MARK = "闲不住？上闲鱼"
DESC_JUNK_PREFIXES = ("搜索 网页版发闲置功能又升级啦！", "网页版发闲置功能又升级啦！", "为你推荐")


def _clean_desc(text: str) -> str:
    for junk in DESC_JUNK_PREFIXES:
        text = text.replace(junk, " ")
    return " ".join(text.split())[:2000]


class XianyuCollector(BaseCollector):
    platform = "xianyu"

    def collect(self, keyword: str) -> RunStore:
        store = RunStore(self.root, self.platform, keyword)
        with sync_playwright() as pw:
            browser, ctx, page = self._new_page(pw)
            try:
                cards = self._search(page, keyword)
                logger.info("[xianyu] 关键词 %r 命中 %s 个结果", keyword, len(cards))
                for card in cards[: self.max_items]:
                    item = self._collect_detail(page, card)
                    if not item:
                        continue
                    item["images"] = self.save_images(store, item["item_id"],
                                                      item.pop("image_urls"))
                    # 闲鱼详情页基本不带尺码表，占位空列表保持与淘宝 run 同构
                    item["size_charts"] = []
                    store.add_item(item)
                    self._human_delay()
            finally:
                ctx.close()
                browser.close()
        store.save()
        return store

    def _search(self, page, keyword: str) -> list[dict]:
        page.goto(SEARCH_URL.format(kw=keyword), wait_until="domcontentloaded",
                  timeout=60_000)
        page.wait_for_timeout(4000)
        self._dismiss_login_modal(page)
        # 未登录时结果区可能只有推荐流；等待真实结果渲染
        for _ in range(3):
            items = self._extract_cards(page)
            if items:
                return items
            page.mouse.wheel(0, 2400)
            page.wait_for_timeout(3500)
            self._dismiss_login_modal(page)
        if self._login_modal_visible(page):
            raise RuntimeError("闲鱼搜索需要登录（结果区未渲染）："
                               "先运行 login_helper.py xianyu 生成登录态")
        raise RuntimeError("闲鱼搜索未解析到商品卡片：可能是页面结构变化，"
                           "请检查 _extract_cards 选择器")

    @staticmethod
    def _login_modal_visible(page) -> bool:
        try:
            return page.query_selector('text=手机扫码安全登录') is not None
        except Exception:  # noqa: BLE001
            return False

    @staticmethod
    def _dismiss_login_modal(page) -> None:
        """登录弹窗不致命：关掉它，背后的搜索结果/推荐流可继续解析。"""
        try:
            for sel in ('[class*="login"] [class*="close"]',
                        'div[role="dialog"] [class*="close"]',
                        'text=✕', 'text=×'):
                el = page.query_selector(sel)
                if el and el.is_visible():
                    el.click()
                    page.wait_for_timeout(1200)
                    return
            page.keyboard.press("Escape")
            page.wait_for_timeout(800)
        except Exception:  # noqa: BLE001
            pass

    @staticmethod
    def _extract_cards(page) -> list[dict]:
        cards: dict[str, dict] = {}
        for a in page.query_selector_all('a[href*="/item?id="]'):
            href = a.get_attribute("href") or ""
            item_id = (parse_qs(urlparse(href).query).get("id") or [None])[0]
            if not item_id or item_id in cards:
                continue
            text = " ".join((a.inner_text() or "").split())
            img = a.query_selector("img")
            img_url = (img.get_attribute("src") or img.get_attribute("data-src") or "") if img else ""
            price_m = re.search(r"[¥￥]\s*([0-9]+(?:\.[0-9]+)?)", text)
            cards[item_id] = {
                "item_id": item_id,
                "title": text[:200],
                "price": price_m.group(1) if price_m else None,
                "detail_url": DETAIL_URL.format(item_id=item_id),
                "image_urls": [img_url] if img_url else [],
            }
        return list(cards.values())

    def _collect_detail(self, page, card: dict) -> dict | None:
        logger.info("抓取闲鱼详情 %s", card["item_id"])
        for attempt in range(2):
            try:
                page.goto(card["detail_url"], wait_until="domcontentloaded", timeout=60_000)
                page.wait_for_timeout(4000 if attempt == 0 else 6000)
            except PWTimeout:
                logger.warning("闲鱼详情页超时 %s", card["item_id"])
                return None
            if not self._is_blocked(page):
                detail = self._extract_detail(page, card.get("title") or "")
                card.update({k: v for k, v in detail.items() if v})
                return card
            # 间歇性风控：冷却后重试一次
            wait_s = 30 * (attempt + 1)
            logger.warning("详情页被风控（非法访问），冷却 %ss 后重试", wait_s)
            page.wait_for_timeout(wait_s * 1000)
        logger.error("详情页持续被风控，跳过 %s", card["item_id"])
        return None

    @staticmethod
    def _is_blocked(page) -> bool:
        try:
            return page.query_selector('text=非法访问') is not None
        except Exception:  # noqa: BLE001
            return False

    @staticmethod
    def _extract_detail(page, fallback_title: str) -> dict:
        # 标题：优先 DOM；页面 title 是站点名时回退用搜索卡片标题
        title = ""
        for sel in ('h1', '[class*="ItemHeader"]', '[class*="itemTitle"]'):
            el = page.query_selector(sel)
            if el and len((el.inner_text() or "").strip()) >= 5:
                title = " ".join(el.inner_text().split())
                break
        page_title = (page.title() or "").replace("- 闲鱼", "").strip()
        if not title or SITE_TITLE_MARK in page_title:
            title = title or fallback_title or page_title
        # 描述：找最长的一段正文文本（详情描述区没有稳定 class）
        desc = ""
        try:
            texts = page.eval_on_selector_all(
                "div, p, span",
                "els => els.map(e => (e.innerText||'').trim()).filter(t => t.length > 30)")
            for t in texts[:10]:
                if len(t) > len(desc) and len(t) < 3000:
                    desc = " ".join(t.split())
        except Exception:  # noqa: BLE001
            pass
        if not desc:
            desc_el = page.query_selector('[class*="desc"]')
            if desc_el:
                desc = " ".join((desc_el.inner_text() or "").split())[:2000]
        desc = _clean_desc(desc)
        price = None
        price_el = page.query_selector('[class*="price"]')
        if price_el:
            m = re.search(r"([0-9]+(?:\.[0-9]+)?)", price_el.inner_text() or "")
            price = m.group(1) if m else None
        gallery: list[str] = []
        seen: set[str] = set()
        for img in page.query_selector_all("img"):
            src = img.get_attribute("src") or img.get_attribute("data-src") or ""
            if not any(k in src for k in ("alicdn.com", "goofish.com")):
                continue
            src = "https:" + src if src.startswith("//") else src
            if src not in seen and not re.search(r"\.(gif|svg)(\?|$)", src, re.I):
                seen.add(src)
                gallery.append(src)
        return {"title": title, "description": desc, "price": price, "image_urls": gallery}
