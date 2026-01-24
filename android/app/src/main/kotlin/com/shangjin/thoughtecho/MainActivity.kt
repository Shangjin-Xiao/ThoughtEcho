package com.shangjin.thoughtecho

import android.os.Build
import android.os.Bundle
import android.util.Log
import android.view.WindowManager
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine

import io.flutter.plugin.common.MethodChannel
import java.util.TimeZone

class MainActivity : FlutterFragmentActivity() {

    private val CHANNEL = "com.shangjin.thoughtecho/timezone"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        flutterEngine.plugins.add(MemoryInfoPlugin())
        flutterEngine.plugins.add(StreamFileSelector())

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            if (call.method == "getTimeZone") {
                result.success(TimeZone.getDefault().id)
            } else {
                result.notImplemented()
            }
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        // ARM32设备在Application层已经设置了系统属性
        // 这里再次确保窗口级别的硬件加速被禁用
        if (isArm32Device()) {
            Log.i("MainActivity", "ARM32设备：确保窗口级硬件加速被禁用")
            try {
                window.clearFlags(WindowManager.LayoutParams.FLAG_HARDWARE_ACCELERATED)
                // 强制设置软件渲染
                window.setFlags(0, WindowManager.LayoutParams.FLAG_HARDWARE_ACCELERATED)
            } catch (e: Exception) {
                Log.w("MainActivity", "无法设置窗口渲染模式: ${e.message}")
            }
        }

        super.onCreate(savedInstanceState)
    }

    /**
     * 检测是否为ARM32设备（包括ARM32 binder64）
     */
    private fun isArm32Device(): Boolean {
        return try {
            val supportedAbis = Build.SUPPORTED_ABIS
            val hasArm32 = supportedAbis.contains("armeabi-v7a")
            val hasArm64 = supportedAbis.contains("arm64-v8a")

            // ARM32设备：有armeabi-v7a但没有arm64-v8a
            val isArm32 = hasArm32 && !hasArm64

            Log.i("MainActivity", "设备架构: ${supportedAbis.joinToString()}, ARM32: $isArm32")
            isArm32
        } catch (e: Exception) {
            Log.e("MainActivity", "检测设备架构失败", e)
            false // 保守起见，不禁用硬件加速
        }
    }
}