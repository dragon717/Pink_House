# -*- coding: utf-8 -*-
"""结构化存储：每次采集生成一个 run 目录，写 items.json 与汇总索引。"""
import json
import logging
import time
from datetime import datetime
from pathlib import Path

logger = logging.getLogger(__name__)


class RunStore:
    """管理一次采集的结构化输出：

    scrapers/
    ├── data/runs/<ts>_<platform>_<keyword>/items.json
    └── assets/images/<platform>/<keyword>/<item_id>/001.jpg
    """

    def __init__(self, scrapers_root: Path, platform: str, keyword: str):
        self.root = Path(scrapers_root)
        self.platform = platform
        self.keyword = keyword
        ts = datetime.now().strftime("%Y%m%d_%H%M%S")
        from .image_downloader import slugify
        self.run_id = f"{ts}_{platform}_{slugify(keyword, 24)}"
        self.run_dir = self.root / "data" / "runs" / self.run_id
        self.run_dir.mkdir(parents=True, exist_ok=True)
        self.items: list[dict] = []

    @property
    def images_root(self) -> Path:
        return self.root / "assets" / "images"

    def item_image_dir(self, item_id: str) -> Path:
        from .image_downloader import slugify
        rel = Path(self.platform) / slugify(self.keyword, 24) / slugify(item_id, 48)
        return rel

    def add_item(self, item: dict) -> None:
        self.items.append(item)

    def save(self, extra: dict | None = None) -> Path:
        payload = {
            "run_id": self.run_id,
            "platform": self.platform,
            "keyword": self.keyword,
            "collected_at": datetime.now().isoformat(timespec="seconds"),
            "item_count": len(self.items),
            "items": self.items,
        }
        if extra:
            payload.update(extra)
        out = self.run_dir / "items.json"
        out.write_text(json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8")
        self._update_index(payload)
        logger.info("已写入 %s（%s 个商品）", out, len(self.items))
        return out

    def _update_index(self, payload: dict) -> None:
        index_path = self.root / "data" / "index.json"
        index: list[dict] = []
        if index_path.exists():
            try:
                index = json.loads(index_path.read_text(encoding="utf-8"))
            except Exception:  # noqa: BLE001
                index = []
        index.append({
            "run_id": payload["run_id"],
            "platform": payload["platform"],
            "keyword": payload["keyword"],
            "collected_at": payload["collected_at"],
            "item_count": payload["item_count"],
            "items_json": str(Path("data") / "runs" / self.run_id / "items.json"),
        })
        index_path.write_text(json.dumps(index, ensure_ascii=False, indent=2), encoding="utf-8")
