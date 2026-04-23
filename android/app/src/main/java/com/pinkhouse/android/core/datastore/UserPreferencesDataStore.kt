package com.pinkhouse.android.core.datastore

import android.content.Context
import androidx.datastore.preferences.core.booleanPreferencesKey
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.stringPreferencesKey
import androidx.datastore.preferences.preferencesDataStore
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map

private val Context.userPreferencesStore by preferencesDataStore(name = "user_preferences")

class UserPreferencesDataStore(
    private val context: Context,
) {
    val preferences: Flow<UserPreferences> = context.userPreferencesStore.data.map { values ->
        UserPreferences(
            darkThemeMode = values[Keys.DarkThemeMode] ?: "system",
            wardrobeViewMode = values[Keys.WardrobeViewMode] ?: "grid2",
            wardrobeSortOption = values[Keys.WardrobeSortOption] ?: "createdAtDesc",
            wardrobeHomeTab = values[Keys.WardrobeHomeTab] ?: "wardrobe",
            depositDisplayMode = values[Keys.DepositDisplayMode] ?: "detail",
            depositReminderEnabled = values[Keys.DepositReminderEnabled] ?: false,
            depositReminderDaysBefore = values[Keys.DepositReminderDaysBefore] ?: "7,3,1",
            depositReminderTime = values[Keys.DepositReminderTime] ?: "09:00",
            soundEnabled = values[Keys.SoundEnabled] ?: true,
            hapticsEnabled = values[Keys.HapticsEnabled] ?: true,
            languageTag = values[Keys.LanguageTag] ?: "system",
        )
    }

    suspend fun setWardrobeViewMode(viewMode: String) {
        context.userPreferencesStore.edit { values ->
            values[Keys.WardrobeViewMode] = viewMode
        }
    }

    suspend fun setWardrobeSortOption(sortOption: String) {
        context.userPreferencesStore.edit { values ->
            values[Keys.WardrobeSortOption] = sortOption
        }
    }

    suspend fun setWardrobeHomeTab(tab: String) {
        context.userPreferencesStore.edit { values ->
            values[Keys.WardrobeHomeTab] = tab
        }
    }

    suspend fun setDepositDisplayMode(displayMode: String) {
        context.userPreferencesStore.edit { values ->
            values[Keys.DepositDisplayMode] = displayMode
        }
    }

    suspend fun setDepositReminderEnabled(enabled: Boolean) {
        context.userPreferencesStore.edit { values ->
            values[Keys.DepositReminderEnabled] = enabled
        }
    }

    suspend fun setDepositReminderDaysBefore(daysBefore: String) {
        context.userPreferencesStore.edit { values ->
            values[Keys.DepositReminderDaysBefore] = daysBefore
        }
    }

    suspend fun setDepositReminderTime(time: String) {
        context.userPreferencesStore.edit { values ->
            values[Keys.DepositReminderTime] = time
        }
    }

    private object Keys {
        val DarkThemeMode = stringPreferencesKey("dark_theme_mode")
        val WardrobeViewMode = stringPreferencesKey("wardrobe_view_mode")
        val WardrobeSortOption = stringPreferencesKey("wardrobe_sort_option")
        val WardrobeHomeTab = stringPreferencesKey("wardrobe_home_tab")
        val DepositDisplayMode = stringPreferencesKey("deposit_display_mode")
        val DepositReminderEnabled = booleanPreferencesKey("deposit_reminder_enabled")
        val DepositReminderDaysBefore = stringPreferencesKey("deposit_reminder_days_before")
        val DepositReminderTime = stringPreferencesKey("deposit_reminder_time")
        val SoundEnabled = booleanPreferencesKey("sound_enabled")
        val HapticsEnabled = booleanPreferencesKey("haptics_enabled")
        val LanguageTag = stringPreferencesKey("language_tag")
    }
}
