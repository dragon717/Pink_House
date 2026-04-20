package com.pinkhouse.android.core.ui.theme

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable

private val LightColors = lightColorScheme(
    primary = PinkHousePrimary,
    onPrimary = PinkHouseOnPrimary,
    primaryContainer = PinkHousePrimaryContainer,
    surface = PinkHouseSurface,
)

private val DarkColors = darkColorScheme(
    primary = PinkHousePrimaryContainer,
    onPrimary = PinkHouseSurfaceDark,
    surface = PinkHouseSurfaceDark,
)

@Composable
fun PinkHouseTheme(
    darkTheme: Boolean = isSystemInDarkTheme(),
    content: @Composable () -> Unit,
) {
    MaterialTheme(
        colorScheme = if (darkTheme) DarkColors else LightColors,
        content = content,
    )
}
