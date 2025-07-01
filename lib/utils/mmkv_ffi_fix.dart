// MMKV 包装类
// 这个文件提供了一个安全的 MMKV 包装，避免直接使用 FFI 接口
// 主要目的是解决 MMKV 在某些设备上的兼容性问题，特别是32位ARM设备

import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart' as sp;
import 'mmkv_adapter.dart';
import 'package:thoughtecho/utils/app_logger.dart';

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
  bool _initializing = false;

  // 标记是否是32位ARM设备
  bool _isArm32Device = false;

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
      // 检查是否是32位ARM设备
      if (!kIsWeb && Platform.isAndroid) {
        try {
          final is64bit = await _checkIs64BitDevice();
          _isArm32Device = !is64bit;
          logDebug('SafeMMKV: 检测到${is64bit ? '64位' : '32位'}设备');
        } catch (e) {
          logDebug('SafeMMKV: 检测设备架构失败: $e');
          _isArm32Device = false; // 默认假设不是32位设备
        }
      }

      if (kIsWeb) {
        _storage = SharedPrefsAdapter();
        await _storage!.initialize();
        logDebug('SafeMMKV: Web 平台，使用 SharedPreferences');
      } else {
        // 32位ARM设备优先使用SharedPreferences，避免MMKV可能存在的兼容性问题
        if (_isArm32Device) {
          logDebug('SafeMMKV: 检测到32位ARM设备，优先使用SharedPreferences');
          _storage = SharedPrefsAdapter();
          await _storage!.initialize();
        } else {
          try {
            _storage = MMKVAdapter();
            await _storage!.initialize();
            logDebug('SafeMMKV: 使用 MMKVAdapter 作为存储');
          } catch (e) {
            logDebug('SafeMMKV: MMKVAdapter 初始化失败: $e，回退到 SharedPreferences');
            _storage = SharedPrefsAdapter();
            await _storage!.initialize();
          }
        }
      }
      _initialized = true;
    } catch (e) {
      logDebug('SafeMMKV 初始化失败: $e');
      // 最终回退：如果所有存储机制都失败，尝试使用内存存储
      try {
        _storage = _InMemoryStorageAdapter();
        await _storage!.initialize();
        logDebug('SafeMMKV: 所有存储机制失败，回退到内存存储');
        _initialized = true;
      } catch (e2) {
        logDebug('SafeMMKV: 内存存储也初始化失败: $e2');
        rethrow;
      }
    } finally {
      _initializing = false;
    }
  }

  // 检测设备是否为64位
  Future<bool> _checkIs64BitDevice() async {
    try {
      if (!kIsWeb && Platform.isAndroid) {
        // 基于设备架构检测64位系统
        final arch = await _getPlatformArchitecture();
        return arch.contains('64') ||
            arch == 'aarch64' ||
            arch == 'x86_64' ||
            arch == 'mips64';
      } else if (!kIsWeb && Platform.isIOS) {
        // iOS模拟器可能返回x86_64，真机一般是arm64
        return true; // iOS设备大多都是64位了
      }
      // 其他平台假定为64位
      return true;
    } catch (e) {
      logDebug('检测设备架构失败: $e');
      // 安全起见，如果检测失败，假定为32位设备避免使用MMKV 2.x
      return false;
    }
  }

  // 获取设备架构
  Future<String> _getPlatformArchitecture() async {
    try {
      if (Platform.isAndroid) {
        // 尝试获取系统架构信息
        final archInfo = await Process.run('getprop', ['ro.product.cpu.abi']);
        if (archInfo.exitCode == 0 && archInfo.stdout != null) {
          final arch = (archInfo.stdout as String).trim().toLowerCase();
          logDebug('检测到CPU架构: $arch');
          return arch;
        }
      }
      // 如果无法通过命令获取，使用Dart自身检测
      String arch = Platform.operatingSystemVersion.toLowerCase();
      if (arch.contains('64')) return 'arm64';

      // 最后使用dart:io的内置属性
      return Platform.version.toLowerCase();
    } catch (e) {
      logDebug('获取平台架构失败: $e');
      return ''; // 返回空字符串，让调用者判断为32位设备
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

/// 内存存储适配器（作为最终回退）
class _InMemoryStorageAdapter implements StorageAdapter {
  final Map<String, dynamic> _data = {};

  @override
  Future<void> initialize() async {
    // 内存存储不需要初始化
  }

  @override
  Future<bool> setString(String key, String value) async {
    _data[key] = value;
    return true;
  }

  @override
  String? getString(String key) {
    final value = _data[key];
    return value is String ? value : null;
  }

  @override
  Future<bool> setInt(String key, int value) async {
    _data[key] = value;
    return true;
  }

  @override
  int? getInt(String key) {
    final value = _data[key];
    return value is int ? value : null;
  }

  @override
  Future<bool> setDouble(String key, double value) async {
    _data[key] = value;
    return true;
  }

  @override
  double? getDouble(String key) {
    final value = _data[key];
    return value is double ? value : null;
  }

  @override
  Future<bool> setBool(String key, bool value) async {
    _data[key] = value;
    return true;
  }

  @override
  bool? getBool(String key) {
    final value = _data[key];
    return value is bool ? value : null;
  }

  @override
  Future<bool> setStringList(String key, List<String> value) async {
    _data[key] = value;
    return true;
  }

  @override
  List<String>? getStringList(String key) {
    final value = _data[key];
    return value is List<String> ? value : null;
  }

  @override
  bool containsKey(String key) {
    return _data.containsKey(key);
  }

  @override
  Future<bool> remove(String key) async {
    _data.remove(key);
    return true;
  }

  @override
  Future<bool> clear() async {
    _data.clear();
    return true;
  }

  @override
  Set<String> getKeys() {
    return _data.keys.toSet();
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
  sp.SharedPreferences? _prefs;
  bool _initialized = false;

  @override
  Future<void> initialize() async {
    if (_initialized) return; // 防止重复初始化
    _prefs = await sp.SharedPreferences.getInstance();
    _initialized = true;
  }

  sp.SharedPreferences get prefs {
    if (_prefs == null) {
      throw StateError('SharedPrefsAdapter 尚未初始化');
    }
    return _prefs!;
  }

  @override
  Future<bool> setString(String key, String value) {
    return prefs.setString(key, value);
  }

  @override
  String? getString(String key) {
    return prefs.getString(key);
  }

  @override
  Future<bool> setInt(String key, int value) {
    return prefs.setInt(key, value);
  }

  @override
  int? getInt(String key) {
    return prefs.getInt(key);
  }

  @override
  Future<bool> setDouble(String key, double value) {
    return prefs.setDouble(key, value);
  }

  @override
  double? getDouble(String key) {
    return prefs.getDouble(key);
  }

  @override
  Future<bool> setBool(String key, bool value) {
    return prefs.setBool(key, value);
  }

  @override
  bool? getBool(String key) {
    return prefs.getBool(key);
  }

  @override
  Future<bool> setStringList(String key, List<String> value) async {
    return prefs.setStringList(key, value);
  }

  @override
  List<String>? getStringList(String key) {
    return prefs.getStringList(key);
  }

  @override
  bool containsKey(String key) {
    return prefs.containsKey(key);
  }

  @override
  Future<bool> remove(String key) {
    return prefs.remove(key);
  }

  @override
  Future<bool> clear() {
    return prefs.clear();
  }

  @override
  Set<String> getKeys() {
    return prefs.getKeys();
  }
}

// MMKVAdapter 实现已移至 mmkv_adapter_io.dart
