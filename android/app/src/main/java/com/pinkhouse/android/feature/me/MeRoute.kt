package com.pinkhouse.android.feature.me

import androidx.compose.foundation.Image
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.AccountCircle
import androidx.compose.material.icons.filled.AutoAwesome
import androidx.compose.material.icons.filled.CloudSync
import androidx.compose.material.icons.filled.ColorLens
import androidx.compose.material.icons.filled.ContactMail
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Home
import androidx.compose.material.icons.filled.Inventory2
import androidx.compose.material.icons.filled.Pets
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material.icons.filled.Stars
import androidx.compose.material.icons.filled.Widgets
import androidx.compose.material.icons.filled.WorkspacePremium
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.pinkhouse.android.core.assets.PinkHouseAssets
import com.pinkhouse.android.core.ui.PinkHouseDesignTokens
import com.pinkhouse.android.core.ui.PinkSurfaceScaffold

private data class MeGridEntry(
    val title: String,
    val subtitle: String,
    val icon: ImageVector,
    val tint: Color,
)

private val meGridEntries = listOf(
    MeGridEntry("账户云同步", "登录 · 备份 · 同步", Icons.Filled.CloudSync, Color(0xFF5C86D1)),
    MeGridEntry("梦幻衣橱", "外观 · 隐私 · 提醒", Icons.Filled.Inventory2, PinkHouseDesignTokens.Primary),
    MeGridEntry("House", "风格 · 场景 · 3D", Icons.Filled.Home, Color(0xFF6F63C4)),
    MeGridEntry("智能萌宠", "AI · 语音 · 形象", Icons.Filled.Pets, PinkHouseDesignTokens.WarmAccent),
    MeGridEntry("主题配色", "配色方案 · 魔法皮肤", Icons.Filled.ColorLens, Color(0xFF9C6ADE)),
    MeGridEntry("常用菜单", "长按菜单 · 常用设置", Icons.Filled.Stars, Color(0xFFE0A321)),
    MeGridEntry("小组件", "桌面组件 · 快捷入口", Icons.Filled.Widgets, Color(0xFF5E9F7B)),
    MeGridEntry("回收站", "恢复 · 清空", Icons.Filled.Delete, Color(0xFFE36A7A)),
    MeGridEntry("系统与更多", "组件 · 备份 · 通用", Icons.Filled.Settings, Color(0xFF7B747A)),
    MeGridEntry("联系我们", "协议 · 备案 · 邮箱", Icons.Filled.ContactMail, Color(0xFF4FA6A0)),
)

@Composable
fun MeRoute(
    onOpenWardrobeSettings: () -> Unit,
    onOpenPetSettings: () -> Unit,
) {
    PinkSurfaceScaffold {
        LazyColumn(
            modifier = Modifier.fillMaxSize(),
            contentPadding = PaddingValues(
                start = PinkHouseDesignTokens.PageHorizontalPadding,
                top = PinkHouseDesignTokens.PageVerticalPadding,
                end = PinkHouseDesignTokens.PageHorizontalPadding,
                bottom = PinkHouseDesignTokens.BottomNavHeight + 34.dp,
            ),
            verticalArrangement = Arrangement.spacedBy(18.dp),
        ) {
            item { MeHeader() }
            item { VipCard() }
            item { MagicTaskCard() }
            item {
                LazyVerticalGrid(
                    columns = GridCells.Fixed(2),
                    modifier = Modifier.height(760.dp),
                    userScrollEnabled = false,
                    horizontalArrangement = Arrangement.spacedBy(14.dp),
                    verticalArrangement = Arrangement.spacedBy(14.dp),
                ) {
                    items(meGridEntries, key = { it.title }) { entry ->
                        MeGridCard(
                            entry = entry,
                            onClick = {
                                when (entry.title) {
                                    "梦幻衣橱" -> onOpenWardrobeSettings()
                                    "智能萌宠" -> onOpenPetSettings()
                                }
                            },
                        )
                    }
                }
            }
        }
    }
}

@Composable
private fun MeHeader() {
    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.SpaceBetween,
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Text(
                text = "我",
                style = MaterialTheme.typography.headlineMedium,
                fontWeight = FontWeight.Bold,
                color = PinkHouseDesignTokens.TextPrimary,
            )
            Text(
                text = "账户、云同步、主题和常用设置",
                style = MaterialTheme.typography.bodyMedium,
                color = PinkHouseDesignTokens.TextSecondary,
            )
        }
        Surface(
            modifier = Modifier.size(54.dp),
            shape = CircleShape,
            color = Color.White.copy(alpha = 0.86f),
            tonalElevation = 4.dp,
            shadowElevation = 2.dp,
        ) {
            Icon(
                imageVector = Icons.Filled.AccountCircle,
                contentDescription = null,
                modifier = Modifier.padding(10.dp),
                tint = PinkHouseDesignTokens.Primary,
            )
        }
    }
}

@Composable
private fun VipCard() {
    Card(
        modifier = Modifier.fillMaxWidth(),
        shape = RoundedCornerShape(PinkHouseDesignTokens.LargeCardRadius),
        colors = CardDefaults.cardColors(containerColor = Color.White.copy(alpha = 0.88f)),
    ) {
        Box(modifier = Modifier.fillMaxWidth()) {
            Image(
                painter = painterResource(PinkHouseAssets.vipCardFront),
                contentDescription = null,
                modifier = Modifier
                    .align(Alignment.CenterEnd)
                    .size(width = 172.dp, height = 112.dp),
                contentScale = ContentScale.Fit,
                alpha = 0.92f,
            )
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(18.dp),
                horizontalArrangement = Arrangement.spacedBy(14.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Surface(shape = CircleShape, color = PinkHouseDesignTokens.Primary.copy(alpha = 0.14f)) {
                    Icon(
                        imageVector = Icons.Filled.WorkspacePremium,
                        contentDescription = null,
                        modifier = Modifier.padding(12.dp),
                        tint = PinkHouseDesignTokens.Primary,
                    )
                }
                Column(
                    modifier = Modifier.weight(1f),
                    verticalArrangement = Arrangement.spacedBy(5.dp),
                ) {
                    Text("Pink House VIP", style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.Bold)
                    Text(
                        "会员卡、试用状态和喵币权益",
                        style = MaterialTheme.typography.bodyMedium,
                        color = PinkHouseDesignTokens.TextSecondary,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                    )
                }
            }
        }
    }
}

@Composable
private fun MagicTaskCard() {
    Card(
        modifier = Modifier.fillMaxWidth(),
        shape = RoundedCornerShape(PinkHouseDesignTokens.CardRadius),
        colors = CardDefaults.cardColors(containerColor = Color.White.copy(alpha = 0.88f)),
    ) {
        Row(
            modifier = Modifier.padding(16.dp),
            horizontalArrangement = Arrangement.spacedBy(14.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Surface(shape = RoundedCornerShape(14.dp), color = PinkHouseDesignTokens.Accent.copy(alpha = 0.12f)) {
                Icon(
                    imageVector = Icons.Filled.AutoAwesome,
                    contentDescription = null,
                    modifier = Modifier.padding(12.dp),
                    tint = PinkHouseDesignTokens.Accent,
                )
            }
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                Text("魔法任务", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold)
                Text("完成任务解锁更多功能", style = MaterialTheme.typography.bodySmall, color = PinkHouseDesignTokens.TextSecondary)
            }
        }
    }
}

@Composable
private fun MeGridCard(
    entry: MeGridEntry,
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
            Surface(shape = RoundedCornerShape(14.dp), color = entry.tint.copy(alpha = 0.12f)) {
                Icon(
                    imageVector = entry.icon,
                    contentDescription = null,
                    modifier = Modifier.padding(10.dp),
                    tint = entry.tint,
                )
            }
            Spacer(Modifier.height(2.dp))
            Text(entry.title, fontWeight = FontWeight.Bold, maxLines = 1)
            Text(
                entry.subtitle,
                style = MaterialTheme.typography.bodySmall,
                color = PinkHouseDesignTokens.TextSecondary,
                maxLines = 2,
                overflow = TextOverflow.Ellipsis,
            )
        }
    }
}
