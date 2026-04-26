package com.pinkhouse.android.domain.repository

import com.pinkhouse.android.domain.model.WardrobeItem
import kotlinx.coroutines.flow.Flow

interface WardrobeRepository {
    fun observeItems(searchQuery: String = ""): Flow<List<WardrobeItem>>

    fun observeItem(id: Long): Flow<WardrobeItem?>

    fun observeTrashedItems(): Flow<List<WardrobeItem>>

    suspend fun addItem(item: WardrobeItem): Long

    suspend fun updateItem(item: WardrobeItem)

    suspend fun addItems(items: List<WardrobeItem>): List<Long>

    suspend fun softDeleteItem(id: Long)

    suspend fun softDeleteItems(ids: List<Long>)

    suspend fun restoreItems(ids: List<Long>)

    suspend fun permanentlyDeleteItems(ids: List<Long>)

    suspend fun purgeTrashedBefore(thresholdEpochMillis: Long)
}
