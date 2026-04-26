package com.pinkhouse.android.feature.calendar

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowLeft
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.filled.CalendarMonth
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.LocalOffer
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import com.pinkhouse.android.PinkHouseApplication
import com.pinkhouse.android.core.ui.PinkHouseDesignTokens
import com.pinkhouse.android.core.ui.PinkSegmentedTabs
import com.pinkhouse.android.domain.model.WardrobeItem
import java.math.BigDecimal
import java.math.RoundingMode
import java.time.LocalDate
import java.time.YearMonth
import java.time.format.DateTimeFormatter
import java.util.Locale

@Composable
fun CalendarRoute(modifier: Modifier = Modifier) {
    val context = LocalContext.current.applicationContext as PinkHouseApplication
    val repository = remember(context) { context.appContainer.wardrobeRepositoryForViewModel }
    val sourceItems by remember(repository) { repository.observeItems() }.collectAsState(initial = emptyList())
    var selectedModeIndex by rememberSaveable { mutableStateOf(DreamCalendarMode.Month.ordinal) }
    var showDepositPlanOnly by rememberSaveable { mutableStateOf(true) }
    var anchorMonthEpochDay by rememberSaveable {
        mutableStateOf(LocalDate.now().withDayOfMonth(1).toEpochDay())
    }
    var selectedDateEpochDay by rememberSaveable { mutableStateOf(LocalDate.now().toEpochDay()) }

    val selectedMode = DreamCalendarMode.entries[selectedModeIndex]
    val today = LocalDate.now()
    val anchorMonth = LocalDate.ofEpochDay(anchorMonthEpochDay).withDayOfMonth(1)
    val selectedDate = LocalDate.ofEpochDay(selectedDateEpochDay)
    val visibleItems = remember(sourceItems, showDepositPlanOnly) {
        if (showDepositPlanOnly) sourceItems.filter { it.isDepositPlan } else sourceItems
    }
    val events = remember(visibleItems) { visibleItems.flatMap { it.toDreamCalendarEvents() } }
    val eventsByDate = remember(events) { events.groupBy { it.date } }

    Column(
        modifier = modifier,
        verticalArrangement = Arrangement.spacedBy(14.dp),
    ) {
        CalendarHeroCard(
            today = today,
            events = events,
            showDepositPlanOnly = showDepositPlanOnly,
            onDepositOnlyChange = { showDepositPlanOnly = it },
        )
        PinkSegmentedTabs(
            tabs = DreamCalendarMode.entries.map { it.label },
            selectedIndex = selectedModeIndex,
            onSelected = { selectedModeIndex = it },
            modifier = Modifier.fillMaxWidth(),
        )

        when (selectedMode) {
            DreamCalendarMode.Recent -> RecentTimelineSection(
                today = today,
                eventsByDate = eventsByDate,
                selectedDate = selectedDate,
                onDateSelected = { selectedDateEpochDay = it.toEpochDay() },
            )
            DreamCalendarMode.Month -> MonthModeSection(
                anchorMonth = anchorMonth,
                eventsByDate = eventsByDate,
                selectedDate = selectedDate,
                onPreviousMonth = {
                    anchorMonthEpochDay = anchorMonth.minusMonths(1).toEpochDay()
                },
                onNextMonth = {
                    anchorMonthEpochDay = anchorMonth.plusMonths(1).toEpochDay()
                },
                onDateSelected = { selectedDateEpochDay = it.toEpochDay() },
            )
            DreamCalendarMode.Year -> YearHeatmapSection(
                year = anchorMonth.year,
                events = events,
                onPreviousYear = {
                    anchorMonthEpochDay = anchorMonth.minusYears(1).toEpochDay()
                },
                onNextYear = {
                    anchorMonthEpochDay = anchorMonth.plusYears(1).toEpochDay()
                },
                onMonthSelected = { month ->
                    anchorMonthEpochDay = LocalDate.of(anchorMonth.year, month, 1).toEpochDay()
                    selectedModeIndex = DreamCalendarMode.Month.ordinal
                },
            )
        }

        SelectedDateEventsCard(
            date = selectedDate,
            events = eventsByDate[selectedDate].orEmpty(),
        )
    }
}

@Composable
private fun CalendarHeroCard(
    today: LocalDate,
    events: List<DreamCalendarEvent>,
    showDepositPlanOnly: Boolean,
    onDepositOnlyChange: (Boolean) -> Unit,
) {
    val upcoming = remember(events, today) {
        events.filter { it.date in today..today.plusDays(30) }
    }
    val upcomingBalance = remember(upcoming) {
        upcoming
            .filter { it.kind == DreamCalendarEventKind.FinalPaymentEnd }
            .fold(BigDecimal.ZERO) { acc, event -> acc + event.amount }
    }
    val nextDate = upcoming.minByOrNull { it.date }?.date

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
                        imageVector = Icons.Filled.CalendarMonth,
                        contentDescription = null,
                        tint = PinkHouseDesignTokens.Primary,
                        modifier = Modifier.padding(10.dp),
                    )
                }
                Spacer(Modifier.width(10.dp))
                Column(modifier = Modifier.weight(1f)) {
                    Text(
                        text = "梦裙日历",
                        style = MaterialTheme.typography.titleLarge,
                        fontWeight = FontWeight.Bold,
                        color = PinkHouseDesignTokens.TextPrimary,
                    )
                    Text(
                        text = today.format(DateTimeFormatter.ofPattern("yyyy年M月d日 EEEE", Locale.CHINA)),
                        style = MaterialTheme.typography.bodyMedium,
                        color = PinkHouseDesignTokens.TextSecondary,
                    )
                }
            }

            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(10.dp),
            ) {
                CalendarSummaryMetric(
                    label = "30天安排",
                    value = "${upcoming.size}",
                    helper = "条",
                    modifier = Modifier.weight(1f),
                )
                CalendarSummaryMetric(
                    label = "待付尾款",
                    value = upcomingBalance.moneyText(),
                    helper = nextDate?.format(DateTimeFormatter.ofPattern("M/d")) ?: "暂无",
                    modifier = Modifier.weight(1f),
                )
            }

            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                CalendarFilterPill(
                    label = "只看心愿尾款",
                    selected = showDepositPlanOnly,
                    onClick = { onDepositOnlyChange(true) },
                )
                CalendarFilterPill(
                    label = "全部衣物日期",
                    selected = !showDepositPlanOnly,
                    onClick = { onDepositOnlyChange(false) },
                )
            }
        }
    }
}

@Composable
private fun RowScope.CalendarSummaryMetric(
    label: String,
    value: String,
    helper: String,
    modifier: Modifier = Modifier,
) {
    Surface(
        modifier = modifier,
        shape = RoundedCornerShape(20.dp),
        color = PinkHouseDesignTokens.Surface.copy(alpha = 0.78f),
        border = BorderStroke(1.dp, Color.White.copy(alpha = 0.62f)),
    ) {
        Column(
            modifier = Modifier.padding(14.dp),
            verticalArrangement = Arrangement.spacedBy(4.dp),
        ) {
            Text(label, style = MaterialTheme.typography.labelMedium, color = PinkHouseDesignTokens.TextSecondary)
            Text(
                value,
                style = MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.Bold,
                color = PinkHouseDesignTokens.Primary,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
            Text(helper, style = MaterialTheme.typography.labelSmall, color = PinkHouseDesignTokens.TextMuted)
        }
    }
}

@Composable
private fun CalendarFilterPill(label: String, selected: Boolean, onClick: () -> Unit) {
    Surface(
        modifier = Modifier.clickable(onClick = onClick),
        shape = RoundedCornerShape(999.dp),
        color = if (selected) PinkHouseDesignTokens.Primary else Color.White.copy(alpha = 0.58f),
    ) {
        Row(
            modifier = Modifier.padding(horizontal = 12.dp, vertical = 8.dp),
            horizontalArrangement = Arrangement.spacedBy(6.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            if (selected) {
                Icon(Icons.Filled.CheckCircle, contentDescription = null, tint = Color.White, modifier = Modifier.size(16.dp))
            }
            Text(
                text = label,
                style = MaterialTheme.typography.labelMedium,
                fontWeight = if (selected) FontWeight.Bold else FontWeight.Medium,
                color = if (selected) Color.White else PinkHouseDesignTokens.TextSecondary,
            )
        }
    }
}

@Composable
private fun RecentTimelineSection(
    today: LocalDate,
    eventsByDate: Map<LocalDate, List<DreamCalendarEvent>>,
    selectedDate: LocalDate,
    onDateSelected: (LocalDate) -> Unit,
) {
    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
        listOf(-1L to "昨天", 0L to "今天", 1L to "明天").forEach { (offset, label) ->
            val date = today.plusDays(offset)
            TimelineDayCard(
                title = label,
                date = date,
                events = eventsByDate[date].orEmpty(),
                selected = date == selectedDate,
                onClick = { onDateSelected(date) },
            )
        }

        Text(
            text = "未来一周",
            style = MaterialTheme.typography.titleMedium,
            fontWeight = FontWeight.Bold,
            color = PinkHouseDesignTokens.TextSecondary,
            modifier = Modifier.padding(top = 4.dp),
        )
        val futureDates = (2L..7L).map { today.plusDays(it) }.filter { eventsByDate[it].orEmpty().isNotEmpty() }
        if (futureDates.isEmpty()) {
            EmptyCalendarHint(text = "未来一周暂无特殊安排")
        } else {
            futureDates.forEach { date ->
                CompactTimelineRow(
                    date = date,
                    events = eventsByDate[date].orEmpty(),
                    onClick = { onDateSelected(date) },
                )
            }
        }
    }
}

@Composable
private fun TimelineDayCard(
    title: String,
    date: LocalDate,
    events: List<DreamCalendarEvent>,
    selected: Boolean,
    onClick: () -> Unit,
) {
    Surface(
        modifier = Modifier.fillMaxWidth().clickable(onClick = onClick),
        shape = RoundedCornerShape(22.dp),
        color = if (selected) PinkHouseDesignTokens.Primary.copy(alpha = 0.14f) else Color.White.copy(alpha = 0.74f),
        border = BorderStroke(1.dp, if (selected) PinkHouseDesignTokens.Primary.copy(alpha = 0.46f) else Color.White.copy(alpha = 0.52f)),
        shadowElevation = 1.dp,
    ) {
        Column(
            modifier = Modifier.padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(title, style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold, color = PinkHouseDesignTokens.Primary)
                Spacer(Modifier.width(8.dp))
                Text(date.format(DateTimeFormatter.ofPattern("M月d日 E", Locale.CHINA)), color = PinkHouseDesignTokens.TextSecondary)
                Spacer(Modifier.weight(1f))
                Text("${events.size} 项", style = MaterialTheme.typography.labelMedium, color = PinkHouseDesignTokens.TextMuted)
            }
            if (events.isEmpty()) {
                Text("无特殊安排", style = MaterialTheme.typography.bodyMedium, color = PinkHouseDesignTokens.TextMuted)
            } else {
                Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    events.take(3).forEach { event ->
                        TinyEventCard(event = event, modifier = Modifier.weight(1f))
                    }
                }
            }
        }
    }
}

@Composable
private fun CompactTimelineRow(date: LocalDate, events: List<DreamCalendarEvent>, onClick: () -> Unit) {
    Surface(
        modifier = Modifier.fillMaxWidth().clickable(onClick = onClick),
        shape = RoundedCornerShape(18.dp),
        color = Color.White.copy(alpha = 0.76f),
    ) {
        Row(
            modifier = Modifier.padding(14.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Text(
                date.format(DateTimeFormatter.ofPattern("M月d日", Locale.CHINA)),
                style = MaterialTheme.typography.labelLarge,
                fontWeight = FontWeight.Bold,
                color = PinkHouseDesignTokens.TextSecondary,
                modifier = Modifier.width(74.dp),
            )
            EventAvatarStack(events = events)
            Text(
                text = events.joinToString(" / ") { it.kind.label }.ifBlank { "无安排" },
                modifier = Modifier.weight(1f),
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
                style = MaterialTheme.typography.bodyMedium,
                color = PinkHouseDesignTokens.TextPrimary,
            )
        }
    }
}

@Composable
private fun MonthModeSection(
    anchorMonth: LocalDate,
    eventsByDate: Map<LocalDate, List<DreamCalendarEvent>>,
    selectedDate: LocalDate,
    onPreviousMonth: () -> Unit,
    onNextMonth: () -> Unit,
    onDateSelected: (LocalDate) -> Unit,
) {
    Column(verticalArrangement = Arrangement.spacedBy(14.dp)) {
        MonthHeader(anchorMonth = anchorMonth, onPreviousMonth = onPreviousMonth, onNextMonth = onNextMonth)
        MonthCalendarSection(
            monthStart = anchorMonth,
            eventsByDate = eventsByDate,
            selectedDate = selectedDate,
            onDateSelected = onDateSelected,
        )
        MonthCalendarSection(
            monthStart = anchorMonth.plusMonths(1),
            eventsByDate = eventsByDate,
            selectedDate = selectedDate,
            onDateSelected = onDateSelected,
        )
    }
}

@Composable
private fun MonthHeader(anchorMonth: LocalDate, onPreviousMonth: () -> Unit, onNextMonth: () -> Unit) {
    Surface(
        modifier = Modifier.fillMaxWidth(),
        shape = RoundedCornerShape(22.dp),
        color = Color.White.copy(alpha = 0.74f),
    ) {
        Row(
            modifier = Modifier.padding(horizontal = 10.dp, vertical = 8.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.SpaceBetween,
        ) {
            IconButton(onClick = onPreviousMonth) {
                Icon(Icons.AutoMirrored.Filled.KeyboardArrowLeft, contentDescription = "上一月", tint = PinkHouseDesignTokens.Primary)
            }
            Column(horizontalAlignment = Alignment.CenterHorizontally) {
                Text(
                    text = anchorMonth.format(DateTimeFormatter.ofPattern("yyyy年M月", Locale.CHINA)),
                    style = MaterialTheme.typography.titleMedium,
                    fontWeight = FontWeight.Bold,
                    color = PinkHouseDesignTokens.TextPrimary,
                )
                Text("双月滚动视图", style = MaterialTheme.typography.labelMedium, color = PinkHouseDesignTokens.TextMuted)
            }
            IconButton(onClick = onNextMonth) {
                Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, contentDescription = "下一月", tint = PinkHouseDesignTokens.Primary)
            }
        }
    }
}

@Composable
private fun MonthCalendarSection(
    monthStart: LocalDate,
    eventsByDate: Map<LocalDate, List<DreamCalendarEvent>>,
    selectedDate: LocalDate,
    onDateSelected: (LocalDate) -> Unit,
) {
    Surface(
        modifier = Modifier.fillMaxWidth(),
        shape = RoundedCornerShape(24.dp),
        color = Color.White.copy(alpha = 0.76f),
        shadowElevation = 1.dp,
    ) {
        Column(
            modifier = Modifier.padding(14.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            Text(
                text = monthStart.format(DateTimeFormatter.ofPattern("yyyy年M月", Locale.CHINA)),
                style = MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.Bold,
                color = PinkHouseDesignTokens.Primary,
                modifier = Modifier.padding(horizontal = 2.dp),
            )
            WeekHeaderRow()
            monthGridDays(monthStart).chunked(7).forEach { week ->
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.spacedBy(6.dp),
                ) {
                    week.forEach { date ->
                        if (date == null) {
                            Spacer(Modifier.weight(1f).height(58.dp))
                        } else {
                            CalendarDayCell(
                                date = date,
                                isSelected = date == selectedDate,
                                isToday = date == LocalDate.now(),
                                events = eventsByDate[date].orEmpty(),
                                onClick = { onDateSelected(date) },
                                modifier = Modifier.weight(1f),
                            )
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun WeekHeaderRow() {
    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        listOf("一", "二", "三", "四", "五", "六", "日").forEach { label ->
            Text(
                text = label,
                modifier = Modifier.weight(1f),
                textAlign = TextAlign.Center,
                style = MaterialTheme.typography.labelMedium,
                fontWeight = FontWeight.Bold,
                color = PinkHouseDesignTokens.TextSecondary,
            )
        }
    }
}

@Composable
private fun CalendarDayCell(
    date: LocalDate,
    isSelected: Boolean,
    isToday: Boolean,
    events: List<DreamCalendarEvent>,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
) {
    Surface(
        modifier = modifier.height(58.dp).clickable(onClick = onClick),
        shape = RoundedCornerShape(16.dp),
        color = when {
            isSelected -> PinkHouseDesignTokens.Primary.copy(alpha = 0.22f)
            isToday -> PinkHouseDesignTokens.Surface.copy(alpha = 0.92f)
            else -> Color.White.copy(alpha = 0.54f)
        },
        border = if (isSelected) BorderStroke(1.dp, PinkHouseDesignTokens.Primary.copy(alpha = 0.55f)) else null,
    ) {
        Column(
            modifier = Modifier.fillMaxSize().padding(vertical = 6.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.SpaceBetween,
        ) {
            Text(
                text = date.dayOfMonth.toString(),
                style = MaterialTheme.typography.labelMedium,
                fontWeight = if (isToday || isSelected) FontWeight.Bold else FontWeight.Medium,
                color = if (isSelected) PinkHouseDesignTokens.Primary else PinkHouseDesignTokens.TextPrimary,
            )
            if (events.isNotEmpty()) {
                Row(horizontalArrangement = Arrangement.spacedBy(2.dp)) {
                    events.take(3).forEach { event ->
                        Box(
                            modifier = Modifier
                                .size(6.dp)
                                .background(event.kind.color.copy(alpha = 0.82f), CircleShape),
                        )
                    }
                }
            } else {
                Spacer(Modifier.size(6.dp))
            }
        }
    }
}

@Composable
private fun YearHeatmapSection(
    year: Int,
    events: List<DreamCalendarEvent>,
    onPreviousYear: () -> Unit,
    onNextYear: () -> Unit,
    onMonthSelected: (Int) -> Unit,
) {
    val eventsByMonth = remember(events, year) { events.filter { it.date.year == year }.groupBy { it.date.monthValue } }
    Column(verticalArrangement = Arrangement.spacedBy(14.dp)) {
        Surface(
            modifier = Modifier.fillMaxWidth(),
            shape = RoundedCornerShape(22.dp),
            color = Color.White.copy(alpha = 0.74f),
        ) {
            Row(
                modifier = Modifier.padding(horizontal = 10.dp, vertical = 8.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.SpaceBetween,
            ) {
                IconButton(onClick = onPreviousYear) {
                    Icon(Icons.AutoMirrored.Filled.KeyboardArrowLeft, contentDescription = "上一年", tint = PinkHouseDesignTokens.Primary)
                }
                Text(
                    text = "${year}年 概览",
                    style = MaterialTheme.typography.titleMedium,
                    fontWeight = FontWeight.Bold,
                    color = PinkHouseDesignTokens.TextPrimary,
                )
                IconButton(onClick = onNextYear) {
                    Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, contentDescription = "下一年", tint = PinkHouseDesignTokens.Primary)
                }
            }
        }
        (1..12).chunked(3).forEach { rowMonths ->
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(10.dp),
            ) {
                rowMonths.forEach { month ->
                    MonthHeatCard(
                        year = year,
                        month = month,
                        events = eventsByMonth[month].orEmpty(),
                        onClick = { onMonthSelected(month) },
                        modifier = Modifier.weight(1f),
                    )
                }
            }
        }
    }
}

@Composable
private fun MonthHeatCard(year: Int, month: Int, events: List<DreamCalendarEvent>, onClick: () -> Unit, modifier: Modifier = Modifier) {
    val amount = remember(events) {
        events.filter { it.kind == DreamCalendarEventKind.FinalPaymentEnd }.fold(BigDecimal.ZERO) { acc, event -> acc + event.amount }
    }
    Surface(
        modifier = modifier.clickable(onClick = onClick),
        shape = RoundedCornerShape(18.dp),
        color = Color.White.copy(alpha = 0.76f),
        border = BorderStroke(1.dp, Color.White.copy(alpha = 0.58f)),
    ) {
        Column(
            modifier = Modifier.padding(10.dp).height(118.dp),
            verticalArrangement = Arrangement.SpaceBetween,
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            Text("${month}月", style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.Bold, color = PinkHouseDesignTokens.TextSecondary)
            MiniMonthDots(year = year, month = month, eventDates = events.groupBy { it.date }.keys)
            Text(
                text = if (events.isEmpty()) "暂无" else "${events.size}项 · ${amount.moneyText()}",
                style = MaterialTheme.typography.labelSmall,
                color = if (events.isEmpty()) PinkHouseDesignTokens.TextMuted else PinkHouseDesignTokens.Primary,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
        }
    }
}

@Composable
private fun MiniMonthDots(year: Int, month: Int, eventDates: Set<LocalDate>) {
    val days = YearMonth.of(year, month).lengthOfMonth()
    val sampledDays = (1..days step 2).take(18)
    Column(verticalArrangement = Arrangement.spacedBy(3.dp)) {
        sampledDays.chunked(6).forEach { row ->
            Row(horizontalArrangement = Arrangement.spacedBy(3.dp)) {
                row.forEach { day ->
                    val hasEvent = eventDates.any { it.dayOfMonth == day || it.dayOfMonth == day + 1 }
                    Box(
                        modifier = Modifier
                            .size(6.dp)
                            .background(
                                if (hasEvent) PinkHouseDesignTokens.Primary.copy(alpha = 0.78f) else PinkHouseDesignTokens.TextMuted.copy(alpha = 0.16f),
                                CircleShape,
                            ),
                    )
                }
            }
        }
    }
}

@Composable
private fun SelectedDateEventsCard(date: LocalDate, events: List<DreamCalendarEvent>) {
    Surface(
        modifier = Modifier.fillMaxWidth(),
        shape = RoundedCornerShape(24.dp),
        color = Color.White.copy(alpha = 0.78f),
    ) {
        Column(
            modifier = Modifier.padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(
                    text = date.format(DateTimeFormatter.ofPattern("M月d日 EEEE", Locale.CHINA)),
                    style = MaterialTheme.typography.titleMedium,
                    fontWeight = FontWeight.Bold,
                    color = PinkHouseDesignTokens.TextPrimary,
                    modifier = Modifier.weight(1f),
                )
                Surface(shape = CircleShape, color = PinkHouseDesignTokens.Primary.copy(alpha = 0.10f)) {
                    Text(
                        text = "${events.size} 项",
                        modifier = Modifier.padding(horizontal = 10.dp, vertical = 4.dp),
                        style = MaterialTheme.typography.labelMedium,
                        color = PinkHouseDesignTokens.Primary,
                    )
                }
            }
            if (events.isEmpty()) {
                EmptyCalendarHint(text = "这一天暂无定金、尾款或入手记录")
            } else {
                events.forEach { event ->
                    EventDetailRow(event = event)
                }
            }
        }
    }
}

@Composable
private fun TinyEventCard(event: DreamCalendarEvent, modifier: Modifier = Modifier) {
    Surface(
        modifier = modifier,
        shape = RoundedCornerShape(16.dp),
        color = Color.White.copy(alpha = 0.74f),
    ) {
        Column(
            modifier = Modifier.padding(10.dp),
            verticalArrangement = Arrangement.spacedBy(5.dp),
        ) {
            EventKindPill(event.kind)
            Text(
                text = event.itemName,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
                style = MaterialTheme.typography.labelMedium,
                fontWeight = FontWeight.Bold,
                color = PinkHouseDesignTokens.TextPrimary,
            )
            Text(event.amount.moneyText(), style = MaterialTheme.typography.labelSmall, color = PinkHouseDesignTokens.TextMuted)
        }
    }
}

@Composable
private fun EventDetailRow(event: DreamCalendarEvent) {
    Surface(shape = RoundedCornerShape(18.dp), color = PinkHouseDesignTokens.Surface.copy(alpha = 0.82f)) {
        Row(
            modifier = Modifier.fillMaxWidth().padding(12.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            Surface(shape = CircleShape, color = event.kind.color.copy(alpha = 0.16f)) {
                Icon(
                    imageVector = if (event.kind == DreamCalendarEventKind.Purchase) Icons.Filled.CalendarMonth else Icons.Filled.LocalOffer,
                    contentDescription = null,
                    tint = event.kind.color,
                    modifier = Modifier.padding(8.dp),
                )
            }
            Column(modifier = Modifier.weight(1f)) {
                Text(event.itemName, style = MaterialTheme.typography.bodyMedium, fontWeight = FontWeight.Bold, color = PinkHouseDesignTokens.TextPrimary)
                Text(event.kind.label, style = MaterialTheme.typography.labelMedium, color = PinkHouseDesignTokens.TextSecondary)
            }
            Text(event.amount.moneyText(), style = MaterialTheme.typography.labelLarge, fontWeight = FontWeight.Bold, color = event.kind.color)
        }
    }
}

@Composable
private fun EventKindPill(kind: DreamCalendarEventKind) {
    Surface(shape = RoundedCornerShape(999.dp), color = kind.color.copy(alpha = 0.12f)) {
        Text(
            text = kind.label,
            modifier = Modifier.padding(horizontal = 8.dp, vertical = 3.dp),
            style = MaterialTheme.typography.labelSmall,
            color = kind.color,
            maxLines = 1,
        )
    }
}

@Composable
private fun EventAvatarStack(events: List<DreamCalendarEvent>) {
    Row(horizontalArrangement = Arrangement.spacedBy(2.dp)) {
        events.take(5).forEach { event ->
            Surface(
                modifier = Modifier.size(28.dp),
                shape = CircleShape,
                color = event.kind.color,
                border = BorderStroke(1.dp, Color.White),
            ) {
                Box(contentAlignment = Alignment.Center) {
                    Text(
                        text = event.itemName.take(1),
                        style = MaterialTheme.typography.labelSmall,
                        fontWeight = FontWeight.Bold,
                        color = Color.White,
                    )
                }
            }
        }
    }
}

@Composable
private fun EmptyCalendarHint(text: String) {
    Surface(shape = RoundedCornerShape(16.dp), color = PinkHouseDesignTokens.Surface.copy(alpha = 0.72f)) {
        Text(
            text = text,
            modifier = Modifier.fillMaxWidth().padding(14.dp),
            style = MaterialTheme.typography.bodyMedium,
            color = PinkHouseDesignTokens.TextMuted,
        )
    }
}

private fun WardrobeItem.toDreamCalendarEvents(): List<DreamCalendarEvent> {
    val result = mutableListOf<DreamCalendarEvent>()
    depositDate?.let { date ->
        if (isDepositPlan) {
            result += DreamCalendarEvent(
                itemName = name,
                date = date,
                kind = DreamCalendarEventKind.Deposit,
                amount = totalDeposit,
            )
        }
    }
    finalPaymentStartDate?.let { date ->
        if (isDepositPlan && date != finalPaymentEndDate) {
            result += DreamCalendarEvent(
                itemName = name,
                date = date,
                kind = DreamCalendarEventKind.FinalPaymentStart,
                amount = totalBalance,
            )
        }
    }
    finalPaymentEndDate?.let { date ->
        if (isDepositPlan) {
            result += DreamCalendarEvent(
                itemName = name,
                date = date,
                kind = DreamCalendarEventKind.FinalPaymentEnd,
                amount = totalBalance,
            )
        }
    }
    if (!isDepositPlan) {
        purchaseDate?.let { date ->
            result += DreamCalendarEvent(
                itemName = name,
                date = date,
                kind = DreamCalendarEventKind.Purchase,
                amount = inventoryTotalPrice,
            )
        }
    }
    return result
}

private fun monthGridDays(monthStart: LocalDate): List<LocalDate?> {
    val first = monthStart.withDayOfMonth(1)
    val leadingEmpty = first.dayOfWeek.value - 1
    val days = YearMonth.from(first).lengthOfMonth()
    val result = MutableList<LocalDate?>(leadingEmpty) { null }
    repeat(days) { index -> result += first.plusDays(index.toLong()) }
    while (result.size % 7 != 0) result += null
    return result
}

private fun BigDecimal.moneyText(): String {
    return "¥${setScale(2, RoundingMode.HALF_UP).toPlainString()}"
}

private enum class DreamCalendarMode(val label: String) {
    Recent("近期"),
    Month("月视图"),
    Year("年视图"),
}

private enum class DreamCalendarEventKind(val label: String, val color: Color) {
    Deposit("定金", PinkHouseDesignTokens.Deposit),
    FinalPaymentStart("尾款开始", PinkHouseDesignTokens.WarmAccent),
    FinalPaymentEnd("尾款截止", PinkHouseDesignTokens.Primary),
    Purchase("入手", PinkHouseDesignTokens.Info),
}

private data class DreamCalendarEvent(
    val itemName: String,
    val date: LocalDate,
    val kind: DreamCalendarEventKind,
    val amount: BigDecimal,
)
