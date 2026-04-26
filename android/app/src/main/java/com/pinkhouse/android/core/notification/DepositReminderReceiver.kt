package com.pinkhouse.android.core.notification

import android.Manifest
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import com.pinkhouse.android.MainActivity
import com.pinkhouse.android.R

class DepositReminderReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            ContextCompat.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
        ) {
            return
        }

        val daysBefore = intent.getIntExtra(EXTRA_DAYS_BEFORE, 0)
        val itemId = intent.getLongExtra(EXTRA_ITEM_ID, 0L)
        val openIntent = PendingIntent.getActivity(
            context,
            itemId.toInt(),
            Intent(context, MainActivity::class.java),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val title = if (daysBefore > 0) {
            "心愿尾款还有 ${daysBefore} 天"
        } else {
            "今天有心愿尾款"
        }
        val notification = NotificationCompat.Builder(context, DepositReminderScheduler.CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_launcher_foreground)
            .setContentTitle(title)
            .setContentText("打开少女心愿查看待付清单和尾款日期。")
            .setContentIntent(openIntent)
            .setAutoCancel(true)
            .setPriority(NotificationCompat.PRIORITY_DEFAULT)
            .build()
        NotificationManagerCompat.from(context).notify(itemId.toInt(), notification)
    }

    companion object {
        const val EXTRA_ITEM_ID = "extra_item_id"
        const val EXTRA_DAYS_BEFORE = "extra_days_before"
    }
}
