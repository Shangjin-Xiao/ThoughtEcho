import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/ai_settings.dart';
import '../models/app_settings.dart';
import '../services/secure_storage_service.dart';

class SettingsService extends ChangeNotifier {
  static const String _aiSettingsKey = 'ai_settings';
  static const String _appSettingsKey = 'app_settings';
  static const String _themeModeKey = 'theme_mode';
  final SharedPreferences _prefs;
  late AISettings _aiSettings;
  late AppSettings _appSettings;
  late ThemeMode _themeMode;
  final SecureStorageService _secureStorage = SecureStorageService();

  AISettings get aiSettings => _aiSettings;
  AppSettings get appSettings => _appSettings;
  ThemeMode get themeMode => _themeMode;

  SettingsService(this._prefs) {
    _loadSettings();
  }

  void _loadSettings() async {
    final String? aiSettingsJson = _prefs.getString(_aiSettingsKey);
    if (aiSettingsJson != null) {
      // 从JSON加载设置，但API密钥将从安全存储中加载
      final Map<String, dynamic> settingsMap = json.decode(aiSettingsJson);
      
      // 尝试从安全存储加载API密钥
      final secureApiKey = await _secureStorage.getApiKey();
      
      // 如果安全存储中有密钥，使用它，否则使用常规设置中的密钥（兼容旧版本）
      if (secureApiKey != null && secureApiKey.isNotEmpty) {
        settingsMap['apiKey'] = secureApiKey;
        
        // 清除普通存储中的API密钥（迁移到安全存储）
        if (settingsMap['apiKey'].isNotEmpty) {
          _migrateApiKeyToSecureStorage(settingsMap['apiKey']);
          settingsMap['apiKey'] = '';
          await _prefs.setString(_aiSettingsKey, json.encode(settingsMap));
        }
      }
      
      _aiSettings = AISettings.fromJson(settingsMap);
    } else {
      _aiSettings = AISettings.defaultSettings();
    }

    final String? appSettingsJson = _prefs.getString(_appSettingsKey);
    if (appSettingsJson != null) {
      _appSettings = AppSettings.fromJson(json.decode(appSettingsJson));
      
      // 确保一言类型不为空，如果为空则设置为默认全选
      if (_appSettings.hitokotoType.isEmpty) {
        _appSettings = AppSettings.defaultSettings();
        await _prefs.setString(_appSettingsKey, json.encode(_appSettings.toJson()));
        debugPrint('检测到一言类型为空，已重置为默认全选值');
      }
    } else {
      _appSettings = AppSettings.defaultSettings();
      // 首次启动时保存默认设置到存储
      await _prefs.setString(_appSettingsKey, json.encode(_appSettings.toJson()));
      debugPrint('首次启动，已初始化默认一言类型设置: ${_appSettings.hitokotoType}');
    }

    // 加载主题模式
    dynamic themeModeValue = _prefs.get(_themeModeKey);
    String? themeModeString = themeModeValue?.toString();
    if (themeModeString != null && themeModeString.isNotEmpty) {
      try {
        _themeMode = ThemeMode.values.byName(themeModeString);
      } catch (e) {
        _themeMode = ThemeMode.system; // 默认回退到系统主题
      }
    } else {
      _themeMode = ThemeMode.system; // 默认 ThemeMode.system
    }
    notifyListeners();
  }

  // 将API密钥从普通存储迁移到安全存储
  Future<void> _migrateApiKeyToSecureStorage(String apiKey) async {
    await _secureStorage.saveApiKey(apiKey);
  }

  static Future<SettingsService> create() async {
    final prefs = await SharedPreferences.getInstance();
    return SettingsService(prefs);
  }

  Future<void> updateAISettings(AISettings settings) async {
    // 保存API密钥到安全存储
    if (settings.apiKey.isNotEmpty) {
      await _secureStorage.saveApiKey(settings.apiKey);
    }
    
    // 创建不包含API密钥的设置副本
    final settingsWithoutApiKey = settings.copyWith(apiKey: '');
    
    // 保存不含API密钥的设置到普通存储
    await _prefs.setString(_aiSettingsKey, json.encode(settingsWithoutApiKey.toJson()));
    
    // 更新内存中的设置（保留完整API密钥）
    _aiSettings = settings;
    
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

  Future<void> updateThemeMode(ThemeMode mode) async {
    _themeMode = mode;
    await _prefs.setString(_themeModeKey, mode.name);
    notifyListeners();
  }
}