package com.shangjin.thoughtecho

import android.os.Build
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import android.view.WindowManager

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        // 检测设备架构是否为32位，如果是则禁用硬件加速
        super.onCreate(savedInstanceState)
    }
    
    /**
     * 检查设备是否为64位架构
     * 返回true表示64位设备，false表示32位设备
     */
    private fun is64BitDevice(): Boolean {
        return try {
            // Android API 21+ (Lollipop及以上)可以通过Build类直接检测
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
                Build.SUPPORTED_64_BIT_ABIS.isNotEmpty()
            } else {
                // 对于更老的设备，通过CPU架构字符串判断
                val arch = System.getProperty("os.arch")?.lowercase() ?: ""
                arch.contains("64") || arch == "aarch64" || arch == "x86_64" || arch == "mips64"
            }
        } catch (e: Exception) {
            // 如果发生异常，保守起见返回false (当作32位处理)
            false
        }
    }
}