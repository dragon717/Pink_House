#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""`sources.yaml` 的严格子集加载器。

设计上刻意**不**引入 PyYAML：
  * 运维 Mac 上不应因为少一个第三方包就阻塞发布；
  * 更重要的是，一个「看不懂就报错」的严格解析器比「尽力猜测」的通用解析器
    更适合权限配置——权限配置被误解的代价是把未授权内容发出去。

支持的语法子集（超出即报错，绝不静默忽略）：
  * 整行注释：以 `#` 开头的行
  * 映射：`key:` 或无值的 `key: value`
  * 列表：`- ` 起始；元素为标量，或内联键值对 + 后续缩进的键值对
  * 字符串 / 整数 / 布尔 / 空列表 `[]`
"""

from __future__ import annotations

from pathlib import Path
from typing import Any, Dict, List, Tuple

class SourcesConfigError(Exception):
    """配置文件不合法。宁可中止发布，也不猜测运维的意图。"""


def _parse_scalar(raw: str) -> Any:
    value = raw.strip()
    if value == "[]":
        return []
    if value == "{}":
        return {}
    if value in ("true", "false"):
        return value == "true"
    if value in ("null", "~"):
        return None
    if value.startswith('"') and value.endswith('"') and len(value) >= 2:
        return value[1:-1]
    if value.startswith("'") and value.endswith("'") and len(value) >= 2:
        return value[1:-1]
    if " #" in value:
        raise SourcesConfigError(
            "标量值中不允许行尾注释：{!r}。请把注释单独放一行。".format(raw)
        )
    if value.lstrip("-").isdigit():
        return int(value)
    return value


def _indent_of(line: str) -> int:
    return len(line) - len(line.lstrip(" "))


def _prepare(text: str) -> List[Tuple[int, str]]:
    rows: List[Tuple[int, str]] = []
    for number, raw_line in enumerate(text.splitlines(), start=1):
        if "\t" in raw_line:
            raise SourcesConfigError("第 {} 行含制表符，请统一使用空格缩进".format(number))
        stripped = raw_line.strip()
        if not stripped or stripped.startswith("#"):
            continue
        rows.append((_indent_of(raw_line), stripped))
    return rows


def _parse_child(
    rows: List[Tuple[int, str]], index: int, parent_indent: int
) -> Tuple[Any, int]:
    """解析 `key:` 之后更深一层的子块。

    子块缩进取**下一行的实际缩进**，不假设固定步长（2 空格与 4 空格都能读）。
    """
    if index >= len(rows):
        return {}, index
    child_indent = rows[index][0]
    if child_indent <= parent_indent:
        raise SourcesConfigError("`key:` 之后缺少缩进子块")
    return _parse_block(rows, index, child_indent)


def _parse_block(rows: List[Tuple[int, str]], index: int, indent: int) -> Tuple[Any, int]:
    if index >= len(rows):
        return {}, index
    is_list = rows[index][1].startswith("- ")
    container: Any = [] if is_list else {}

    while index < len(rows):
        current_indent, text = rows[index]
        if current_indent < indent:
            break
        if current_indent > indent:
            raise SourcesConfigError("缩进层级意外加深：{!r}".format(text))

        if is_list:
            if not text.startswith("- "):
                raise SourcesConfigError("列表中混入了非列表项：{!r}".format(text))
            item_text = text[2:].strip()
            if not item_text:
                index += 1
                value, index = _parse_child(rows, index, current_indent)
                container.append(value)
                continue
            if ":" in item_text and not item_text.startswith("http"):
                key, _, raw_value = item_text.partition(":")
                item: Dict[str, Any] = {}
                raw_value = raw_value.strip()
                if raw_value:
                    item[key.strip()] = _parse_scalar(raw_value)
                    index += 1
                else:
                    index += 1
                    nested, index = _parse_child(rows, index, current_indent)
                    item[key.strip()] = nested
                    container.append(item)
                    continue
                # 继续吃掉属于同一列表项的更深缩进键值对
                while index < len(rows) and rows[index][0] > current_indent:
                    sub_indent, sub_text = rows[index]
                    if sub_text.startswith("- "):
                        raise SourcesConfigError(
                            "列表项内部不支持嵌套列表：{!r}".format(sub_text)
                        )
                    sub_key, _, sub_raw = sub_text.partition(":")
                    if not sub_key:
                        raise SourcesConfigError("无法解析：{!r}".format(sub_text))
                    sub_raw = sub_raw.strip()
                    if sub_raw:
                        item[sub_key.strip()] = _parse_scalar(sub_raw)
                        index += 1
                    else:
                        index += 1
                        nested, index = _parse_child(rows, index, sub_indent)
                        item[sub_key.strip()] = nested
                container.append(item)
                continue
            container.append(_parse_scalar(item_text))
            index += 1
            continue

        if text.startswith("- "):
            raise SourcesConfigError("映射中混入了列表项：{!r}".format(text))
        key, separator, raw_value = text.partition(":")
        if not separator:
            raise SourcesConfigError("无法解析：{!r}".format(text))
        key = key.strip()
        raw_value = raw_value.strip()
        if raw_value:
            container[key] = _parse_scalar(raw_value)
            index += 1
        else:
            index += 1
            value, index = _parse_child(rows, index, current_indent)
            container[key] = value
    return container, index


def load_sources(path: Path) -> Dict[str, Any]:
    text = Path(path).read_text(encoding="utf-8")
    rows = _prepare(text)
    if not rows:
        raise SourcesConfigError("配置文件为空：{}".format(path))
    value, index = _parse_block(rows, 0, rows[0][0])
    if index != len(rows):
        raise SourcesConfigError("存在未能解析的残留内容，请检查缩进")
    if not isinstance(value, dict):
        raise SourcesConfigError("配置文件顶层必须是映射")
    return value


def approved_brands(config: Dict[str, Any]) -> List[Dict[str, Any]]:
    """筛出**已批准**的来源。

    默认禁止：permissionStatus 只要不是精确的 `approved`，一律排除；
    allowedContentTypes 为空的来源也排除（批准了也不代表批准了全部内容类型）。
    """
    result: List[Dict[str, Any]] = []
    for brand in config.get("brands") or []:
        if not isinstance(brand, dict):
            continue
        if brand.get("permissionStatus") != "approved":
            continue
        if not (brand.get("allowedContentTypes") or []):
            continue
        result.append(brand)
    return result


def rejected_summary(config: Dict[str, Any]) -> List[str]:
    lines: List[str] = []
    for brand in config.get("brands") or []:
        if not isinstance(brand, dict):
            continue
        brand_id = str(brand.get("brandID", "?"))
        status = str(brand.get("permissionStatus", "missing"))
        if status != "approved":
            lines.append("{}: permissionStatus={}（未批准，不发布）".format(brand_id, status))
        elif not (brand.get("allowedContentTypes") or []):
            lines.append("{}: allowedContentTypes 为空（未明确允许的内容类型，不发布）".format(brand_id))
    return lines
