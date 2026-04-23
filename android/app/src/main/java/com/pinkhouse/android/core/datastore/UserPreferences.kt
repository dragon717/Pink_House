package com.pinkhouse.android.core.datastore

data class UserPreferences(
    val darkThemeMode: String = "system",
    val wardrobeViewMode: String = "grid2",
    val wardrobeSortOption: String = "createdAtDesc",
    val wardrobeHomeTab: String = "wardrobe",
    val depositDisplayMode: String = "detail",
    val soundEnabled: Boolean = true,
    val hapticsEnabled: Boolean = true,
    val languageTag: String = "system",
)
