package com.pinkhouse.android.domain.model

import java.math.BigDecimal

data class WardrobeAccessoryItem(
    val name: String,
    val price: BigDecimal = BigDecimal.ZERO,
    val quantity: Int = 1,
) {
    val totalPrice: BigDecimal
        get() = price.multiply(BigDecimal(quantity.coerceAtLeast(1)))
}
