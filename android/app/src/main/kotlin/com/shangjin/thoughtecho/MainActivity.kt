package com.shangjin.thoughtecho

import android.os.Build
import android.os.Bundle
import android.util.Log
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        flutterEngine.plugins.add(MemoryInfoPlugin())
        flutterEngine.plugins.add(StreamFileSelector())
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        // 只对ARM32设备禁用硬件加速，保持64位设备性能
        if (isArm32Device()) {
            Log.i("MainActivity", "检测到ARM32设备，禁用硬件加速以避免崩溃")
            try {
                window.clearFlags(WindowManager.LayoutParams.FLAG_HARDWARE_ACCELERATED)
            } catch (e: Exception) {
                Log.w("MainActivity", "无法禁用硬件加速: ${e.message}")
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