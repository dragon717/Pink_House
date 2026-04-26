package com.pinkhouse.android.domain.model

import java.time.Instant

data class VipState(
    val isActive: Boolean,
    val vipNumber: String?,
    val expiresAt: Instant?,
    val trialUsed: Boolean,
)
