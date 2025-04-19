package com.tencent.mmkv;

import androidx.annotation.NonNull;
import io.flutter.embedding.engine.plugins.FlutterPlugin;
import com.tencent.mmkv.impl.MMKVPlugin;

/**
 * MMKV插件注册类 - 替代原有注册机制，使用修复版MMKVPlugin
 */
public class MMKVPluginRegistrant {
    public static void registerWith(@NonNull FlutterPlugin.FlutterPluginBinding binding) {
        final MMKVPlugin plugin = new MMKVPlugin();
        plugin.onAttachedToEngine(binding);
    }
}