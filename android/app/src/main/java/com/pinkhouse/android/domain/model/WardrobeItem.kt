package com.pinkhouse.android.domain.model

import java.math.BigDecimal
import java.time.LocalDate

data class WardrobeItem(
    val id: Long,
    val name: String,
    val category: String,
    val brand: String?,
    val color: String?,
    val colors: String = color.orEmpty(),
    val sizes: String = "",
    val length: String = "",
    val condition: String = "全新",
    val accessories: String = "",
    val imagePaths: List<String> = emptyList(),
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
) {
    val inventoryTotalPrice: BigDecimal
        get() = (price ?: BigDecimal.ZERO)
            .multiply(BigDecimal(stock.coerceAtLeast(1)))
            .add(accessoriesPrice)

    val totalDeposit: BigDecimal
        get() = deposit.multiply(BigDecimal(stock.coerceAtLeast(1)))

    val totalBalance: BigDecimal
        get() = balance.multiply(BigDecimal(stock.coerceAtLeast(1)))
}
