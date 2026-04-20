package com.pinkhouse.android.data.local

import android.content.Context
import androidx.room.Database
import androidx.room.Room
import androidx.room.RoomDatabase

@Database(
    entities = [WardrobeItemEntity::class],
    version = 1,
    exportSchema = true,
)
abstract class PinkHouseDatabase : RoomDatabase() {
    abstract fun wardrobeItemDao(): WardrobeItemDao

    companion object {
        fun create(context: Context): PinkHouseDatabase {
            return Room.databaseBuilder(
                context.applicationContext,
                PinkHouseDatabase::class.java,
                "pink_house.db",
            ).build()
        }
    }
}
