package com.shangjin.thoughtecho

import android.os.Build
import android.os.Bundle
import android.util.Log
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    private val DEVICE_INFO_CHANNEL = "com.shangjin.thoughtecho/device_info"

    override fun provideFlutterEngine(context: android.content.Context): FlutterEngine? {
        // 对于ARM32 binder64设备，使用预配置的引擎
        if (Arm32Binder64CompatibilityHelper.isArm32Binder64Device()) {
            Log.i("MainActivity", "使用ARM32 binder64预配置的Flutter引擎")
            return FlutterEngineCache.getInstance().get("arm32_binder64_engine")
        }
        return super.provideFlutterEngine(context)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        flutterEngine.plugins.add(MemoryInfoPlugin())
        flutterEngine.plugins.add(StreamFileSelector())

        // 设置设备信息通道
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, DEVICE_INFO_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "is64BitDevice" -> {
                    result.success(is64BitDevice())
                }
                "isArm32Binder64Device" -> {
                    result.success(Arm32Binder64CompatibilityHelper.isArm32Binder64Device())
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        // ARM32 binder64设备特殊处理
        if (!is64BitDevice()) {
            Log.i("MainActivity", "检测到ARM32设备，应用binder64兼容性配置")
            try {
                // ARM32 binder64设备需要特殊的窗口配置
                window.setFlags(
                    WindowManager.LayoutParams.FLAG_HARDWARE_ACCELERATED,
                    0
                )
                // 强制软件渲染
                window.setFlags(
                    WindowManager.LayoutParams.FLAG_FORCE_NOT_FULLSCREEN,
                    WindowManager.LayoutParams.FLAG_FORCE_NOT_FULLSCREEN
                )
            } catch (e: Exception) {
                Log.w("MainActivity", "ARM32 binder64设备窗口配置失败: ${e.message}")
            }
        } else {
            Log.i("MainActivity", "检测到64位设备，保持默认配置")
        }

        super.onCreate(savedInstanceState)

        // ARM32 binder64设备的后续配置
        if (!is64BitDevice()) {
            try {
                // 完全禁用硬件加速
                window.clearFlags(WindowManager.LayoutParams.FLAG_HARDWARE_ACCELERATED)
                // 设置软件渲染模式
                window.setFlags(0, WindowManager.LayoutParams.FLAG_HARDWARE_ACCELERATED)
                Log.i("MainActivity", "ARM32 binder64设备渲染模式已设置")
            } catch (e: Exception) {
                Log.w("MainActivity", "ARM32 binder64设备渲染配置失败: ${e.message}")
            }
        }
    }

    /**
     * 检查设备是否为64位架构
     * 返回true表示64位设备，false表示32位设备
     * Note: This function is currently unused.
     */
    private fun is64BitDevice(): Boolean {
        return try {
            // Android API 21+ (Lollipop及以上)可以通过Build类直接检测
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
                Build.SUPPORTED_64_BIT_ABIS.isNotEmpty()
            } else {
                // 对于更老的设备，通过CPU架构字符串判断
                // 注意：这种方法可能不完全可靠，但作为一种兼容性尝试
                val arch = System.getProperty("os.arch")?.lowercase() ?: ""
                // Log.d("MainActivity", "Device architecture string: $arch") // Log the architecture string for debugging
                arch.contains("64") || arch == "aarch64" || arch == "x86_64" || arch == "mips64"
            }
        } catch (e: Exception) {
            // 如果发生异常，保守起见返回false (当作32位处理)
            // Log.e("MainActivity", "Error checking device architecture", e)
            false
        }
    }
}