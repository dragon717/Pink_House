package com.pinkhouse.android.core.datastore

data class UserPreferences(
    val darkThemeMode: String = "system",
    val wardrobeViewMode: String = "grid",
    val soundEnabled: Boolean = true,
    val hapticsEnabled: Boolean = true,
    val languageTag: String = "system",
)
