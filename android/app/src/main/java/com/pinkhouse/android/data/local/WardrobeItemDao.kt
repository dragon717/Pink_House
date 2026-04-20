package com.pinkhouse.android.data.local

import androidx.room.Dao
import androidx.room.Query
import kotlinx.coroutines.flow.Flow

@Dao
interface WardrobeItemDao {
    @Query("SELECT * FROM wardrobe_item WHERE status != 'Trashed' ORDER BY updatedAtEpochMillis DESC")
    fun observeActiveItems(): Flow<List<WardrobeItemEntity>>
}
