package com.pinkhouse.android.core.navigation

import androidx.compose.foundation.Image
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.asPaddingValues
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.navigationBars
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.unit.dp
import androidx.navigation.NavDestination.Companion.hierarchy
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.currentBackStackEntryAsState
import androidx.navigation.compose.rememberNavController
import com.pinkhouse.android.core.assets.PinkHouseAssets
import com.pinkhouse.android.core.di.AppContainer
import com.pinkhouse.android.core.ui.PinkBottomNavBar
import com.pinkhouse.android.core.ui.PinkBottomNavItem
import com.pinkhouse.android.core.ui.PinkHouseDesignTokens
import com.pinkhouse.android.feature.me.MeRoute
import com.pinkhouse.android.feature.pet.PetRoute
import com.pinkhouse.android.feature.smallworld.SmallWorldRoute
import com.pinkhouse.android.feature.wardrobe.WardrobeHomeTab
import com.pinkhouse.android.feature.wardrobe.WardrobeRoute

@Composable
fun PinkHouseApp(appContainer: AppContainer) {
    val navController = rememberNavController()
    var requestedWardrobeHomeTab by rememberSaveable { mutableStateOf<WardrobeHomeTab?>(null) }
    val bottomDestinations = AppDestination.entries.filter { it.showInBottomBar }
    val navBackStackEntry by navController.currentBackStackEntryAsState()
    val currentDestination = navBackStackEntry?.destination
    val currentRoute = currentDestination?.route
    val showPetFloatingEntry = currentRoute != AppDestination.House.route && currentRoute != AppDestination.PetChat.route

    Box(modifier = Modifier.fillMaxSize()) {
        NavHost(
            navController = navController,
            startDestination = AppDestination.Wardrobe.route,
            modifier = Modifier.fillMaxSize(),
        ) {
            composable(AppDestination.Wardrobe.route) {
                WardrobeRoute(
                    appContainer = appContainer,
                    requestedHomeTab = requestedWardrobeHomeTab,
                    onRequestedHomeTabConsumed = { requestedWardrobeHomeTab = null },
                )
            }
            composable(AppDestination.House.route) {
                SmallWorldRoute(
                    onNavigateWardrobeTab = { tab ->
                        requestedWardrobeHomeTab = tab
                        navController.navigate(AppDestination.Wardrobe.route) {
                            launchSingleTop = true
                            restoreState = true
                        }
                    },
                    onNavigatePetChat = {
                        navController.navigate(AppDestination.PetChat.route) {
                            launchSingleTop = true
                        }
                    },
                )
            }
            composable(AppDestination.Me.route) {
                MeRoute(
                    onOpenWardrobeSettings = {
                        navController.navigate(AppDestination.Wardrobe.route) {
                            launchSingleTop = true
                            restoreState = true
                        }
                    },
                    onOpenPetSettings = {
                        navController.navigate(AppDestination.PetChat.route) {
                            launchSingleTop = true
                        }
                    },
                )
            }
            composable(AppDestination.PetChat.route) {
                PetRoute(onBackToWardrobe = {
                    navController.navigate(AppDestination.Wardrobe.route) {
                        popUpTo(AppDestination.Wardrobe.route) { inclusive = false }
                        launchSingleTop = true
                    }
                })
            }
        }

        if (showPetFloatingEntry) {
            Image(
                painter = painterResource(PinkHouseAssets.naichaPeeking),
                contentDescription = "naicha_peeking",
                modifier = Modifier
                    .align(Alignment.BottomCenter)
                    .padding(
                        bottom = PinkHouseDesignTokens.BottomNavHeight +
                            WindowInsets.navigationBars.asPaddingValues().calculateBottomPadding() +
                            2.dp,
                    )
                    .size(width = 112.dp, height = 70.dp),
                contentScale = ContentScale.Fit,
            )
        }

        if (currentRoute != AppDestination.PetChat.route) {
            PinkBottomNavBar(modifier = Modifier.align(Alignment.BottomCenter)) {
                bottomDestinations.forEach { destination ->
                    val selected = currentDestination
                        ?.hierarchy
                        ?.any { it.route == destination.route } == true
                    PinkBottomNavItem(
                        selected = selected,
                        label = destination.label,
                        icon = destination.icon,
                        onClick = {
                            navController.navigate(destination.route) {
                                popUpTo(navController.graph.startDestinationId) {
                                    saveState = true
                                }
                                launchSingleTop = true
                                restoreState = true
                            }
                        },
                        modifier = Modifier.weight(1f),
                    )
                }
            }
        }
    }
}
