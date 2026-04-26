package com.pinkhouse.android.feature.notice

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Notifications
import androidx.compose.material.icons.filled.NotificationsOff
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.pinkhouse.android.core.ui.PinkHouseDesignTokens
import com.pinkhouse.android.core.ui.PinkSegmentedTabs
import java.time.LocalDate
import java.time.format.DateTimeFormatter
import java.util.Locale

@Composable
fun NoticeCenterRoute(modifier: Modifier = Modifier) {
    var selectedFilterIndex by rememberSaveable { mutableStateOf(0) }
    var readIds by rememberSaveable { mutableStateOf(setOf<String>()) }
    var acknowledgedIds by rememberSaveable { mutableStateOf(setOf<String>()) }
    var expandedNoticeId by rememberSaveable { mutableStateOf<String?>(null) }
    val notices = remember { emptyList<NoticeUiItem>() }
    val filteredNotices = remember(selectedFilterIndex, notices, readIds, acknowledgedIds) {
        when (NoticeFilter.entries[selectedFilterIndex]) {
            NoticeFilter.All -> notices
            NoticeFilter.Unread -> notices.filterNot { it.id in readIds }
            NoticeFilter.Ack -> notices.filter { it.requiresAck && it.id !in acknowledgedIds }
        }
    }

    Column(
        modifier = modifier,
        verticalArrangement = Arrangement.spacedBy(14.dp),
    ) {
        NoticeHeroCard(
            notices = notices,
            unreadCount = notices.count { it.id !in readIds },
            pendingAckCount = notices.count { it.requiresAck && it.id !in acknowledgedIds },
        )
        PinkSegmentedTabs(
            tabs = NoticeFilter.entries.map { it.label },
            selectedIndex = selectedFilterIndex,
            onSelected = { selectedFilterIndex = it },
            modifier = Modifier.fillMaxWidth(),
        )
        if (filteredNotices.isEmpty()) {
            EmptyNoticeState(filter = NoticeFilter.entries[selectedFilterIndex])
        } else {
            filteredNotices.forEach { notice ->
                NoticeCard(
                    notice = notice,
                    isRead = notice.id in readIds,
                    isAcknowledged = notice.id in acknowledgedIds,
                    expanded = expandedNoticeId == notice.id,
                    onToggleExpanded = {
                        expandedNoticeId = if (expandedNoticeId == notice.id) null else notice.id
                        readIds = readIds + notice.id
                    },
                    onMarkRead = { readIds = readIds + notice.id },
                    onAcknowledge = {
                        readIds = readIds + notice.id
                        acknowledgedIds = acknowledgedIds + notice.id
                    },
                )
            }
        }
    }
}

@Composable
private fun NoticeHeroCard(notices: List<NoticeUiItem>, unreadCount: Int, pendingAckCount: Int) {
    val latestLabel = notices
        .maxByOrNull { it.publishDate }
        ?.publishDate
        ?.format(DateTimeFormatter.ofPattern("M/d", Locale.CHINA))
        ?: "暂无"
    Surface(
        modifier = Modifier.fillMaxWidth(),
        shape = RoundedCornerShape(26.dp),
        color = Color.White.copy(alpha = 0.78f),
        shadowElevation = 2.dp,
    ) {
        Column(
            modifier = Modifier.padding(18.dp),
            verticalArrangement = Arrangement.spacedBy(14.dp),
        ) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Surface(shape = CircleShape, color = PinkHouseDesignTokens.Primary.copy(alpha = 0.12f)) {
                    Icon(
                        imageVector = Icons.Filled.Notifications,
                        contentDescription = null,
                        tint = PinkHouseDesignTokens.Primary,
                        modifier = Modifier.padding(10.dp),
                    )
                }
                Spacer(Modifier.width(10.dp))
                Column(modifier = Modifier.weight(1f)) {
                    Text(
                        text = "通知中心",
                        style = MaterialTheme.typography.titleLarge,
                        fontWeight = FontWeight.Bold,
                        color = PinkHouseDesignTokens.TextPrimary,
                    )
                    Text(
                        text = "公告、提醒与待确认消息",
                        style = MaterialTheme.typography.bodyMedium,
                        color = PinkHouseDesignTokens.TextSecondary,
                    )
                }
                NoticeBadge(text = latestLabel, color = PinkHouseDesignTokens.Primary)
            }
            Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                NoticeMetric(label = "未读", value = "$unreadCount", helper = "条", modifier = Modifier.weight(1f))
                NoticeMetric(label = "需确认", value = "$pendingAckCount", helper = "消息", modifier = Modifier.weight(1f))
                NoticeMetric(label = "全部", value = "${notices.size}", helper = "公告", modifier = Modifier.weight(1f))
            }
        }
    }
}

@Composable
private fun RowScope.NoticeMetric(label: String, value: String, helper: String, modifier: Modifier = Modifier) {
    Surface(
        modifier = modifier,
        shape = RoundedCornerShape(18.dp),
        color = PinkHouseDesignTokens.Surface.copy(alpha = 0.78f),
        border = BorderStroke(1.dp, Color.White.copy(alpha = 0.62f)),
    ) {
        Column(
            modifier = Modifier.padding(12.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(3.dp),
        ) {
            Text(label, style = MaterialTheme.typography.labelMedium, color = PinkHouseDesignTokens.TextSecondary)
            Text(value, style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold, color = PinkHouseDesignTokens.Primary)
            Text(helper, style = MaterialTheme.typography.labelSmall, color = PinkHouseDesignTokens.TextMuted)
        }
    }
}

@Composable
private fun NoticeCard(
    notice: NoticeUiItem,
    isRead: Boolean,
    isAcknowledged: Boolean,
    expanded: Boolean,
    onToggleExpanded: () -> Unit,
    onMarkRead: () -> Unit,
    onAcknowledge: () -> Unit,
) {
    Surface(
        modifier = Modifier.fillMaxWidth().clickable(onClick = onToggleExpanded),
        shape = RoundedCornerShape(28.dp),
        color = Color.White.copy(alpha = if (isRead) 0.70f else 0.84f),
        border = BorderStroke(
            1.dp,
            if (isRead) Color.White.copy(alpha = 0.50f) else notice.severity.color.copy(alpha = 0.34f),
        ),
        shadowElevation = if (isRead) 1.dp else 3.dp,
    ) {
        Column(verticalArrangement = Arrangement.spacedBy(0.dp)) {
            NoticeMediaPlaceholder(notice = notice)
            Column(
                modifier = Modifier.padding(16.dp),
                verticalArrangement = Arrangement.spacedBy(10.dp),
                horizontalAlignment = Alignment.CenterHorizontally,
            ) {
                Row(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
                    NoticeBadge(text = notice.severity.label, color = notice.severity.color)
                    NoticeBadge(text = notice.channel.label, color = PinkHouseDesignTokens.Info)
                    if (notice.requiresAck) NoticeBadge(text = if (isAcknowledged) "已确认" else "需确认", color = PinkHouseDesignTokens.WarmAccent)
                }
                Text(
                    text = notice.title,
                    style = MaterialTheme.typography.titleMedium,
                    fontWeight = FontWeight.Bold,
                    color = PinkHouseDesignTokens.TextPrimary,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                    textAlign = TextAlign.Center,
                    modifier = Modifier.fillMaxWidth(),
                )
                Text(
                    text = notice.summary,
                    style = MaterialTheme.typography.bodyMedium,
                    color = PinkHouseDesignTokens.TextSecondary,
                    maxLines = if (expanded) 4 else 2,
                    overflow = TextOverflow.Ellipsis,
                    textAlign = TextAlign.Center,
                    modifier = Modifier.fillMaxWidth(),
                )
                if (expanded) {
                    Text(
                        text = notice.content,
                        style = MaterialTheme.typography.bodyMedium,
                        color = PinkHouseDesignTokens.TextSecondary,
                        textAlign = TextAlign.Center,
                        modifier = Modifier.fillMaxWidth(),
                    )
                }
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text(
                        text = notice.publishDate.format(DateTimeFormatter.ofPattern("yyyy年M月d日", Locale.CHINA)),
                        style = MaterialTheme.typography.labelSmall,
                        color = PinkHouseDesignTokens.TextMuted,
                        modifier = Modifier.weight(1f),
                    )
                    if (!isRead) {
                        NoticeActionPill(text = "标记已读", onClick = onMarkRead)
                    }
                    if (notice.requiresAck && !isAcknowledged) {
                        Spacer(Modifier.width(8.dp))
                        NoticeActionPill(text = "我已知晓", onClick = onAcknowledge, emphasized = true)
                    }
                }
            }
        }
    }
}

@Composable
private fun NoticeMediaPlaceholder(notice: NoticeUiItem) {
    Box(
        modifier = Modifier
            .fillMaxWidth()
            .aspectRatio(1.92f)
            .clip(RoundedCornerShape(topStart = 28.dp, topEnd = 28.dp))
            .background(notice.severity.color.copy(alpha = 0.10f)),
        contentAlignment = Alignment.Center,
    ) {
        Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Surface(shape = CircleShape, color = Color.White.copy(alpha = 0.78f)) {
                Icon(
                    imageVector = if (notice.severity == NoticeSeverity.Info) Icons.Filled.Notifications else Icons.Filled.NotificationsOff,
                    contentDescription = null,
                    tint = notice.severity.color,
                    modifier = Modifier.padding(16.dp).size(36.dp),
                )
            }
            Text("公告", style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.Bold, color = PinkHouseDesignTokens.TextSecondary)
        }
    }
}

@Composable
private fun NoticeBadge(text: String, color: Color) {
    Surface(shape = RoundedCornerShape(999.dp), color = color.copy(alpha = 0.12f)) {
        Text(
            text = text,
            modifier = Modifier.padding(horizontal = 8.dp, vertical = 4.dp),
            style = MaterialTheme.typography.labelSmall,
            fontWeight = FontWeight.Bold,
            color = color,
            maxLines = 1,
        )
    }
}

@Composable
private fun NoticeActionPill(text: String, onClick: () -> Unit, emphasized: Boolean = false) {
    Surface(
        modifier = Modifier.clickable(onClick = onClick),
        shape = RoundedCornerShape(999.dp),
        color = if (emphasized) PinkHouseDesignTokens.Primary else PinkHouseDesignTokens.Surface.copy(alpha = 0.82f),
    ) {
        Text(
            text = text,
            modifier = Modifier.padding(horizontal = 12.dp, vertical = 7.dp),
            style = MaterialTheme.typography.labelMedium,
            fontWeight = FontWeight.Bold,
            color = if (emphasized) Color.White else PinkHouseDesignTokens.Primary,
        )
    }
}

@Composable
private fun EmptyNoticeState(filter: NoticeFilter) {
    Surface(
        modifier = Modifier.fillMaxWidth().height(260.dp),
        shape = RoundedCornerShape(28.dp),
        color = Color.White.copy(alpha = 0.76f),
    ) {
        Column(
            modifier = Modifier.padding(24.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.Center,
        ) {
            Icon(Icons.Filled.NotificationsOff, contentDescription = null, tint = PinkHouseDesignTokens.Primary.copy(alpha = 0.55f), modifier = Modifier.size(58.dp))
            Spacer(Modifier.height(14.dp))
            Text(filter.emptyTitle, style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold, color = PinkHouseDesignTokens.TextSecondary)
            Text("有新消息时会显示在这里", style = MaterialTheme.typography.bodyMedium, color = PinkHouseDesignTokens.TextMuted)
        }
    }
}

private enum class NoticeFilter(val label: String) {
    All("全部"),
    Unread("未读"),
    Ack("需确认");

    val emptyTitle: String
        get() = when (this) {
            All -> "暂无公告"
            Unread -> "没有未读消息"
            Ack -> "没有需要确认的消息"
        }
}

private enum class NoticeSeverity(val label: String, val color: Color) {
    Info("普通", PinkHouseDesignTokens.Info),
    Important("重要", PinkHouseDesignTokens.WarmAccent),
    Critical("紧急", PinkHouseDesignTokens.Primary),
}

private enum class NoticeChannel(val label: String) {
    Inbox("收件箱"),
    Banner("横幅"),
    Modal("弹窗"),
}

private data class NoticeUiItem(
    val id: String,
    val title: String,
    val summary: String,
    val content: String,
    val severity: NoticeSeverity,
    val channel: NoticeChannel,
    val publishDate: LocalDate,
    val requiresAck: Boolean = false,
)
