package com.pinkhouse.android.data.local

import com.pinkhouse.android.domain.model.WardrobeItem
import com.pinkhouse.android.domain.model.WardrobeItemStatus
import java.math.BigDecimal
import java.math.RoundingMode
import java.time.LocalDate

fun WardrobeItemEntity.toDomain(): WardrobeItem {
    return WardrobeItem(
        id = id,
        name = name,
        category = category,
        brand = brand,
        color = color,
        price = priceCents?.let { BigDecimal(it).movePointLeft(2) },
        purchaseDate = purchaseDateEpochDay?.let(LocalDate::ofEpochDay),
        status = runCatching { WardrobeItemStatus.valueOf(status) }
            .getOrDefault(WardrobeItemStatus.Owned),
    )
}

fun WardrobeItem.toEntity(nowEpochMillis: Long): WardrobeItemEntity {
    return WardrobeItemEntity(
        id = id,
        name = name,
        category = category,
        brand = brand,
        color = color,
        priceCents = price
            ?.setScale(2, RoundingMode.HALF_UP)
            ?.movePointRight(2)
            ?.longValueExact(),
        purchaseDateEpochDay = purchaseDate?.toEpochDay(),
        status = status.name,
        createdAtEpochMillis = nowEpochMillis,
        updatedAtEpochMillis = nowEpochMillis,
        trashedAtEpochMillis = if (status == WardrobeItemStatus.Trashed) nowEpochMillis else null,
    )
}
