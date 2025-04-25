package com.shangjin.thoughtecho;

import android.app.Application;
import io.flutter.app.FlutterApplication;
import androidx.multidex.MultiDex;
import android.content.Context;
import android.os.Build;

import com.tencent.mmkv.MMKV;
import com.tencent.mmkv.MMKVLogLevel;

public class ThoughtEchoApplication extends FlutterApplication {
    @Override
    public void onCreate() {
        super.onCreate();
        
        // 检测是否为64位设备
        if (is64BitDevice()) {
            // 只在64位设备上初始化MMKV
            try {
                String rootDir = MMKV.initialize(this);
                System.out.println("MMKV initialized with root dir: " + rootDir);
                // 可选：设置日志级别
                MMKV.setLogLevel(MMKVLogLevel.LevelInfo);
            } catch (Exception e) {
                System.err.println("Failed to initialize MMKV: " + e.getMessage());
                e.printStackTrace();
            }
        } else {
            // 32位设备，输出信息但不初始化MMKV
            System.out.println("32-bit device detected, skipping MMKV initialization");
        }
    }

    /**
     * 检测设备是否为64位架构
     * @return true表示64位设备，false表示32位设备
     */
    private boolean is64BitDevice() {
        // Android API 21+ (Lollipop及以上)可以通过Build类直接检测
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
            return Build.SUPPORTED_64_BIT_ABIS != null && Build.SUPPORTED_64_BIT_ABIS.length > 0;
        } else {
            // 对于较老的设备，通过CPU架构字符串判断
            String arch = System.getProperty("os.arch");
            if (arch != null) {
                arch = arch.toLowerCase();
                return arch.contains("64") || arch.equals("aarch64") || 
                       arch.equals("x86_64") || arch.equals("mips64");
            }
            // 无法确定时，保守处理为32位设备
            return false;
        }
    }

    @Override
    protected void attachBaseContext(Context base) {
        super.attachBaseContext(base);
        MultiDex.install(this);
    }
}