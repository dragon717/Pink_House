package com.pinkhouse.android.data.local

import com.pinkhouse.android.domain.model.WardrobeItem
import com.pinkhouse.android.domain.model.WardrobeItemStatus
import java.math.BigDecimal
import java.math.RoundingMode
import java.time.LocalDate
import org.json.JSONArray

fun WardrobeItemEntity.toDomain(): WardrobeItem {
    return WardrobeItem(
        id = id,
        name = name,
        category = category,
        brand = brand,
        color = color,
        colors = colors.ifBlank { color.orEmpty() },
        sizes = sizes,
        length = length,
        condition = condition,
        accessories = accessories,
        imagePaths = imagePathsJson.toStringList(),
        originalPrice = originalPriceCents.toMoney(),
        price = priceCents?.let { BigDecimal(it).movePointLeft(2) },
        deposit = depositCents.toMoney(),
        balance = balanceCents.toMoney(),
        accessoriesPrice = accessoriesPriceCents.toMoney(),
        stock = stock.coerceAtLeast(1),
        purchaseDate = purchaseDateEpochDay?.let(LocalDate::ofEpochDay),
        depositDate = depositDateEpochDay?.let(LocalDate::ofEpochDay),
        isDepositPlan = isDepositPlan,
        finalPaymentStartDate = finalPaymentStartEpochDay?.let(LocalDate::ofEpochDay),
        finalPaymentEndDate = finalPaymentEndEpochDay?.let(LocalDate::ofEpochDay),
        note = note,
        sortIndex = sortIndex,
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
        colors = colors.ifBlank { color.orEmpty() },
        sizes = sizes,
        length = length,
        condition = condition,
        accessories = accessories,
        imagePathsJson = imagePaths.toJsonArrayString(),
        originalPriceCents = originalPrice.toCents(),
        priceCents = price
            ?.toCents(),
        depositCents = deposit.toCents(),
        balanceCents = balance.toCents(),
        accessoriesPriceCents = accessoriesPrice.toCents(),
        stock = stock.coerceAtLeast(1),
        purchaseDateEpochDay = purchaseDate?.toEpochDay(),
        depositDateEpochDay = depositDate?.toEpochDay(),
        isDepositPlan = isDepositPlan,
        finalPaymentStartEpochDay = finalPaymentStartDate?.toEpochDay(),
        finalPaymentEndEpochDay = finalPaymentEndDate?.toEpochDay(),
        note = note,
        sortIndex = sortIndex.takeIf { it > 0 } ?: nowEpochMillis,
        status = status.name,
        createdAtEpochMillis = nowEpochMillis,
        updatedAtEpochMillis = nowEpochMillis,
        trashedAtEpochMillis = if (status == WardrobeItemStatus.Trashed) nowEpochMillis else null,
    )
}

private fun Long.toMoney(): BigDecimal = BigDecimal(this).movePointLeft(2)

private fun BigDecimal.toCents(): Long {
    return setScale(2, RoundingMode.HALF_UP)
        .movePointRight(2)
        .longValueExact()
}

private fun String.toStringList(): List<String> {
    return runCatching {
        val array = JSONArray(this)
        List(array.length()) { index -> array.optString(index) }
            .filter { it.isNotBlank() }
    }.getOrDefault(emptyList())
}

private fun List<String>.toJsonArrayString(): String {
    val array = JSONArray()
    forEach { value -> array.put(value) }
    return array.toString()
}
