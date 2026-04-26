package com.pinkhouse.android.core.notification

import android.app.AlarmManager
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import androidx.core.app.NotificationManagerCompat
import com.pinkhouse.android.domain.model.WardrobeItem
import java.time.LocalDate
import java.time.LocalTime
import java.time.ZoneId

class DepositReminderScheduler(
    private val context: Context,
) {
    private val alarmManager = context.getSystemService(AlarmManager::class.java)

    fun ensureChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val channel = NotificationChannel(
            CHANNEL_ID,
            "心愿尾款提醒",
            NotificationManager.IMPORTANCE_DEFAULT,
        ).apply {
            description = "本地提醒待付尾款，不接入云端或第三方推送。"
        }
        NotificationManagerCompat.from(context).createNotificationChannel(channel)
    }

    fun scheduleDepositReminders(
        items: List<WardrobeItem>,
        daysBefore: List<Int>,
        reminderTime: LocalTime,
    ): Int {
        ensureChannel()
        var scheduled = 0
        val today = LocalDate.now()
        items
            .filter { it.isDepositPlan && it.finalPaymentEndDate != null && it.totalBalance.signum() > 0 }
            .forEach { item ->
                val dueDate = item.finalPaymentEndDate ?: return@forEach
                daysBefore.distinct().forEach { day ->
                    val reminderDate = dueDate.minusDays(day.toLong())
                    if (reminderDate.isBefore(today)) return@forEach
                    val triggerAt = reminderDate
                        .atTime(reminderTime)
                        .atZone(ZoneId.systemDefault())
                        .toInstant()
                        .toEpochMilli()
                    alarmManager.setAndAllowWhileIdle(
                        AlarmManager.RTC_WAKEUP,
                        triggerAt,
                        pendingIntent(item.id, day),
                    )
                    scheduled += 1
                }
            }
        return scheduled
    }

    fun cancelDepositReminders(items: List<WardrobeItem>, daysBefore: List<Int> = DEFAULT_DAYS) {
        items.forEach { item ->
            daysBefore.distinct().forEach { day ->
                alarmManager.cancel(pendingIntent(item.id, day))
            }
        }
    }

    private fun pendingIntent(itemId: Long, daysBefore: Int): PendingIntent {
        val intent = Intent(context, DepositReminderReceiver::class.java)
            .putExtra(DepositReminderReceiver.EXTRA_ITEM_ID, itemId)
            .putExtra(DepositReminderReceiver.EXTRA_DAYS_BEFORE, daysBefore)
        return PendingIntent.getBroadcast(
            context,
            (itemId * 31 + daysBefore).toInt(),
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    companion object {
        const val CHANNEL_ID = "deposit_reminders"
        val DEFAULT_DAYS = listOf(7, 3, 1)
    }
}
