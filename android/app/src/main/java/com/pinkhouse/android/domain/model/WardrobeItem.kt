package com.pinkhouse.android.domain.model

import java.math.BigDecimal
import java.time.LocalDate

data class WardrobeItem(
    val id: Long,
    val name: String,
    val category: String,
    val brand: String?,
    val color: String?,
    val price: BigDecimal?,
    val purchaseDate: LocalDate?,
    val status: WardrobeItemStatus,
)
