package com.pinkhouse.android.data.local

import android.content.Context
import androidx.room.Database
import androidx.room.Room
import androidx.room.RoomDatabase
import androidx.room.migration.Migration
import androidx.sqlite.db.SupportSQLiteDatabase

@Database(
    entities = [WardrobeItemEntity::class],
    version = 3,
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
            ).addMigrations(Migration1To2, Migration2To3).build()
        }

        private val Migration1To2 = object : Migration(1, 2) {
            override fun migrate(db: SupportSQLiteDatabase) {
                db.execSQL("ALTER TABLE wardrobe_item ADD COLUMN colors TEXT NOT NULL DEFAULT ''")
                db.execSQL("ALTER TABLE wardrobe_item ADD COLUMN sizes TEXT NOT NULL DEFAULT ''")
                db.execSQL("ALTER TABLE wardrobe_item ADD COLUMN length TEXT NOT NULL DEFAULT ''")
                db.execSQL("ALTER TABLE wardrobe_item ADD COLUMN condition TEXT NOT NULL DEFAULT '全新'")
                db.execSQL("ALTER TABLE wardrobe_item ADD COLUMN accessories TEXT NOT NULL DEFAULT ''")
                db.execSQL("ALTER TABLE wardrobe_item ADD COLUMN imagePathsJson TEXT NOT NULL DEFAULT '[]'")
                db.execSQL("ALTER TABLE wardrobe_item ADD COLUMN originalPriceCents INTEGER NOT NULL DEFAULT 0")
                db.execSQL("ALTER TABLE wardrobe_item ADD COLUMN depositCents INTEGER NOT NULL DEFAULT 0")
                db.execSQL("ALTER TABLE wardrobe_item ADD COLUMN balanceCents INTEGER NOT NULL DEFAULT 0")
                db.execSQL("ALTER TABLE wardrobe_item ADD COLUMN accessoriesPriceCents INTEGER NOT NULL DEFAULT 0")
                db.execSQL("ALTER TABLE wardrobe_item ADD COLUMN stock INTEGER NOT NULL DEFAULT 1")
                db.execSQL("ALTER TABLE wardrobe_item ADD COLUMN depositDateEpochDay INTEGER")
                db.execSQL("ALTER TABLE wardrobe_item ADD COLUMN isDepositPlan INTEGER NOT NULL DEFAULT 0")
                db.execSQL("ALTER TABLE wardrobe_item ADD COLUMN finalPaymentStartEpochDay INTEGER")
                db.execSQL("ALTER TABLE wardrobe_item ADD COLUMN finalPaymentEndEpochDay INTEGER")
                db.execSQL("ALTER TABLE wardrobe_item ADD COLUMN note TEXT NOT NULL DEFAULT ''")
                db.execSQL("ALTER TABLE wardrobe_item ADD COLUMN sortIndex INTEGER NOT NULL DEFAULT 0")
            }
        }

        private val Migration2To3 = object : Migration(2, 3) {
            override fun migrate(db: SupportSQLiteDatabase) {
                db.execSQL("ALTER TABLE wardrobe_item ADD COLUMN uuid TEXT NOT NULL DEFAULT ''")
                db.execSQL("ALTER TABLE wardrobe_item ADD COLUMN tagNamesJson TEXT NOT NULL DEFAULT '[]'")
                db.execSQL("ALTER TABLE wardrobe_item ADD COLUMN accessoryItemsJson TEXT NOT NULL DEFAULT '[]'")
                db.execSQL("ALTER TABLE wardrobe_item ADD COLUMN sizeChartImagePathsJson TEXT NOT NULL DEFAULT '[]'")
                db.execSQL("ALTER TABLE wardrobe_item ADD COLUMN priceChartImagePathsJson TEXT NOT NULL DEFAULT '[]'")
            }
        }
    }
}
