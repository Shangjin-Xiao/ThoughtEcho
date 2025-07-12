package com.shangjin.thoughtecho

import android.os.Build
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
// import android.view.WindowManager // Commented out as it's no longer needed
// import android.util.Log // Commented out as it's no longer needed

class MainActivity : FlutterActivity() {
    
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        flutterEngine.plugins.add(MemoryInfoPlugin())
        flutterEngine.plugins.add(StreamFileSelector())
    }
    override fun onCreate(savedInstanceState: Bundle?) {
        // Temporarily comment out the hardware acceleration check as it might cause issues before super.onCreate()
        // if (!is64BitDevice()) {
        //     Log.i("MainActivity", "Detected 32-bit device, disabling hardware acceleration.")
        //     // The following line was likely causing the crash by being called before super.onCreate()
        //     // and potentially enabling HW acceleration instead of disabling it.
        //     // window.setFlags(
        //     //     WindowManager.LayoutParams.FLAG_HARDWARE_ACCELERATED,
        //     //     WindowManager.LayoutParams.FLAG_HARDWARE_ACCELERATED
        //     // )
        // } else {
        //      Log.i("MainActivity", "Detected 64-bit device, hardware acceleration remains enabled.")
        // }
        
        // Call super.onCreate() first before any window modifications if needed later
        super.onCreate(savedInstanceState)

        // If you need to modify window flags later, do it *after* super.onCreate()
        // For example (though disabling HW accel is usually done in AndroidManifest):
        // if (!is64BitDevice()) {
        //    window.clearFlags(WindowManager.LayoutParams.FLAG_HARDWARE_ACCELERATED)
        // }
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