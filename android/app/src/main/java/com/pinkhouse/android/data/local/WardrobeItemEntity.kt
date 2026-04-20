package com.pinkhouse.android.data.local

import androidx.room.Entity
import androidx.room.PrimaryKey

@Entity(tableName = "wardrobe_item")
data class WardrobeItemEntity(
    @PrimaryKey(autoGenerate = true)
    val id: Long = 0,
    val name: String,
    val category: String,
    val brand: String? = null,
    val color: String? = null,
    val priceCents: Long? = null,
    val purchaseDateEpochDay: Long? = null,
    val status: String,
    val createdAtEpochMillis: Long,
    val updatedAtEpochMillis: Long,
    val trashedAtEpochMillis: Long? = null,
)
