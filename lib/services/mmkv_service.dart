// filepath: /workspaces/ThoughtEcho/lib/services/mmkv_service.dart
import 'package:flutter/foundation.dart';
import 'package:mmkv/mmkv.dart';
import 'dart:convert';

/// MMKV存储服务，替代SharedPreferences以提高性能和可靠性
class MMKVService {
  static final MMKVService _instance = MMKVService._internal();

  factory MMKVService() => _instance;

  late final MMKV _mmkv;
  bool _isInitialized = false;

  MMKVService._internal();

  /// 初始化MMKV存储
  Future<void> init() async {
    if (_isInitialized) return;

    try {
      // Web平台不支持MMKV，使用mock实现
      if (kIsWeb) {
        debugPrint('在Web平台上MMKV不可用，使用内存存储模拟');
        _isInitialized = true;
        return;
      }

      final rootDir = await MMKV.initialize();
      debugPrint('MMKV已初始化，根目录: $rootDir');
      _mmkv = MMKV('thought_echo');
      _isInitialized = true;
    } catch (e) {
      debugPrint('初始化MMKV失败: $e');
      rethrow;
    }
  }

  /// 确保MMKV已初始化
  void _ensureInitialized() {
    if (!_isInitialized) {
      throw StateError('MMKV尚未初始化，请先调用init()方法');
    }

    if (kIsWeb) {
      return; // Web平台使用模拟实现，不需要检查_mmkv
    }
  }

  /// 存储字符串值
  Future<bool> setString(String key, String value) async {
    _ensureInitialized();
    try {
      if (kIsWeb) {
        // Web平台模拟实现
        _webStorage[key] = value;
        return true;
      }
      return _mmkv.encodeString(key, value);
    } catch (e) {
      debugPrint('MMKV保存字符串失败: $e');
      return false;
    }
  }

  /// 获取字符串值
  String? getString(String key) {
    _ensureInitialized();
    try {
      if (kIsWeb) {
        // Web平台模拟实现
        return _webStorage[key] as String?;
      }
      return _mmkv.decodeString(key);
    } catch (e) {
      debugPrint('MMKV获取字符串失败: $e');
      return null;
    }
  }

  /// 存储布尔值
  Future<bool> setBool(String key, bool value) async {
    _ensureInitialized();
    try {
      if (kIsWeb) {
        // Web平台模拟实现
        _webStorage[key] = value;
        return true;
      }
      return _mmkv.encodeBool(key, value);
    } catch (e) {
      debugPrint('MMKV保存布尔值失败: $e');
      return false;
    }
  }

  /// 获取布尔值
  bool? getBool(String key) {
    _ensureInitialized();
    try {
      if (kIsWeb) {
        // Web平台模拟实现
        return _webStorage[key] as bool?;
      }
      return _mmkv.decodeBool(key);
    } catch (e) {
      debugPrint('MMKV获取布尔值失败: $e');
      return null;
    }
  }

  /// 存储整数值
  Future<bool> setInt(String key, int value) async {
    _ensureInitialized();
    try {
      if (kIsWeb) {
        // Web平台模拟实现
        _webStorage[key] = value;
        return true;
      }
      return _mmkv.encodeInt(key, value);
    } catch (e) {
      debugPrint('MMKV保存整数值失败: $e');
      return false;
    }
  }

  /// 获取整数值
  int? getInt(String key) {
    _ensureInitialized();
    try {
      if (kIsWeb) {
        // Web平台模拟实现
        return _webStorage[key] as int?;
      }
      return _mmkv.decodeInt(key);
    } catch (e) {
      debugPrint('MMKV获取整数值失败: $e');
      return null;
    }
  }

  /// 存储双精度浮点值
  Future<bool> setDouble(String key, double value) async {
    _ensureInitialized();
    try {
      if (kIsWeb) {
        // Web平台模拟实现
        _webStorage[key] = value;
        return true;
      }
      return _mmkv.encodeDouble(key, value);
    } catch (e) {
      debugPrint('MMKV保存浮点值失败: $e');
      return false;
    }
  }

  /// 获取双精度浮点值
  double? getDouble(String key) {
    _ensureInitialized();
    try {
      if (kIsWeb) {
        // Web平台模拟实现
        return _webStorage[key] as double?;
      }
      return _mmkv.decodeDouble(key);
    } catch (e) {
      debugPrint('MMKV获取浮点值失败: $e');
      return null;
    }
  }

  /// 存储字符串列表
  Future<bool> setStringList(String key, List<String> value) async {
    _ensureInitialized();
    try {
      if (kIsWeb) {
        // Web平台模拟实现
        _webStorage[key] = value;
        return true;
      }
      return _mmkv.encodeString(key, json.encode(value));
    } catch (e) {
      debugPrint('MMKV保存字符串列表失败: $e');
      return false;
    }
  }

  /// 获取字符串列表
  List<String>? getStringList(String key) {
    _ensureInitialized();
    try {
      if (kIsWeb) {
        // Web平台模拟实现
        final value = _webStorage[key];
        if (value is List) {
          return value.cast<String>();
        }
        return null;
      }

      final jsonStr = _mmkv.decodeString(key);
      if (jsonStr == null) return null;

      final decoded = json.decode(jsonStr);
      if (decoded is List) {
        return decoded.cast<String>();
      }
      return null;
    } catch (e) {
      debugPrint('MMKV获取字符串列表失败: $e');
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
      debugPrint('MMKV保存JSON对象失败: $e');
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
      debugPrint('MMKV获取JSON对象失败: $e');
      return null;
    }
  }

  /// 检查键是否存在
  bool containsKey(String key) {
    _ensureInitialized();
    try {
      if (kIsWeb) {
        // Web平台模拟实现
        return _webStorage.containsKey(key);
      }
      return _mmkv.containsKey(key);
    } catch (e) {
      debugPrint('MMKV检查键失败: $e');
      return false;
    }
  }

  /// 删除指定键的值
  Future<bool> remove(String key) async {
    _ensureInitialized();
    try {
      if (kIsWeb) {
        // Web平台模拟实现
        _webStorage.remove(key);
        return true;
      }
      _mmkv.removeValue(key);
      return true;
    } catch (e) {
      debugPrint('MMKV删除键失败: $e');
      return false;
    }
  }

  /// 清除所有存储的值
  Future<bool> clear() async {
    _ensureInitialized();
    try {
      if (kIsWeb) {
        // Web平台模拟实现
        _webStorage.clear();
        return true;
      }
      _mmkv.clearAll();
      return true;
    } catch (e) {
      debugPrint('MMKV清除所有数据失败: $e');
      return false;
    }
  }

  /// 获取所有键
  List<String> getAllKeys() {
    _ensureInitialized();
    try {
      if (kIsWeb) {
        // Web平台模拟实现
        return _webStorage.keys.cast<String>().toList();
      }
      return _mmkv.allKeys; // Remove unnecessary null-aware operator
    } catch (e) {
      debugPrint('MMKV获取所有键失败: $e');
      return [];
    }
  }

  // Web平台模拟存储
  static final Map<String, dynamic> _webStorage = {};
}
