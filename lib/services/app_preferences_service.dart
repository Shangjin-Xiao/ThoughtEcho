import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../utils/app_logger.dart';
import '../utils/mmkv_ffi_fix.dart';

/// 应用轻量配置 KV 存储服务（内部委托给 SafeMMKV，主存储为 SharedPreferences + 过渡期原生 MMKV 镜像）
class AppPreferencesService {
  static final AppPreferencesService _instance =
      AppPreferencesService._internal();

  factory AppPreferencesService() => _instance;

  SafeMMKV? _storage;
  bool _isInitializing = false;
  Completer<void>? _initCompleter;

  AppPreferencesService._internal();

  /// 重置测试状态（连同底层 SafeMMKV 一并重置）
  @visibleForTesting
  void resetForTesting() {
    _isInitializing = false;
    _initCompleter = null;
    _storage = null;
    SafeMMKV().resetForTesting();
  }

  bool get _hasInitializedStorage {
    final storage = _storage ?? SafeMMKV();
    if (!storage.isInitialized) return false;
    _storage = storage;
    return true;
  }

  /// 初始化 KV 存储，增加并发控制
  Future<void> init() async {
    final existingStorage = _storage ?? SafeMMKV();
    if (existingStorage.isInitialized) {
      _storage = existingStorage;
      return;
    }

    if (_isInitializing) {
      await _initCompleter?.future;
      return;
    }

    _isInitializing = true;
    final completer = Completer<void>();
    _initCompleter = completer;

    try {
      final storage = SafeMMKV();
      _storage = storage;
      await storage.initialize();
      logDebug('AppPreferencesService 已初始化（SafeMMKV Phase 1 引擎）');
      _isInitializing = false;
      completer.complete();
    } catch (e) {
      _isInitializing = false;
      completer.completeError(e);
      logDebug('初始化 AppPreferencesService 失败: $e');
      rethrow;
    }
  }

  /// 确保已初始化，支持自动初始化
  Future<void> _ensureInitialized() async {
    if (!_hasInitializedStorage) {
      await init();
    }
  }

  /// 刷新跨 Isolate 的最新持久化数据
  Future<void> reload() async {
    await _ensureInitialized();
    await _storage!.reload();
  }

  /// 获取诊断报告（供开发者设置「MMKV 迁移与解析诊断」页面使用）
  Future<MmkvDiagnosticReport> collectDiagnosticReport() async {
    await _ensureInitialized();
    return _storage!.collectDiagnosticReport();
  }

  /// 手动触发迁移或重新校验迁移
  Future<MmkvMigrationSnapshot> runMigration({bool force = false}) async {
    await _ensureInitialized();
    return _storage!.runMigration(force: force);
  }

  /// 带重试机制的操作执行器
  Future<T> _executeWithRetry<T>(
    Future<T> Function() operation, {
    int maxRetries = 3,
    Duration delay = const Duration(milliseconds: 100),
  }) async {
    for (int attempt = 0; attempt < maxRetries; attempt++) {
      try {
        return await operation();
      } catch (e) {
        if (attempt == maxRetries - 1) {
          logDebug('KV操作失败，已重试$maxRetries次: $e');
          rethrow;
        }
        logDebug('KV操作失败，第${attempt + 1}次重试: $e');
        await Future.delayed(delay * (attempt + 1));
      }
    }
    throw Exception('操作重试失败');
  }

  /// 存储字符串值，增加重试机制
  Future<bool> setString(String key, String value) async {
    await _ensureInitialized();
    return _executeWithRetry(() async {
      return await _storage!.setString(key, value);
    });
  }

  /// 获取字符串值
  String? getString(String key) {
    try {
      if (!_hasInitializedStorage) {
        logDebug('KV存储未初始化，无法获取字符串值');
        return null;
      }
      return _storage!.getString(key);
    } catch (e) {
      logDebug('KV获取字符串失败: $e');
      return null;
    }
  }

  /// 存储布尔值
  Future<bool> setBool(String key, bool value) async {
    await _ensureInitialized();
    try {
      return await _storage!.setBool(key, value);
    } catch (e) {
      logDebug('KV保存布尔值失败: $e');
      return false;
    }
  }

  /// 获取布尔值
  bool? getBool(String key) {
    try {
      if (!_hasInitializedStorage) {
        logDebug('KV存储未初始化，无法获取布尔值');
        return null;
      }
      return _storage!.getBool(key);
    } catch (e) {
      logDebug('KV获取布尔值失败: $e');
      return null;
    }
  }

  /// 存储整数值
  Future<bool> setInt(String key, int value) async {
    await _ensureInitialized();
    try {
      return await _storage!.setInt(key, value);
    } catch (e) {
      logDebug('KV保存整数值失败: $e');
      return false;
    }
  }

  /// 获取整数值
  int? getInt(String key) {
    try {
      if (!_hasInitializedStorage) {
        logDebug('KV存储未初始化，无法获取整数值');
        return null;
      }
      return _storage!.getInt(key);
    } catch (e) {
      logDebug('KV获取整数值失败: $e');
      return null;
    }
  }

  /// 存储双精度浮点值
  Future<bool> setDouble(String key, double value) async {
    await _ensureInitialized();
    try {
      return await _storage!.setDouble(key, value);
    } catch (e) {
      logDebug('KV保存浮点值失败: $e');
      return false;
    }
  }

  /// 获取双精度浮点值
  double? getDouble(String key) {
    try {
      if (!_hasInitializedStorage) {
        logDebug('KV存储未初始化，无法获取浮点值');
        return null;
      }
      return _storage!.getDouble(key);
    } catch (e) {
      logDebug('KV获取浮点值失败: $e');
      return null;
    }
  }

  /// 存储字符串列表
  Future<bool> setStringList(String key, List<String> value) async {
    await _ensureInitialized();
    try {
      return await _storage!.setStringList(key, value);
    } catch (e) {
      logDebug('KV保存字符串列表失败: $e');
      return false;
    }
  }

  /// 获取字符串列表
  List<String>? getStringList(String key) {
    try {
      if (!_hasInitializedStorage) {
        logDebug('KV存储未初始化，无法获取字符串列表');
        return null;
      }
      return _storage!.getStringList(key);
    } catch (e) {
      logDebug('KV获取字符串列表失败: $e');
      return null;
    }
  }

  /// 存储JSON对象（Map或List）
  Future<bool> setJson(String key, dynamic value) async {
    await _ensureInitialized();
    try {
      final jsonStr = json.encode(value);
      return await setString(key, jsonStr);
    } catch (e) {
      logDebug('KV保存JSON对象失败: $e');
      return false;
    }
  }

  /// 获取JSON对象
  dynamic getJson(String key) {
    try {
      if (!_hasInitializedStorage) {
        logDebug('KV存储未初始化，无法获取JSON对象');
        return null;
      }
      final jsonStr = getString(key);
      if (jsonStr == null) return null;
      return json.decode(jsonStr);
    } catch (e) {
      logDebug('KV获取JSON对象失败: $e');
      return null;
    }
  }

  /// 检查键是否存在
  bool containsKey(String key) {
    try {
      if (!_hasInitializedStorage) {
        logDebug('KV存储未初始化，无法检查键');
        return false;
      }
      return _storage!.containsKey(key);
    } catch (e) {
      logDebug('KV检查键失败: $e');
      return false;
    }
  }

  /// 删除指定键的值
  Future<bool> remove(String key) async {
    await _ensureInitialized();
    try {
      return await _storage!.remove(key);
    } catch (e) {
      logDebug('KV删除键失败: $e');
      return false;
    }
  }

  /// 清除所有存储的值
  Future<bool> clear() async {
    await _ensureInitialized();
    try {
      return await _storage!.clear();
    } catch (e) {
      logDebug('KV清除所有数据失败: $e');
      return false;
    }
  }

  /// 获取所有键
  List<String> getAllKeys() {
    try {
      if (!_hasInitializedStorage) {
        logDebug('KV存储未初始化，无法获取所有键');
        return [];
      }
      final keys = _storage!.getKeys();
      return keys.map((e) => e.toString()).toList();
    } catch (e) {
      logDebug('KV获取所有键失败: $e');
      return [];
    }
  }
}
