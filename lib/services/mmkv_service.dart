// filepath: /workspaces/ThoughtEcho/lib/services/mmkv_service.dart
import 'dart:convert';
import '../utils/mmkv_ffi_fix.dart'; // 导入安全包装类
import '../utils/app_logger.dart';

/// MMKV存储服务，替代SharedPreferences以提高性能和可靠性
class MMKVService {
  static final MMKVService _instance = MMKVService._internal();

  factory MMKVService() => _instance;

  late final SafeMMKV _storage; // 使用我们的安全包装类
  bool _isInitialized = false;

  MMKVService._internal();

  /// 初始化MMKV存储
  Future<void> init() async {
    if (_isInitialized) return;

    try {
      _storage = SafeMMKV(); // 使用安全包装类
      await _storage.initialize(); // 初始化存储
      logDebug('MMKV已初始化，使用安全包装');
      _isInitialized = true;
    } catch (e) {
      logDebug('初始化MMKV失败: $e');
      rethrow;
    }
  }

  /// 确保MMKV已初始化
  void _ensureInitialized() {
    if (!_isInitialized) {
      throw StateError('MMKV尚未初始化，请先调用init()方法');
    }
  }

  /// 存储字符串值
  Future<bool> setString(String key, String value) async {
    _ensureInitialized();
    try {
      return await _storage.setString(key, value);
    } catch (e) {
      logDebug('MMKV保存字符串失败: $e');
      return false;
    }
  }

  /// 获取字符串值
  String? getString(String key) {
    _ensureInitialized();
    try {
      return _storage.getString(key);
    } catch (e) {
      logDebug('MMKV获取字符串失败: $e');
      return null;
    }
  }

  /// 存储布尔值
  Future<bool> setBool(String key, bool value) async {
    _ensureInitialized();
    try {
      return await _storage.setBool(key, value);
    } catch (e) {
      logDebug('MMKV保存布尔值失败: $e');
      return false;
    }
  }

  /// 获取布尔值
  bool? getBool(String key) {
    _ensureInitialized();
    try {
      return _storage.getBool(key);
    } catch (e) {
      logDebug('MMKV获取布尔值失败: $e');
      return null;
    }
  }

  /// 存储整数值
  Future<bool> setInt(String key, int value) async {
    _ensureInitialized();
    try {
      return await _storage.setInt(key, value);
    } catch (e) {
      logDebug('MMKV保存整数值失败: $e');
      return false;
    }
  }

  /// 获取整数值
  int? getInt(String key) {
    _ensureInitialized();
    try {
      return _storage.getInt(key);
    } catch (e) {
      logDebug('MMKV获取整数值失败: $e');
      return null;
    }
  }

  /// 存储双精度浮点值
  Future<bool> setDouble(String key, double value) async {
    _ensureInitialized();
    try {
      return await _storage.setDouble(key, value);
    } catch (e) {
      logDebug('MMKV保存浮点值失败: $e');
      return false;
    }
  }

  /// 获取双精度浮点值
  double? getDouble(String key) {
    _ensureInitialized();
    try {
      return _storage.getDouble(key);
    } catch (e) {
      logDebug('MMKV获取浮点值失败: $e');
      return null;
    }
  }

  /// 存储字符串列表
  Future<bool> setStringList(String key, List<String> value) async {
    _ensureInitialized();
    try {
      return await _storage.setStringList(key, value);
    } catch (e) {
      logDebug('MMKV保存字符串列表失败: $e');
      return false;
    }
  }

  /// 获取字符串列表
  List<String>? getStringList(String key) {
    _ensureInitialized();
    try {
      return _storage.getStringList(key);
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
      return _storage.containsKey(key);
    } catch (e) {
      logDebug('MMKV检查键失败: $e');
      return false;
    }
  }

  /// 删除指定键的值
  Future<bool> remove(String key) async {
    _ensureInitialized();
    try {
      return await _storage.remove(key);
    } catch (e) {
      logDebug('MMKV删除键失败: $e');
      return false;
    }
  }

  /// 清除所有存储的值
  Future<bool> clear() async {
    _ensureInitialized();
    try {
      return await _storage.clear();
    } catch (e) {
      logDebug('MMKV清除所有数据失败: $e');
      return false;
    }
  }

  /// 获取所有键
  List<String> getAllKeys() {
    _ensureInitialized();
    try {
      return _storage.getKeys().toList();
    } catch (e) {
      logDebug('MMKV获取所有键失败: $e');
      return [];
    }
  }
}
