package com.shangjin.thoughtecho

import android.app.Application
import android.os.Build
import android.util.Log
import androidx.multidex.MultiDexApplication

class ThoughtEchoApplication : MultiDexApplication() {
    
    override fun onCreate() {
        super.onCreate()

        // 初始化MMKV
        try {
            com.tencent.mmkv.MMKV.initialize(this)
            Log.i("ThoughtEchoApp", "MMKV初始化成功")
        } catch (e: Exception) {
            Log.e("ThoughtEchoApp", "MMKV初始化失败", e)
        }
    }
    

}
