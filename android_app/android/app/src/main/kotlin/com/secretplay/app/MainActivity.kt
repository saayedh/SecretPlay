package com.secretplay.app

import android.content.Context
import android.content.Intent
import android.media.AudioAttributes
import android.media.AudioFocusRequest
import android.media.AudioManager
import android.os.Build
import android.os.Bundle
import android.view.WindowManager
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterFragmentActivity() {
    private val SECURITY_CHANNEL = "com.secretplay.app/security"
    private var securityMethodChannel: MethodChannel? = null
    private var audioFocusRequest: AudioFocusRequest? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Default to FLAG_SECURE to prevent screenshots, screen recorders, and task snapshot leak
        window.setFlags(
            WindowManager.LayoutParams.FLAG_SECURE,
            WindowManager.LayoutParams.FLAG_SECURE
        )
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

    override fun onUserLeaveHint() {
        super.onUserLeaveHint()
        // Hardware Home or Recents gesture detected: immediately alert Flutter engine
        securityMethodChannel?.invokeMethod("onAppBackgrounded", null)
    }

    override fun onStop() {
        super.onStop()
        securityMethodChannel?.invokeMethod("onAppBackgrounded", null)
    }
}
