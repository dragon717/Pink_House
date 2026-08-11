#!/usr/bin/env python3
"""Generate bundled Simplified Chinese product descriptions with Apple Translation."""

from __future__ import annotations

import argparse
import json
import os
import subprocess
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path


PROJ = Path(__file__).resolve().parents[2]
CATALOG_DIR = PROJ / "ItemManager" / "Resources" / "TimeHall"
CATALOGS = {
    "angelic-pretty": "catalog-angelic-pretty.json",
    "baby": "catalog-baby-stars-shine-bright.json",
    "juliette": "catalog-juliette-et-justine.json",
    "wunderwelt": "catalog-wunderwelt-fleur.json",
}
TRANSLATOR = Path(__file__).with_suffix(".swift")


def normalize_translation(text: str) -> str:
    return (
        text.replace("[比赛]", "[蕾丝]")
        .replace("布鲁玛", "南瓜裤")
        .replace("宽（100%棉）", "平纹棉布（100%棉）")
    )


def translate_batch(label: str, pending: list[dict[str, str]]) -> dict[str, str]:
    process = subprocess.Popen(
        ["xcrun", "swift", str(TRANSLATOR)],
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        env=os.environ.copy(),
    )
    assert process.stdin is not None and process.stdout is not None
    process.stdin.write(
        "".join(json.dumps(item, ensure_ascii=False) + "\n" for item in pending)
    )
    process.stdin.close()
    translated: dict[str, str] = {}
    for line in process.stdout:
        value = json.loads(line)
        translated[value["id"]] = normalize_translation(value["text"])
        if len(translated) % 100 == 0:
            print(f"{label}: {len(translated)}/{len(pending)} translated", flush=True)
    stderr = process.stderr.read() if process.stderr is not None else ""
    if process.wait() != 0:
        raise RuntimeError(stderr.strip() or f"{label}: translator failed")
    if len(translated) != len(pending):
        raise RuntimeError(f"{label}: translated {len(translated)} of {len(pending)}")
    if len(translated) % 100:
        print(f"{label}: {len(translated)}/{len(pending)} translated", flush=True)
    return translated


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--brand", choices=["all", *CATALOGS], default="all")
    parser.add_argument("--force", action="store_true")
    parser.add_argument("--self-check", action="store_true")
    args = parser.parse_args()

    if args.self_check:
        assert TRANSLATOR.exists() and set(CATALOGS) == {
            "angelic-pretty", "baby", "juliette", "wunderwelt"
        }
        print("self-check: PASS")
        return 0

    brands = CATALOGS if args.brand == "all" else {args.brand: CATALOGS[args.brand]}
    catalogs: dict[str, dict] = {}
    pending_by_brand: dict[str, list[dict[str, str]]] = {}
    for brand, filename in brands.items():
        catalog = json.loads((CATALOG_DIR / filename).read_text(encoding="utf-8"))
        catalogs[brand] = catalog
        pending_by_brand[brand] = []
        for item in catalog["commerceItems"]:
            if item["description"] and (args.force or not item.get("descriptionZH")):
                pending_by_brand[brand].append({"id": item["id"], "text": item["description"]})

    if not any(pending_by_brand.values()):
        print("all requested descriptions are already translated")
        return 0

    translated: dict[str, str] = {}
    jobs = []
    for brand, pending in pending_by_brand.items():
        parts = [pending[index:index + 300] for index in range(0, len(pending), 300)]
        jobs.extend(
            (f"{brand} {index + 1}/{len(parts)}", part)
            for index, part in enumerate(parts)
        )
    with ThreadPoolExecutor(max_workers=min(4, len(jobs))) as executor:
        futures = {
            executor.submit(translate_batch, label, pending): label
            for label, pending in jobs
        }
        for future in as_completed(futures):
            try:
                translated.update(future.result())
            except Exception as error:
                raise SystemExit(str(error))

    for brand, filename in brands.items():
        catalog = catalogs[brand]
        for item in catalog["commerceItems"]:
            if item["id"] in translated:
                item["descriptionZH"] = translated[item["id"]]
            else:
                item.setdefault("descriptionZH", "")
        path = CATALOG_DIR / filename
        temporary = path.with_suffix(".json.tmp")
        temporary.write_text(
            json.dumps(catalog, ensure_ascii=False, indent=2) + "\n",
            encoding="utf-8",
        )
        temporary.replace(path)
        print(f"{brand}: descriptions updated")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
