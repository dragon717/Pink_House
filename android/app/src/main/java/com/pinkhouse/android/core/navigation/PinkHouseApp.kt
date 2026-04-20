package com.pinkhouse.android.core.navigation

import androidx.compose.foundation.layout.padding
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.navigation.NavDestination.Companion.hierarchy
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.currentBackStackEntryAsState
import androidx.navigation.compose.rememberNavController
import com.pinkhouse.android.feature.pet.PetRoute
import com.pinkhouse.android.feature.settings.SettingsRoute
import com.pinkhouse.android.feature.smallworld.SmallWorldRoute
import com.pinkhouse.android.feature.vip.VipRoute
import com.pinkhouse.android.feature.wardrobe.WardrobeRoute
import com.pinkhouse.android.feature.wealth.WealthRoute

@Composable
fun PinkHouseApp() {
    val navController = rememberNavController()
    val destinations = AppDestination.entries
    val navBackStackEntry by navController.currentBackStackEntryAsState()
    val currentDestination = navBackStackEntry?.destination

    Scaffold(
        bottomBar = {
            NavigationBar {
                destinations.forEach { destination ->
                    val selected = currentDestination
                        ?.hierarchy
                        ?.any { it.route == destination.route } == true
                    NavigationBarItem(
                        selected = selected,
                        onClick = {
                            navController.navigate(destination.route) {
                                popUpTo(navController.graph.startDestinationId) {
                                    saveState = true
                                }
                                launchSingleTop = true
                                restoreState = true
                            }
                        },
                        icon = { Text(destination.label.take(1)) },
                        label = { Text(destination.label) },
                    )
                }
            }
        },
    ) { innerPadding ->
        NavHost(
            navController = navController,
            startDestination = AppDestination.Wardrobe.route,
            modifier = Modifier.padding(innerPadding),
        ) {
            composable(AppDestination.Wardrobe.route) { WardrobeRoute() }
            composable(AppDestination.Pet.route) { PetRoute() }
            composable(AppDestination.SmallWorld.route) { SmallWorldRoute() }
            composable(AppDestination.Wealth.route) { WealthRoute() }
            composable(AppDestination.Vip.route) { VipRoute() }
            composable(AppDestination.Settings.route) { SettingsRoute() }
        }
    }
}
