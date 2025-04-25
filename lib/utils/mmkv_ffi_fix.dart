// MMKV 包装类
// 这个文件提供了一个安全的 MMKV 包装，避免直接使用 FFI 接口
// 主要目的是解决 MMKV 2.1.1 版本与当前 Dart/Flutter 版本的兼容性问题

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart' as sp;
import 'mmkv_adapter.dart';

/// 安全的 MMKV 包装类，当 MMKV 出现问题时会回退到 shared_preferences
class SafeMMKV {
  // 单例模式
  static final SafeMMKV _instance = SafeMMKV._internal();
  factory SafeMMKV() => _instance;
  SafeMMKV._internal();
  
  // 存储适配器 - 改为非 late，允许为 null
  StorageAdapter? _storage;
  
  // 初始化标识
  bool _initialized = false;
  
  // 初始化锁，防止并发初始化
  final _initLock = Object();
  bool _initializing = false;
  
  /// 初始化存储
  Future<void> initialize() async {
    // 如果已经初始化，则直接返回，避免重复初始化
    if (_initialized) return;
    
    // 简单的锁机制，避免并发初始化
    if (_initializing) {
      // 如果已经有其他线程在初始化，等待它完成
      while (_initializing && !_initialized) {
        await Future.delayed(const Duration(milliseconds: 50));
      }
      return;
    }
    
    _initializing = true;
    try {
      if (kIsWeb) {
        _storage = SharedPrefsAdapter();
        await _storage!.initialize();
        debugPrint('SafeMMKV: Web 平台，使用 SharedPreferences');
      } else {
        try {
          _storage = MMKVAdapter();
          await _storage!.initialize();
          debugPrint('SafeMMKV: 使用 MMKVAdapter (移动端) 作为存储');
        } catch (e) {
          debugPrint('SafeMMKV: MMKVAdapter 初始化失败: $e，回退到 SharedPreferences');
          _storage = SharedPrefsAdapter();
          await _storage!.initialize();
        }
      }
      _initialized = true;
    } catch (e) {
      debugPrint('SafeMMKV 初始化失败: $e');
      rethrow;
    } finally {
      _initializing = false;
    }
  }
  
  /// 确保已初始化
  void _ensureInitialized() {
    if (!_initialized || _storage == null) {
      throw StateError('SafeMMKV 尚未初始化，请先调用 initialize() 方法');
    }
  }
  
  /// 设置字符串值
  Future<bool> setString(String key, String value) async {
    _ensureInitialized();
    return _storage!.setString(key, value);
  }
  
  /// 获取字符串值
  String? getString(String key) {
    _ensureInitialized();
    return _storage!.getString(key);
  }
  
  /// 设置整数值
  Future<bool> setInt(String key, int value) async {
    _ensureInitialized();
    return _storage!.setInt(key, value);
  }
  
  /// 获取整数值
  int? getInt(String key) {
    _ensureInitialized();
    return _storage!.getInt(key);
  }
  
  /// 设置双精度浮点值
  Future<bool> setDouble(String key, double value) async {
    _ensureInitialized();
    return _storage!.setDouble(key, value);
  }
  
  /// 获取双精度浮点值
  double? getDouble(String key) {
    _ensureInitialized();
    return _storage!.getDouble(key);
  }
  
  /// 设置布尔值
  Future<bool> setBool(String key, bool value) async {
    _ensureInitialized();
    return _storage!.setBool(key, value);
  }
  
  /// 获取布尔值
  bool? getBool(String key) {
    _ensureInitialized();
    return _storage!.getBool(key);
  }
  
  /// 设置字符串列表
  Future<bool> setStringList(String key, List<String> value) async {
    _ensureInitialized();
    return _storage!.setStringList(key, value);
  }
  
  /// 获取字符串列表
  List<String>? getStringList(String key) {
    _ensureInitialized();
    return _storage!.getStringList(key);
  }
  
  /// 检查键是否存在
  bool containsKey(String key) {
    _ensureInitialized();
    return _storage!.containsKey(key);
  }
  
  /// 删除指定键的值
  Future<bool> remove(String key) async {
    _ensureInitialized();
    return _storage!.remove(key);
  }
  
  /// 清除所有值
  Future<bool> clear() async {
    _ensureInitialized();
    return _storage!.clear();
  }
  
  /// 获取所有键名
  Set<String> getKeys() {
    _ensureInitialized();
    return _storage!.getKeys();
  }
}

/// 存储适配器接口
abstract class StorageAdapter {
  Future<void> initialize();
  Future<bool> setString(String key, String value);
  String? getString(String key);
  Future<bool> setInt(String key, int value);
  int? getInt(String key);
  Future<bool> setDouble(String key, double value);
  double? getDouble(String key);
  Future<bool> setBool(String key, bool value);
  bool? getBool(String key);
  Future<bool> setStringList(String key, List<String> value);
  List<String>? getStringList(String key);
  bool containsKey(String key);
  Future<bool> remove(String key);
  Future<bool> clear();
  Set<String> getKeys();
}

/// SharedPreferences 存储适配器
class SharedPrefsAdapter implements StorageAdapter {
  late sp.SharedPreferences _prefs;
  
  @override
  Future<void> initialize() async {
    _prefs = await sp.SharedPreferences.getInstance();
  }
  
  @override
  Future<bool> setString(String key, String value) {
    return _prefs.setString(key, value);
  }
  
  @override
  String? getString(String key) {
    return _prefs.getString(key);
  }
  
  @override
  Future<bool> setInt(String key, int value) {
    return _prefs.setInt(key, value);
  }
  
  @override
  int? getInt(String key) {
    return _prefs.getInt(key);
  }
  
  @override
  Future<bool> setDouble(String key, double value) {
    return _prefs.setDouble(key, value);
  }
  
  @override
  double? getDouble(String key) {
    return _prefs.getDouble(key);
  }
  
  @override
  Future<bool> setBool(String key, bool value) {
    return _prefs.setBool(key, value);
  }
  
  @override
  bool? getBool(String key) {
    return _prefs.getBool(key);
  }
  
  @override
  Future<bool> setStringList(String key, List<String> value) {
    return _prefs.setStringList(key, value);
  }
  
  @override
  List<String>? getStringList(String key) {
    return _prefs.getStringList(key);
  }
  
  @override
  bool containsKey(String key) {
    return _prefs.containsKey(key);
  }
  
  @override
  Future<bool> remove(String key) {
    return _prefs.remove(key);
  }
  
  @override
  Future<bool> clear() {
    return _prefs.clear();
  }
  
  @override
  Set<String> getKeys() {
    return _prefs.getKeys();
  }
}

// MMKVAdapter 实现已移至 mmkv_adapter_io.dart