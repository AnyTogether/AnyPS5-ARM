package org.anyps5.anyps5_remote

import android.Manifest
import android.app.Activity
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.drawable.Icon
import android.media.AudioAttributes
import android.media.RingtoneManager
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import com.google.firebase.messaging.FirebaseMessaging
import com.google.firebase.messaging.FirebaseMessagingService
import com.google.firebase.messaging.RemoteMessage
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/// Push on Android, through Firebase Cloud Messaging: the token for the server, asking the person
/// (Android 13 and newer ask), the channels, a friend's call drawn over the lock screen with Answer
/// and Decline, and the taps for the app to open where they lead. Without the Firebase project's
/// values in the build there is no token, and the app says push is not set up.
object Push {
    const val TOGETHER = "together"
    const val CALLS = "calls"
    private const val ASK = 4711
    private const val ASKED = "push.asked"

    /// The keys a push carries for the app (FCM keeps its own beside them in a tap's extras).
    private val keys = listOf("type", "kind", "tag", "callId", "caller", "notice", "url", "action")

    private var channel: MethodChannel? = null
    private var heard = false
    private var unheard: Map<String, Any?>? = null
    private var asking: MethodChannel.Result? = null

    /// The app is in front: it shows things itself.
    @Volatile var foreground = false

    fun listen(activity: Activity, messenger: BinaryMessenger) {
        channels(activity)
        val made = MethodChannel(messenger, "org.anyps5.remote/push")
        channel = made
        made.setMethodCallHandler { call, result ->
            heard = true
            when (call.method) {
                "token" -> token(result)
                "permission" -> result.success(permission(activity))
                "ask" -> ask(activity, result)
                "launchedWith" -> {
                    result.success(unheard)
                    unheard = null
                }
                "clearCall" -> {
                    val callId = call.argument<String>("callId") ?: ""
                    manager(activity).cancel("missed_call:$callId", 0)
                    result.success(null)
                }
                "badge" -> {
                    // Everything read: what waited in the list is old news.
                    if ((call.argument<Int>("count") ?: 0) == 0) clearTogether(activity)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun token(result: MethodChannel.Result) {
        val messaging = try {
            FirebaseMessaging.getInstance()
        } catch (_: IllegalStateException) {
            // No Firebase project in this build.
            return result.success(null)
        }
        messaging.token.addOnCompleteListener { task ->
            result.success(if (task.isSuccessful && task.result != null) mapOf("token" to task.result) else null)
        }
    }

    /// From the messaging service's thread: the channel is used on the main one.
    fun renewed(token: String) {
        Handler(Looper.getMainLooper()).post { channel?.invokeMethod("token", token) }
    }

    private fun permission(context: Context): String {
        if (Build.VERSION.SDK_INT < 33) {
            return if (manager(context).areNotificationsEnabled()) "granted" else "denied"
        }
        if (context.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED) {
            return "granted"
        }
        val asked = context.getSharedPreferences("push", Context.MODE_PRIVATE).getBoolean(ASKED, false)
        return if (asked) "denied" else "undetermined"
    }

    private fun ask(activity: Activity, result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < 33 || permission(activity) == "granted") {
            return result.success(permission(activity) == "granted")
        }
        asking?.success(false)
        asking = result
        activity.getSharedPreferences("push", Context.MODE_PRIVATE).edit().putBoolean(ASKED, true).apply()
        activity.requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), ASK)
    }

    fun answered(requestCode: Int, results: IntArray) {
        if (requestCode != ASK) return
        asking?.success(results.firstOrNull() == PackageManager.PERMISSION_GRANTED)
        asking = null
    }

    /// A tap on one of ours (the app started by it, or brought to the front).
    fun opened(intent: Intent?) {
        val extras = intent?.extras ?: return
        if (extras.getString("kind") == null) return
        val payload = keys.mapNotNull { key -> extras.getString(key)?.let { key to it } }.toMap()
        // Read once: the same intent coming back (a rotation) opens nothing again.
        intent.removeExtra("kind")
        val open = channel
        if (heard && open != null) open.invokeMethod("opened", payload) else unheard = payload
    }

    fun manager(context: Context): NotificationManager =
        context.getSystemService(NotificationManager::class.java)

    fun channels(context: Context) {
        if (Build.VERSION.SDK_INT < 26) return
        val manager = manager(context)
        manager.createNotificationChannel(
            NotificationChannel(TOGETHER, context.getString(R.string.push_channel_together), NotificationManager.IMPORTANCE_HIGH).apply {
                description = context.getString(R.string.push_channel_together_detail)
            },
        )
        manager.createNotificationChannel(
            NotificationChannel(CALLS, context.getString(R.string.push_channel_calls), NotificationManager.IMPORTANCE_HIGH).apply {
                description = context.getString(R.string.push_channel_calls_detail)
                setSound(
                    RingtoneManager.getDefaultUri(RingtoneManager.TYPE_RINGTONE),
                    AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_NOTIFICATION_RINGTONE)
                        .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION).build(),
                )
                enableVibration(true)
                vibrationPattern = longArrayOf(0, 800, 600, 800, 600, 800)
            },
        )
    }

    private fun clearTogether(context: Context) {
        val manager = manager(context)
        for (shown in manager.activeNotifications) {
            if (Build.VERSION.SDK_INT < 26 || shown.notification.channelId == TOGETHER) manager.cancel(shown.tag, shown.id)
        }
    }

    private fun builder(context: Context, channel: String): Notification.Builder =
        if (Build.VERSION.SDK_INT >= 26) {
            Notification.Builder(context, channel)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(context)
        }

    /// Opens the app with what the push carried, and what was pressed.
    private fun tap(context: Context, data: Map<String, String>, action: String?, code: Int): PendingIntent {
        val intent = Intent(context, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
            putExtras(Bundle().apply {
                for ((key, value) in data) if (key in keys) putString(key, value)
                if (action != null) putString("action", action)
            })
        }
        return PendingIntent.getActivity(context, code, intent, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
    }

    /// A friend calling: over the lock screen as a call, ringing until answered, declined or 45
    /// seconds have gone by.
    fun ring(context: Context, data: Map<String, String>) {
        channels(context)
        val tag = data["tag"] ?: return
        val code = tag.hashCode()
        val open = tap(context, data, null, code)
        val notification = builder(context, CALLS)
            .setSmallIcon(R.drawable.ic_stat_anyps5)
            .setColor(context.getColor(R.color.push_accent))
            .setContentTitle(data["title"])
            .setContentText(data["body"])
            .setCategory(Notification.CATEGORY_CALL)
            .setContentIntent(open)
            .setFullScreenIntent(open, true)
            .setOngoing(true)
            .setAutoCancel(true)
            .addAction(Notification.Action.Builder(null as Icon?, context.getString(R.string.push_decline), tap(context, data, "decline", code + 1)).build())
            .addAction(Notification.Action.Builder(null as Icon?, context.getString(R.string.push_answer), tap(context, data, "answer", code + 2)).build())
        if (Build.VERSION.SDK_INT >= 26) notification.setTimeoutAfter(45_000)
        manager(context).notify(tag, 0, notification.build())
    }

    /// The ringing is over: gone, or a missed call in its place.
    fun over(context: Context, data: Map<String, String>) {
        val tag = data["tag"] ?: return
        manager(context).cancel(tag, 0)
        val title = data["title"] ?: return
        channels(context)
        val notification = builder(context, TOGETHER)
            .setSmallIcon(R.drawable.ic_stat_anyps5)
            .setColor(context.getColor(R.color.push_accent))
            .setContentTitle(title)
            .setContentText(data["body"])
            .setCategory(Notification.CATEGORY_MISSED_CALL)
            .setContentIntent(tap(context, data, null, tag.hashCode()))
            .setAutoCancel(true)
        manager(context).notify(tag, 0, notification.build())
    }
}

/// Messages from Firebase Cloud Messaging. A notification is shown by Android itself while the app
/// is not in front; a call, and its end, are drawn here.
class PushService : FirebaseMessagingService() {
    override fun onNewToken(token: String) {
        Push.renewed(token)
    }

    override fun onMessageReceived(message: RemoteMessage) {
        when (message.data["type"]) {
            "call" -> if (!Push.foreground) Push.ring(this, message.data)
            "call_over" -> Push.over(this, message.data)
        }
    }
}
