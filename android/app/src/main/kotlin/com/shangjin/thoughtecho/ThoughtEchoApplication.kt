package com.shangjin.thoughtecho

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.Build
import androidx.multidex.MultiDexApplication
import java.util.TimeZone

class ThoughtEchoApplication : MultiDexApplication() {
    override fun onCreate() {
        super.onCreate()
        syncDeviceTimeZone(this)
        registerTimeZoneReceiver()
    }

    private fun registerTimeZoneReceiver() {
        val filter = IntentFilter(Intent.ACTION_TIMEZONE_CHANGED)
        val receiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context?, intent: Intent?) {
                if (intent?.action == Intent.ACTION_TIMEZONE_CHANGED && context != null) {
                    syncDeviceTimeZone(context)
                }
            }
        }
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                registerReceiver(receiver, filter, Context.RECEIVER_NOT_EXPORTED)
            } else {
                @Suppress("UnspecifiedRegisterReceiverFlag")
                registerReceiver(receiver, filter)
            }
        } catch (_: Throwable) {
            // Best-effort registration; onCreate already synced the current zone.
        }
    }

    companion object {
        private const val FLUTTER_PREFS_NAME = "FlutterSharedPreferences"
        private const val DEVICE_TIMEZONE_PREF_KEY = "flutter.smart_push_device_timezone_v1"

        fun syncDeviceTimeZone(context: Context): String {
            val tzId = TimeZone.getDefault().id ?: ""
            if (tzId.isNotEmpty()) {
                try {
                    context.applicationContext
                        .getSharedPreferences(FLUTTER_PREFS_NAME, Context.MODE_PRIVATE)
                        .edit()
                        .putString(DEVICE_TIMEZONE_PREF_KEY, tzId)
                        .apply()
                } catch (_: Throwable) {
                }
            }
            return tzId
        }
    }
}
