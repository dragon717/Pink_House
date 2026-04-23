package com.pinkhouse.android

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.core.splashscreen.SplashScreen.Companion.installSplashScreen
import com.pinkhouse.android.core.navigation.PinkHouseApp
import com.pinkhouse.android.core.ui.theme.PinkHouseTheme

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        installSplashScreen()
        super.onCreate(savedInstanceState)
        val appContainer = (application as PinkHouseApplication).appContainer
        setContent {
            PinkHouseTheme {
                PinkHouseApp(appContainer = appContainer)
            }
        }
    }
}
