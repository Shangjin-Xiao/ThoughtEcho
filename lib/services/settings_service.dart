import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/ai_settings.dart';
import '../models/app_settings.dart';

class SettingsService extends ChangeNotifier {
  static const String _aiSettingsKey = 'ai_settings';
  static const String _appSettingsKey = 'app_settings';
  static const String _themeModeKey = 'theme_mode';
  final SharedPreferences _prefs;
  late AISettings _aiSettings;
  late AppSettings _appSettings;
  late ThemeMode _themeMode;

  AISettings get aiSettings => _aiSettings;
  AppSettings get appSettings => _appSettings;
  ThemeMode get themeMode => _themeMode;

  SettingsService(this._prefs) {
    _loadSettings();
  }

  void _loadSettings() {
    final String? aiSettingsJson = _prefs.getString(_aiSettingsKey);
    if (aiSettingsJson != null) {
      _aiSettings = AISettings.fromJson(json.decode(aiSettingsJson));
    } else {
      _aiSettings = AISettings.defaultSettings();
    }

    final String? appSettingsJson = _prefs.getString(_appSettingsKey);
    if (appSettingsJson != null) {
      _appSettings = AppSettings.fromJson(json.decode(appSettingsJson));
    } else {
      _appSettings = AppSettings.defaultSettings();
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

  Future<void> updateAppSettings(AppSettings settings) async {
    _appSettings = settings;
    await _prefs.setString(_appSettingsKey, json.encode(settings.toJson()));
    notifyListeners();
  }

  Future<void> updateHitokotoType(String type) async {
    _appSettings = _appSettings.copyWith(hitokotoType: type);
    await _prefs.setString(_appSettingsKey, json.encode(_appSettings.toJson()));
    notifyListeners();
  }

  Future<void> updateThemeMode(ThemeMode mode) async { // 新增 updateThemeMode 方法
    _themeMode = mode;
    await _prefs.setString(_themeModeKey, mode.name);
    notifyListeners();
  }
}