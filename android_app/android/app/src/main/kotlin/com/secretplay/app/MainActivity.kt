package com.secretplay.app

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.media.AudioAttributes
import android.media.AudioFocusRequest
import android.media.AudioManager
import android.media.MediaPlayer
import android.media.MediaRecorder
import android.media.PlaybackParams
import android.media.ToneGenerator
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import android.provider.Settings
import android.util.Base64
import android.view.WindowManager
import androidx.core.app.NotificationCompat
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream
import java.net.HttpURLConnection
import java.net.URL
import kotlin.math.sqrt

class MainActivity : FlutterFragmentActivity(), SensorEventListener {
    private val SECURITY_CHANNEL = "com.secretplay.app/security"
    private val FLASH_CHANNEL_ID = "secretplay_live_flash_channel"
    private var securityMethodChannel: MethodChannel? = null
    private var audioFocusRequest: AudioFocusRequest? = null

    // Accelerometer Shake-to-Lock
    private var sensorManager: SensorManager? = null
    private var accelerometer: Sensor? = null
    private var lastShakeTimeMs: Long = 0

    // Ephemeral Voice Note Recorder
    private var voiceRecorder: MediaRecorder? = null
    private var tempVoiceFile: File? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            setShowWhenLocked(true)
            setTurnScreenOn(true)
        } else {
            @Suppress("DEPRECATION")
            window.addFlags(
                WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                        WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON
            )
        }
        window.setFlags(
            WindowManager.LayoutParams.FLAG_SECURE,
            WindowManager.LayoutParams.FLAG_SECURE
        )
        createFlashNotificationChannel()

        sensorManager = getSystemService(Context.SENSOR_SERVICE) as? SensorManager
        accelerometer = sensorManager?.getDefaultSensor(Sensor.TYPE_ACCELEROMETER)
    }

    override fun onResume() {
        super.onResume()
        accelerometer?.let {
            sensorManager?.registerListener(this, it, SensorManager.SENSOR_DELAY_UI)
        }
    }

    override fun onPause() {
        super.onPause()
        sensorManager?.unregisterListener(this)
    }

    override fun onSensorChanged(event: SensorEvent?) {
        if (event?.sensor?.type != Sensor.TYPE_ACCELEROMETER) return
        val x = event.values[0]
        val y = event.values[1]
        val z = event.values[2]
        val gX = x / SensorManager.GRAVITY_EARTH
        val gY = y / SensorManager.GRAVITY_EARTH
        val gZ = z / SensorManager.GRAVITY_EARTH
        val gForce = sqrt((gX * gX + gY * gY + gZ * gZ).toDouble()).toFloat()

        if (gForce > 2.65f) {
            val now = System.currentTimeMillis()
            if (now - lastShakeTimeMs > 1200) {
                lastShakeTimeMs = now
                securityMethodChannel?.invokeMethod("onShakeDetected", null)
            }
        }
    }

    override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) {}

    private fun startVoiceNoteRecording(): Boolean {
        return try {
            stopVoiceNoteRecording()
            val file = File(cacheDir, "sp_ephemeral_voice.m4a")
            if (file.exists()) file.delete()
            tempVoiceFile = file

            val recorder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                MediaRecorder(this)
            } else {
                @Suppress("DEPRECATION")
                MediaRecorder()
            }
            recorder.setAudioSource(MediaRecorder.AudioSource.MIC)
            recorder.setOutputFormat(MediaRecorder.OutputFormat.MPEG_4)
            recorder.setAudioEncoder(MediaRecorder.AudioEncoder.AAC)
            recorder.setAudioSamplingRate(16000)
            recorder.setAudioEncodingBitRate(24000)
            recorder.setOutputFile(file.absolutePath)
            recorder.prepare()
            recorder.start()
            voiceRecorder = recorder
            true
        } catch (_: Exception) {
            false
        }
    }

    private fun stopVoiceNoteRecording(): String? {
        return try {
            voiceRecorder?.apply {
                try {
                    stop()
                } catch (_: Exception) {}
                release()
            }
            voiceRecorder = null
            val file = tempVoiceFile
            tempVoiceFile = null
            if (file != null && file.exists()) {
                val bytes = file.readBytes()
                // Overwrite and delete temporary file immediately after reading into RAM
                file.writeBytes(ByteArray(bytes.size))
                file.delete()
                Base64.encodeToString(bytes, Base64.NO_WRAP)
            } else {
                null
            }
        } catch (_: Exception) {
            null
        }
    }

    private fun playVoiceNote(audioBase64: String, cyberPitch: Boolean) {
        try {
            val bytes = Base64.decode(audioBase64, Base64.DEFAULT)
            val playFile = File(cacheDir, "sp_play_temp.m4a")
            playFile.writeBytes(bytes)

            val player = MediaPlayer()
            player.setDataSource(playFile.absolutePath)
            player.prepare()
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M && cyberPitch) {
                try {
                    val params = PlaybackParams()
                    params.pitch = 0.80f // Anonymous deep cyber voice pitch
                    params.speed = 1.02f
                    player.playbackParams = params
                } catch (_: Exception) {}
            }
            player.setOnCompletionListener { mp ->
                mp.release()
                if (playFile.exists()) {
                    playFile.writeBytes(ByteArray(16))
                    playFile.delete()
                }
            }
            player.start()
        } catch (_: Exception) {}
    }

    private fun createFlashNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                FLASH_CHANNEL_ID,
                "SecretPlay Live Flash Hologram",
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "Wakes lock screen when partner sends a live sketch or flash note"
                enableVibration(true)
                lockscreenVisibility = android.app.Notification.VISIBILITY_PUBLIC
            }
            val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            manager.createNotificationChannel(channel)
        }
    }

    private fun wakeScreenAndShowFlashAlert(title: String, subtitle: String) {
        try {
            val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
            @Suppress("DEPRECATION")
            val wakeLock = pm.newWakeLock(
                PowerManager.FULL_WAKE_LOCK or
                        PowerManager.ACQUIRE_CAUSES_WAKEUP or
                        PowerManager.ON_AFTER_RELEASE,
                "secretplay:flash_wakeup"
            )
            wakeLock.acquire(5000L)

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
                setShowWhenLocked(true)
                setTurnScreenOn(true)
            }

            val fullScreenIntent = Intent(this, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or
                        Intent.FLAG_ACTIVITY_SINGLE_TOP or
                        Intent.FLAG_ACTIVITY_CLEAR_TOP
            }
            val pendingFlags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            } else {
                PendingIntent.FLAG_UPDATE_CURRENT
            }
            val fullScreenPendingIntent = PendingIntent.getActivity(
                this,
                3001,
                fullScreenIntent,
                pendingFlags
            )

            val notification = NotificationCompat.Builder(this, FLASH_CHANNEL_ID)
                .setSmallIcon(android.R.drawable.ic_dialog_info)
                .setContentTitle(title)
                .setContentText(subtitle)
                .setPriority(NotificationCompat.PRIORITY_MAX)
                .setCategory(NotificationCompat.CATEGORY_CALL)
                .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
                .setAutoCancel(true)
                .setFullScreenIntent(fullScreenPendingIntent, true)
                .build()

            val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            manager.notify(3001, notification)
            vibratePattern(longArrayOf(0, 140, 70, 220))

            startActivity(fullScreenIntent)
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

    private fun playGhostTouchChime(style: String) {
        try {
            val am = getSystemService(Context.AUDIO_SERVICE) as AudioManager
            if (am.ringerMode != AudioManager.RINGER_MODE_NORMAL) return
            val tone = when (style) {
                "mega_heart", "heart" -> ToneGenerator.TONE_PROP_BEEP2
                "bolt" -> ToneGenerator.TONE_PROP_ACK
                "spark" -> ToneGenerator.TONE_PROP_PROMPT
                else -> ToneGenerator.TONE_PROP_BEEP
            }
            val tg = ToneGenerator(AudioManager.STREAM_NOTIFICATION, 55)
            tg.startTone(tone, 140)
            Handler(Looper.getMainLooper()).postDelayed({
                try {
                    tg.release()
                } catch (_: Exception) {}
            }, 240L)
        } catch (_: Exception) {}
    }

    private fun showDisguisedOnlinePing(title: String, body: String) {
        try {
            // Secret signature vibration: tap-tap... buzzz (only your partner recognizes it!)
            vibratePattern(longArrayOf(0, 110, 80, 110, 260, 220))

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
            val pi = PendingIntent.getActivity(this, 3009, openIntent, pendingFlags)

            val notification = NotificationCompat.Builder(this, FLASH_CHANNEL_ID)
                .setSmallIcon(android.R.drawable.star_big_on)
                .setContentTitle(title)
                .setContentText(body)
                .setPriority(NotificationCompat.PRIORITY_HIGH)
                .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
                .setAutoCancel(true)
                .setContentIntent(pi)
                .build()

            val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            manager.notify(3009, notification)
        } catch (_: Exception) {}
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        securityMethodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SECURITY_CHANNEL)
        securityMethodChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "setSecureFlag" -> {
                    val enable = call.argument<Boolean>("enable") ?: true
                    if (enable) {
                        window.setFlags(
                            WindowManager.LayoutParams.FLAG_SECURE,
                            WindowManager.LayoutParams.FLAG_SECURE
                        )
                    } else {
                        window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
                    }
                    result.success(true)
                }
                "minimizeApp" -> {
                    moveTaskToBack(true)
                    result.success(true)
                }
                "openUrl" -> {
                    val url = call.argument<String>("url") ?: ""
                    if (url.isNotEmpty()) {
                        try {
                            val intent = Intent(Intent.ACTION_VIEW, Uri.parse(url)).apply {
                                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            }
                            startActivity(intent)
                        } catch (_: Exception) {}
                    }
                    result.success(true)
                }
                "downloadAndInstallApk" -> {
                    val url = call.argument<String>("url") ?: ""
                    if (url.isEmpty()) {
                        result.success(false)
                    } else {
                        downloadAndInstallApk(url, result)
                    }
                }
                "wakeAndShowFlashAlert" -> {
                    val title = call.argument<String>("title") ?: "⚡ SecretPlay Live Flash"
                    val subtitle = call.argument<String>("subtitle") ?: "New Hologram Flash!"
                    wakeScreenAndShowFlashAlert(title, subtitle)
                    result.success(true)
                }
                "startVoiceNoteRecording" -> {
                    result.success(startVoiceNoteRecording())
                }
                "stopVoiceNoteRecording" -> {
                    result.success(stopVoiceNoteRecording())
                }
                "playVoiceNote" -> {
                    val b64 = call.argument<String>("audioBase64") ?: ""
                    val pitch = call.argument<Boolean>("cyberPitch") ?: false
                    if (b64.isNotEmpty()) {
                        playVoiceNote(b64, pitch)
                    }
                    result.success(true)
                }
                "startStandbyService" -> {
                    try {
                        val intent = Intent(this, StealthStandbyService::class.java).apply {
                            action = StealthStandbyService.ACTION_START
                        }
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            startForegroundService(intent)
                        } else {
                            startService(intent)
                        }
                    } catch (_: Exception) {}
                    result.success(true)
                }
                "stopStandbyService" -> {
                    try {
                        val intent = Intent(this, StealthStandbyService::class.java).apply {
                            action = StealthStandbyService.ACTION_STOP
                        }
                        startService(intent)
                    } catch (_: Exception) {}
                    result.success(true)
                }
                "triggerStealthOnlinePing" -> {
                    val title = call.argument<String>("title") ?: "🎮 Cyber Circuit"
                    val body = call.argument<String>("body") ?: "جایزه روزانه شما آماده است! 💎"
                    showDisguisedOnlinePing(title, body)
                    result.success(true)
                }
                "triggerHeartbeatVibration" -> {
                    vibratePattern(longArrayOf(0, 90, 85, 150))
                    result.success(true)
                }
                "playGhostTouchChime" -> {
                    val style = call.argument<String>("style") ?: "default"
                    playGhostTouchChime(style)
                    result.success(true)
                }
                "configureStandbyEngine" -> {
                    val devId = call.argument<String>("deviceId") ?: ""
                    val wsBase = call.argument<String>("wsBase") ?: StealthStandbyService.DEFAULT_WS_BASE
                    if (devId.isNotEmpty()) {
                        getSharedPreferences(StealthStandbyService.PREFS_NAME, Context.MODE_PRIVATE)
                            .edit()
                            .putString(StealthStandbyService.KEY_DEVICE_ID, devId)
                            .putString(StealthStandbyService.KEY_WS_BASE, wsBase)
                            .apply()
                        try {
                            val svcIntent = Intent(this, StealthStandbyService::class.java).apply {
                                action = StealthStandbyService.ACTION_START
                            }
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                                startForegroundService(svcIntent)
                            } else {
                                startService(svcIntent)
                            }
                        } catch (_: Exception) {}
                    }
                    result.success(true)
                }
                "checkOverlayAndBatteryStatus" -> {
                    val canDraw = NativeOverlayRenderer.canDraw(this)
                    val ignoringBattery = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                        val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
                        pm.isIgnoringBatteryOptimizations(packageName)
                    } else {
                        true
                    }
                    result.success(
                        mapOf(
                            "canDrawOverlays" to canDraw,
                            "ignoringBatteryOptimizations" to ignoringBattery
                        )
                    )
                }
                "requestOverlayPermission" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M && !Settings.canDrawOverlays(this)) {
                        try {
                            val intent = Intent(
                                Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                                Uri.parse("package:$packageName")
                            ).apply {
                                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            }
                            startActivity(intent)
                        } catch (_: Exception) {}
                    }
                    result.success(true)
                }
                "requestIgnoreBatteryOptimizations" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                        val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
                        if (!pm.isIgnoringBatteryOptimizations(packageName)) {
                            try {
                                val intent = Intent(
                                    Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS,
                                    Uri.parse("package:$packageName")
                                ).apply {
                                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                                }
                                startActivity(intent)
                            } catch (_: Exception) {
                                try {
                                    startActivity(
                                        Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS).apply {
                                            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                                        }
                                    )
                                } catch (_: Exception) {}
                            }
                        }
                    }
                    result.success(true)
                }
                "testOverlayHeartbeat" -> {
                    vibratePattern(longArrayOf(0, 90, 80, 150, 260, 90, 80, 150))
                    val drawn = NativeOverlayRenderer.showFloatingHeartbeat(this)
                    result.success(drawn)
                }
                "syncGhostTouchPrefs" -> {
                    val position = call.argument<String>("position") ?: "center"
                    val durationSec = call.argument<Int>("displayDurationSec") ?: 7
                    val vibrateEnabled = call.argument<Boolean>("vibrateEnabled") ?: true
                    val soundEnabled = call.argument<Boolean>("soundEnabled") ?: true
                    val intensity = (call.argument<Number>("effectIntensity")?.toFloat() ?: 0.85f)
                    val reducedMotion = call.argument<Boolean>("reducedMotion") ?: false
                    getSharedPreferences(StealthStandbyService.PREFS_NAME, Context.MODE_PRIVATE)
                        .edit()
                        .putString(StealthStandbyService.KEY_GT_POSITION, position)
                        .putInt(StealthStandbyService.KEY_GT_DURATION, durationSec)
                        .putBoolean(StealthStandbyService.KEY_GT_VIBRATE, vibrateEnabled)
                        .putBoolean(StealthStandbyService.KEY_GT_SOUND, soundEnabled)
                        .putFloat(StealthStandbyService.KEY_GT_INTENSITY, intensity)
                        .putBoolean(StealthStandbyService.KEY_GT_REDUCED_MOTION, reducedMotion)
                        .apply()
                    result.success(true)
                }
                "startVoiceCallService" -> {
                    requestCallAudioFocus()
                    val intent = Intent(this, VoiceCallService::class.java).apply {
                        action = VoiceCallService.ACTION_START_CALL
                    }
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        startForegroundService(intent)
                    } else {
                        startService(intent)
                    }
                    result.success(true)
                }
                "stopVoiceCallService" -> {
                    releaseCallAudioFocus()
                    val intent = Intent(this, VoiceCallService::class.java).apply {
                        action = VoiceCallService.ACTION_STOP_CALL
                    }
                    startService(intent)
                    result.success(true)
                }
                "setAudioRoute" -> {
                    val route = call.argument<String>("route") ?: "earpiece"
                    applyAudioRoute(route)
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun requestCallAudioFocus() {
        val audioManager = getSystemService(Context.AUDIO_SERVICE) as AudioManager
        audioManager.mode = AudioManager.MODE_IN_COMMUNICATION
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val req = AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN_TRANSIENT)
                .setAudioAttributes(
                    AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_VOICE_COMMUNICATION)
                        .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
                        .build()
                )
                .build()
            audioFocusRequest = req
            audioManager.requestAudioFocus(req)
        }
    }

    private fun releaseCallAudioFocus() {
        val audioManager = getSystemService(Context.AUDIO_SERVICE) as AudioManager
        audioManager.isSpeakerphoneOn = false
        audioManager.stopBluetoothSco()
        audioManager.isBluetoothScoOn = false
        audioManager.mode = AudioManager.MODE_NORMAL
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            audioFocusRequest?.let { audioManager.abandonAudioFocusRequest(it) }
            audioFocusRequest = null
        }
    }

    private fun applyAudioRoute(route: String) {
        val audioManager = getSystemService(Context.AUDIO_SERVICE) as AudioManager
        audioManager.mode = AudioManager.MODE_IN_COMMUNICATION
        when (route) {
            "speaker" -> {
                audioManager.stopBluetoothSco()
                audioManager.isBluetoothScoOn = false
                audioManager.isSpeakerphoneOn = true
            }
            "bluetooth" -> {
                audioManager.isSpeakerphoneOn = false
                audioManager.startBluetoothSco()
                audioManager.isBluetoothScoOn = true
            }
            else -> {
                audioManager.stopBluetoothSco()
                audioManager.isBluetoothScoOn = false
                audioManager.isSpeakerphoneOn = false
            }
        }
    }

    private fun downloadAndInstallApk(initialUrl: String, result: MethodChannel.Result) {
        Thread {
            try {
                var currentUrl = initialUrl
                var conn: HttpURLConnection? = null
                var redirects = 0
                while (redirects < 8) {
                    val urlObj = URL(currentUrl)
                    conn = (urlObj.openConnection() as HttpURLConnection).apply {
                        instanceFollowRedirects = false
                        connectTimeout = 15000
                        readTimeout = 30000
                        setRequestProperty("User-Agent", "SecretPlay-Updater/1.3")
                    }
                    val code = conn.responseCode
                    if (code in 300..399) {
                        val loc = conn.getHeaderField("Location")
                        conn.disconnect()
                        if (loc.isNullOrEmpty()) break
                        currentUrl = URL(urlObj, loc).toString()
                        redirects++
                    } else {
                        break
                    }
                }

                if (conn == null || conn.responseCode !in 200..299) {
                    conn?.disconnect()
                    runOnUiThread { result.success(false) }
                    return@Thread
                }

                val totalBytes = conn.contentLengthLong
                val apkFile = File(cacheDir, "secretplay_update.apk")
                if (apkFile.exists()) apkFile.delete()

                conn.inputStream.use { input ->
                    FileOutputStream(apkFile).use { output ->
                        val buffer = ByteArray(16384)
                        var downloaded = 0L
                        var lastPct = -1
                        while (true) {
                            val read = input.read(buffer)
                            if (read <= 0) break
                            output.write(buffer, 0, read)
                            downloaded += read
                            if (totalBytes > 0) {
                                val pct = ((downloaded * 100) / totalBytes).toInt().coerceIn(0, 100)
                                if (pct != lastPct && (pct % 5 == 0 || pct == 100)) {
                                    lastPct = pct
                                    runOnUiThread {
                                        securityMethodChannel?.invokeMethod("onUpdateProgress", pct)
                                    }
                                }
                            }
                        }
                    }
                }
                conn.disconnect()

                val apkUri = FileProvider.getUriForFile(
                    this,
                    "${packageName}.fileprovider",
                    apkFile
                )
                val installIntent = Intent(Intent.ACTION_VIEW).apply {
                    setDataAndType(apkUri, "application/vnd.android.package-archive")
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_GRANT_READ_URI_PERMISSION)
                }
                runOnUiThread {
                    startActivity(installIntent)
                    result.success(true)
                }
            } catch (_: Exception) {
                runOnUiThread { result.success(false) }
            }
        }.start()
    }

    override fun onStop() {
        super.onStop()
        securityMethodChannel?.invokeMethod("onAppBackgrounded", null)
    }
}
