package com.pinkhouse.android

import android.app.Application
import com.pinkhouse.android.core.datastore.UserPreferencesDataStore
import com.pinkhouse.android.core.di.AppContainer
import com.pinkhouse.android.core.media.WardrobeImageStore
import com.pinkhouse.android.data.local.PinkHouseDatabase
import timber.log.Timber

class PinkHouseApplication : Application() {
    val database: PinkHouseDatabase by lazy {
        PinkHouseDatabase.create(applicationContext)
    }
    val appContainer: AppContainer by lazy {
        AppContainer(
            database = database,
            userPreferencesDataStore = UserPreferencesDataStore(applicationContext),
            wardrobeImageStore = WardrobeImageStore(applicationContext),
        )
    }

    override fun onCreate() {
        super.onCreate()
        if (BuildConfig.DEBUG) {
            Timber.plant(Timber.DebugTree())
        }
    }
}
