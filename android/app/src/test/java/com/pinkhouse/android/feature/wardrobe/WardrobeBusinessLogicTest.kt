package com.pinkhouse.android.feature.wardrobe

import com.pinkhouse.android.domain.model.WardrobeAccessoryItem
import com.pinkhouse.android.domain.model.WardrobeItem
import com.pinkhouse.android.domain.model.WardrobeItemStatus
import java.math.BigDecimal
import java.time.LocalDate
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class WardrobeBusinessLogicTest {
    @Test
    fun searchItems_matchesPriceRangeAndDeepFields() {
        val items = listOf(
            item(name = "蝴蝶结小皮鞋", brand = "Pink House", price = "259", tags = listOf("鞋履")),
            item(name = "奶油半身裙", brand = "Milk", price = "168", tags = listOf("通勤"), note = "粉色穿搭"),
        )

        assertEquals(listOf("蝴蝶结小皮鞋"), WardrobeBusinessLogic.searchItems(items, "200-300").map { it.name })
        assertEquals(listOf("奶油半身裙"), WardrobeBusinessLogic.searchItems(items, "粉色").map { it.name })
        assertEquals(listOf("蝴蝶结小皮鞋"), WardrobeBusinessLogic.searchItems(items, "鞋履").map { it.name })
    }

    @Test
    fun filterItems_supportsNoValueTokens() {
        val items = listOf(
            item(name = "无牌裙", brand = null, tags = emptyList(), accessories = ""),
            item(name = "有牌裙", brand = "Baby", tags = listOf("茶会"), accessories = "KC"),
        )

        assertEquals(listOf("无牌裙"), WardrobeBusinessLogic.filterItems(items, WardrobeFilterState(brand = "无品牌")).map { it.name })
        assertEquals(listOf("无牌裙"), WardrobeBusinessLogic.filterItems(items, WardrobeFilterState(tag = "无标签")).map { it.name })
        assertEquals(listOf("无牌裙"), WardrobeBusinessLogic.filterItems(items, WardrobeFilterState(accessory = "无小物")).map { it.name })
    }

    @Test
    fun monthlyDepositSummaries_groupsByFinalPaymentMonth() {
        val items = listOf(
            item(name = "A", price = "100", isDepositPlan = true, balance = "80", finalPaymentEndDate = LocalDate.of(2026, 5, 20)),
            item(name = "B", price = "100", isDepositPlan = true, balance = "60", finalPaymentEndDate = LocalDate.of(2026, 5, 28)),
            item(name = "C", price = "100", isDepositPlan = true, balance = "40", finalPaymentEndDate = LocalDate.of(2026, 6, 1)),
        )

        val summaries = WardrobeBusinessLogic.monthlyDepositSummaries(items)

        assertEquals(2, summaries.size)
        assertEquals("2026-05", summaries[0].month.toString())
        assertEquals(BigDecimal("140"), summaries[0].totalBalance)
        assertEquals(2, summaries[0].itemCount)
    }

    @Test
    fun accessoryItemsOverrideFlatAccessoryPrice() {
        val item = item(
            name = "带小物裙",
            price = "100",
            accessoriesPrice = "999",
            accessoryItems = listOf(
                WardrobeAccessoryItem("KC", BigDecimal("30"), quantity = 2),
                WardrobeAccessoryItem("BNT", BigDecimal("20"), quantity = 1),
            ),
        )

        assertEquals(BigDecimal("80"), item.resolvedAccessoriesPrice)
        assertEquals(BigDecimal("180"), item.inventoryTotalPrice)
    }

    @Test
    fun sortItems_priceDescendingUsesInventoryTotal() {
        val items = listOf(
            item(name = "低价", price = "10"),
            item(name = "高价", price = "20", stock = 2),
        )

        assertTrue(WardrobeBusinessLogic.sortItems(items, WardrobeSortOption.PriceDesc).first().name == "高价")
    }

    private fun item(
        name: String,
        brand: String? = "Baby",
        price: String = "0",
        tags: List<String> = emptyList(),
        accessories: String = "",
        accessoriesPrice: String = "0",
        accessoryItems: List<WardrobeAccessoryItem> = emptyList(),
        stock: Int = 1,
        note: String = "",
        isDepositPlan: Boolean = false,
        balance: String = "0",
        finalPaymentEndDate: LocalDate? = null,
    ): WardrobeItem {
        return WardrobeItem(
            id = name.hashCode().toLong(),
            name = name,
            category = "裙装",
            brand = brand,
            tags = tags,
            color = null,
            accessories = accessories,
            accessoryItems = accessoryItems,
            price = BigDecimal(price),
            accessoriesPrice = BigDecimal(accessoriesPrice),
            stock = stock,
            purchaseDate = null,
            note = note,
            isDepositPlan = isDepositPlan,
            balance = BigDecimal(balance),
            finalPaymentEndDate = finalPaymentEndDate,
            status = WardrobeItemStatus.Owned,
        )
    }
}
