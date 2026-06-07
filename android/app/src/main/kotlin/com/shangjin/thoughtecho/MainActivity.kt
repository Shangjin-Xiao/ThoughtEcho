package com.shangjin.thoughtecho

import android.content.ComponentName
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Bundle
import android.util.Log
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine

import io.flutter.plugin.common.MethodChannel
import java.util.TimeZone

class MainActivity : FlutterFragmentActivity() {

    private val timezoneChannel = "com.shangjin.thoughtecho/timezone"
    private val excerptIntentChannel = "com.shangjin.thoughtecho/excerpt_intent"
    private val excerptAliasName = "com.shangjin.thoughtecho.ExcerptEntryActivity"
    private var pendingExcerptText: String? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        flutterEngine.plugins.add(MemoryInfoPlugin())
        flutterEngine.plugins.add(StreamFileSelector())

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, timezoneChannel).setMethodCallHandler { call, result ->
            if (call.method == "getTimeZone") {
                result.success(TimeZone.getDefault().id)
            } else {
                result.notImplemented()
            }
        }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, excerptIntentChannel).setMethodCallHandler { call, result ->
            when (call.method) {
                "consumePendingExcerptText" -> {
                    val text = pendingExcerptText
                    pendingExcerptText = null
                    result.success(text)
                }

                "setExcerptEntryEnabled" -> {
                    val enabled = call.arguments as? Boolean
                    if (enabled == null) {
                        result.error("INVALID_ARGUMENT", "Missing enabled flag", null)
                    } else {
                        setExcerptEntryEnabled(enabled)
                        result.success(null)
                    }
                }

                else -> result.notImplemented()
            }
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        captureExcerptIntent(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        captureExcerptIntent(intent)
    }

    private fun captureExcerptIntent(intent: Intent?) {
        if (intent == null) return

        val action = intent.action
        val type = intent.type
        val text = when (action) {
            Intent.ACTION_PROCESS_TEXT -> intent.getCharSequenceExtra(Intent.EXTRA_PROCESS_TEXT)?.toString()
            Intent.ACTION_SEND -> {
                if (type == "text/plain") {
                    intent.getStringExtra(Intent.EXTRA_TEXT)
                        ?: intent.getCharSequenceExtra(Intent.EXTRA_TEXT)?.toString()
                } else {
                    null
                }
            }

            else -> null
        }?.trim()?.takeIf { it.isNotEmpty() }

        if (text != null) {
            pendingExcerptText = text
            Log.i("MainActivity", "Captured external excerpt text (${text.length} chars)")
        }
    }

    private fun setExcerptEntryEnabled(enabled: Boolean) {
        val componentName = ComponentName(this, excerptAliasName)
        val newState = if (enabled) {
            PackageManager.COMPONENT_ENABLED_STATE_ENABLED
        } else {
            PackageManager.COMPONENT_ENABLED_STATE_DISABLED
        }

        packageManager.setComponentEnabledSetting(
            componentName,
            newState,
            PackageManager.DONT_KILL_APP,
        )

        if (!enabled) {
            pendingExcerptText = null
        }

        Log.i("MainActivity", "Excerpt entry enabled: $enabled")
    }
}
