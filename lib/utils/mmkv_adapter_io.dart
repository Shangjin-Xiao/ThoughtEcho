import 'package:mmkv/mmkv.dart';
import 'dart:convert';
import 'mmkv_ffi_fix.dart'; // 引入 StorageAdapter 和 SharedPrefsAdapter

/// MMKV 存储适配器 - 仅在移动端使用
class MMKVAdapter implements StorageAdapter {
  late final MMKV _mmkv;

  @override
  Future<void> initialize() async {
    await MMKV.initialize();
    _mmkv = MMKV.defaultMMKV();
  }

  @override
  Future<bool> setString(String key, String value) async => Future.value(_mmkv.encodeString(key, value));

  @override
  String? getString(String key) => _mmkv.decodeString(key);

  @override
  Future<bool> setInt(String key, int value) async => Future.value(_mmkv.encodeInt(key, value));

  @override
  int? getInt(String key) => _mmkv.decodeInt(key);

  @override
  Future<bool> setDouble(String key, double value) async => Future.value(_mmkv.encodeDouble(key, value));

  @override
  double? getDouble(String key) => _mmkv.decodeDouble(key);

  @override
  Future<bool> setBool(String key, bool value) async => Future.value(_mmkv.encodeBool(key, value));

  @override
  bool? getBool(String key) => _mmkv.decodeBool(key);

  @override
  Future<bool> setStringList(String key, List<String> value) async => setString(key, json.encode(value));

  @override
  List<String>? getStringList(String key) {
    final s = getString(key);
    return s == null ? null : List<String>.from(json.decode(s));
  }

  @override
  bool containsKey(String key) => _mmkv.containsKey(key);

  @override
  Future<bool> remove(String key) async {
    _mmkv.removeValue(key);
    return true;
  }

  @override
  Future<bool> clear() async {
    _mmkv.removeValues(_mmkv.allKeys);
    return true;
  }

  @override
  Set<String> getKeys() => _mmkv.allKeys.toSet();
}