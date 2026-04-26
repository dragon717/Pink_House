package com.pinkhouse.android.feature.checkin

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.Favorite
import androidx.compose.material.icons.filled.LocalFlorist
import androidx.compose.material.icons.filled.Pets
import androidx.compose.material.icons.filled.TouchApp
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.pinkhouse.android.core.ui.PinkHouseDesignTokens
import java.time.LocalDate
import java.time.format.DateTimeFormatter
import java.util.Locale

@Composable
fun CheckInRoute(modifier: Modifier = Modifier) {
    var hasCheckedIn by rememberSaveable { mutableStateOf(false) }
    val today = LocalDate.now()

    Column(
        modifier = modifier,
        verticalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        CheckInHeader(today = today)
        WeekCheckInCard(today = today, hasCheckedIn = hasCheckedIn)
        OutfitColorCard(hasCheckedIn = hasCheckedIn)
        CheckInActionButton(
            hasCheckedIn = hasCheckedIn,
            onClick = { hasCheckedIn = true },
        )
        if (hasCheckedIn) {
            OutlinedButton(
                onClick = {},
                modifier = Modifier.fillMaxWidth(),
                colors = ButtonDefaults.outlinedButtonColors(contentColor = PinkHouseDesignTokens.Primary),
            ) {
                Text("分享今日穿搭")
            }
        }
    }
}

@Composable
private fun CheckInHeader(today: LocalDate) {
    Column(
        modifier = Modifier.fillMaxWidth(),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        Text(
            text = today.format(DateTimeFormatter.ofPattern("yyyy年M月d日 EEEE", Locale.CHINA)),
            style = androidx.compose.material3.MaterialTheme.typography.labelLarge,
            color = PinkHouseDesignTokens.TextSecondary,
        )
        Surface(
            modifier = Modifier.fillMaxWidth(),
            shape = RoundedCornerShape(22.dp),
            color = Color.White.copy(alpha = 0.78f),
            shadowElevation = 2.dp,
        ) {
            Column(
                modifier = Modifier.padding(18.dp),
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(10.dp),
            ) {
                Text(
                    text = "• 岁月漫长，然而值得等待。",
                    style = androidx.compose.material3.MaterialTheme.typography.titleMedium,
                    color = PinkHouseDesignTokens.TextPrimary,
                    textAlign = TextAlign.Center,
                    fontWeight = FontWeight.SemiBold,
                )
                Surface(
                    shape = RoundedCornerShape(999.dp),
                    color = PinkHouseDesignTokens.Primary.copy(alpha = 0.10f),
                ) {
                    Row(
                        modifier = Modifier.padding(horizontal = 12.dp, vertical = 6.dp),
                        horizontalArrangement = Arrangement.spacedBy(5.dp),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Icon(Icons.Filled.Pets, contentDescription = null, modifier = Modifier.size(16.dp), tint = PinkHouseDesignTokens.Primary)
                        Text("萌宠推荐", color = PinkHouseDesignTokens.Primary, style = androidx.compose.material3.MaterialTheme.typography.labelMedium)
                    }
                }
                Text(
                    text = "连续打卡 0 天",
                    style = androidx.compose.material3.MaterialTheme.typography.bodyMedium,
                    color = PinkHouseDesignTokens.TextSecondary,
                )
            }
        }
    }
}

@Composable
private fun WeekCheckInCard(today: LocalDate, hasCheckedIn: Boolean) {
    val weekDays = listOf("周一", "周二", "周三", "周四", "周五", "周六", "周日")
    val todayIndex = (today.dayOfWeek.value - 1).coerceIn(0, 6)
    Surface(
        modifier = Modifier.fillMaxWidth(),
        shape = RoundedCornerShape(22.dp),
        color = Color.White.copy(alpha = 0.74f),
        shadowElevation = 2.dp,
    ) {
        Column(
            modifier = Modifier.padding(18.dp),
            verticalArrangement = Arrangement.spacedBy(14.dp),
        ) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text("本周签到", style = androidx.compose.material3.MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold)
                Spacer(Modifier.weight(1f))
                Text("累计 ${if (hasCheckedIn) 1 else 0} 天", color = PinkHouseDesignTokens.TextSecondary)
            }
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
            ) {
                weekDays.forEachIndexed { index, label ->
                    WeekDayCell(
                        label = label,
                        dayNumber = today.minusDays((todayIndex - index).toLong()).dayOfMonth,
                        isToday = index == todayIndex,
                        isChecked = hasCheckedIn && index == todayIndex,
                    )
                }
            }
        }
    }
}

@Composable
private fun WeekDayCell(label: String, dayNumber: Int, isToday: Boolean, isChecked: Boolean) {
    Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(6.dp)) {
        Text(
            text = label,
            style = androidx.compose.material3.MaterialTheme.typography.labelSmall,
            color = if (isToday) PinkHouseDesignTokens.Primary else PinkHouseDesignTokens.TextSecondary,
        )
        Box(
            modifier = Modifier
                .size(36.dp)
                .clip(CircleShape)
                .background(if (isChecked) PinkHouseDesignTokens.Primary.copy(alpha = 0.18f) else Color.White.copy(alpha = 0.42f)),
            contentAlignment = Alignment.Center,
        ) {
            if (isChecked) {
                Icon(Icons.Filled.Check, contentDescription = null, modifier = Modifier.size(18.dp), tint = PinkHouseDesignTokens.Primary)
            } else {
                Text("$dayNumber", color = PinkHouseDesignTokens.TextSecondary, style = androidx.compose.material3.MaterialTheme.typography.labelMedium)
            }
        }
    }
}

@Composable
private fun OutfitColorCard(hasCheckedIn: Boolean) {
    Surface(
        modifier = Modifier.fillMaxWidth(),
        shape = RoundedCornerShape(22.dp),
        color = Color.White.copy(alpha = 0.76f),
        shadowElevation = 2.dp,
    ) {
        Column(
            modifier = Modifier.padding(18.dp),
            verticalArrangement = Arrangement.spacedBy(14.dp),
        ) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text("今日穿搭色", style = androidx.compose.material3.MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold)
                Spacer(Modifier.weight(1f))
                Surface(shape = RoundedCornerShape(999.dp), color = PinkHouseDesignTokens.Primary.copy(alpha = 0.10f)) {
                    Text(
                        modifier = Modifier.padding(horizontal = 10.dp, vertical = 5.dp),
                        text = "奶茶推荐",
                        color = PinkHouseDesignTokens.Primary,
                        style = androidx.compose.material3.MaterialTheme.typography.labelMedium,
                    )
                }
            }
            Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                OutfitColorTile("奶油粉", Brush.verticalGradient(listOf(PinkHouseDesignTokens.Primary.copy(alpha = 0.38f), Color.White)))
                OutfitColorTile("月光白", Brush.verticalGradient(listOf(Color.White, PinkHouseDesignTokens.Surface)))
                OutfitColorTile("樱桃雾", Brush.verticalGradient(listOf(PinkHouseDesignTokens.Primary.copy(alpha = 0.52f), PinkHouseDesignTokens.Background)))
            }
            Surface(shape = RoundedCornerShape(16.dp), color = PinkHouseDesignTokens.Primary.copy(alpha = 0.06f)) {
                Row(
                    modifier = Modifier.padding(14.dp),
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                    verticalAlignment = Alignment.Top,
                ) {
                    Icon(Icons.Filled.LocalFlorist, contentDescription = null, tint = PinkHouseDesignTokens.Primary)
                    Text(
                        text = if (hasCheckedIn) "小物搭配：珍珠发夹、白色短袜、浅粉小包。" else "打卡后解锁今日穿搭色和小物搭配建议。",
                        color = PinkHouseDesignTokens.TextPrimary,
                        style = androidx.compose.material3.MaterialTheme.typography.bodyMedium,
                    )
                }
            }
        }
    }
}

@Composable
private fun RowScope.OutfitColorTile(name: String, brush: Brush) {
    Surface(
        modifier = Modifier.weight(1f),
        shape = RoundedCornerShape(18.dp),
        color = Color.White.copy(alpha = 0.62f),
    ) {
        Column(
            modifier = Modifier.padding(10.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            Box(
                modifier = Modifier
                    .size(46.dp)
                    .clip(CircleShape)
                    .background(brush),
            )
            Text(name, color = PinkHouseDesignTokens.TextPrimary, style = androidx.compose.material3.MaterialTheme.typography.labelMedium)
        }
    }
}

@Composable
private fun CheckInActionButton(hasCheckedIn: Boolean, onClick: () -> Unit) {
    Surface(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(999.dp))
            .clickable(enabled = !hasCheckedIn, onClick = onClick),
        shape = RoundedCornerShape(999.dp),
        color = if (hasCheckedIn) PinkHouseDesignTokens.Positive else PinkHouseDesignTokens.Primary,
        shadowElevation = 4.dp,
    ) {
        Row(
            modifier = Modifier.padding(vertical = 16.dp),
            horizontalArrangement = Arrangement.Center,
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Icon(
                imageVector = if (hasCheckedIn) Icons.Filled.Favorite else Icons.Filled.TouchApp,
                contentDescription = null,
                tint = Color.White,
            )
            Spacer(Modifier.size(8.dp))
            Text(
                text = if (hasCheckedIn) "今日已打卡" else "立即打卡",
                color = Color.White,
                fontWeight = FontWeight.Bold,
                style = androidx.compose.material3.MaterialTheme.typography.titleMedium,
            )
        }
    }
}
