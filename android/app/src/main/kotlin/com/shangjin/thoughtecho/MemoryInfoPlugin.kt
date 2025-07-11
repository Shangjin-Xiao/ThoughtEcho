package com.shangjin.thoughtecho

import android.app.ActivityManager
import android.content.Context
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result

class MemoryInfoPlugin: FlutterPlugin, MethodCallHandler {
    private lateinit var channel: MethodChannel
    private lateinit var context: Context

    override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        channel = MethodChannel(flutterPluginBinding.binaryMessenger, "thoughtecho/memory_info")
        channel.setMethodCallHandler(this)
        context = flutterPluginBinding.applicationContext
    }

    override fun onMethodCall(call: MethodCall, result: Result) {
        when (call.method) {
            "getMemoryInfo" -> {
                try {
                    val memoryInfo = getMemoryInfo()
                    result.success(memoryInfo)
                } catch (e: Exception) {
                    result.error("MEMORY_ERROR", "Failed to get memory info: ${e.message}", null)
                }
            }
            else -> {
                result.notImplemented()
            }
        }
    }

    private fun getMemoryInfo(): Map<String, Any> {
        val activityManager = context.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
        val memoryInfo = ActivityManager.MemoryInfo()
        activityManager.getMemoryInfo(memoryInfo)

        // 获取应用的内存使用情况
        val runtime = Runtime.getRuntime()
        val maxMemory = runtime.maxMemory()
        val totalMemory = runtime.totalMemory()
        val freeMemory = runtime.freeMemory()
        val usedMemory = totalMemory - freeMemory

        return mapOf(
            "totalMem" to memoryInfo.totalMem,
            "availMem" to memoryInfo.availMem,
            "threshold" to memoryInfo.threshold,
            "lowMemory" to memoryInfo.lowMemory,
            "appMaxMemory" to maxMemory,
            "appTotalMemory" to totalMemory,
            "appUsedMemory" to usedMemory,
            "appFreeMemory" to freeMemory
        )
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
    }
}