import 'mmkv_ffi_fix.dart';

/// MMKVAdapter - Web 平台使用 SharedPreferences 作为后端存储
class MMKVAdapter implements StorageAdapter {
  late final SharedPrefsAdapter _prefs;

  @override
  Future<void> initialize() async {
    _prefs = SharedPrefsAdapter();
    await _prefs.initialize();
  }

  @override Future<bool> setString(String key, String value) => _prefs.setString(key, value);
  @override String? getString(String key) => _prefs.getString(key);

  @override Future<bool> setInt(String key, int value) => _prefs.setInt(key, value);
  @override int? getInt(String key) => _prefs.getInt(key);

  @override Future<bool> setDouble(String key, double value) => _prefs.setDouble(key, value);
  @override double? getDouble(String key) => _prefs.getDouble(key);

  @override Future<bool> setBool(String key, bool value) => _prefs.setBool(key, value);
  @override bool? getBool(String key) => _prefs.getBool(key);

  @override Future<bool> setStringList(String key, List<String> value) => _prefs.setStringList(key, value);
  @override List<String>? getStringList(String key) => _prefs.getStringList(key);

  @override bool containsKey(String key) => _prefs.containsKey(key);

  @override Future<bool> remove(String key) => _prefs.remove(key);

  @override Future<bool> clear() => _prefs.clear();

  @override Set<String> getKeys() => _prefs.getKeys();
}