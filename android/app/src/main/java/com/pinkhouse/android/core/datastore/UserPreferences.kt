package com.pinkhouse.android.core.datastore

data class UserPreferences(
    val darkThemeMode: String = "system",
    val wardrobeViewMode: String = "grid2",
    val wardrobeSortOption: String = "createdAtDesc",
    val wardrobeHomeTab: String = "wardrobe",
    val depositDisplayMode: String = "detail",
    val depositReminderEnabled: Boolean = false,
    val depositReminderDaysBefore: String = "7,3,1",
    val depositReminderTime: String = "09:00",
    val soundEnabled: Boolean = true,
    val hapticsEnabled: Boolean = true,
    val languageTag: String = "system",
)
