package com.pinkhouse.android

import android.app.Application
import com.pinkhouse.android.data.local.PinkHouseDatabase
import timber.log.Timber

class PinkHouseApplication : Application() {
    val database: PinkHouseDatabase by lazy {
        PinkHouseDatabase.create(applicationContext)
    }

    override fun onCreate() {
        super.onCreate()
        if (BuildConfig.DEBUG) {
            Timber.plant(Timber.DebugTree())
        }
    }
}
