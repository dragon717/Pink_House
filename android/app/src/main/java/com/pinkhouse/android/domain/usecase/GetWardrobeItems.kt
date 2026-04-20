package com.pinkhouse.android.domain.usecase

import com.pinkhouse.android.domain.model.WardrobeItem
import com.pinkhouse.android.domain.repository.WardrobeRepository
import kotlinx.coroutines.flow.Flow

class GetWardrobeItems(
    private val wardrobeRepository: WardrobeRepository,
) {
    operator fun invoke(searchQuery: String = ""): Flow<List<WardrobeItem>> {
        return wardrobeRepository.observeItems(searchQuery)
    }
}
