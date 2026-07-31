# Time Hall news scraper

Crawl `https://pinkhouse-webshop.jp/pinkhouse/news` into local Bundle catalog for 梦裙时光馆.

```bash
PROJ="/Users/muniao/Library/Mobile Documents/com~apple~CloudDocs/游戏/github/Pink_House"
cd "$PROJ"
python3 -u tools/time_hall/scrape_pinkhouse_news.py
```

Writes:

- `ItemManager/Resources/TimeHall/catalog.json`
- `ItemManager/Resources/TimeHall/images/news_<id>_*.jpg`
- `tools/time_hall/_artifacts/` (logs / id cache; gitignored)

Hand-curated archive-print dresses are preserved via `catalog.curated.json`.
