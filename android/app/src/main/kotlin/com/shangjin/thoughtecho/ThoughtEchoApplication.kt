package com.shangjin.thoughtecho

import android.app.Application
import android.os.Build
import android.util.Log
import androidx.multidex.MultiDexApplication

class ThoughtEchoApplication : MultiDexApplication() {
    
    override fun onCreate() {
        super.onCreate()

        // ARM32 binder64设备特殊处理
        if (Arm32Binder64CompatibilityHelper.isArm32Binder64Device()) {
            Log.i("ThoughtEchoApp", "检测到ARM32 binder64设备，应用特殊配置")
            Arm32Binder64CompatibilityHelper.applySystemOptimizations()
            // 预配置Flutter引擎
            Arm32Binder64CompatibilityHelper.preconfigureFlutterEngine(this)
        } else if (!is64BitDevice()) {
            Log.i("ThoughtEchoApp", "初始化32位设备兼容性配置")
            initFor32BitDevice()
        } else {
            Log.i("ThoughtEchoApp", "检测到64位设备，使用标准配置")
        }

        // 初始化MMKV
        try {
            com.tencent.mmkv.MMKV.initialize(this)
            Log.i("ThoughtEchoApp", "MMKV初始化成功")
        } catch (e: Exception) {
            Log.e("ThoughtEchoApp", "MMKV初始化失败", e)
        }
    }
    
    /**
     * ARM32 binder64设备特殊初始化配置
     */
    private fun initFor32BitDevice() {
        try {
            // ARM32 binder64设备特殊配置
            System.setProperty("flutter.embedding.android.SurfaceProducerTextureRegistry.enable_surface_producer_texture_registry", "false")
            System.setProperty("flutter.embedding.android.SurfaceProducerTextureRegistry.enable_impeller", "false")

            // 禁用可能导致ARM32 binder64设备崩溃的特性
            System.setProperty("ro.config.disable_hw_accel", "true")
            System.setProperty("debug.egl.hw", "0")
            System.setProperty("ro.kernel.qemu.gles", "0")

            // ARM32 binder64特殊的内存管理
            System.setProperty("dalvik.vm.heapsize", "128m")
            System.setProperty("dalvik.vm.heapgrowthlimit", "96m")

            Log.i("ThoughtEchoApp", "ARM32 binder64设备系统属性配置完成")
        } catch (e: Exception) {
            Log.w("ThoughtEchoApp", "ARM32 binder64设备系统属性配置失败: ${e.message}")
        }
    }
    
    /**
     * 检查设备是否为64位架构
     */
    private fun is64BitDevice(): Boolean {
        return try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
                Build.SUPPORTED_64_BIT_ABIS.isNotEmpty()
            } else {
                val arch = System.getProperty("os.arch")?.lowercase() ?: ""
                arch.contains("64") || arch == "aarch64" || arch == "x86_64" || arch == "mips64"
            }
        } catch (e: Exception) {
            Log.e("ThoughtEchoApp", "检测设备架构时出错", e)
            false // 保守起见，当作32位处理
        }
    }
}
