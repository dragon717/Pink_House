package com.pinkhouse.android.data.local

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import androidx.room.Update
import kotlinx.coroutines.flow.Flow

@Dao
interface WardrobeItemDao {
    @Query(
        """
        SELECT * FROM wardrobe_item
        WHERE status != 'Trashed'
          AND trashedAtEpochMillis IS NULL
        ORDER BY createdAtEpochMillis DESC
        """,
    )
    fun observeActiveItems(): Flow<List<WardrobeItemEntity>>

    @Query(
        """
        SELECT * FROM wardrobe_item
        WHERE status != 'Trashed'
          AND trashedAtEpochMillis IS NULL
          AND (
              name LIKE '%' || :query || '%'
              OR IFNULL(brand, '') LIKE '%' || :query || '%'
              OR category LIKE '%' || :query || '%'
              OR IFNULL(color, '') LIKE '%' || :query || '%'
              OR colors LIKE '%' || :query || '%'
              OR sizes LIKE '%' || :query || '%'
              OR condition LIKE '%' || :query || '%'
              OR accessories LIKE '%' || :query || '%'
          )
        ORDER BY createdAtEpochMillis DESC
        """,
    )
    fun observeActiveItemsByQuery(query: String): Flow<List<WardrobeItemEntity>>

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insert(item: WardrobeItemEntity): Long

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insertAll(items: List<WardrobeItemEntity>): List<Long>

    @Update
    suspend fun update(item: WardrobeItemEntity)

    @Query(
        """
        UPDATE wardrobe_item
        SET status = 'Trashed',
            updatedAtEpochMillis = :trashedAtEpochMillis,
            trashedAtEpochMillis = :trashedAtEpochMillis
        WHERE id = :id
        """,
    )
    suspend fun softDelete(id: Long, trashedAtEpochMillis: Long)

    @Query(
        """
        UPDATE wardrobe_item
        SET status = 'Trashed',
            updatedAtEpochMillis = :trashedAtEpochMillis,
            trashedAtEpochMillis = :trashedAtEpochMillis
        WHERE id IN (:ids)
        """,
    )
    suspend fun softDeleteItems(ids: List<Long>, trashedAtEpochMillis: Long)
}
