package com.pinkhouse.android.core.di

import android.content.Context
import com.pinkhouse.android.core.datastore.UserPreferencesDataStore
import com.pinkhouse.android.core.media.WardrobeImageStore
import com.pinkhouse.android.core.notification.DepositReminderScheduler
import com.pinkhouse.android.data.local.PinkHouseDatabase
import com.pinkhouse.android.data.repository.RoomWardrobeRepository
import com.pinkhouse.android.domain.repository.WardrobeRepository
import com.pinkhouse.android.domain.usecase.AddSampleWardrobeItems
import com.pinkhouse.android.domain.usecase.BatchSoftDeleteWardrobeItems
import com.pinkhouse.android.domain.usecase.GetWardrobeItems

class AppContainer(
    private val context: Context,
    database: PinkHouseDatabase,
    val userPreferencesDataStore: UserPreferencesDataStore,
    val wardrobeImageStore: WardrobeImageStore,
) {
    private val wardrobeRepository: WardrobeRepository by lazy {
        RoomWardrobeRepository(database.wardrobeItemDao())
    }

    val getWardrobeItems: GetWardrobeItems by lazy {
        GetWardrobeItems(wardrobeRepository)
    }

    val addSampleWardrobeItems: AddSampleWardrobeItems by lazy {
        AddSampleWardrobeItems(wardrobeRepository)
    }

    val batchSoftDeleteWardrobeItems: BatchSoftDeleteWardrobeItems by lazy {
        BatchSoftDeleteWardrobeItems(wardrobeRepository)
    }

    val depositReminderScheduler: DepositReminderScheduler by lazy {
        DepositReminderScheduler(context.applicationContext)
    }

    val wardrobeRepositoryForViewModel: WardrobeRepository
        get() = wardrobeRepository
}
