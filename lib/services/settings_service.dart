import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/ai_settings.dart';

class SettingsService extends ChangeNotifier {
  static const String _aiSettingsKey = 'ai_settings';
  static const String _themeModeKey = 'theme_mode'; // 新增 themeMode key
  final SharedPreferences _prefs;
  late AISettings _aiSettings;
  late ThemeMode _themeMode; // 新增 _themeMode field

  AISettings get aiSettings => _aiSettings;
  ThemeMode get themeMode => _themeMode; // 新增 themeMode getter

  SettingsService(this._prefs) {
    _loadSettings();
  }

  void _loadSettings() {
    final String? settingsJson = _prefs.getString(_aiSettingsKey);
    if (settingsJson != null) {
      _aiSettings = AISettings.fromJson(json.decode(settingsJson));
    } else {
      _aiSettings = AISettings.defaultSettings();
    }

    // 加载主题模式
    final String? themeModeString = _prefs.getString(_themeModeKey);
    if (themeModeString != null) {
      _themeMode = ThemeMode.values.byName(themeModeString);
    } else {
      _themeMode = ThemeMode.system; // 默认 ThemeMode.system
    }
    notifyListeners();
  }

  static Future<SettingsService> create() async {
    final prefs = await SharedPreferences.getInstance();
    return SettingsService(prefs);
  }

  Future<void> updateAISettings(AISettings settings) async {
    _aiSettings = settings;
    await _prefs.setString(_aiSettingsKey, json.encode(settings.toJson()));
    notifyListeners();
  }

  Future<void> updateThemeMode(ThemeMode mode) async { // 新增 updateThemeMode 方法
    _themeMode = mode;
    await _prefs.setString(_themeModeKey, mode.name);
    notifyListeners();
  }
}