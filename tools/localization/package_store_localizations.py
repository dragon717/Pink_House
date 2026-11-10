"""Package the nine store localizations with the release team's verified gallery."""

import argparse
import csv
import io
import json
import re
from pathlib import Path
from tempfile import TemporaryDirectory
from zipfile import ZIP_DEFLATED, ZIP_STORED, ZipFile

ROOT = Path(__file__).resolve().parents[2]
SOURCES = ROOT / "docs/localization/app-store-metadata"
LOCALES = {
    "zh-Hans": "zh-Hans", "zh-Hant": "zh-Hant", "en": "en-US", "ja": "ja",
    "ko": "ko", "fr": "fr-FR", "de": "de-DE", "es": "es-ES", "pt-BR": "pt-BR",
}
LIMITS = {"Name": 30, "Subtitle": 30, "Promotional Text": 170,
          "Description": 4000, "Keywords": 100, "What's New": 4000}
URL_FIELDS = ("Support URL", "Privacy Policy URL")
SKU_IDS = [f"com.pinkhouse.app.{suffix}" for suffix in (
    "meowcoin_60", "meowcoin_120", "meowcoin_300", "meowcoin_500", "mcoin_1280", "mcoin_3280"
)]


def read_page(language):
    source = (SOURCES / language / "metadata.md").read_text(encoding="utf-8")
    if f"ASC locale `{LOCALES[language]}`" not in source:
        raise ValueError(f"{language}: unexpected ASC locale")
    contents = re.split(r"^## (.+)$", source, flags=re.MULTILINE)
    sections = {heading: body.strip() for heading, body in zip(contents[1::2], contents[2::2])}
    table = dict(re.findall(r"^\| \*\*(.+?)\*\* \| (.+?) \|$", sections["App Information"], re.M))
    page = {}
    for field, limit in LIMITS.items():
        text = (table | sections)[field]
        size = len(text.encode("utf-8")) if field == "Keywords" else len(text)
        if not (0 < size <= limit):
            raise ValueError(f"{language}: invalid {field} length {size}")
        page[field] = text
    return page, {field: table[field] for field in URL_FIELDS}


def read_products():
    source = (SOURCES / "iap-localizations.md").read_text(encoding="utf-8")
    products = {language: {} for language in LOCALES}
    blocks = re.findall(r"^## (com\.[\w.]+)[^\n]*\n(.*?)(?=^## |\Z)", source, re.M | re.S)
    for sku, body in blocks:
        for language, name, description in re.findall(r"^\| ([\w-]+) \| ([^|]+?) \| ([^|]+?) \|$", body, re.M):
            if language == "Locale":
                continue
            if sku in products[language] or not (2 <= len(name) <= 30 and 0 < len(description) <= 45):
                raise ValueError(f"{language}: invalid or duplicate product entry for {sku}")
            products[language][sku] = {"Display Name": name, "Description": description}
    for language, records in products.items():
        if set(records) != set(SKU_IDS):
            raise ValueError(f"{language}: missing or unexpected product IDs")
    return products


def package(release_dir):
    gallery_path = release_dir / "少女心愿-4.4-商店截图.zip"
    output = release_dir / "少女心愿-4.4-九语商店资料.zip"
    products = read_products()
    all_data = {}
    with TemporaryDirectory(dir=release_dir) as work:
        archive = Path(work) / output.name
        with ZipFile(archive, "w", compression=ZIP_DEFLATED) as out, ZipFile(gallery_path) as gallery:
            for language, locale in LOCALES.items():
                page, urls = read_page(language)
                all_data[locale] = {"storeFields": page, "inAppPurchases": products[language],
                                    "urlsPendingVerification": urls}
                for field, value in page.items():
                    out.writestr(f"{locale}/商品页/{field}.txt", value)
                buffer = io.StringIO(newline="")
                writer = csv.writer(buffer)
                writer.writerow(["Product ID", "Display Name", "Description"])
                for sku in SKU_IDS:
                    entry = products[language][sku]
                    writer.writerow([sku, entry["Display Name"], entry["Description"]])
                out.writestr(f"{locale}/喵币内购.csv", buffer.getvalue().encode("utf-8-sig"))
            expected = {f"{language}/{device}/{scene}.png" for language in ("en", "zh-Hans", "zh-Hant")
                        for device in ("iphone12", "iphone17pro", "iphone17promax", "ipad13")
                        for scene in ("01-wardrobe", "02-payments", "03-stats")}
            optional = {f"{language}/{image}" for language in ("zh-Hans", "zh-Hant", "en")
                        for image in ("duo-inner-landscape/02-open-wardrobe.png", "duo-outer/01-wardrobe.png",
                                      "duo-outer/03-dress-details.png")}
            optional.add("zh-Hans/duo-outer/04-daily-colors.png")
            names = gallery.namelist()
            if len(set(names)) != len(names) or not expected <= set(names) <= expected | optional:
                raise ValueError("Screenshot archive differs from the approved release gallery")
            for source in sorted(names):
                language, relative = source.split("/", 1)
                out.writestr(f"{LOCALES[language]}/截图/{relative}", gallery.read(source), compress_type=ZIP_STORED)
            out.writestr("九语字段.json", json.dumps(all_data, indent=2, ensure_ascii=False) + "\n")
            out.writestr("录入说明.txt", """少女心愿 4.4 · App ID 6758352161

1. 选择与文件夹名称一致的 App Store Connect 语言。在「App 信息」录入 Name 和 Subtitle，在 iOS 4.4 版本页录入 Description、Keywords、What's New 和 Promotional Text（选填）。每个 TXT 只含该字段的可粘贴内容。简中有线上版本，保存前比对已有文案。
2. 六个消耗型内购按 CSV 的完整 Product ID 核对。保留后台原有的简体中文名称及描述。其他语言只填缺少的条目，已在审核的条目等待 Apple 处理。各档最新后台进度见仓库 docs/localization/runs/2026-11-03/RESULT.md。
3. 简中、繁中和美国英语的原生商品图在各自的「截图」目录。Duo 外屏和展开内屏的图片上传至同一个 iPhone Duo 栏位。其他图片按设备、编号上传。日、韩、法、德、西班牙语（西班牙）和巴西葡语使用主语言截图继承方案。已有本地化须在媒体管理器核对实际引用的截图；新建语言会默认继承主语言截图。保存后检查各槽位，不要把继承图片标记为该语言原生图。
4. 支持和隐私网址单列在 JSON 的 urlsPendingVerification 中，留到网站验证阶段。此包只供填报，最终提交状态以后台为准。

Apple 本地化说明 https://developer.apple.com/help/app-store-connect/manage-app-information/localize-app-information/
""")
        with ZipFile(archive) as built:
            if built.testzip() is not None:
                raise ValueError("Output archive failed its integrity check")
        archive.replace(output)
    return output


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("release_dir", type=Path)
    print(package(parser.parse_args().release_dir))
