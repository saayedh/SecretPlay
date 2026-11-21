package com.secretplay.app

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build

/**
 * Automatically resumes StealthStandbyService after device reboot if a SecretPlay
 * device identity is already configured, ensuring 24/7 delivery.
 */
class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent?) {
        if (intent?.action != Intent.ACTION_BOOT_COMPLETED) return
        val prefs = context.getSharedPreferences(StealthStandbyService.PREFS_NAME, Context.MODE_PRIVATE)
        val deviceId = prefs.getString(StealthStandbyService.KEY_DEVICE_ID, "") ?: ""
        if (deviceId.isEmpty()) return

        try {
            val svcIntent = Intent(context, StealthStandbyService::class.java).apply {
                action = StealthStandbyService.ACTION_START
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(svcIntent)
            } else {
                context.startService(svcIntent)
            }
        } catch (_: Exception) {}
    }
}
