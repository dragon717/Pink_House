package com.pinkhouse.android.domain.usecase

import com.pinkhouse.android.core.media.WardrobeTestMediaManager
import com.pinkhouse.android.domain.model.WardrobeItem
import com.pinkhouse.android.domain.model.WardrobeItemStatus
import com.pinkhouse.android.domain.repository.WardrobeRepository
import java.math.BigDecimal
import java.time.LocalDate

class AddSampleWardrobeItems(
    private val wardrobeRepository: WardrobeRepository,
    private val wardrobeTestMediaManager: WardrobeTestMediaManager,
) {
    suspend operator fun invoke() {
        val importedImages = wardrobeTestMediaManager.importAllMedia()
        wardrobeRepository.addItems(
            sampleItems.mapIndexed { index, item ->
                item.copy(imagePaths = importedImages.getOrNull(index)?.let(::listOf).orEmpty())
            },
        )
    }

    private val sampleItems = listOf(
        WardrobeItem(
            id = 0,
            name = "粉色针织开衫",
            category = "上衣",
            brand = "Pink House",
            color = "樱花粉",
            colors = "樱花粉",
            sizes = "M",
            length = "短款",
            condition = "全新",
            originalPrice = BigDecimal("188.00"),
            price = BigDecimal("168.00"),
            accessoriesPrice = BigDecimal("0.00"),
            stock = 1,
            purchaseDate = LocalDate.of(2026, 3, 12),
            status = WardrobeItemStatus.Owned,
        ),
        WardrobeItem(
            id = 0,
            name = "奶油白半身裙",
            category = "下装",
            brand = null,
            color = "奶油白",
            colors = "奶油白",
            sizes = "S,M",
            length = "80cm",
            condition = "95新",
            originalPrice = BigDecimal("159.00"),
            price = BigDecimal("129.00"),
            accessoriesPrice = BigDecimal("0.00"),
            stock = 1,
            purchaseDate = LocalDate.of(2026, 2, 20),
            status = WardrobeItemStatus.Owned,
        ),
        WardrobeItem(
            id = 0,
            name = "蝴蝶结小皮鞋",
            category = "鞋履",
            brand = "Sweet Step",
            color = "可可棕",
            colors = "可可棕",
            sizes = "37",
            length = "",
            condition = "全新",
            originalPrice = BigDecimal("299.00"),
            price = BigDecimal("259.00"),
            deposit = BigDecimal("50.00"),
            balance = BigDecimal("209.00"),
            stock = 1,
            purchaseDate = LocalDate.of(2026, 1, 8),
            isDepositPlan = true,
            finalPaymentStartDate = LocalDate.of(2026, 5, 1),
            finalPaymentEndDate = LocalDate.of(2026, 5, 7),
            status = WardrobeItemStatus.Reserved,
        ),
    )
}
