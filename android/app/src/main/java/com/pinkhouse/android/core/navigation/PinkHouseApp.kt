package com.pinkhouse.android.core.navigation

import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Icon
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
import com.pinkhouse.android.core.di.AppContainer
import com.pinkhouse.android.core.ui.FeaturePlaceholder
import com.pinkhouse.android.feature.wardrobe.WardrobeRoute

@Composable
fun PinkHouseApp(appContainer: AppContainer) {
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
                        icon = {
                            Icon(
                                imageVector = destination.icon,
                                contentDescription = destination.label,
                            )
                        },
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
            composable(AppDestination.Wardrobe.route) {
                WardrobeRoute(
                    appContainer = appContainer,
                )
            }
            composable(AppDestination.House.route) {
                FeaturePlaceholder(
                    title = "House",
                    description = "小世界热区、梦裙日历、穿搭手帐和来财入口会在后续版本接入。",
                )
            }
            composable(AppDestination.Me.route) {
                FeaturePlaceholder(
                    title = "我",
                    description = "主题、备份、VIP、魔法任务和本地设置入口保留占位。",
                )
            }
            composable(AppDestination.PetChat.route) {
                FeaturePlaceholder(
                    title = "萌宠对话",
                    description = "本地规则式气泡和聊天历史会在宠物闭环中实现，本轮不接 AI。",
                )
            }
        }
    }
}
