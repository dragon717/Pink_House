package com.pinkhouse.android.core.navigation

enum class AppDestination(
    val route: String,
    val label: String,
) {
    Wardrobe("wardrobe", "Wardrobe"),
    Pet("pet", "Pet"),
    SmallWorld("smallworld", "World"),
    Wealth("wealth", "Wealth"),
    Vip("vip", "VIP"),
    Settings("settings", "Settings"),
}
