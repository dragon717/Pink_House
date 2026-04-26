package com.pinkhouse.android.domain.usecase

import com.pinkhouse.android.domain.repository.WardrobeRepository

class BatchSoftDeleteWardrobeItems(
    private val wardrobeRepository: WardrobeRepository,
) {
    suspend operator fun invoke(ids: Set<Long>) {
        wardrobeRepository.softDeleteItems(ids.toList())
    }
}
