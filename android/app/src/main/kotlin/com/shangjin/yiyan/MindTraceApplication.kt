package com.shangjin.yiyan

import android.app.Application
import android.content.Context
import androidx.multidex.MultiDex
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.embedding.engine.dart.DartExecutor

class MindTraceApplication : Application() {
    override fun attachBaseContext(base: Context) {
        super.attachBaseContext(base)
        MultiDex.install(this)
    }

    override fun onCreate() {
        super.onCreate()
        
        // 预热Flutter引擎，可以提高首次启动性能
        val flutterEngine = FlutterEngine(this)
        flutterEngine.dartExecutor.executeDartEntrypoint(
            DartExecutor.DartEntrypoint.createDefault()
        )
        
        // 缓存Flutter引擎以便快速启动
        FlutterEngineCache.getInstance().put("mind_trace_engine", flutterEngine)
    }
}