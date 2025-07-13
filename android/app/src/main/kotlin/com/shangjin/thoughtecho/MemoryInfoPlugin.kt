package com.shangjin.thoughtecho

import android.app.ActivityManager
import android.content.Context
import android.os.Debug
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import java.io.File
import java.io.RandomAccessFile
import kotlin.math.max

class MemoryInfoPlugin: FlutterPlugin, MethodCallHandler {
    private lateinit var channel: MethodChannel
    private lateinit var context: Context
    private val handler = Handler(Looper.getMainLooper())
    private var memoryMonitoringRunnable: Runnable? = null
    private var isMonitoring = false

    // 内存压力阈值
    private val MEMORY_PRESSURE_HIGH = 0.85  // 85%使用率为高压力
    private val MEMORY_PRESSURE_CRITICAL = 0.95  // 95%使用率为临界状态

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
            "getDetailedMemoryInfo" -> {
                try {
                    val detailedInfo = getDetailedMemoryInfo()
                    result.success(detailedInfo)
                } catch (e: Exception) {
                    result.error("MEMORY_ERROR", "Failed to get detailed memory info: ${e.message}", null)
                }
            }
            "startMemoryMonitoring" -> {
                try {
                    val intervalMs = call.argument<Int>("intervalMs") ?: 5000
                    startMemoryMonitoring(intervalMs)
                    result.success(true)
                } catch (e: Exception) {
                    result.error("MONITORING_ERROR", "Failed to start memory monitoring: ${e.message}", null)
                }
            }
            "stopMemoryMonitoring" -> {
                try {
                    stopMemoryMonitoring()
                    result.success(true)
                } catch (e: Exception) {
                    result.error("MONITORING_ERROR", "Failed to stop memory monitoring: ${e.message}", null)
                }
            }
            "forceGarbageCollection" -> {
                try {
                    forceGarbageCollection()
                    result.success(true)
                } catch (e: Exception) {
                    result.error("GC_ERROR", "Failed to force garbage collection: ${e.message}", null)
                }
            }
            "getMemoryPressureLevel" -> {
                try {
                    val pressureLevel = getMemoryPressureLevel()
                    result.success(pressureLevel)
                } catch (e: Exception) {
                    result.error("PRESSURE_ERROR", "Failed to get memory pressure level: ${e.message}", null)
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
        stopMemoryMonitoring()
        channel.setMethodCallHandler(null)
    }

    private fun getDetailedMemoryInfo(): Map<String, Any> {
        val basicInfo = getMemoryInfo()
        val debug = Debug.MemoryInfo()
        Debug.getMemoryInfo(debug)

        // 获取系统内存信息
        val systemMemInfo = getSystemMemoryInfo()

        return basicInfo.toMutableMap().apply {
            put("dalvikPrivateDirty", debug.dalvikPrivateDirty * 1024L)
            put("dalvikPss", debug.dalvikPss * 1024L)
            put("nativePrivateDirty", debug.nativePrivateDirty * 1024L)
            put("nativePss", debug.nativePss * 1024L)
            put("otherPrivateDirty", debug.otherPrivateDirty * 1024L)
            put("otherPss", debug.otherPss * 1024L)
            put("totalPrivateDirty", debug.totalPrivateDirty * 1024L)
            put("totalPss", debug.totalPss * 1024L)
            put("totalSharedDirty", debug.totalSharedDirty * 1024L)
            putAll(systemMemInfo)
        }
    }

    private fun getSystemMemoryInfo(): Map<String, Any> {
        val memInfo = mutableMapOf<String, Any>()

        try {
            // 读取 /proc/meminfo 获取更详细的系统内存信息
            val memInfoFile = File("/proc/meminfo")
            if (memInfoFile.exists()) {
                memInfoFile.readLines().forEach { line ->
                    val parts = line.split(":")
                    if (parts.size >= 2) {
                        val key = parts[0].trim()
                        val valueStr = parts[1].trim().replace(" kB", "")
                        try {
                            val value = valueStr.toLong() * 1024L // 转换为字节
                            when (key) {
                                "MemTotal" -> memInfo["systemTotalMemory"] = value
                                "MemFree" -> memInfo["systemFreeMemory"] = value
                                "MemAvailable" -> memInfo["systemAvailableMemory"] = value
                                "Buffers" -> memInfo["systemBuffers"] = value
                                "Cached" -> memInfo["systemCached"] = value
                                "SwapTotal" -> memInfo["systemSwapTotal"] = value
                                "SwapFree" -> memInfo["systemSwapFree"] = value
                            }
                        } catch (e: NumberFormatException) {
                            // 忽略无法解析的行
                        }
                    }
                }
            }
        } catch (e: Exception) {
            // 如果读取失败，添加默认值
            memInfo["systemMemoryReadError"] = e.message ?: "Unknown error"
        }

        return memInfo
    }

    private fun startMemoryMonitoring(intervalMs: Int) {
        if (isMonitoring) {
            stopMemoryMonitoring()
        }

        isMonitoring = true
        memoryMonitoringRunnable = object : Runnable {
            override fun run() {
                if (isMonitoring) {
                    try {
                        val memoryInfo = getMemoryInfo()
                        val pressureLevel = getMemoryPressureLevel()

                        // 发送内存状态更新到Flutter
                        handler.post {
                            channel.invokeMethod("onMemoryStatusUpdate", mapOf(
                                "memoryInfo" to memoryInfo,
                                "pressureLevel" to pressureLevel,
                                "timestamp" to System.currentTimeMillis()
                            ))
                        }

                        // 如果内存压力过高，触发自动清理
                        if (pressureLevel >= 2) { // 高压力或临界状态
                            forceGarbageCollection()
                        }

                    } catch (e: Exception) {
                        // 监控出错时通知Flutter
                        handler.post {
                            channel.invokeMethod("onMemoryMonitoringError", mapOf(
                                "error" to e.message,
                                "timestamp" to System.currentTimeMillis()
                            ))
                        }
                    }

                    // 安排下次检查
                    handler.postDelayed(this, intervalMs.toLong())
                }
            }
        }

        // 立即开始监控
        handler.post(memoryMonitoringRunnable!!)
    }

    private fun stopMemoryMonitoring() {
        isMonitoring = false
        memoryMonitoringRunnable?.let { runnable ->
            handler.removeCallbacks(runnable)
        }
        memoryMonitoringRunnable = null
    }

    private fun forceGarbageCollection() {
        try {
            // 建议进行垃圾回收
            System.gc()

            // 等待一小段时间让GC完成
            Thread.sleep(100)

            // 再次建议GC以确保彻底清理
            System.gc()

        } catch (e: Exception) {
            // 忽略GC过程中的异常
        }
    }

    private fun getMemoryPressureLevel(): Int {
        try {
            val runtime = Runtime.getRuntime()
            val maxMemory = runtime.maxMemory()
            val totalMemory = runtime.totalMemory()
            val freeMemory = runtime.freeMemory()
            val usedMemory = totalMemory - freeMemory

            val usageRatio = usedMemory.toDouble() / maxMemory.toDouble()

            return when {
                usageRatio >= MEMORY_PRESSURE_CRITICAL -> 3 // 临界状态
                usageRatio >= MEMORY_PRESSURE_HIGH -> 2     // 高压力
                usageRatio >= 0.6 -> 1                     // 中等压力
                else -> 0                                   // 正常状态
            }
        } catch (e: Exception) {
            return 1 // 出错时返回中等压力作为安全值
        }
    }
}