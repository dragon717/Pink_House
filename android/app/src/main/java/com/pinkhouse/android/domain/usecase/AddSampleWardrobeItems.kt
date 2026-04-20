package com.pinkhouse.android.domain.usecase

import com.pinkhouse.android.domain.model.WardrobeItem
import com.pinkhouse.android.domain.model.WardrobeItemStatus
import com.pinkhouse.android.domain.repository.WardrobeRepository
import java.math.BigDecimal
import java.time.LocalDate

class AddSampleWardrobeItems(
    private val wardrobeRepository: WardrobeRepository,
) {
    suspend operator fun invoke() {
        wardrobeRepository.addItems(sampleItems)
    }

    private val sampleItems = listOf(
        WardrobeItem(
            id = 0,
            name = "粉色针织开衫",
            category = "上衣",
            brand = "Pink House",
            color = "樱花粉",
            price = BigDecimal("168.00"),
            purchaseDate = LocalDate.of(2026, 3, 12),
            status = WardrobeItemStatus.Owned,
        ),
        WardrobeItem(
            id = 0,
            name = "奶油白半身裙",
            category = "下装",
            brand = null,
            color = "奶油白",
            price = BigDecimal("129.00"),
            purchaseDate = LocalDate.of(2026, 2, 20),
            status = WardrobeItemStatus.Owned,
        ),
        WardrobeItem(
            id = 0,
            name = "蝴蝶结小皮鞋",
            category = "鞋履",
            brand = "Sweet Step",
            color = "可可棕",
            price = BigDecimal("259.00"),
            purchaseDate = LocalDate.of(2026, 1, 8),
            status = WardrobeItemStatus.Reserved,
        ),
    )
}
