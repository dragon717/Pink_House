#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""时光馆发布协议共享实现。

对应 docs/Pink_House_TimeHall_Static_CloudKit_Design.md §4 / §5 / §6。

本模块只做「协议」与「纯函数校验」，不做网络与磁盘副作用，
以便 build / validate / publish / verify / rollback 五步共用同一套判定。

硬约定：
  * canonicalEntityID = brandID / entityType / stableSourceID
  * stableSourceID 沿用现有 catalog 里的实体 `id`（`news-<officialID>` 等），
    因此旧收藏 `timeHall.treasured.v1` 里的 ID 无需迁移。
  * payloadHash = 压缩文件的 SHA-256（客户端比对的是压缩字节，不是解压后内容）。
  * 传输包内只有纯数据，不含脚本或可执行表达式。
"""

from __future__ import annotations

import gzip
import hashlib
import json
import re
from typing import Any, Dict, Iterable, List, Optional, Sequence, Tuple

PROTOCOL_SCHEMA_VERSION = 1
READER_VERSION = 1

RELEASE_RECORD_NAME = "th.release.catalog-v1"
RECORD_TYPE_RELEASE = "THRelease"
RECORD_TYPE_DATA_PACK = "THDataPack"
RECORD_TYPE_MEDIA = "THMedia"

ENCODING_JSON_GZIP = "json+gzip"
ENCODING_JSON_PLAIN = "json"

COVERAGE_COMPLETE = "complete"
COVERAGE_EMPTY = "empty"
COVERAGE_PARTIAL = "partial"
COVERAGE_UNKNOWN = "unknown"
COVERAGE_NOT_SUPPORTED = "notSupported"
COVERAGE_WITHDRAWN = "withdrawn"

COVERAGE_STATUSES = {
    COVERAGE_COMPLETE,
    COVERAGE_EMPTY,
    COVERAGE_PARTIAL,
    COVERAGE_UNKNOWN,
    COVERAGE_NOT_SUPPORTED,
    COVERAGE_WITHDRAWN,
}

# 「已得出确定结论」的覆盖状态：不再循环补拉
COVERAGE_CONCLUSIVE = {
    COVERAGE_COMPLETE,
    COVERAGE_EMPTY,
    COVERAGE_NOT_SUPPORTED,
    COVERAGE_WITHDRAWN,
}

SOURCE_COVERAGES = {"currentlyEnumerable", "curatedSelection", "historicalComplete"}

# ---------------------------------------------------------------- 商店目录分片
#
# 「店家上新 / 公共 Catalog」（时光馆「商店」内容）走**整包单分片**：
#   · entityType 固定为 `shop-catalog`，一个分片承载**合并后的完整目录**
#     （shops/series/products/variants/sizeCharts/saleEvents/assets/styleProfiles
#       + 三组删除墓碑），不按实体类型拆包；
#   · 不拆包的原因：「商品 → 系列 → 店家」「规格/销售记录/尺码表 → 商品」是强引用，
#     拆包会让引用跨包悬空、客户端必须一次取齐 8 个包才能渲染；
#   · 载荷键为 `shopCatalog`（TimeHall 分片是 `records`），校验走本节专用函数，
#     **禁止**与 TimeHall 实体机制混用（两边的日期口径、引用规则都不同）；
#   · brandID 用运营自有内容源标识（`shaonv-xinyuan`），**不与画册品牌共用**：
#     根清单 brands 按 brandID 去重，共用会让两边同时发布时报重复品牌。
SHOP_CATALOG_ENTITY_TYPE = "shop-catalog"
SHOP_CATALOG_SCOPE = "all"

SHOP_CATALOG_ENTITY_FIELDS: Tuple[str, ...] = (
    "shops",
    "series",
    "products",
    "variants",
    "sizeCharts",
    "saleEvents",
    "assets",
    "styleProfiles",
)
SHOP_CATALOG_TOMBSTONE_FIELDS: Tuple[str, ...] = (
    "removedShopIDs",
    "removedSeriesIDs",
    "removedProductIDs",
)
SHOP_CATALOG_ALL_FIELDS: Tuple[str, ...] = (
    SHOP_CATALOG_ENTITY_FIELDS + SHOP_CATALOG_TOMBSTONE_FIELDS
)

# canonicalEntityID 第二段（撤回清单与客户端身份映射用）。与 TimeHall 的
# ENTITY_TYPES 分开登记：商店实体**不**参与 TimeHall 的日期格式与引用规则。
SHOP_ENTITY_TYPES: Tuple[str, ...] = (
    "catalog-shop",
    "catalog-series",
    "catalog-product",
    "catalog-variant",
    "catalog-size-chart",
    "catalog-sale-event",
    "catalog-asset",
    "catalog-style-profile",
)
SHOP_CANONICAL_TYPE_BY_FIELD: Dict[str, str] = {
    "shops": "catalog-shop",
    "series": "catalog-series",
    "products": "catalog-product",
    "variants": "catalog-variant",
    "sizeCharts": "catalog-size-chart",
    "saleEvents": "catalog-sale-event",
    "assets": "catalog-asset",
    "styleProfiles": "catalog-style-profile",
}

SHOP_SALE_EVENT_TYPES = {"reservation", "stock", "rerelease"}
SHOP_CURRENCIES = {"CNY", "JPY", "UNKNOWN"}
SHOP_SALE_PHASES = {"reservation_active", "reservation_ended", "balance_pending", "in_stock"}
SHOP_BALANCE_DUE_KINDS = {"approximate", "exact"}


# entityType -> catalog 中的数组字段
ENTITY_FIELD: Dict[str, str] = {
    "event": "events",
    "commerce-product": "commerceItems",
    "commerce-snapshot": "commerceSnapshots",
    "catalogue": "catalogues",
    "archive-catalogue": "archiveCatalogues",
    "item": "items",
    "coordinate": "coordinates",
    "story": "stories",
    "history-entry": "historyEntries",
}

ENTITY_TYPES = tuple(ENTITY_FIELD.keys())

# 每类实体自身的日期字段，用于校验与覆盖边界
ENTITY_DATE_FIELD: Dict[str, str] = {
    "event": "publishedOn",
    "commerce-product": "observedAt",
    "commerce-snapshot": "observedAt",
    "item": "observedAt",
    "coordinate": "observedAt",
    "story": "publishedOn",
    "history-entry": "observedAt",
}

ISO_DATE_RE = re.compile(r"^\d{4}-\d{2}-\d{2}$")
SHA256_HEX_RE = re.compile(r"^[0-9a-f]{64}$")
PARTITION_ID_RE = re.compile(r"^[a-z0-9][a-z0-9._-]*(/[a-z0-9][a-z0-9._-]*){2,}$")

# 单个数据包的上限，与客户端 TimeHallCacheLimits 保持一致（客户端另有硬上限）
MAX_PACK_COMPRESSED_BYTES = 16 * 1024 * 1024
MAX_PACK_UNCOMPRESSED_BYTES = 64 * 1024 * 1024


class ProtocolError(Exception):
    """协议级错误：产物不符合客户端与服务端共同遵守的契约。"""


# ---------------------------------------------------------------- 规范化


def canonical_json_bytes(value: Any) -> bytes:
    """确定性 JSON 字节。

    哈希必须落在「确定的原始字节」上，不能由不同语言各自拼 JSON 再签（§12.3）。
    因此排序键、固定分隔符、UTF-8、不转义非 ASCII。
    """
    return json.dumps(
        value, sort_keys=True, separators=(",", ":"), ensure_ascii=False
    ).encode("utf-8")


def sha256_hex(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def gzip_bytes(data: bytes) -> bytes:
    """确定性 gzip：mtime 固定为 0，避免同一内容产出不同字节、进而 hash 漂移。"""
    return gzip.compress(data, compresslevel=9, mtime=0)


def pack_record_name(payload_hash: str) -> str:
    return "th.pack.{}".format(payload_hash)


def media_record_name(content_hash: str) -> str:
    return "th.media.{}".format(content_hash)


def canonical_entity_id(brand_id: str, entity_type: str, stable_source_id: str) -> str:
    return "{}/{}/{}".format(brand_id, entity_type, stable_source_id)


def is_canonical_entity_id(value: str) -> bool:
    parts = value.split("/")
    if len(parts) != 3 or not all(parts):
        return False
    return parts[1] in ENTITY_TYPES or parts[1] in SHOP_ENTITY_TYPES


def partition_id(brand_id: str, entity_type: str, scope_key: str) -> str:
    return "{}/{}/{}".format(brand_id, entity_type, scope_key)


def is_safe_partition_id(value: str) -> bool:
    if ".." in value or value.startswith("/") or value.endswith("/"):
        return False
    return bool(PARTITION_ID_RE.match(value))


# ---------------------------------------------------------------- 实体抽取


def entity_records(catalog: Dict[str, Any], entity_type: str) -> List[Dict[str, Any]]:
    field = ENTITY_FIELD.get(entity_type)
    if field is None:
        return []
    values = catalog.get(field)
    if not isinstance(values, list):
        return []
    return [item for item in values if isinstance(item, dict)]


def timeline_years(catalog: Dict[str, Any]) -> List[Dict[str, Any]]:
    values = catalog.get("timelineYears")
    return [item for item in values if isinstance(item, dict)] if isinstance(values, list) else []


def entity_stable_ids(records: Sequence[Dict[str, Any]]) -> List[str]:
    return [str(record.get("id", "")) for record in records]


# ---------------------------------------------------------------- 校验


def _issue(code: str, message: str, entity_id: Optional[str] = None) -> Dict[str, str]:
    issue: Dict[str, str] = {"code": code, "message": message}
    if entity_id:
        issue["entityID"] = entity_id
    return issue


def validate_fragment(
    fragment: Dict[str, Any],
    brand_id: str,
    entity_type: str,
    coverage_status: str,
) -> List[Dict[str, str]]:
    """通用结构校验（与客户端 `validateStructural` 对应）。

    分片独立、与品牌数据集规则无关：多品牌、每日空结果、云端增量包都要能过。
    """
    issues: List[Dict[str, str]] = []
    if not brand_id:
        issues.append(_issue("brandID.empty", "brandID 不得为空"))

    own_records = entity_records(fragment, entity_type)
    extras = sum(
        len(entity_records(fragment, other))
        for other in ENTITY_TYPES
        if other != entity_type
    )
    total = len(own_records) + extras + len(timeline_years(fragment))

    if coverage_status == COVERAGE_EMPTY and total:
        issues.append(_issue("empty.notEmpty", "覆盖状态为 empty 的数据包不得携带任何条目"))
    if coverage_status in (COVERAGE_COMPLETE, COVERAGE_PARTIAL) and total == 0:
        issues.append(_issue("records.empty", "覆盖状态为 {} 的数据包不得为空".format(coverage_status)))

    # ID 非空与唯一
    for other in ENTITY_TYPES:
        ids = entity_stable_ids(entity_records(fragment, other))
        for value in ids:
            if not value:
                issues.append(_issue("{}.id.empty".format(other), "{} 存在空 ID".format(other)))
        seen = set()
        for value in ids:
            if value in seen:
                issues.append(
                    _issue("{}.id.duplicate".format(other), "{} 存在重复 ID".format(other), value)
                )
            seen.add(value)

    # canonical ID 规范与唯一
    canonical: List[str] = []
    for other in ENTITY_TYPES:
        for value in entity_stable_ids(entity_records(fragment, other)):
            canonical.append(canonical_entity_id(brand_id, other, value))
    for value in canonical:
        if not is_canonical_entity_id(value):
            issues.append(_issue("canonicalID.invalid", "canonical ID 不符合规范"))
            break
    duplicates = sorted({value for value in canonical if canonical.count(value) > 1})
    for value in duplicates[:5]:
        issues.append(_issue("canonicalID.duplicate", "canonical ID 重复", value))

    # 日期格式
    for other, field_name in ENTITY_DATE_FIELD.items():
        for record in entity_records(fragment, other):
            value = record.get(field_name)
            if isinstance(value, str) and value and not ISO_DATE_RE.match(value):
                issues.append(
                    _issue(
                        "{}.{}".format(other, field_name),
                        "{} 必须是 yyyy-MM-dd".format(field_name),
                        str(record.get("id", "")),
                    )
                )

    # 引用完整性：**包内可解析的引用**不得悬空（§18.1 D09）。
    #
    # 分片拆包后，被引用的实体可能在另一个包里（§6.7）。因此只有当被引用类型
    # 也出现在本包中时才要求引用闭合；跨包引用由根清单的 dependencyPackRecordNames
    # 声明，不在这里误判为损坏数据。跨包引用由 validate_release_references 整体校验。
    commerce_ids = {str(r.get("id", "")) for r in entity_records(fragment, "commerce-product")}
    if commerce_ids:
        for other in ("event", "story", "coordinate"):
            for record in entity_records(fragment, other):
                for linked in record.get("linkedCommerceItemIDs") or []:
                    if linked not in commerce_ids:
                        issues.append(
                            _issue(
                                "{}.linkedCommerceItem.dangling".format(other),
                                "引用了包内不存在的商品 {}".format(linked),
                                str(record.get("id", "")),
                            )
                        )
    catalogue_ids = {str(r.get("id", "")) for r in entity_records(fragment, "catalogue")}
    if catalogue_ids:
        for record in entity_records(fragment, "item"):
            catalogue_id = record.get("catalogueID")
            if catalogue_id not in catalogue_ids:
                issues.append(
                    _issue(
                        "item.catalogueID.dangling",
                        "引用了包内不存在的目录 {}".format(catalogue_id),
                        str(record.get("id", "")),
                    )
                )
    archive_ids = {str(r.get("id", "")) for r in entity_records(fragment, "archive-catalogue")}
    if archive_ids:
        for record in timeline_years(fragment):
            for catalogue_id in record.get("catalogueIDs") or []:
                if catalogue_id not in archive_ids:
                    issues.append(
                        _issue(
                            "timelineYear.catalogueID.dangling",
                            "引用了包内不存在的官方目录 {}".format(catalogue_id),
                            str(record.get("year", "")),
                        )
                    )
    return issues


def validate_release_references(
    packs: Sequence[Tuple[Dict[str, Any], Dict[str, Any]]]
) -> List[Dict[str, str]]:
    """整份发布的跨包引用与唯一性校验。

    单包校验只能看到包内；拆包之后，
    「同品番跨品牌被合并」「同一实体出现在两个包里」这类问题只有全局视角才能发现。
    """
    issues: List[Dict[str, str]] = []
    commerce_ids: set = set()
    catalogue_ids: set = set()
    archive_ids: set = set()
    owner: Dict[str, str] = {}

    for descriptor, payload in packs:
        records = payload.get("records") or {}
        pid = str(descriptor.get("partitionID", ""))
        for entity_type in ENTITY_TYPES:
            for record in entity_records(records, entity_type):
                stable_id = str(record.get("id", ""))
                key = "{}/{}".format(entity_type, stable_id)
                if key in owner and owner[key] != pid:
                    issues.append(
                        _issue(
                            "entity.duplicateAcrossPacks",
                            "同一实体出现在两个分片中：{} 与 {}".format(owner[key], pid),
                            stable_id,
                        )
                    )
                owner[key] = pid
        commerce_ids |= {str(r.get("id", "")) for r in entity_records(records, "commerce-product")}
        catalogue_ids |= {str(r.get("id", "")) for r in entity_records(records, "catalogue")}
        archive_ids |= {str(r.get("id", "")) for r in entity_records(records, "archive-catalogue")}

    for descriptor, payload in packs:
        records = payload.get("records") or {}
        for other in ("event", "story", "coordinate"):
            for record in entity_records(records, other):
                for linked in record.get("linkedCommerceItemIDs") or []:
                    if linked not in commerce_ids:
                        issues.append(
                            _issue(
                                "{}.linkedCommerceItem.unresolved".format(other),
                                "全量发布视图里仍找不到被引用商品 {}".format(linked),
                                str(record.get("id", "")),
                            )
                        )
        for record in entity_records(records, "item"):
            catalogue_id = record.get("catalogueID")
            if catalogue_ids and catalogue_id not in catalogue_ids:
                issues.append(
                    _issue(
                        "item.catalogueID.unresolved",
                        "全量发布视图里仍找不到被引用目录 {}".format(catalogue_id),
                        str(record.get("id", "")),
                    )
                )
        for record in timeline_years(records):
            for catalogue_id in record.get("catalogueIDs") or []:
                if archive_ids and catalogue_id not in archive_ids:
                    issues.append(
                        _issue(
                            "timelineYear.catalogueID.unresolved",
                            "全量发布视图里仍找不到被引用官方目录 {}".format(catalogue_id),
                            str(record.get("year", "")),
                        )
                    )
    return issues


def validate_partition_descriptor(
    descriptor: Dict[str, Any],
    payload: Dict[str, Any],
    compressed_bytes: int,
    uncompressed_bytes: int,
) -> List[Dict[str, str]]:
    """分片契约校验（与客户端 `validatePartition` 对应）。"""
    issues: List[Dict[str, str]] = []
    pid = str(descriptor.get("partitionID", ""))
    brand_id = str(descriptor.get("brandID", ""))
    entity_type = str(descriptor.get("entityType", ""))
    coverage = str(descriptor.get("coverageStatus", ""))

    if not is_safe_partition_id(pid):
        issues.append(_issue("partitionID.unsafe", "分片 ID 含非法字符或路径穿越片段"))
    elif pid.split("/")[0] != brand_id or pid.split("/")[1] != entity_type:
        issues.append(_issue("partitionID.mismatch", "分片 ID 的品牌或实体类型段与声明不一致"))

    if not brand_id:
        issues.append(_issue("brandID.empty", "分片必须声明 brandID"))
    if entity_type not in ENTITY_TYPES and entity_type != SHOP_CATALOG_ENTITY_TYPE:
        issues.append(_issue("entityType.invalid", "未知实体类型 {}".format(entity_type)))
    if coverage not in COVERAGE_STATUSES:
        issues.append(_issue("coverageStatus.invalid", "未知覆盖状态 {}".format(coverage)))

    revision = descriptor.get("partitionRevision")
    if not isinstance(revision, int) or revision <= 0:
        issues.append(_issue("partitionRevision.invalid", "分片修订号必须为正整数"))

    if not SHA256_HEX_RE.match(str(descriptor.get("payloadHash", ""))):
        issues.append(_issue("payloadHash.invalid", "payloadHash 必须是 64 位小写十六进制 SHA-256"))
    if not descriptor.get("packRecordName"):
        issues.append(_issue("packRecordName.empty", "分片必须指向数据包 Record ID"))

    # 有效结论必须带检查时间
    if coverage in (COVERAGE_COMPLETE, COVERAGE_EMPTY) and not str(
        descriptor.get("checkedThrough") or ""
    ).strip():
        issues.append(_issue("checkedThrough.missing", "{} 必须声明 checkedThrough".format(coverage)))

    for day_key, status in (descriptor.get("dayCoverage") or {}).items():
        if not ISO_DATE_RE.match(str(day_key)):
            issues.append(_issue("dayCoverage.key", "日覆盖键必须是 yyyy-MM-dd：{}".format(day_key)))
        if status not in COVERAGE_STATUSES:
            issues.append(_issue("dayCoverage.status", "未知日覆盖状态 {}".format(status)))

    # 负载自洽
    if payload.get("partitionID") != pid:
        issues.append(_issue("payload.mismatch", "数据包负载声明的分片与根清单描述不一致"))
    if payload.get("brandID") != brand_id or payload.get("entityType") != entity_type:
        issues.append(_issue("payload.mismatch", "数据包负载的品牌或实体类型与根清单不一致"))
    if payload.get("partitionRevision") != revision:
        issues.append(_issue("payload.mismatch", "数据包负载的修订号与根清单不一致"))

    # 数量一致性
    records = payload.get("records") or {}
    if entity_type == SHOP_CATALOG_ENTITY_TYPE:
        own_count = shop_catalog_entity_count(payload.get("shopCatalog"))
    else:
        own_count = len(entity_records(records, entity_type))
    declared_count = descriptor.get("recordCount")
    if not isinstance(declared_count, int) or declared_count < 0:
        issues.append(_issue("recordCount.invalid", "recordCount 不得为负"))
    elif coverage == COVERAGE_COMPLETE and own_count != declared_count:
        issues.append(
            _issue(
                "recordCount.mismatch",
                "complete 分片声明 {} 条，实际 {} 条".format(declared_count, own_count),
            )
        )
    elif coverage == COVERAGE_EMPTY and own_count != 0:
        issues.append(_issue("recordCount.empty", "empty 分片不得携带条目"))
    elif coverage in (COVERAGE_PARTIAL, COVERAGE_UNKNOWN) and own_count > declared_count:
        issues.append(_issue("recordCount.overflow", "实际条目多于声明数量"))

    # 体积上限
    if compressed_bytes <= 0:
        issues.append(_issue("bytes.compressed", "压缩后字节数必须大于 0"))
    if compressed_bytes > MAX_PACK_COMPRESSED_BYTES:
        issues.append(
            _issue("bytes.compressedTooLarge", "压缩后超出上限 {}".format(MAX_PACK_COMPRESSED_BYTES))
        )
    if uncompressed_bytes <= 0:
        issues.append(_issue("bytes.uncompressed", "解压后字节数必须大于 0"))
    if uncompressed_bytes > MAX_PACK_UNCOMPRESSED_BYTES:
        issues.append(
            _issue(
                "bytes.uncompressedTooLarge",
                "解压后超出上限 {}".format(MAX_PACK_UNCOMPRESSED_BYTES),
            )
        )
    return issues


def validate_root_index(root_index: Dict[str, Any], expect_release_seq: Optional[int] = None) -> List[Dict[str, str]]:
    issues: List[Dict[str, str]] = []
    if root_index.get("schemaVersion") != PROTOCOL_SCHEMA_VERSION:
        issues.append(_issue("schemaVersion", "根清单 schemaVersion 不受支持"))
    seq = root_index.get("releaseSeq")
    if not isinstance(seq, int) or seq <= 0:
        issues.append(_issue("releaseSeq", "releaseSeq 必须为正整数"))
    elif expect_release_seq is not None and seq != expect_release_seq:
        issues.append(_issue("releaseSeq.mismatch", "根清单序号与发布头不一致"))

    brands = root_index.get("brands") or []
    partitions = root_index.get("partitions") or []
    brand_ids = [str(b.get("brandID", "")) for b in brands]
    if len(set(brand_ids)) != len(brand_ids):
        issues.append(_issue("brand.duplicate", "根清单存在重复品牌"))
    for brand in brands:
        if str(brand.get("sourceCoverage", "")) not in SOURCE_COVERAGES:
            issues.append(_issue("sourceCoverage.invalid", "未知来源覆盖类型"))
        if not str(brand.get("coverageDescription", "")).strip():
            issues.append(
                _issue("coverageDescription.empty", "品牌必须给出对用户可理解的范围说明（§5.3）")
            )
        if not str(brand.get("sourceTimeZone", "")).strip():
            issues.append(_issue("sourceTimeZone.empty", "品牌必须显式配置来源业务时区"))

    partition_ids = [str(p.get("partitionID", "")) for p in partitions]
    if len(set(partition_ids)) != len(partition_ids):
        issues.append(_issue("partition.duplicate", "根清单存在重复分片"))

    known_packs = {str(p.get("packRecordName", "")) for p in partitions}
    for partition in partitions:
        for dependency in partition.get("dependencyPackRecordNames") or []:
            if dependency not in known_packs:
                issues.append(
                    _issue("dependency.missing", "分片声明了根清单中不存在的依赖包 {}".format(dependency))
                )

    for withdrawal in root_index.get("withdrawals") or []:
        entity_id = str(withdrawal.get("canonicalEntityID", ""))
        media_hashes = withdrawal.get("mediaHashes") or []
        if not is_canonical_entity_id(entity_id) and not media_hashes:
            issues.append(_issue("withdrawal.invalid", "撤回条目必须给出合法 canonical ID 或媒体 hash"))
    return issues


# ---------------------------------------------------------------- 覆盖计算


def compute_checked_through(catalog: Dict[str, Any], entity_type: str) -> Optional[str]:
    """该实体类型的真实检查上界 = 已有条目 observedAt 的最大值。

    绝不把「生成时间」当作检查时间，也不推测覆盖今天。
    目录类 DTO 没有 observedAt，返回 None。
    """
    field_name = "observedAt"
    records = entity_records(catalog, entity_type)
    values = [
        str(record.get(field_name))
        for record in records
        if isinstance(record.get(field_name), str) and ISO_DATE_RE.match(str(record.get(field_name)))
    ]
    if not values:
        return None
    return max(values) + "T00:00:00Z"


def entity_count(catalog: Dict[str, Any], entity_type: str) -> int:
    return len(entity_records(catalog, entity_type))


def fragment_for(catalog: Dict[str, Any], entity_type: str, include_timeline_years: bool = False) -> Dict[str, Any]:
    """从整馆 catalog 中切出某实体类型的分片内容。

    `timelineYears` 是年度卡片，随归档类分片一起走；
    只在归档分片非空时附带，避免被塞进 `empty` 分片而触发结构校验失败。
    """
    field = ENTITY_FIELD.get(entity_type)
    fragment: Dict[str, Any] = {}
    if field:
        values = catalog.get(field)
        if values:
            fragment[field] = values
    if include_timeline_years and timeline_years(catalog):
        fragment["timelineYears"] = timeline_years(catalog)
    return fragment


def all_entity_ids(catalog: Dict[str, Any]) -> Iterable[Tuple[str, str]]:
    """(entityType, stableSourceID) 全量枚举"""
    for entity_type in ENTITY_TYPES:
        for value in entity_stable_ids(entity_records(catalog, entity_type)):
            yield entity_type, value


# ---------------------------------------------------------------- 商店目录校验


def _shop_records(doc: Dict[str, Any], field: str) -> List[Dict[str, Any]]:
    values = doc.get(field)
    if not isinstance(values, list):
        return []
    return [item for item in values if isinstance(item, dict)]


def _shop_ids(doc: Dict[str, Any], field: str) -> List[str]:
    return [str(record.get("id", "")) for record in _shop_records(doc, field)]


def shop_catalog_entity_count(doc: Any) -> int:
    """商店目录的条目总数（只数实体，不数墓碑；墓碑不是条目）。"""
    if not isinstance(doc, dict):
        return 0
    return sum(len(_shop_ids(doc, field)) for field in SHOP_CATALOG_ENTITY_FIELDS)


def strip_archived_shop_catalog(doc: Any) -> Tuple[Dict[str, Any], Dict[str, int]]:
    """剔除**已归档**条目（2026-09-25 需求：归档的不下发）。

    归档 = `archivedAt` 非空 —— 运营端仍要能管理与追溯，用户端不再展示。
    发布包是「给用户的快照」，所以整条链路连带剔除：

        店家 → 系列 → 商品 → 规格 / 尺码表 / 销售事件 / 款式档案 → 图片资源

    ⚠️ 不连带剔除的后果不只是「多传了点数据」：客户端结构校验要求
    **引用必须包内可解析**（`validate_shop_catalog` 与 Swift 侧
    `ShopCatalogCloudSyncValidator.structuralIssues` 同口径），
    归档商品被剔除而它的规格/尺码表/销售事件还留着 → 悬空引用 →
    整个包被客户端拒绝安装，表现为「所有人什么都看不到」。

    墓碑（removed*IDs）**保留**：那是「已强制删除」的声明，与归档是两件事，
    且墓碑指向的实体本来就不在包内，不构成悬空引用。

    返回 (新目录, 各类剔除条数)；输入不是 dict 时原样返回。
    """
    if not isinstance(doc, dict):
        return doc, {}

    def archived(record: Dict[str, Any]) -> bool:
        value = record.get("archivedAt")
        return value is not None and value != ""

    def records(field: str) -> List[Dict[str, Any]]:
        value = doc.get(field) or []
        return [item for item in value if isinstance(item, dict)]

    all_shops = records("shops")
    all_series = records("series")
    all_products = records("products")
    all_variants = records("variants")
    all_charts = records("sizeCharts")
    all_events = records("saleEvents")
    all_profiles = records("styleProfiles")
    all_assets = records("assets")

    # ⚠️ 连坐判定只认「因归档而被剔除」的上级，**不**认「上级本来就缺失」。
    # 后者是发布端的数据错误（商品指向不存在的系列），必须留下来让结构校验报错，
    # 不能被裁剪悄悄抹平（否则坏数据会静默消失，演练第 28 项就是防这个的）。
    live_shops = [item for item in all_shops if not archived(item)]
    dropped_shop_ids = {str(item.get("id")) for item in all_shops if archived(item)}

    live_series = [
        item for item in all_series
        if not archived(item) and str(item.get("shopID")) not in dropped_shop_ids
    ]
    dropped_series_ids = {
        str(item.get("id")) for item in all_series
        if archived(item) or str(item.get("shopID")) in dropped_shop_ids
    }
    live_products = [
        item for item in all_products
        if not archived(item)
        and str(item.get("shopID")) not in dropped_shop_ids
        and str(item.get("seriesID")) not in dropped_series_ids
    ]
    dropped_product_ids = {
        str(item.get("id")) for item in all_products
        if archived(item)
        or str(item.get("shopID")) in dropped_shop_ids
        or str(item.get("seriesID")) in dropped_series_ids
    }
    # 只有「上级存在但被归档连坐」的系列 id 才连坐款式档案
    dropped_profile_series_ids = dropped_series_ids

    live_variants = [
        i for i in all_variants if str(i.get("productID")) not in dropped_product_ids]
    live_charts = [
        i for i in all_charts if str(i.get("productID")) not in dropped_product_ids]
    live_events = [
        i for i in all_events if str(i.get("productID")) not in dropped_product_ids]
    live_profiles = [
        i for i in all_profiles if str(i.get("seriesID")) not in dropped_profile_series_ids]

    def asset_refs(
        shops: List[Dict[str, Any]],
        series: List[Dict[str, Any]],
        products: List[Dict[str, Any]],
        variants: List[Dict[str, Any]],
        charts: List[Dict[str, Any]],
    ) -> set:
        refs: set = set()
        for shop in shops:
            for key in ("logo", "cover"):
                if shop.get(key):
                    refs.add(str(shop[key]))
        for item in series:
            if item.get("cover"):
                refs.add(str(item["cover"]))
            chart = item.get("priceChart")
            if isinstance(chart, dict):
                if chart.get("sourceImage"):
                    refs.add(str(chart["sourceImage"]))
                for one in chart.get("sourceImages") or []:
                    if one:
                        refs.add(str(one))
        for product in products:
            for one in product.get("images") or []:
                if one:
                    refs.add(str(one))
        for variant in variants:
            if variant.get("imageAssetID"):
                refs.add(str(variant["imageAssetID"]))
        for chart in charts:
            if chart.get("sourceImage"):
                refs.add(str(chart["sourceImage"]))
        return refs

    live_refs = asset_refs(live_shops, live_series, live_products, live_variants, live_charts)
    # 「被剔除实体」= 因归档（含连坐）而消失的那部分
    dropped_refs = asset_refs(
        [i for i in all_shops if str(i.get("id")) in dropped_shop_ids],
        [i for i in all_series if str(i.get("id")) in dropped_series_ids],
        [i for i in all_products if str(i.get("id")) in dropped_product_ids],
        [i for i in all_variants if str(i.get("productID")) in dropped_product_ids],
        [i for i in all_charts if str(i.get("productID")) in dropped_product_ids],
    )
    # 只剔除「确定只被归档实体引用」的资源；两边都没引用的孤儿**保持原样**
    # （引用形式可能有未覆盖的角落，宁可多传一张图，也不要把在用的图删掉）
    exclusive_dropped = dropped_refs - live_refs
    live_assets = [
        item for item in all_assets
        if str(item.get("id")) in live_refs or str(item.get("id")) not in exclusive_dropped
    ]

    new_doc = dict(doc)
    new_doc.update({
        "shops": live_shops,
        "series": live_series,
        "products": live_products,
        "variants": live_variants,
        "sizeCharts": live_charts,
        "saleEvents": live_events,
        "styleProfiles": live_profiles,
        "assets": live_assets,
    })
    report = {
        "shops": len(all_shops) - len(live_shops),
        "series": len(all_series) - len(live_series),
        "products": len(all_products) - len(live_products),
        "variants": len(all_variants) - len(live_variants),
        "sizeCharts": len(all_charts) - len(live_charts),
        "saleEvents": len(all_events) - len(live_events),
        "styleProfiles": len(all_profiles) - len(live_profiles),
        "assets": len(all_assets) - len(live_assets),
    }
    return new_doc, report


def validate_shop_catalog(
    doc: Any,
    brand_id: str,
    coverage_status: str,
) -> List[Dict[str, str]]:
    """商店目录整包分片的结构校验。

    与 `validate_fragment`（TimeHall 实体）刻意分开：
      · 商店实体的时间是 ISO8601 **日期时间**（Swift `.iso8601` 编解码），
        不适用 TimeHall 的 `yyyy-MM-dd` 规则；
      · 图片引用允许指向 Bundle 内置资源（`bundle:` 前缀），包内无法判定
        是否存在，因此**只**校验纯 id→id 的实体引用，不做资产引用校验；
      · 上架销售历史是 append-only，这里只校验它引用的商品存在。
    """
    issues: List[Dict[str, str]] = []
    if not brand_id:
        issues.append(_issue("brandID.empty", "brandID 不得为空"))
    if not isinstance(doc, dict):
        return issues + [_issue("shopCatalog.invalid", "商店目录分片负载必须是对象")]

    total = shop_catalog_entity_count(doc)
    if coverage_status == COVERAGE_EMPTY and total:
        issues.append(_issue("empty.notEmpty", "覆盖状态为 empty 的商店目录分片不得携带任何条目"))
    if coverage_status in (COVERAGE_COMPLETE, COVERAGE_PARTIAL) and total == 0:
        issues.append(
            _issue("records.empty", "覆盖状态为 {} 的商店目录分片不得为空".format(coverage_status))
        )

    # 数组字段类型（缺键视为空；类型错必须报）
    for field in SHOP_CATALOG_ALL_FIELDS:
        value = doc.get(field)
        if value is not None and not isinstance(value, list):
            issues.append(_issue("shopCatalog.fieldType", "{} 必须是数组".format(field), field))

    # 每类实体 id 非空且唯一
    for field in SHOP_CATALOG_ENTITY_FIELDS:
        seen: set = set()
        for value in _shop_ids(doc, field):
            if not value:
                issues.append(_issue("{}.id.empty".format(field), "{} 存在空 ID".format(field)))
                continue
            if value in seen:
                issues.append(
                    _issue("{}.id.duplicate".format(field), "{} 存在重复 ID".format(field), value)
                )
            seen.add(value)

    shop_ids = set(_shop_ids(doc, "shops"))
    series_ids = set(_shop_ids(doc, "series"))
    product_ids = set(_shop_ids(doc, "products"))

    # 引用完整性：整包发布，被引用实体必须同包可解析（§18.1 D09）
    if shop_ids:
        for record in _shop_records(doc, "series"):
            if str(record.get("shopID", "")) not in shop_ids:
                issues.append(
                    _issue(
                        "series.shopID.dangling",
                        "系列引用了包内不存在的店家 {}".format(record.get("shopID")),
                        str(record.get("id", "")),
                    )
                )
        for record in _shop_records(doc, "products"):
            if str(record.get("shopID", "")) not in shop_ids:
                issues.append(
                    _issue(
                        "product.shopID.dangling",
                        "商品引用了包内不存在的店家 {}".format(record.get("shopID")),
                        str(record.get("id", "")),
                    )
                )
    if series_ids:
        for record in _shop_records(doc, "products"):
            if str(record.get("seriesID", "")) not in series_ids:
                issues.append(
                    _issue(
                        "product.seriesID.dangling",
                        "商品引用了包内不存在的系列 {}".format(record.get("seriesID")),
                        str(record.get("id", "")),
                    )
                )
        for record in _shop_records(doc, "styleProfiles"):
            if str(record.get("seriesID", "")) not in series_ids:
                issues.append(
                    _issue(
                        "styleProfile.seriesID.dangling",
                        "款式档案引用了包内不存在的系列 {}".format(record.get("seriesID")),
                        str(record.get("id", "")),
                    )
                )
    if product_ids:
        for record in _shop_records(doc, "variants"):
            if str(record.get("productID", "")) not in product_ids:
                issues.append(
                    _issue(
                        "variant.productID.dangling",
                        "规格引用了包内不存在的商品 {}".format(record.get("productID")),
                        str(record.get("id", "")),
                    )
                )
        for record in _shop_records(doc, "saleEvents"):
            if str(record.get("productID", "")) not in product_ids:
                issues.append(
                    _issue(
                        "saleEvent.productID.dangling",
                        "销售记录引用了包内不存在的商品 {}".format(record.get("productID")),
                        str(record.get("id", "")),
                    )
                )
        for record in _shop_records(doc, "sizeCharts"):
            if str(record.get("productID", "")) not in product_ids:
                issues.append(
                    _issue(
                        "sizeChart.productID.dangling",
                        "尺码表引用了包内不存在的商品 {}".format(record.get("productID")),
                        str(record.get("id", "")),
                    )
                )

    # 枚举取值（与 Swift 侧 CatalogSaleEventType / CatalogCurrency /
    # CatalogSeriesSalePhase / CatalogBalanceDueKind 的 rawValue 对齐）
    for record in _shop_records(doc, "saleEvents"):
        event_type = str(record.get("type", ""))
        if event_type not in SHOP_SALE_EVENT_TYPES:
            issues.append(
                _issue(
                    "saleEvent.type.invalid",
                    "销售记录类型 {} 不在 {} 内".format(event_type, sorted(SHOP_SALE_EVENT_TYPES)),
                    str(record.get("id", "")),
                )
            )
        currency = record.get("currency")
        if currency is not None and str(currency) not in SHOP_CURRENCIES:
            issues.append(
                _issue(
                    "saleEvent.currency.invalid",
                    "币种 {} 不在 {} 内".format(currency, sorted(SHOP_CURRENCIES)),
                    str(record.get("id", "")),
                )
            )
        price = record.get("price")
        if isinstance(price, bool) or not isinstance(price, (int, float)):
            issues.append(
                _issue("saleEvent.price.type", "price 必须是数字", str(record.get("id", "")))
            )
    for record in _shop_records(doc, "series"):
        phase = record.get("salePhase")
        if phase is not None and str(phase) not in SHOP_SALE_PHASES:
            issues.append(
                _issue(
                    "series.salePhase.invalid",
                    "发售阶段 {} 不在 {} 内".format(phase, sorted(SHOP_SALE_PHASES)),
                    str(record.get("id", "")),
                )
            )
        kind = record.get("balanceDueKind")
        if kind is not None and str(kind) not in SHOP_BALANCE_DUE_KINDS:
            issues.append(
                _issue(
                    "series.balanceDueKind.invalid",
                    "尾款时间粒度 {} 不在 {} 内".format(kind, sorted(SHOP_BALANCE_DUE_KINDS)),
                    str(record.get("id", "")),
                )
            )

    # 墓碑与现存实体不得同 id（既「在售」又「已删除」= 数据自相矛盾）
    for field, tombstone in (
        ("shops", "removedShopIDs"),
        ("series", "removedSeriesIDs"),
        ("products", "removedProductIDs"),
    ):
        alive = set(_shop_ids(doc, field))
        removed = {str(value) for value in (doc.get(tombstone) or [])}
        for value in sorted(alive & removed)[:5]:
            issues.append(
                _issue("tombstone.conflict", "墓碑 {} 与现存实体同 id".format(tombstone), value)
            )

    # canonical ID 唯一（跨实体类型：同一个 id 同时当商品和系列也是错的）
    canonical: List[str] = []
    for field in SHOP_CATALOG_ENTITY_FIELDS:
        entity_type = SHOP_CANONICAL_TYPE_BY_FIELD[field]
        canonical += [
            canonical_entity_id(brand_id, entity_type, value) for value in _shop_ids(doc, field)
        ]
    duplicates = sorted({value for value in canonical if canonical.count(value) > 1})
    for value in duplicates[:5]:
        issues.append(_issue("canonicalID.duplicate", "canonical ID 重复", value))

    return issues


def validate_pack_payload(
    payload: Dict[str, Any],
    brand_id: str,
    entity_type: str,
    coverage_status: str,
) -> List[Dict[str, str]]:
    """按分片类型分发结构校验（build / validate / verify 三处共用同一入口）。"""
    if entity_type == SHOP_CATALOG_ENTITY_TYPE:
        return validate_shop_catalog(payload.get("shopCatalog"), brand_id, coverage_status)
    return validate_fragment(payload.get("records") or {}, brand_id, entity_type, coverage_status)
