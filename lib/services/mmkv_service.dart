// filepath: /workspaces/ThoughtEcho/lib/services/mmkv_service.dart
import 'dart:async';
import 'dart:convert';
import '../utils/mmkv_ffi_fix.dart'; // 导入安全包装类
import '../utils/app_logger.dart';

/// 修复：MMKV存储服务，增加并发控制和错误恢复
class MMKVService {
  static final MMKVService _instance = MMKVService._internal();

  factory MMKVService() => _instance;

  SafeMMKV? _storage; // 使用我们的安全包装类
  bool _isInitialized = false;
  bool _isInitializing = false;
  Completer<void>? _initCompleter;

  MMKVService._internal();

  /// 修复：初始化MMKV存储，增加并发控制
  Future<void> init() async {
    if (_isInitialized) return;

    // 防止并发初始化
    if (_isInitializing) {
      await _initCompleter?.future;
      return;
    }

    _isInitializing = true;
    _initCompleter = Completer<void>();

    try {
      _storage = SafeMMKV(); // 使用安全包装类
      await _storage!.initialize(); // 初始化存储
      logDebug('MMKV已初始化，使用安全包装');
      _isInitialized = true;
      _isInitializing = false;
      _initCompleter!.complete();
    } catch (e) {
      _isInitializing = false;
      _initCompleter!.completeError(e);
      logDebug('初始化MMKV失败: $e');
      rethrow;
    }
  }

  /// 修复：确保MMKV已初始化，支持自动初始化
  Future<void> _ensureInitialized() async {
    if (!_isInitialized) {
      await init();
    }
  }

  /// 修复：带重试机制的操作执行器
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
          logDebug('MMKV操作失败，已重试$maxRetries次: $e');
          rethrow;
        }
        logDebug('MMKV操作失败，第${attempt + 1}次重试: $e');
        await Future.delayed(delay * (attempt + 1));
      }
    }
    throw Exception('操作重试失败');
  }

  /// 修复：存储字符串值，增加重试机制
  Future<bool> setString(String key, String value) async {
    await _ensureInitialized();
    return _executeWithRetry(() async {
      return await _storage!.setString(key, value);
    });
  }

  /// 修复：获取字符串值，增加错误恢复
  String? getString(String key) {
    try {
      if (!_isInitialized) {
        logDebug('MMKV未初始化，无法获取字符串值');
        return null;
      }
      return _storage!.getString(key);
    } catch (e) {
      logDebug('MMKV获取字符串失败: $e');
      return null;
    }
  }

  /// 存储布尔值
  Future<bool> setBool(String key, bool value) async {
    _ensureInitialized();
    try {
      return await _storage!.setBool(key, value);
    } catch (e) {
      logDebug('MMKV保存布尔值失败: $e');
      return false;
    }
  }

  /// 获取布尔值
  bool? getBool(String key) {
    _ensureInitialized();
    try {
      return _storage!.getBool(key);
    } catch (e) {
      logDebug('MMKV获取布尔值失败: $e');
      return null;
    }
  }

  /// 存储整数值
  Future<bool> setInt(String key, int value) async {
    _ensureInitialized();
    try {
      return await _storage!.setInt(key, value);
    } catch (e) {
      logDebug('MMKV保存整数值失败: $e');
      return false;
    }
  }

  /// 获取整数值
  int? getInt(String key) {
    _ensureInitialized();
    try {
      return _storage!.getInt(key);
    } catch (e) {
      logDebug('MMKV获取整数值失败: $e');
      return null;
    }
  }

  /// 存储双精度浮点值
  Future<bool> setDouble(String key, double value) async {
    _ensureInitialized();
    try {
      return await _storage!.setDouble(key, value);
    } catch (e) {
      logDebug('MMKV保存浮点值失败: $e');
      return false;
    }
  }

  /// 获取双精度浮点值
  double? getDouble(String key) {
    _ensureInitialized();
    try {
      return _storage!.getDouble(key);
    } catch (e) {
      logDebug('MMKV获取浮点值失败: $e');
      return null;
    }
  }

  /// 存储字符串列表
  Future<bool> setStringList(String key, List<String> value) async {
    _ensureInitialized();
    try {
      return await _storage!.setStringList(key, value);
    } catch (e) {
      logDebug('MMKV保存字符串列表失败: $e');
      return false;
    }
  }

  /// 获取字符串列表
  List<String>? getStringList(String key) {
    _ensureInitialized();
    try {
      return _storage!.getStringList(key);
    } catch (e) {
      logDebug('MMKV获取字符串列表失败: $e');
      return null;
    }
  }

  /// 存储JSON对象（Map或List）
  Future<bool> setJson(String key, dynamic value) async {
    _ensureInitialized();
    try {
      final jsonStr = json.encode(value);
      return await setString(key, jsonStr);
    } catch (e) {
      logDebug('MMKV保存JSON对象失败: $e');
      return false;
    }
  }

  /// 获取JSON对象
  dynamic getJson(String key) {
    _ensureInitialized();
    try {
      final jsonStr = getString(key);
      if (jsonStr == null) return null;
      return json.decode(jsonStr);
    } catch (e) {
      logDebug('MMKV获取JSON对象失败: $e');
      return null;
    }
  }

  /// 检查键是否存在
  bool containsKey(String key) {
    _ensureInitialized();
    try {
      return _storage!.containsKey(key);
    } catch (e) {
      logDebug('MMKV检查键失败: $e');
      return false;
    }
  }

  /// 删除指定键的值
  Future<bool> remove(String key) async {
    _ensureInitialized();
    try {
      return await _storage!.remove(key);
    } catch (e) {
      logDebug('MMKV删除键失败: $e');
      return false;
    }
  }

  /// 清除所有存储的值
  Future<bool> clear() async {
    _ensureInitialized();
    try {
      return await _storage!.clear();
    } catch (e) {
      logDebug('MMKV清除所有数据失败: $e');
      return false;
    }
  }

  /// 获取所有键
  List<String> getAllKeys() {
    _ensureInitialized();
    try {
      return _storage!.getKeys().toList();
    } catch (e) {
      logDebug('MMKV获取所有键失败: $e');
      return [];
    }
  }
}
