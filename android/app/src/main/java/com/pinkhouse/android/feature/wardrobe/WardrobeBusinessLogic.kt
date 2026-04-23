package com.pinkhouse.android.feature.wardrobe

import com.pinkhouse.android.domain.model.WardrobeItem
import java.math.BigDecimal
import java.time.YearMonth

object WardrobeBusinessLogic {
    private val noValueTokens = setOf("无", "none", "无标签", "无品牌", "无类型", "无颜色", "无尺码", "无衣长", "无成色", "无小物")

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

    private fun String.splitValues(): List<String> {
        return replace("，", ",")
            .replace("、", ",")
            .split(",")
            .map { it.trim() }
            .filter { it.isNotBlank() }
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
