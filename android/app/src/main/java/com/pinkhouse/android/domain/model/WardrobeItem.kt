package com.pinkhouse.android.domain.model

import java.math.BigDecimal
import java.time.LocalDate

data class WardrobeItem(
    val id: Long,
    val uuid: String = "",
    val name: String,
    val category: String,
    val brand: String?,
    val tags: List<String> = emptyList(),
    val color: String?,
    val colors: String = color.orEmpty(),
    val sizes: String = "",
    val length: String = "",
    val condition: String = "全新",
    val accessories: String = "",
    val accessoryItems: List<WardrobeAccessoryItem> = emptyList(),
    val imagePaths: List<String> = emptyList(),
    val sizeChartImagePaths: List<String> = emptyList(),
    val priceChartImagePaths: List<String> = emptyList(),
    val originalPrice: BigDecimal = BigDecimal.ZERO,
    val price: BigDecimal?,
    val deposit: BigDecimal = BigDecimal.ZERO,
    val balance: BigDecimal = BigDecimal.ZERO,
    val accessoriesPrice: BigDecimal = BigDecimal.ZERO,
    val stock: Int = 1,
    val purchaseDate: LocalDate?,
    val depositDate: LocalDate? = null,
    val isDepositPlan: Boolean = false,
    val finalPaymentStartDate: LocalDate? = null,
    val finalPaymentEndDate: LocalDate? = null,
    val note: String = "",
    val sortIndex: Long = 0,
    val status: WardrobeItemStatus,
    val createdAtEpochMillis: Long = 0,
    val updatedAtEpochMillis: Long = 0,
    val trashedAtEpochMillis: Long? = null,
) {
    val inventoryTotalPrice: BigDecimal
        get() = (price ?: BigDecimal.ZERO)
            .multiply(BigDecimal(stock.coerceAtLeast(1)))
            .add(resolvedAccessoriesPrice)

    val resolvedAccessoriesPrice: BigDecimal
        get() = if (accessoryItems.isEmpty()) {
            accessoriesPrice
        } else {
            accessoryItems.fold(BigDecimal.ZERO) { acc, item -> acc + item.totalPrice }
        }

    val totalDeposit: BigDecimal
        get() = deposit.multiply(BigDecimal(stock.coerceAtLeast(1)))

    val totalBalance: BigDecimal
        get() = balance.multiply(BigDecimal(stock.coerceAtLeast(1)))
}
