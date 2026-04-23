package com.pinkhouse.android.data.local

import androidx.room.Entity
import androidx.room.PrimaryKey

@Entity(tableName = "wardrobe_item")
data class WardrobeItemEntity(
    @PrimaryKey(autoGenerate = true)
    val id: Long = 0,
    val uuid: String = "",
    val name: String,
    val category: String,
    val brand: String? = null,
    val tagNamesJson: String = "[]",
    val color: String? = null,
    val colors: String = "",
    val sizes: String = "",
    val length: String = "",
    val condition: String = "全新",
    val accessories: String = "",
    val accessoryItemsJson: String = "[]",
    val imagePathsJson: String = "[]",
    val sizeChartImagePathsJson: String = "[]",
    val priceChartImagePathsJson: String = "[]",
    val originalPriceCents: Long = 0,
    val priceCents: Long? = null,
    val depositCents: Long = 0,
    val balanceCents: Long = 0,
    val accessoriesPriceCents: Long = 0,
    val stock: Int = 1,
    val purchaseDateEpochDay: Long? = null,
    val depositDateEpochDay: Long? = null,
    val isDepositPlan: Boolean = false,
    val finalPaymentStartEpochDay: Long? = null,
    val finalPaymentEndEpochDay: Long? = null,
    val note: String = "",
    val sortIndex: Long = 0,
    val status: String,
    val createdAtEpochMillis: Long,
    val updatedAtEpochMillis: Long,
    val trashedAtEpochMillis: Long? = null,
)
