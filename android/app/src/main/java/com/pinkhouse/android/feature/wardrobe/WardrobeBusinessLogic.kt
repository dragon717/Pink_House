package com.pinkhouse.android.feature.wardrobe

import com.pinkhouse.android.domain.model.WardrobeItem
import java.math.BigDecimal
import java.time.YearMonth

object WardrobeBusinessLogic {
    private val noValueTokens = setOf("无", "none", "无标签", "无品牌", "无类型", "无颜色", "无尺码", "无衣长", "无成色", "无小物")
    private val depositTokens = setOf("尾款", "心愿尾款", "定金", "deposit")
    private val scopedSearchAliases = mapOf(
        "name" to ScopedSearchField.Name,
        "名称" to ScopedSearchField.Name,
        "brand" to ScopedSearchField.Brand,
        "品牌" to ScopedSearchField.Brand,
        "type" to ScopedSearchField.Type,
        "类型" to ScopedSearchField.Type,
        "category" to ScopedSearchField.Type,
        "分类" to ScopedSearchField.Type,
        "color" to ScopedSearchField.Color,
        "颜色" to ScopedSearchField.Color,
        "size" to ScopedSearchField.Size,
        "尺码" to ScopedSearchField.Size,
        "length" to ScopedSearchField.Length,
        "衣长" to ScopedSearchField.Length,
        "condition" to ScopedSearchField.Condition,
        "状态" to ScopedSearchField.Condition,
        "成色" to ScopedSearchField.Condition,
        "accessory" to ScopedSearchField.Accessory,
        "小物" to ScopedSearchField.Accessory,
        "tag" to ScopedSearchField.Tag,
        "标签" to ScopedSearchField.Tag,
        "note" to ScopedSearchField.Note,
        "备注" to ScopedSearchField.Note,
    )

    fun filterItems(items: List<WardrobeItem>, filter: WardrobeFilterState): List<WardrobeItem> {
        return items.filter { item ->
            item.matchesDimension(filter.brand, item.brand.orEmpty()) &&
                item.matchesDimension(filter.type, item.category) &&
                item.matchesDimension(filter.color, item.colors.ifBlank { item.color.orEmpty() }) &&
                item.matchesDimension(filter.size, item.sizes) &&
                item.matchesDimension(filter.length, item.length) &&
                item.matchesDimension(filter.condition, item.condition) &&
                item.matchesDimension(filter.accessory, item.accessories) &&
                item.matchesDimension(filter.tag, item.tags.joinToString(",")) &&
                (!filter.depositOnly || item.isDepositPlan)
        }
    }

    fun searchItems(items: List<WardrobeItem>, query: String): List<WardrobeItem> {
        val trimmed = query.trim()
        if (trimmed.isBlank()) return items
        parseScopedSearch(trimmed)?.let { scoped ->
            return items.filter { it.matchesScopedSearch(scoped) }
        }
        parseNoValueSearch(trimmed)?.let { scoped ->
            return items.filter { it.matchesScopedSearch(scoped) }
        }
        if (trimmed.lowercase() in depositTokens) {
            return items.filter { it.isDepositPlan }
        }
        parsePriceRange(trimmed)?.let { range ->
            return items.filter { item ->
                item.inventoryTotalPrice >= range.first && item.inventoryTotalPrice <= range.second
            }
        }
        return items.filter { item ->
            listOf(
                item.name,
                item.brand.orEmpty(),
                item.category,
                item.color.orEmpty(),
                item.colors,
                item.sizes,
                item.length,
                item.condition,
                item.accessories,
                item.tags.joinToString(","),
                item.note,
                item.stock.toString(),
            ).any { it.contains(trimmed, ignoreCase = true) }
        }
    }

    fun queryShortcuts(items: List<WardrobeItem>): List<WardrobeQueryShortcut> {
        val dynamicShortcuts =
            items.topDimensionShortcuts("品牌") { it.brand.orEmpty() } +
                items.topDimensionShortcuts("类型") { it.category } +
                items.topDimensionShortcuts("颜色") { it.colors.ifBlank { it.color.orEmpty() } } +
                items.topDimensionShortcuts("状态") { it.condition }

        val helperShortcuts = listOf(
            WardrobeQueryShortcut("价格 100-300", "100-300", "按当前总价区间查询"),
            WardrobeQueryShortcut("无品牌", "品牌:无品牌", "找未填写品牌的衣物"),
            WardrobeQueryShortcut("无标签", "标签:无标签", "找未添加标签的衣物"),
            WardrobeQueryShortcut("无小物", "小物:无小物", "找未填写小物的衣物"),
            WardrobeQueryShortcut("心愿尾款", "尾款", "只看心愿尾款"),
        )

        return (helperShortcuts + dynamicShortcuts)
            .distinctBy { it.query.lowercase() }
            .take(12)
    }

    fun sortItems(items: List<WardrobeItem>, sort: WardrobeSortOption): List<WardrobeItem> {
        return items.sortedWith(sort.comparator())
    }

    fun monthlyDepositSummaries(items: List<WardrobeItem>): List<DepositMonthSummary> {
        return items
            .filter { it.isDepositPlan && it.finalPaymentEndDate != null }
            .groupBy { YearMonth.from(it.finalPaymentEndDate) }
            .map { (month, monthItems) ->
                DepositMonthSummary(
                    month = month,
                    itemCount = monthItems.size,
                    totalBalance = monthItems.fold(BigDecimal.ZERO) { acc, item -> acc + item.totalBalance },
                )
            }
            .sortedBy { it.month }
    }

    fun seriesDepositSummaries(items: List<WardrobeItem>): List<DepositSeriesSummary> {
        return items
            .filter { it.isDepositPlan }
            .groupBy { it.brand?.takeIf(String::isNotBlank) ?: "未填写品牌" }
            .map { (series, seriesItems) ->
                DepositSeriesSummary(
                    series = series,
                    itemCount = seriesItems.size,
                    totalBalance = seriesItems.fold(BigDecimal.ZERO) { acc, item -> acc + item.totalBalance },
                )
            }
            .sortedByDescending { it.totalBalance }
    }

    private fun WardrobeItem.matchesDimension(query: String, value: String): Boolean {
        val trimmed = query.trim()
        if (trimmed.isBlank()) return true
        if (trimmed.lowercase() in noValueTokens) return value.splitValues().isEmpty()
        return value.splitValues().any { it.contains(trimmed, ignoreCase = true) } ||
            value.contains(trimmed, ignoreCase = true)
    }

    private fun WardrobeItem.matchesScopedSearch(search: ScopedSearch): Boolean {
        return when (search.field) {
            ScopedSearchField.Name -> name.contains(search.value, ignoreCase = true)
            ScopedSearchField.Brand -> matchesDimension(search.value, brand.orEmpty())
            ScopedSearchField.Type -> matchesDimension(search.value, category)
            ScopedSearchField.Color -> matchesDimension(search.value, colors.ifBlank { color.orEmpty() })
            ScopedSearchField.Size -> matchesDimension(search.value, sizes)
            ScopedSearchField.Length -> matchesDimension(search.value, length)
            ScopedSearchField.Condition -> matchesDimension(search.value, condition)
            ScopedSearchField.Accessory -> matchesDimension(search.value, accessories)
            ScopedSearchField.Tag -> matchesDimension(search.value, tags.joinToString(","))
            ScopedSearchField.Note -> note.contains(search.value, ignoreCase = true)
        }
    }

    private fun String.splitValues(): List<String> {
        return replace("，", ",")
            .replace("、", ",")
            .split(",")
            .map { it.trim() }
            .filter { it.isNotBlank() }
    }

    private fun parseScopedSearch(query: String): ScopedSearch? {
        val normalized = query.replace("：", ":")
        val separatorIndex = normalized.indexOf(":")
        if (separatorIndex <= 0) return null
        val prefix = normalized.substring(0, separatorIndex).trim().lowercase()
        val value = normalized.substring(separatorIndex + 1).trim()
        if (value.isBlank()) return null
        return scopedSearchAliases[prefix]?.let { field -> ScopedSearch(field, value) }
    }

    private fun parseNoValueSearch(query: String): ScopedSearch? {
        return when (query.trim().lowercase()) {
            "无品牌" -> ScopedSearch(ScopedSearchField.Brand, query)
            "无类型" -> ScopedSearch(ScopedSearchField.Type, query)
            "无颜色" -> ScopedSearch(ScopedSearchField.Color, query)
            "无尺码" -> ScopedSearch(ScopedSearchField.Size, query)
            "无衣长" -> ScopedSearch(ScopedSearchField.Length, query)
            "无成色" -> ScopedSearch(ScopedSearchField.Condition, query)
            "无小物" -> ScopedSearch(ScopedSearchField.Accessory, query)
            "无标签" -> ScopedSearch(ScopedSearchField.Tag, query)
            else -> null
        }
    }

    private fun parsePriceRange(query: String): Pair<BigDecimal, BigDecimal>? {
        val parts = query
            .replace("￥", "")
            .replace("¥", "")
            .replace("到", "-")
            .replace("~", "-")
            .split("-")
            .map { it.trim() }
        if (parts.size != 2) return null
        val start = parts[0].toBigDecimalOrNull() ?: return null
        val end = parts[1].toBigDecimalOrNull() ?: return null
        return if (start <= end) start to end else end to start
    }

    private fun List<WardrobeItem>.topDimensionShortcuts(
        labelPrefix: String,
        valueSelector: (WardrobeItem) -> String,
    ): List<WardrobeQueryShortcut> {
        return flatMap { valueSelector(it).splitValues() }
            .filterNot { it.lowercase() in noValueTokens }
            .groupingBy { it }
            .eachCount()
            .entries
            .sortedWith(compareByDescending<Map.Entry<String, Int>> { it.value }.thenBy { it.key })
            .take(2)
            .map { (value, count) ->
                WardrobeQueryShortcut(
                    label = "$labelPrefix $value",
                    query = "$labelPrefix:$value",
                    description = "$count 件匹配",
                )
            }
    }
}

data class WardrobeQueryShortcut(
    val label: String,
    val query: String,
    val description: String,
)

private data class ScopedSearch(
    val field: ScopedSearchField,
    val value: String,
)

private enum class ScopedSearchField {
    Name,
    Brand,
    Type,
    Color,
    Size,
    Length,
    Condition,
    Accessory,
    Tag,
    Note,
}

data class DepositMonthSummary(
    val month: YearMonth,
    val itemCount: Int,
    val totalBalance: BigDecimal,
)

data class DepositSeriesSummary(
    val series: String,
    val itemCount: Int,
    val totalBalance: BigDecimal,
)
