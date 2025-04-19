package com.shangjin.thoughtecho;

import android.app.Application;
import io.flutter.app.FlutterApplication;
import androidx.multidex.MultiDex;
import android.content.Context;

import com.tencent.mmkv.MMKV;
import com.tencent.mmkv.MMKVLogLevel;

public class ThoughtEchoApplication extends FlutterApplication {
    @Override
    public void onCreate() {
        super.onCreate();
        
        // 初始化MMKV
        try {
            String rootDir = MMKV.initialize(this);
            System.out.println("MMKV initialized with root dir: " + rootDir);
            // 可选：设置日志级别
            MMKV.setLogLevel(MMKVLogLevel.LevelInfo);
        } catch (Exception e) {
            System.err.println("Failed to initialize MMKV: " + e.getMessage());
            e.printStackTrace();
        }
    }

    @Override
    protected void attachBaseContext(Context base) {
        super.attachBaseContext(base);
        MultiDex.install(this);
    }
}