package com.pinkhouse.android

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import com.pinkhouse.android.core.navigation.PinkHouseApp
import com.pinkhouse.android.core.ui.theme.PinkHouseTheme

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContent {
            PinkHouseTheme {
                PinkHouseApp()
            }
        }
    }
}
