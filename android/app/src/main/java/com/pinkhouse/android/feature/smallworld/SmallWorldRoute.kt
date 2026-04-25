package com.pinkhouse.android.feature.smallworld

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.TrendingUp
import androidx.compose.material.icons.filled.AutoAwesome
import androidx.compose.material.icons.filled.Book
import androidx.compose.material.icons.filled.CalendarMonth
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Flight
import androidx.compose.material.icons.filled.Inventory2
import androidx.compose.material.icons.filled.LocalOffer
import androidx.compose.material.icons.filled.Paid
import androidx.compose.material.icons.filled.Pets
import androidx.compose.material.icons.filled.PieChart
import androidx.compose.material3.AssistChip
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.pinkhouse.android.core.assets.PinkHouseAssets
import com.pinkhouse.android.core.ui.PinkHouseDesignTokens
import com.pinkhouse.android.core.ui.PinkSegmentedTabs
import com.pinkhouse.android.feature.wardrobe.WardrobeHomeTab

private val houseBackgroundOptions = listOf("日常", "洛可可")

enum class SmallWorldDestination(
    val label: String,
    val subtitle: String,
    val icon: ImageVector,
    val supportingCopy: String,
) {
    Menu("House", "房间入口与功能总览", Icons.Filled.AutoAwesome, "入口汇总、背景切换和房间导航。"),
    SmallWorld("小世界", "房间样式、宠物动画与天气入口", Icons.Filled.AutoAwesome, "这里会承接小世界样式切换、宠物停驻和天气入口。"),
    BigWorld("世界书", "旅行、徽章、航线与世界设定", Icons.Filled.Flight, "后续会把世界书主视觉、章节入口和旅行记录搬过来。"),
    Calendar("梦裙日历", "尾款与穿搭日程", Icons.Filled.CalendarMonth, "这里会对齐 iOS 的梦裙日历排期和最近提醒入口。"),
    Wealth("来财", "招财、数钱、储蓄", Icons.Filled.Paid, "来财页会先补入口切换，再逐步接上动画和数据统计。"),
    Ootd("穿搭手帐", "记录每日搭配", Icons.Filled.Book, "穿搭手帐会先复刻列表骨架，再补详情与编辑。"),
    Perler("拼豆工坊", "像素图纸与工坊", Icons.Filled.PieChart, "拼豆工坊先保留独立导航页，后续再接图纸和工坊状态。"),
    DressStock("裙子股市", "监控裙装行情", Icons.AutoMirrored.Filled.TrendingUp, "裙子股市会先接列表与筛选，再补走势与详情。"),
    RecycleBin("回收站", "恢复、清空与历史项", Icons.Filled.Delete, "回收站后面会统一和衣橱软删除链路打通。"),
    DepositPlan("心愿尾款", "按月与按系列查看待付尾款", Icons.Filled.LocalOffer, "该入口会直接切到衣橱页里的心愿尾款子页。"),
}

private val houseMenuEntries = listOf(
    SmallWorldDestination.SmallWorld,
    SmallWorldDestination.BigWorld,
    SmallWorldDestination.Calendar,
    SmallWorldDestination.Wealth,
    SmallWorldDestination.Ootd,
    SmallWorldDestination.Perler,
    SmallWorldDestination.DressStock,
    SmallWorldDestination.RecycleBin,
    SmallWorldDestination.DepositPlan,
)

@Composable
fun SmallWorldRoute(
    onNavigateWardrobeTab: (WardrobeHomeTab) -> Unit,
    onNavigatePetChat: () -> Unit,
) {
    var backgroundIndex by rememberSaveable { mutableStateOf(0) }
    var currentDestination by rememberSaveable { mutableStateOf(SmallWorldDestination.SmallWorld) }
    val backgroundRes = if (backgroundIndex == 0) PinkHouseAssets.smallWorldNormal else PinkHouseAssets.smallWorldRococo

    BackHandler(enabled = currentDestination != SmallWorldDestination.Menu) {
        currentDestination = SmallWorldDestination.Menu
    }

    Box(modifier = Modifier.fillMaxSize()) {
        Image(
            painter = painterResource(backgroundRes),
            contentDescription = null,
            modifier = Modifier.fillMaxSize(),
            contentScale = ContentScale.Crop,
        )
        Box(
            modifier = Modifier
                .fillMaxSize()
                .background(
                    Brush.verticalGradient(
                        listOf(Color.White.copy(alpha = 0.12f), PinkHouseDesignTokens.Background.copy(alpha = 0.88f)),
                    ),
                ),
        )

        when (currentDestination) {
            SmallWorldDestination.Menu -> {
                SmallWorldMenuScreen(
                    backgroundIndex = backgroundIndex,
                    onBackgroundSelected = { backgroundIndex = it },
                    onOpenDestination = { destination ->
                        if (destination == SmallWorldDestination.DepositPlan) {
                            onNavigateWardrobeTab(WardrobeHomeTab.DepositPlan)
                        } else {
                            currentDestination = destination
                        }
                    },
                    onOpenWardrobe = { onNavigateWardrobeTab(WardrobeHomeTab.Wardrobe) },
                    onOpenPetChat = onNavigatePetChat,
                )
            }
            else -> {
                SmallWorldFeatureScreen(
                    destination = currentDestination,
                    backgroundIndex = backgroundIndex,
                    onBackgroundSelected = { backgroundIndex = it },
                    onBack = { currentDestination = SmallWorldDestination.Menu },
                    onOpenWardrobe = { onNavigateWardrobeTab(WardrobeHomeTab.Wardrobe) },
                    onOpenPetChat = onNavigatePetChat,
                )
            }
        }
    }
}

@Composable
private fun SmallWorldMenuScreen(
    backgroundIndex: Int,
    onBackgroundSelected: (Int) -> Unit,
    onOpenDestination: (SmallWorldDestination) -> Unit,
    onOpenWardrobe: () -> Unit,
    onOpenPetChat: () -> Unit,
) {
    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(horizontal = 18.dp, vertical = 18.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Column(
                modifier = Modifier.weight(1f),
                verticalArrangement = Arrangement.spacedBy(4.dp),
            ) {
                Text(
                    text = "House",
                    style = MaterialTheme.typography.headlineMedium,
                    fontWeight = FontWeight.Bold,
                    color = PinkHouseDesignTokens.TextPrimary,
                )
                Text(
                    text = "菜单、小世界、来财和日历入口",
                    style = MaterialTheme.typography.bodyMedium,
                    color = PinkHouseDesignTokens.TextSecondary,
                )
            }
            Spacer(Modifier.size(12.dp))
            PinkSegmentedTabs(
                tabs = houseBackgroundOptions,
                selectedIndex = backgroundIndex,
                onSelected = onBackgroundSelected,
            )
        }

        SmallWorldHeroCard(
            onOpenWardrobe = onOpenWardrobe,
            onOpenPetChat = onOpenPetChat,
        )

        Surface(
            shape = RoundedCornerShape(20.dp),
            color = Color.White.copy(alpha = 0.72f),
        ) {
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 14.dp, vertical = 12.dp),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Column(
                    modifier = Modifier.weight(1f),
                    verticalArrangement = Arrangement.spacedBy(2.dp),
                ) {
                    Text(
                        text = "入口导航已接通",
                        style = MaterialTheme.typography.titleMedium,
                        fontWeight = FontWeight.Bold,
                        color = PinkHouseDesignTokens.TextPrimary,
                    )
                    Text(
                        text = "这一轮先把 House 内部层级和跳转状态固定下来，具体页面分批继续复刻。",
                        style = MaterialTheme.typography.bodySmall,
                        color = PinkHouseDesignTokens.TextSecondary,
                    )
                }
                AssistChip(
                    onClick = { onOpenDestination(SmallWorldDestination.SmallWorld) },
                    label = { Text("先看小世界") },
                )
            }
        }

        LazyVerticalGrid(
            columns = GridCells.Fixed(2),
            modifier = Modifier.weight(1f),
            contentPadding = PaddingValues(bottom = 104.dp),
            horizontalArrangement = Arrangement.spacedBy(12.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            items(houseMenuEntries, key = { it.name }) { destination ->
                SmallWorldEntryCard(
                    destination = destination,
                    onClick = { onOpenDestination(destination) },
                )
            }
        }
    }
}

@Composable
private fun SmallWorldHeroCard(
    onOpenWardrobe: () -> Unit,
    onOpenPetChat: () -> Unit,
) {
    Card(
        modifier = Modifier.fillMaxWidth(),
        shape = RoundedCornerShape(24.dp),
        colors = CardDefaults.cardColors(containerColor = Color.White.copy(alpha = 0.72f)),
    ) {
        Box(
            modifier = Modifier
                .fillMaxWidth()
                .aspectRatio(1.7f)
                .padding(16.dp),
        ) {
            Image(
                painter = painterResource(PinkHouseAssets.naichaPortrait),
                contentDescription = "奶茶",
                modifier = Modifier
                    .align(Alignment.BottomStart)
                    .size(132.dp),
                contentScale = ContentScale.Fit,
            )
            Image(
                painter = painterResource(PinkHouseAssets.maomaoPortrait),
                contentDescription = "毛毛",
                modifier = Modifier
                    .align(Alignment.BottomEnd)
                    .size(132.dp),
                contentScale = ContentScale.Fit,
            )
            Column(
                modifier = Modifier
                    .fillMaxWidth(0.68f)
                    .fillMaxHeight()
                    .align(Alignment.TopStart),
                verticalArrangement = Arrangement.SpaceBetween,
            ) {
                Surface(
                    shape = RoundedCornerShape(18.dp),
                    color = Color.White.copy(alpha = 0.88f),
                ) {
                    Text(
                        modifier = Modifier.padding(horizontal = 16.dp, vertical = 10.dp),
                        text = "今日房间已准备好",
                        fontWeight = FontWeight.Bold,
                        color = PinkHouseDesignTokens.TextPrimary,
                    )
                }
                Column(
                    verticalArrangement = Arrangement.spacedBy(10.dp),
                ) {
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        AssistChip(onClick = onOpenWardrobe, label = { Text("打开衣橱") })
                        AssistChip(onClick = onOpenPetChat, label = { Text("萌宠对话") })
                    }
                    Text(
                        text = "House 内部子页会从这里继续展开，但底部主导航仍保持“衣橱 / House / 我”。",
                        style = MaterialTheme.typography.bodySmall,
                        color = PinkHouseDesignTokens.TextSecondary,
                    )
                }
            }
        }
    }
}

@Composable
private fun SmallWorldFeatureScreen(
    destination: SmallWorldDestination,
    backgroundIndex: Int,
    onBackgroundSelected: (Int) -> Unit,
    onBack: () -> Unit,
    onOpenWardrobe: () -> Unit,
    onOpenPetChat: () -> Unit,
) {
    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(horizontal = 18.dp, vertical = 18.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            Surface(
                shape = RoundedCornerShape(22.dp),
                color = Color.White.copy(alpha = 0.82f),
            ) {
                IconButton(onClick = onBack) {
                    Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "返回 House 菜单")
                }
            }
            Column(
                modifier = Modifier.weight(1f),
                verticalArrangement = Arrangement.spacedBy(4.dp),
            ) {
                Text(
                    text = destination.label,
                    style = MaterialTheme.typography.headlineSmall,
                    fontWeight = FontWeight.Bold,
                    color = PinkHouseDesignTokens.TextPrimary,
                )
                Text(
                    text = destination.subtitle,
                    style = MaterialTheme.typography.bodyMedium,
                    color = PinkHouseDesignTokens.TextSecondary,
                )
            }
            PinkSegmentedTabs(
                tabs = houseBackgroundOptions,
                selectedIndex = backgroundIndex,
                onSelected = onBackgroundSelected,
            )
        }

        Card(
            modifier = Modifier.fillMaxWidth(),
            shape = RoundedCornerShape(24.dp),
            colors = CardDefaults.cardColors(containerColor = Color.White.copy(alpha = 0.76f)),
        ) {
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(18.dp),
                horizontalArrangement = Arrangement.spacedBy(14.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Surface(
                    shape = RoundedCornerShape(20.dp),
                    color = PinkHouseDesignTokens.Primary.copy(alpha = 0.12f),
                ) {
                    Icon(
                        imageVector = destination.icon,
                        contentDescription = null,
                        modifier = Modifier.padding(16.dp),
                        tint = PinkHouseDesignTokens.Primary,
                    )
                }
                Column(
                    modifier = Modifier.weight(1f),
                    verticalArrangement = Arrangement.spacedBy(4.dp),
                ) {
                    Text(
                        text = "已接通导航骨架",
                        style = MaterialTheme.typography.titleMedium,
                        fontWeight = FontWeight.Bold,
                        color = PinkHouseDesignTokens.TextPrimary,
                    )
                    Text(
                        text = destination.supportingCopy,
                        style = MaterialTheme.typography.bodyMedium,
                        color = PinkHouseDesignTokens.TextSecondary,
                    )
                }
            }
        }

        Card(
            modifier = Modifier.fillMaxWidth(),
            shape = RoundedCornerShape(PinkHouseDesignTokens.CardRadius),
            colors = CardDefaults.cardColors(containerColor = Color.White.copy(alpha = 0.82f)),
        ) {
            Column(
                modifier = Modifier.padding(16.dp),
                verticalArrangement = Arrangement.spacedBy(12.dp),
            ) {
                Text(
                    text = "当前保留的复刻规则",
                    style = MaterialTheme.typography.titleMedium,
                    fontWeight = FontWeight.Bold,
                    color = PinkHouseDesignTokens.TextPrimary,
                )
                SmallWorldMilestoneChip(text = "底部主导航不扩张，House 内页自己管理返回")
                SmallWorldMilestoneChip(text = "背景风格切换继续沿用日常 / 洛可可两套素材")
                SmallWorldMilestoneChip(text = "后续页面直接在这个目的地壳层里替换具体 Compose 内容")
            }
        }

        Card(
            modifier = Modifier.fillMaxWidth(),
            shape = RoundedCornerShape(PinkHouseDesignTokens.CardRadius),
            colors = CardDefaults.cardColors(containerColor = Color.White.copy(alpha = 0.84f)),
        ) {
            Column(
                modifier = Modifier.padding(16.dp),
                verticalArrangement = Arrangement.spacedBy(12.dp),
            ) {
                Text(
                    text = "快速入口",
                    style = MaterialTheme.typography.titleMedium,
                    fontWeight = FontWeight.Bold,
                    color = PinkHouseDesignTokens.TextPrimary,
                )
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.spacedBy(10.dp),
                ) {
                    OutlinedButton(
                        onClick = onOpenWardrobe,
                        modifier = Modifier.weight(1f),
                    ) {
                        Icon(Icons.Filled.Inventory2, contentDescription = null)
                        Spacer(Modifier.size(8.dp))
                        Text("衣橱")
                    }
                    OutlinedButton(
                        onClick = onOpenPetChat,
                        modifier = Modifier.weight(1f),
                    ) {
                        Icon(Icons.Filled.Pets, contentDescription = null)
                        Spacer(Modifier.size(8.dp))
                        Text("萌宠对话")
                    }
                }
                TextButton(onClick = onBack) {
                    Text("返回 House 菜单")
                }
            }
        }

        Spacer(Modifier.weight(1f))
    }
}

@Composable
private fun SmallWorldMilestoneChip(text: String) {
    Surface(
        shape = RoundedCornerShape(18.dp),
        color = PinkHouseDesignTokens.Surface,
    ) {
        Text(
            modifier = Modifier.padding(horizontal = 12.dp, vertical = 10.dp),
            text = text,
            style = MaterialTheme.typography.bodyMedium,
            color = PinkHouseDesignTokens.TextPrimary,
        )
    }
}

@Composable
private fun SmallWorldEntryCard(
    destination: SmallWorldDestination,
    onClick: () -> Unit,
) {
    Card(
        modifier = Modifier
            .fillMaxWidth()
            .clickable(onClick = onClick),
        shape = RoundedCornerShape(PinkHouseDesignTokens.CardRadius),
        colors = CardDefaults.cardColors(containerColor = Color.White.copy(alpha = 0.86f)),
    ) {
        Column(
            modifier = Modifier.padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            Icon(
                imageVector = destination.icon,
                contentDescription = null,
                tint = PinkHouseDesignTokens.Primary,
                modifier = Modifier.size(30.dp),
            )
            Spacer(Modifier.height(2.dp))
            Text(destination.label, fontWeight = FontWeight.Bold, maxLines = 1)
            Text(
                destination.subtitle,
                style = MaterialTheme.typography.bodySmall,
                color = PinkHouseDesignTokens.TextSecondary,
                maxLines = 2,
                overflow = TextOverflow.Ellipsis,
            )
            Text(
                destination.supportingCopy,
                style = MaterialTheme.typography.labelMedium,
                color = PinkHouseDesignTokens.TextSecondary,
                maxLines = 2,
                overflow = TextOverflow.Ellipsis,
            )
        }
    }
}
