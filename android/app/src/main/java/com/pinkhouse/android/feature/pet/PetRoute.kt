package com.pinkhouse.android.feature.pet

import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Backpack
import androidx.compose.material.icons.filled.Bolt
import androidx.compose.material.icons.filled.Brush
import androidx.compose.material.icons.filled.CleaningServices
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.ExpandLess
import androidx.compose.material.icons.filled.Favorite
import androidx.compose.material.icons.filled.LocalCafe
import androidx.compose.material.icons.filled.LocalDining
import androidx.compose.material.icons.filled.Paid
import androidx.compose.material.icons.filled.Pets
import androidx.compose.material.icons.filled.ShoppingBag
import androidx.compose.material.icons.filled.Visibility
import androidx.compose.material.icons.filled.VisibilityOff
import androidx.compose.material.icons.filled.Work
import androidx.compose.material3.AssistChip
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.FilterChip
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import com.pinkhouse.android.core.assets.PinkHouseAssets
import com.pinkhouse.android.core.ui.PinkHouseDesignTokens
import com.pinkhouse.android.core.ui.theme.PinkHouseTheme

@Composable
fun PetRoute(
    onBackToWardrobe: () -> Unit,
    modifier: Modifier = Modifier,
    viewModel: PetViewModel = viewModel(),
) {
    val uiState by viewModel.uiState.collectAsStateWithLifecycle()

    PetHomeContent(
        uiState = uiState,
        onBackToWardrobe = onBackToWardrobe,
        onSwitchPet = viewModel::switchPet,
        onToggleStatusBars = viewModel::toggleStatusBars,
        onSetPanelState = viewModel::setPanelState,
        onSetShopTab = viewModel::setShopTab,
        onFeed = viewModel::feed,
        onDrink = viewModel::drink,
        onClean = viewModel::clean,
        onPet = viewModel::pet,
        onToggleWork = viewModel::toggleWork,
        modifier = modifier,
    )
}

@Composable
private fun PetHomeContent(
    uiState: PetUiState,
    onBackToWardrobe: () -> Unit,
    onSwitchPet: (PetCharacter) -> Unit,
    onToggleStatusBars: () -> Unit,
    onSetPanelState: (PetPanelState) -> Unit,
    onSetShopTab: (PetShopTab) -> Unit,
    onFeed: () -> Unit,
    onDrink: () -> Unit,
    onClean: () -> Unit,
    onPet: () -> Unit,
    onToggleWork: () -> Unit,
    modifier: Modifier = Modifier,
) {
    Box(
        modifier = modifier
            .fillMaxSize()
            .background(
                Brush.verticalGradient(
                    listOf(PinkHouseDesignTokens.Background, PinkHouseDesignTokens.Surface),
                ),
            ),
    ) {
        LazyColumn(
            modifier = Modifier
                .fillMaxSize()
                .statusBarsPadding()
                .padding(horizontal = PinkHouseDesignTokens.PageHorizontalPadding),
            verticalArrangement = Arrangement.spacedBy(14.dp),
        ) {
            item {
                PetHomeTopBar(
                    uiState = uiState,
                    onBackToWardrobe = onBackToWardrobe,
                    onToggleStatusBars = onToggleStatusBars,
                )
            }

            item {
                PetSwitchRow(
                    selectedPet = uiState.selectedPet,
                    onSwitchPet = onSwitchPet,
                )
            }

            if (uiState.showStatusBars) {
                item { PetStatusGrid(uiState = uiState) }
            }

            item {
                PetStageCard(
                    uiState = uiState,
                    onPet = onPet,
                )
            }

            item {
                PetActionGrid(
                    isWorking = uiState.isWorking,
                    onFeed = onFeed,
                    onDrink = onDrink,
                    onClean = onClean,
                    onPet = onPet,
                    onToggleWork = onToggleWork,
                )
            }

            item {
                PetMessagePanel(messages = uiState.messages)
            }

            item {
                if (uiState.panelState == PetPanelState.Hidden) {
                    PetFloatingShortcutRow(
                        onDialogue = onPet,
                        onOpenPanel = { onSetPanelState(PetPanelState.Collapsed) },
                    )
                } else {
                    PetBottomPanelCard(
                        uiState = uiState,
                        onSetPanelState = onSetPanelState,
                        onSetShopTab = onSetShopTab,
                    )
                }
            }

            item { Spacer(Modifier.height(12.dp)) }
        }
    }
}

@Composable
private fun PetHomeTopBar(
    uiState: PetUiState,
    onBackToWardrobe: () -> Unit,
    onToggleStatusBars: () -> Unit,
    modifier: Modifier = Modifier,
) {
    Row(
        modifier = modifier
            .fillMaxWidth()
            .padding(top = 8.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        IconButton(onClick = onBackToWardrobe) {
            Icon(
                imageVector = Icons.AutoMirrored.Filled.ArrowBack,
                contentDescription = "返回衣橱",
                tint = PinkHouseDesignTokens.TextPrimary,
            )
        }

        Column(modifier = Modifier.weight(1f)) {
            Text(
                text = "萌宠小家",
                style = MaterialTheme.typography.titleLarge,
                fontWeight = FontWeight.Bold,
                color = PinkHouseDesignTokens.TextPrimary,
            )
            Text(
                text = if (uiState.isWorking) "${uiState.selectedPet.displayName}正在打工" else "本地规则式陪伴模式",
                style = MaterialTheme.typography.labelMedium,
                color = PinkHouseDesignTokens.TextSecondary,
            )
        }

        CurrencyCapsule(icon = Icons.Filled.Paid, text = uiState.meowCoin.toString())
        IconButton(onClick = onToggleStatusBars) {
            Icon(
                imageVector = if (uiState.showStatusBars) Icons.Filled.Visibility else Icons.Filled.VisibilityOff,
                contentDescription = "显示或隐藏状态条",
                tint = PinkHouseDesignTokens.TextSecondary,
            )
        }
    }
}

@Composable
private fun PetSwitchRow(
    selectedPet: PetCharacter,
    onSwitchPet: (PetCharacter) -> Unit,
    modifier: Modifier = Modifier,
) {
    Surface(
        modifier = modifier.fillMaxWidth(),
        shape = RoundedCornerShape(PinkHouseDesignTokens.PlatterRadius),
        color = PinkHouseDesignTokens.SurfaceTranslucent,
    ) {
        Row(
            modifier = Modifier.padding(8.dp),
            horizontalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            PetCharacter.entries.forEach { pet ->
                FilterChip(
                    selected = selectedPet == pet,
                    onClick = { onSwitchPet(pet) },
                    label = { Text(pet.displayName) },
                    leadingIcon = {
                        Icon(
                            imageVector = Icons.Filled.Pets,
                            contentDescription = null,
                            modifier = Modifier.size(18.dp),
                        )
                    },
                    modifier = Modifier.weight(1f),
                )
            }
        }
    }
}

@Composable
private fun PetStatusGrid(
    uiState: PetUiState,
    modifier: Modifier = Modifier,
) {
    Column(
        modifier = modifier.fillMaxWidth(),
        verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            StatusMeter(
                label = "饱腹",
                value = uiState.hunger,
                icon = Icons.Filled.LocalDining,
                modifier = Modifier.weight(1f),
            )
            StatusMeter(
                label = "清洁",
                value = uiState.hygiene,
                icon = Icons.Filled.CleaningServices,
                modifier = Modifier.weight(1f),
            )
        }
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            StatusMeter(
                label = "体力",
                value = uiState.energy,
                icon = Icons.Filled.Bolt,
                modifier = Modifier.weight(1f),
            )
            StatusMeter(
                label = "心情",
                value = uiState.mood,
                icon = Icons.Filled.Favorite,
                modifier = Modifier.weight(1f),
            )
        }
    }
}

@Composable
private fun StatusMeter(
    label: String,
    value: Int,
    icon: ImageVector,
    modifier: Modifier = Modifier,
) {
    Surface(
        modifier = modifier,
        shape = RoundedCornerShape(PinkHouseDesignTokens.CardRadius),
        color = PinkHouseDesignTokens.SurfaceStrong,
        shadowElevation = 1.dp,
    ) {
        Column(
            modifier = Modifier.padding(12.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Icon(icon, contentDescription = null, tint = PinkHouseDesignTokens.Accent)
                Text(
                    text = label,
                    modifier = Modifier
                        .weight(1f)
                        .padding(start = 6.dp),
                    style = MaterialTheme.typography.labelLarge,
                    color = PinkHouseDesignTokens.TextPrimary,
                )
                Text(
                    text = "$value",
                    style = MaterialTheme.typography.labelLarge,
                    fontWeight = FontWeight.Bold,
                    color = PinkHouseDesignTokens.TextSecondary,
                )
            }
            LinearProgressIndicator(
                progress = { value / 100f },
                modifier = Modifier.fillMaxWidth(),
                color = PinkHouseDesignTokens.Accent,
                trackColor = PinkHouseDesignTokens.Background,
            )
        }
    }
}

@Composable
private fun PetStageCard(
    uiState: PetUiState,
    onPet: () -> Unit,
    modifier: Modifier = Modifier,
) {
    Surface(
        modifier = modifier.fillMaxWidth(),
        shape = RoundedCornerShape(PinkHouseDesignTokens.PlatterRadius),
        color = PinkHouseDesignTokens.SurfaceTranslucent,
        shadowElevation = 2.dp,
    ) {
        Column(
            modifier = Modifier.padding(18.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Box(
                modifier = Modifier
                    .size(188.dp)
                    .clip(CircleShape)
                    .background(PinkHouseDesignTokens.Background)
                    .clickable(onClick = onPet),
                contentAlignment = Alignment.Center,
            ) {
                Image(
                    painter = painterResource(petPortrait(uiState.selectedPet)),
                    contentDescription = uiState.selectedPet.displayName,
                    modifier = Modifier.size(158.dp),
                    contentScale = ContentScale.Fit,
                )
            }

            Text(
                text = uiState.selectedPet.displayName,
                style = MaterialTheme.typography.headlineSmall,
                fontWeight = FontWeight.Bold,
                color = PinkHouseDesignTokens.TextPrimary,
            )
            Text(
                text = if (uiState.isWorking) "正在外出打工，结束后会带回喵币" else "点一点它，可以触发抚摸互动",
                style = MaterialTheme.typography.bodyMedium,
                color = PinkHouseDesignTokens.TextSecondary,
            )

            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                CurrencyCapsule(icon = Icons.Filled.Paid, text = "${uiState.meowCoin} 喵币")
                CurrencyCapsule(icon = Icons.Filled.LocalCafe, text = "${uiState.fishCoin} 鱼币")
                CurrencyCapsule(icon = Icons.Filled.Pets, text = "${uiState.boneCoin} 骨币")
            }
        }
    }
}

@Composable
private fun PetActionGrid(
    isWorking: Boolean,
    onFeed: () -> Unit,
    onDrink: () -> Unit,
    onClean: () -> Unit,
    onPet: () -> Unit,
    onToggleWork: () -> Unit,
    modifier: Modifier = Modifier,
) {
    Column(
        modifier = modifier.fillMaxWidth(),
        verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            PetActionButton("喂食", Icons.Filled.LocalDining, onFeed, Modifier.weight(1f))
            PetActionButton("饮水", Icons.Filled.LocalCafe, onDrink, Modifier.weight(1f))
            PetActionButton("抚摸", Icons.Filled.Pets, onPet, Modifier.weight(1f))
        }
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            PetActionButton("清洁", Icons.Filled.CleaningServices, onClean, Modifier.weight(1f))
            PetActionButton(
                label = if (isWorking) "结束打工" else "送去打工",
                icon = Icons.Filled.Work,
                onClick = onToggleWork,
                modifier = Modifier.weight(1f),
            )
        }
    }
}

@Composable
private fun PetActionButton(
    label: String,
    icon: ImageVector,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
) {
    Button(
        onClick = onClick,
        modifier = modifier,
        colors = ButtonDefaults.buttonColors(containerColor = PinkHouseDesignTokens.Accent),
        shape = RoundedCornerShape(PinkHouseDesignTokens.CardRadius),
    ) {
        Icon(icon, contentDescription = null, modifier = Modifier.size(18.dp))
        Text(text = label, modifier = Modifier.padding(start = 6.dp))
    }
}

@Composable
private fun PetMessagePanel(
    messages: List<PetHomeMessage>,
    modifier: Modifier = Modifier,
) {
    Surface(
        modifier = modifier.fillMaxWidth(),
        shape = RoundedCornerShape(PinkHouseDesignTokens.LargeCardRadius),
        color = PinkHouseDesignTokens.SurfaceStrong,
    ) {
        Column(
            modifier = Modifier.padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            Text(
                text = "互动记录",
                style = MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.SemiBold,
                color = PinkHouseDesignTokens.TextPrimary,
            )
            messages.forEach { message ->
                Text(
                    text = message.text,
                    style = MaterialTheme.typography.bodyMedium,
                    color = PinkHouseDesignTokens.TextSecondary,
                )
            }
        }
    }
}

@Composable
private fun PetBottomPanelCard(
    uiState: PetUiState,
    onSetPanelState: (PetPanelState) -> Unit,
    onSetShopTab: (PetShopTab) -> Unit,
    modifier: Modifier = Modifier,
) {
    Surface(
        modifier = modifier.fillMaxWidth(),
        shape = RoundedCornerShape(PinkHouseDesignTokens.PlatterRadius),
        color = PinkHouseDesignTokens.SurfaceTranslucent,
        shadowElevation = 2.dp,
    ) {
        Column(
            modifier = Modifier.padding(14.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                FilterChip(
                    selected = uiState.selectedShopTab == PetShopTab.Inventory,
                    onClick = { onSetShopTab(PetShopTab.Inventory) },
                    label = { Text("背包") },
                    leadingIcon = { Icon(Icons.Filled.Backpack, contentDescription = null) },
                )
                FilterChip(
                    selected = uiState.selectedShopTab == PetShopTab.Shop,
                    onClick = { onSetShopTab(PetShopTab.Shop) },
                    label = { Text("商店") },
                    leadingIcon = { Icon(Icons.Filled.ShoppingBag, contentDescription = null) },
                    modifier = Modifier.padding(start = 8.dp),
                )
                Spacer(Modifier.weight(1f))
                IconButton(onClick = { onSetPanelState(PetPanelState.Hidden) }) {
                    Icon(Icons.Filled.Close, contentDescription = "隐藏面板")
                }
                IconButton(onClick = { onSetPanelState(PetPanelState.Expanded) }) {
                    Icon(Icons.Filled.ExpandLess, contentDescription = "展开面板")
                }
            }

            val items = if (uiState.selectedShopTab == PetShopTab.Inventory) {
                listOf("猫粮罐头 ×2", "清洁喷雾 ×1", "陪玩球 ×3")
            } else {
                listOf("活力小鱼干", "香香沐浴露", "改名项圈")
            }
            val visibleItems = if (uiState.panelState == PetPanelState.Expanded) items else items.take(2)

            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                visibleItems.forEach { label ->
                    AssistChip(
                        onClick = { },
                        label = { Text(label) },
                        leadingIcon = { Icon(Icons.Filled.Brush, contentDescription = null) },
                    )
                }
            }

            if (uiState.panelState == PetPanelState.Hidden) {
                OutlinedButton(onClick = { onSetPanelState(PetPanelState.Collapsed) }) {
                    Icon(Icons.Filled.Backpack, contentDescription = null)
                    Text("打开背包", modifier = Modifier.padding(start = 6.dp))
                }
            }
        }
    }
}

@Composable
private fun PetFloatingShortcutRow(
    onDialogue: () -> Unit,
    onOpenPanel: () -> Unit,
    modifier: Modifier = Modifier,
) {
    Row(
        modifier = modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.SpaceBetween,
        verticalAlignment = Alignment.CenterVertically,
    ) {
        OutlinedButton(onClick = onDialogue) {
            Icon(Icons.Filled.Pets, contentDescription = null)
            Text("对话", modifier = Modifier.padding(start = 6.dp))
        }
        Button(
            onClick = onOpenPanel,
            colors = ButtonDefaults.buttonColors(containerColor = PinkHouseDesignTokens.Accent),
            shape = RoundedCornerShape(PinkHouseDesignTokens.CardRadius),
        ) {
            Icon(Icons.Filled.Backpack, contentDescription = null)
            Text("背包", modifier = Modifier.padding(start = 6.dp))
        }
    }
}

@Composable
private fun CurrencyCapsule(
    icon: ImageVector,
    text: String,
    modifier: Modifier = Modifier,
) {
    Surface(
        modifier = modifier,
        shape = CircleShape,
        color = PinkHouseDesignTokens.SurfaceStrong,
        shadowElevation = 1.dp,
    ) {
        Row(
            modifier = Modifier.padding(horizontal = 10.dp, vertical = 6.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(4.dp),
        ) {
            Icon(
                imageVector = icon,
                contentDescription = null,
                tint = PinkHouseDesignTokens.WarmAccent,
                modifier = Modifier.size(18.dp),
            )
            Text(
                text = text,
                style = MaterialTheme.typography.labelLarge,
                fontWeight = FontWeight.SemiBold,
                color = PinkHouseDesignTokens.TextPrimary,
            )
        }
    }
}

private fun petPortrait(pet: PetCharacter): Int =
    when (pet) {
        PetCharacter.Naicha -> PinkHouseAssets.naichaPortrait
        PetCharacter.Maomao -> PinkHouseAssets.maomaoPortrait
    }

@Preview(showBackground = true, widthDp = 393, heightDp = 852)
@Composable
private fun PetHomeContentPreview() {
    PinkHouseTheme {
        PetHomeContent(
            uiState = PetUiState(panelState = PetPanelState.Collapsed),
            onBackToWardrobe = {},
            onSwitchPet = {},
            onToggleStatusBars = {},
            onSetPanelState = {},
            onSetShopTab = {},
            onFeed = {},
            onDrink = {},
            onClean = {},
            onPet = {},
            onToggleWork = {},
        )
    }
}
