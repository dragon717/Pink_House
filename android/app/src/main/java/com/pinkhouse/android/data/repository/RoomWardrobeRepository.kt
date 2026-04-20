package com.pinkhouse.android.data.repository

import com.pinkhouse.android.data.local.WardrobeItemDao
import com.pinkhouse.android.data.local.toDomain
import com.pinkhouse.android.data.local.toEntity
import com.pinkhouse.android.domain.model.WardrobeItem
import com.pinkhouse.android.domain.repository.WardrobeRepository
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map

class RoomWardrobeRepository(
    private val wardrobeItemDao: WardrobeItemDao,
    private val clock: () -> Long = { System.currentTimeMillis() },
) : WardrobeRepository {
    override fun observeItems(searchQuery: String): Flow<List<WardrobeItem>> {
        val trimmedQuery = searchQuery.trim()
        val items = if (trimmedQuery.isBlank()) {
            wardrobeItemDao.observeActiveItems()
        } else {
            wardrobeItemDao.observeActiveItemsByName(trimmedQuery)
        }

        return items.map { entities -> entities.map { it.toDomain() } }
    }

    override suspend fun addItem(item: WardrobeItem): Long {
        return wardrobeItemDao.insert(item.toEntity(clock()))
    }

    override suspend fun updateItem(item: WardrobeItem) {
        wardrobeItemDao.update(item.toEntity(clock()))
    }

    override suspend fun addItems(items: List<WardrobeItem>): List<Long> {
        val now = clock()
        return wardrobeItemDao.insertAll(items.map { it.toEntity(now) })
    }

    override suspend fun softDeleteItem(id: Long) {
        wardrobeItemDao.softDelete(id = id, trashedAtEpochMillis = clock())
    }
}
