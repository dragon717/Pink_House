package com.pinkhouse.android.core.di

import com.pinkhouse.android.data.local.PinkHouseDatabase
import com.pinkhouse.android.data.repository.RoomWardrobeRepository
import com.pinkhouse.android.domain.repository.WardrobeRepository
import com.pinkhouse.android.domain.usecase.AddSampleWardrobeItems
import com.pinkhouse.android.domain.usecase.GetWardrobeItems

class AppContainer(
    database: PinkHouseDatabase,
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
}
