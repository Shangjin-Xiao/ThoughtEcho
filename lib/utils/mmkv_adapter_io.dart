import 'package:mmkv/mmkv.dart';
import 'dart:convert';
import 'mmkv_ffi_fix.dart'; // 引入 StorageAdapter 和 SharedPrefsAdapter

/// MMKV 存储适配器 - 仅在移动端使用
class MMKVAdapter implements StorageAdapter {
  MMKV? _mmkv;
  bool _initialized = false;
  static bool _mmkvGlobalInitialized = false;

  @override
  Future<void> initialize() async {
    if (_initialized) return; // 防止重复初始化

    // 确保 MMKV 全局只初始化一次
    if (!_mmkvGlobalInitialized) {
      await MMKV.initialize();
      _mmkvGlobalInitialized = true;
    }

    _mmkv = MMKV.defaultMMKV();
    _initialized = true;
  }

  MMKV get mmkv {
    if (_mmkv == null) {
      throw StateError('MMKVAdapter 尚未初始化');
    }
    return _mmkv!;
  }

  @override
  Future<bool> setString(String key, String value) async =>
      Future.value(mmkv.encodeString(key, value));

  @override
  String? getString(String key) => mmkv.decodeString(key);

  @override
  Future<bool> setInt(String key, int value) async =>
      Future.value(mmkv.encodeInt(key, value));

  @override
  int? getInt(String key) => mmkv.decodeInt(key);

  @override
  Future<bool> setDouble(String key, double value) async =>
      Future.value(mmkv.encodeDouble(key, value));

  @override
  double? getDouble(String key) => mmkv.decodeDouble(key);

  @override
  Future<bool> setBool(String key, bool value) async =>
      Future.value(mmkv.encodeBool(key, value));

  @override
  bool? getBool(String key) => mmkv.decodeBool(key);

  @override
  Future<bool> setStringList(String key, List<String> value) async =>
      setString(key, json.encode(value));

  @override
  List<String>? getStringList(String key) {
    final s = getString(key);
    return s == null ? null : List<String>.from(json.decode(s));
  }

  @override
  bool containsKey(String key) => mmkv.containsKey(key);

  @override
  Future<bool> remove(String key) async {
    mmkv.removeValue(key);
    return true;
  }

  @override
  Future<bool> clear() async {
    mmkv.removeValues(mmkv.allKeys);
    return true;
  }

  @override
  Set<String> getKeys() => mmkv.allKeys.toSet();
}
