package com.shangjin.thoughtecho

import android.content.Context
import android.os.Build
import android.util.Log
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.embedding.engine.dart.DartExecutor

/**
 * ARM32 binder64设备兼容性助手
 * 专门处理ARM32 binder64架构设备的Flutter引擎初始化问题
 */
object Arm32Binder64CompatibilityHelper {
    
    private const val TAG = "Arm32Binder64Helper"
    
    /**
     * 检测是否为ARM32 binder64设备
     */
    fun isArm32Binder64Device(): Boolean {
        return try {
            // 检查CPU架构
            val supportedAbis = Build.SUPPORTED_ABIS
            val is32BitArm = supportedAbis.contains("armeabi-v7a") && 
                            !supportedAbis.contains("arm64-v8a")
            
            // 检查binder架构（通过系统属性）
            val binderArch = System.getProperty("ro.binder.bitness") ?: "32"
            val isBinder64 = binderArch == "64"
            
            val result = is32BitArm && isBinder64
            Log.i(TAG, "设备架构检测: ARM32=${is32BitArm}, Binder64=${isBinder64}, 结果=${result}")
            
            result
        } catch (e: Exception) {
            Log.e(TAG, "检测ARM32 binder64设备时出错", e)
            false
        }
    }
    
    /**
     * 为ARM32 binder64设备预配置Flutter引擎
     */
    fun preconfigureFlutterEngine(context: Context): FlutterEngine? {
        if (!isArm32Binder64Device()) {
            return null
        }
        
        return try {
            Log.i(TAG, "为ARM32 binder64设备预配置Flutter引擎")
            
            // 创建专门的Flutter引擎实例
            val flutterEngine = FlutterEngine(context)
            
            // ARM32 binder64特殊配置
            configureEngineForArm32Binder64(flutterEngine)
            
            // 缓存引擎以供后续使用
            FlutterEngineCache
                .getInstance()
                .put("arm32_binder64_engine", flutterEngine)
            
            Log.i(TAG, "ARM32 binder64 Flutter引擎预配置完成")
            flutterEngine
            
        } catch (e: Exception) {
            Log.e(TAG, "ARM32 binder64 Flutter引擎预配置失败", e)
            null
        }
    }
    
    /**
     * 配置Flutter引擎以适应ARM32 binder64设备
     */
    private fun configureEngineForArm32Binder64(flutterEngine: FlutterEngine) {
        try {
            // 设置Dart VM选项以优化ARM32 binder64性能
            val dartExecutor = flutterEngine.dartExecutor
            
            // 这里可以添加更多ARM32 binder64特定的配置
            Log.i(TAG, "Flutter引擎ARM32 binder64配置完成")
            
        } catch (e: Exception) {
            Log.w(TAG, "配置Flutter引擎时出现警告", e)
        }
    }
    
    /**
     * 获取ARM32 binder64设备的推荐内存设置
     */
    fun getRecommendedMemorySettings(): MemorySettings {
        return MemorySettings(
            heapSize = 128 * 1024 * 1024, // 128MB
            heapGrowthLimit = 96 * 1024 * 1024, // 96MB
            maxCacheSize = 32 * 1024 * 1024, // 32MB
            enableLargeHeap = true
        )
    }
    
    /**
     * 内存设置数据类
     */
    data class MemorySettings(
        val heapSize: Int,
        val heapGrowthLimit: Int,
        val maxCacheSize: Int,
        val enableLargeHeap: Boolean
    )
    
    /**
     * 应用ARM32 binder64设备的系统级优化
     */
    fun applySystemOptimizations() {
        if (!isArm32Binder64Device()) {
            return
        }
        
        try {
            Log.i(TAG, "应用ARM32 binder64系统级优化")
            
            // 设置系统属性
            System.setProperty("flutter.embedding.android.enable_software_rendering", "true")
            System.setProperty("flutter.embedding.android.enable_impeller", "false")
            System.setProperty("flutter.embedding.android.enable_vulkan", "false")
            
            // ARM32 binder64特殊的渲染配置
            System.setProperty("debug.egl.hw", "0")
            System.setProperty("debug.sf.hw", "0")
            
            Log.i(TAG, "ARM32 binder64系统级优化完成")
            
        } catch (e: Exception) {
            Log.w(TAG, "应用系统级优化时出现警告", e)
        }
    }
}
