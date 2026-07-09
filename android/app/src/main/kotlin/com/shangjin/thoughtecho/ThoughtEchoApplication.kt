package com.shangjin.thoughtecho

import android.os.Build
import android.util.Log
import androidx.multidex.MultiDexApplication

class ThoughtEchoApplication : MultiDexApplication() {
    
    override fun onCreate() {
        super.onCreate()

        if (isArm32Device()) {
            Log.i("ThoughtEchoApp", "检测到ARM32设备，设置系统级兼容性配置")
            try {
                System.setProperty("ro.config.disable_hw_accel", "true")
                System.setProperty("debug.egl.hw", "0")
                System.setProperty("debug.sf.hw", "0")
                Log.i("ThoughtEchoApp", "ARM32设备系统属性配置完成")
            } catch (e: Exception) {
                Log.w("ThoughtEchoApp", "ARM32设备系统属性配置失败: ${e.message}")
            }
        }

        // 初始化MMKV
        try {
            com.tencent.mmkv.MMKV.initialize(this)
            Log.i("ThoughtEchoApp", "MMKV初始化成功")
        } catch (t: Throwable) {
            Log.e("ThoughtEchoApp", "MMKV初始化失败，继续启动并交由Dart层回退存储", t)
        }
    }

    /**
     * 检测是否为 ARM32 设备（包括 ARM32 binder64）。
     */
    private fun isArm32Device(): Boolean {
        return try {
            val supportedAbis = Build.SUPPORTED_ABIS
            val hasArm32 = supportedAbis.contains("armeabi-v7a")
            val hasArm64 = supportedAbis.contains("arm64-v8a")
            val isArm32 = hasArm32 && !hasArm64

            Log.i("ThoughtEchoApp", "设备架构: ${supportedAbis.joinToString()}, ARM32: $isArm32")
            isArm32
        } catch (e: Exception) {
            Log.e("ThoughtEchoApp", "检测设备架构失败", e)
            false
        }
    }
}
