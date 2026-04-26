package com.pinkhouse.android.core.navigation

import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ChatBubble
import androidx.compose.material.icons.filled.Face
import androidx.compose.material.icons.filled.Home
import androidx.compose.material.icons.filled.Inventory2
import androidx.compose.ui.graphics.vector.ImageVector

enum class AppDestination(
    val route: String,
    val label: String,
    val icon: ImageVector,
    val showInBottomBar: Boolean = true,
) {
    Wardrobe("wardrobe", "衣橱", Icons.Filled.Inventory2),
    House("house", "House", Icons.Filled.Home),
    Me("me", "我", Icons.Filled.Face),
    PetChat("petChat", "萌宠对话", Icons.Filled.ChatBubble),
}
