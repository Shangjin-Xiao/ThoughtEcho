package com.tencent.mmkv.impl;

import android.content.Context;

import androidx.annotation.NonNull;

import io.flutter.embedding.engine.plugins.FlutterPlugin;
import io.flutter.plugin.common.BinaryMessenger;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;
import io.flutter.plugin.common.MethodChannel.MethodCallHandler;
import io.flutter.plugin.common.MethodChannel.Result;
import io.flutter.plugin.common.StandardMethodCodec;

// 导入MMKV类
import com.tencent.mmkv.MMKV;
import com.tencent.mmkv.MMKVHandler;
import com.tencent.mmkv.MMKVLogLevel;
import com.tencent.mmkv.MMKVRecoverStrategic;
import com.getkeepsafe.relinker.ReLinker;

import java.util.HashMap;
import java.util.Map;

/**
 * MMKVPlugin - 修复版
 * 适配MMKV 2.1.1版本
 */
public class MMKVPlugin implements FlutterPlugin, MethodCallHandler {
    private MethodChannel channel;
    private static final String CHANNEL_NAME = "com.tencent/mmkv";
    private Context context;

    @Override
    public void onAttachedToEngine(@NonNull FlutterPluginBinding flutterPluginBinding) {
        setupChannel(flutterPluginBinding.getBinaryMessenger(), flutterPluginBinding.getApplicationContext());
    }

    @Override
    public void onDetachedFromEngine(@NonNull FlutterPluginBinding binding) {
        teardownChannel();
    }

    private void setupChannel(BinaryMessenger messenger, Context context) {
        this.context = context;
        channel = new MethodChannel(messenger, CHANNEL_NAME, StandardMethodCodec.INSTANCE);
        channel.setMethodCallHandler(this);
        
        // 初始化MMKV
        try {
            String rootDir = MMKV.initialize(context);
            System.out.println("MMKV for flutter: " + rootDir);
        } catch (Exception e) {
            System.err.println("Failed to initialize MMKV: " + e.getMessage());
            e.printStackTrace();
        }
    }

    private void teardownChannel() {
        channel.setMethodCallHandler(null);
        channel = null;
    }

    @Override
    public void onMethodCall(@NonNull MethodCall call, @NonNull Result result) {
        try {
            String method = call.method;
            if ("encode".equals(method)) {
                String mmapID = call.argument("mmapID");
                MMKV kv = (mmapID != null) ? MMKV.mmkvWithID(mmapID) : MMKV.defaultMMKV();
                if (kv == null) {
                    result.error("mmkv", "MMKV instance not found", null);
                    return;
                }

                String key = call.argument("key");
                Object value = call.argument("value");
                String type = call.argument("type");
                boolean ret = false;
                if ("bool".equals(type)) {
                    ret = kv.encode(key, (Boolean) value);
                } else if ("int".equals(type)) {
                    ret = kv.encode(key, (int) ((Number) value).intValue());
                } else if ("long".equals(type)) {
                    ret = kv.encode(key, ((Number) value).longValue());
                } else if ("float".equals(type)) {
                    ret = kv.encode(key, ((Number) value).floatValue());
                } else if ("double".equals(type)) {
                    ret = kv.encode(key, ((Number) value).doubleValue());
                } else if ("string".equals(type)) {
                    ret = kv.encode(key, (String) value);
                }
                result.success(ret);
            } else if ("getString".equals(method)) {
                String mmapID = call.argument("mmapID");
                MMKV kv = (mmapID != null) ? MMKV.mmkvWithID(mmapID) : MMKV.defaultMMKV();
                if (kv == null) {
                    result.error("mmkv", "MMKV instance not found", null);
                    return;
                }

                String key = call.argument("key");
                String defaultValue = call.argument("defaultValue");
                String value = kv.decodeString(key, defaultValue);
                result.success(value);
            } else if ("getBool".equals(method)) {
                String mmapID = call.argument("mmapID");
                MMKV kv = (mmapID != null) ? MMKV.mmkvWithID(mmapID) : MMKV.defaultMMKV();
                if (kv == null) {
                    result.error("mmkv", "MMKV instance not found", null);
                    return;
                }

                String key = call.argument("key");
                boolean defaultValue = call.argument("defaultValue");
                boolean value = kv.decodeBool(key, defaultValue);
                result.success(value);
            } else if ("getInt".equals(method)) {
                String mmapID = call.argument("mmapID");
                MMKV kv = (mmapID != null) ? MMKV.mmkvWithID(mmapID) : MMKV.defaultMMKV();
                if (kv == null) {
                    result.error("mmkv", "MMKV instance not found", null);
                    return;
                }

                String key = call.argument("key");
                int defaultValue = call.argument("defaultValue");
                int value = kv.decodeInt(key, defaultValue);
                result.success(value);
            } else if ("getLong".equals(method)) {
                String mmapID = call.argument("mmapID");
                MMKV kv = (mmapID != null) ? MMKV.mmkvWithID(mmapID) : MMKV.defaultMMKV();
                if (kv == null) {
                    result.error("mmkv", "MMKV instance not found", null);
                    return;
                }

                String key = call.argument("key");
                long defaultValue = call.argument("defaultValue");
                long value = kv.decodeLong(key, defaultValue);
                result.success(value);
            } else if ("getDouble".equals(method)) {
                String mmapID = call.argument("mmapID");
                MMKV kv = (mmapID != null) ? MMKV.mmkvWithID(mmapID) : MMKV.defaultMMKV();
                if (kv == null) {
                    result.error("mmkv", "MMKV instance not found", null);
                    return;
                }

                String key = call.argument("key");
                double defaultValue = call.argument("defaultValue");
                double value = kv.decodeDouble(key, defaultValue);
                result.success(value);
            } else if ("contains".equals(method)) {
                String mmapID = call.argument("mmapID");
                MMKV kv = (mmapID != null) ? MMKV.mmkvWithID(mmapID) : MMKV.defaultMMKV();
                if (kv == null) {
                    result.error("mmkv", "MMKV instance not found", null);
                    return;
                }

                String key = call.argument("key");
                boolean ret = kv.containsKey(key);
                result.success(ret);
            } else if ("removeItem".equals(method)) {
                String mmapID = call.argument("mmapID");
                MMKV kv = (mmapID != null) ? MMKV.mmkvWithID(mmapID) : MMKV.defaultMMKV();
                if (kv == null) {
                    result.error("mmkv", "MMKV instance not found", null);
                    return;
                }

                String key = call.argument("key");
                kv.removeValueForKey(key);
                result.success(null);
            } else if ("clearAll".equals(method)) {
                String mmapID = call.argument("mmapID");
                MMKV kv = (mmapID != null) ? MMKV.mmkvWithID(mmapID) : MMKV.defaultMMKV();
                if (kv == null) {
                    result.error("mmkv", "MMKV instance not found", null);
                    return;
                }

                kv.clearAll();
                result.success(null);
            } else if ("allKeys".equals(method)) {
                String mmapID = call.argument("mmapID");
                MMKV kv = (mmapID != null) ? MMKV.mmkvWithID(mmapID) : MMKV.defaultMMKV();
                if (kv == null) {
                    result.error("mmkv", "MMKV instance not found", null);
                    return;
                }

                String[] keys = kv.allKeys();
                result.success(keys);
            } else if ("disableProcessing".equals(method)) {
                // MMKV.disableProcessing(); // Method removed or deprecated
                result.success(null);
            } else {
                result.notImplemented();
            }
        } catch (Exception e) {
            result.error("mmkv_error", "Exception occurred: " + e.getMessage(), null);
        }
    }
}