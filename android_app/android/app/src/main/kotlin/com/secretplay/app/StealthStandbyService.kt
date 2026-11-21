package com.secretplay.app

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.PowerManager
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import androidx.core.app.NotificationCompat
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.Response
import okhttp3.WebSocket
import okhttp3.WebSocketListener
import org.json.JSONObject
import java.util.concurrent.TimeUnit

/**
 * 24/7 Native Android Background & Lock-Screen Engine.
 * Connects directly to the user's personal Cloudflare Inbox WebSocket (/inbox-ws)
 * using OkHttp, so disguised alerts, floating heartbeats, and lock-screen neon sketches/stickers
 * trigger immediately even when Flutter is killed or the user is inside other apps!
 */
class StealthStandbyService : Service() {
    companion object {
        const val PREFS_NAME = "sp_native_standby"
        const val KEY_DEVICE_ID = "device_id"
        const val KEY_WS_BASE = "ws_base"
        const val DEFAULT_WS_BASE = "wss://secretplay-relay.enterprise-config-2026.workers.dev"

        const val CHANNEL_ID = "cyber_circuit_energy_channel"
        const val ALERT_CHANNEL_ID = "cyber_circuit_bonus_channel"
        const val NOTIFICATION_ID = 2009
        const val ACTION_START = "ACTION_START_STANDBY"
        const val ACTION_STOP = "ACTION_STOP_STANDBY"
    }

    private val mainHandler = Handler(Looper.getMainLooper())
    private var okHttpClient: OkHttpClient? = null
    private var inboxSocket: WebSocket? = null
    private var isStopped = false
    private var reconnectAttempt = 0
    private val seenEventIds = LinkedHashSet<String>()

    private val reconnectRunnable = Runnable {
        if (!isStopped) {
            connectInboxSocket()
        }
    }

    override fun onCreate() {
        super.onCreate()
        createNotificationChannels()
        okHttpClient = OkHttpClient.Builder()
            .pingInterval(20, TimeUnit.SECONDS)
            .connectTimeout(15, TimeUnit.SECONDS)
            .readTimeout(0, TimeUnit.SECONDS)
            .build()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_STOP -> {
                isStopped = true
                mainHandler.removeCallbacks(reconnectRunnable)
                inboxSocket?.close(1000, "Stopped")
                inboxSocket = null
                stopForeground(STOP_FOREGROUND_REMOVE)
                stopSelf()
                return START_NOT_STICKY
            }
            else -> {
                isStopped = false
                startForeground(NOTIFICATION_ID, buildDisguisedServiceNotification())
                connectInboxSocket()
            }
        }
        return START_STICKY
    }

    private fun connectInboxSocket() {
        if (isStopped) return
        val prefs = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val deviceId = prefs.getString(KEY_DEVICE_ID, "") ?: ""
        val wsBase = (prefs.getString(KEY_WS_BASE, DEFAULT_WS_BASE) ?: DEFAULT_WS_BASE).trimEnd('/')
        if (deviceId.isEmpty()) return

        inboxSocket?.cancel()
        val url = "$wsBase/inbox-ws?deviceId=$deviceId"
        val request = Request.Builder().url(url).build()
        inboxSocket = okHttpClient?.newWebSocket(request, object : WebSocketListener() {
            override fun onOpen(webSocket: WebSocket, response: Response) {
                reconnectAttempt = 0
            }

            override fun onMessage(webSocket: WebSocket, text: String) {
                try {
                    val obj = JSONObject(text)
                    if (obj.optString("type") == "inbox_event") {
                        handleInboxEvent(obj)
                    }
                } catch (_: Exception) {}
            }

            override fun onClosed(webSocket: WebSocket, code: Int, reason: String) {
                scheduleReconnect()
            }

            override fun onFailure(webSocket: WebSocket, t: Throwable, response: Response?) {
                scheduleReconnect()
            }
        })
    }

    private fun scheduleReconnect() {
        if (isStopped) return
        val delayMs = when (reconnectAttempt) {
            0 -> 2000L
            1 -> 4000L
            2 -> 8000L
            else -> 15000L
        }
        reconnectAttempt++
        mainHandler.removeCallbacks(reconnectRunnable)
        mainHandler.postDelayed(reconnectRunnable, delayMs)
    }

    private fun handleInboxEvent(obj: JSONObject) {
        val eventId = obj.optString("eventId")
        if (eventId.isNotEmpty()) {
            synchronized(seenEventIds) {
                if (seenEventIds.contains(eventId)) return
                if (seenEventIds.size >= 120) {
                    val first = seenEventIds.iterator().next()
                    seenEventIds.remove(first)
                }
                seenEventIds.add(eventId)
            }
        }

        val eventType = obj.optString("eventType", "new_msg")
        when (eventType) {
            "heartbeat_pulse" -> {
                vibratePattern(longArrayOf(0, 90, 80, 150, 260, 90, 80, 150))
                wakeScreenBriefly(3000L)
                val shownOverlay = NativeOverlayRenderer.showFloatingHeartbeat(this)
                if (!shownOverlay) {
                    postDisguisedHeadsUp(
                        id = 3011,
                        title = "🎮 Cyber Circuit",
                        body = "❤️ انرژی قلب شما شارژ شد!",
                        fullScreen = false
                    )
                }
            }
            "stealth_ping" -> {
                vibratePattern(longArrayOf(0, 110, 80, 110, 260, 220))
                wakeScreenBriefly(3000L)
                NativeOverlayRenderer.showFloatingStealthBanner(
                    this,
                    "🎮 Cyber Circuit",
                    "جایزه الماس روزانه شما آماده است! 💎"
                )
                postDisguisedHeadsUp(
                    id = 3009,
                    title = "🎮 Cyber Circuit",
                    body = "جایزه روزانه شما آماده است! 💎",
                    fullScreen = false
                )
            }
            "flash_hologram" -> {
                val emoji = obj.optString("emoji")
                val title = obj.optString("title")
                val body = obj.optString("body")
                val mediaBase64 = obj.optString("mediaBase64")
                val colorHex = obj.optString("colorHex", "#FF007A")
                val vanishSec = obj.optInt("flashSeconds", 7)

                wakeScreenBriefly(6000L)
                vibratePattern(longArrayOf(0, 140, 70, 220))
                val shownOverlay = NativeOverlayRenderer.showFloatingHologram(
                    context = this,
                    emoji = emoji,
                    title = title,
                    body = body,
                    pngBase64 = mediaBase64,
                    colorHex = colorHex,
                    vanishSec = vanishSec
                )
                if (!shownOverlay) {
                    postDisguisedHeadsUp(
                        id = 3001,
                        title = "⚡ Cyber Circuit",
                        body = if (body.isNotEmpty()) body else "جایزه هولوگرافیک فوری باز شد!",
                        fullScreen = true
                    )
                }
            }
            "incoming_call" -> {
                wakeScreenBriefly(7000L)
                vibratePattern(longArrayOf(0, 350, 200, 350, 200, 350))
                postDisguisedHeadsUp(
                    id = 3012,
                    title = "⚡ Cyber Circuit Live",
                    body = "چالش دو نفره زنده در حال شروع است! 🎯",
                    fullScreen = true
                )
            }
            else -> {
                vibratePattern(longArrayOf(0, 80, 60, 80))
                postDisguisedHeadsUp(
                    id = 3010,
                    title = "🎮 Cyber Circuit",
                    body = "یک مرحله جدید باز شد! بزن بریم 🎯",
                    fullScreen = false
                )
            }
        }
    }

    private fun wakeScreenBriefly(durationMs: Long) {
        try {
            val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
            @Suppress("DEPRECATION")
            val wl = pm.newWakeLock(
                PowerManager.FULL_WAKE_LOCK or
                        PowerManager.ACQUIRE_CAUSES_WAKEUP or
                        PowerManager.ON_AFTER_RELEASE,
                "secretplay:inbox_wakeup"
            )
            wl.acquire(durationMs)
        } catch (_: Exception) {}
    }

    private fun vibratePattern(timings: LongArray) {
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                val vm = getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as VibratorManager
                vm.defaultVibrator.vibrate(VibrationEffect.createWaveform(timings, -1))
            } else {
                @Suppress("DEPRECATION")
                val v = getSystemService(Context.VIBRATOR_SERVICE) as Vibrator
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    v.vibrate(VibrationEffect.createWaveform(timings, -1))
                } else {
                    @Suppress("DEPRECATION")
                    v.vibrate(timings, -1)
                }
            }
        } catch (_: Exception) {}
    }

    private fun postDisguisedHeadsUp(id: Int, title: String, body: String, fullScreen: Boolean) {
        try {
            val openIntent = Intent(this, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or
                        Intent.FLAG_ACTIVITY_SINGLE_TOP or
                        Intent.FLAG_ACTIVITY_CLEAR_TOP
            }
            val pendingFlags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            } else {
                PendingIntent.FLAG_UPDATE_CURRENT
            }
            val pi = PendingIntent.getActivity(this, id, openIntent, pendingFlags)

            val builder = NotificationCompat.Builder(this, ALERT_CHANNEL_ID)
                .setSmallIcon(android.R.drawable.star_big_on)
                .setContentTitle(title)
                .setContentText(body)
                .setPriority(NotificationCompat.PRIORITY_MAX)
                .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
                .setAutoCancel(true)
                .setContentIntent(pi)

            if (fullScreen) {
                builder.setCategory(NotificationCompat.CATEGORY_CALL)
                builder.setFullScreenIntent(pi, true)
            }

            val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            manager.notify(id, builder.build())
        } catch (_: Exception) {}
    }

    private fun createNotificationChannels() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            val standbyChannel = NotificationChannel(
                CHANNEL_ID,
                "Cyber Circuit Energy Sync",
                NotificationManager.IMPORTANCE_MIN
            ).apply {
                description = "Background puzzle energy recharge status"
                setShowBadge(false)
            }
            val alertChannel = NotificationChannel(
                ALERT_CHANNEL_ID,
                "Cyber Circuit Daily Rewards",
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "Daily bonus and live challenge alerts"
                enableVibration(true)
                lockscreenVisibility = Notification.VISIBILITY_PUBLIC
            }
            manager.createNotificationChannel(standbyChannel)
            manager.createNotificationChannel(alertChannel)
        }
    }

    private fun buildDisguisedServiceNotification(): Notification {
        val openIntent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        val pendingFlags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        } else {
            PendingIntent.FLAG_UPDATE_CURRENT
        }
        val pi = PendingIntent.getActivity(this, 2009, openIntent, pendingFlags)

        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("Cyber Circuit")
            .setContentText("انرژی مراحل بازی در حال شارژ...")
            .setSmallIcon(android.R.drawable.ic_media_play)
            .setOngoing(true)
            .setSilent(true)
            .setPriority(NotificationCompat.PRIORITY_MIN)
            .setContentIntent(pi)
            .build()
    }

    override fun onDestroy() {
        isStopped = true
        mainHandler.removeCallbacks(reconnectRunnable)
        inboxSocket?.close(1000, "Destroyed")
        inboxSocket = null
        okHttpClient?.dispatcher?.executorService?.shutdown()
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null
}
