import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/ai_settings.dart';
import '../models/app_settings.dart';
import '../services/secure_storage_service.dart';
import '../services/mmkv_service.dart';

class SettingsService extends ChangeNotifier {
  static const String _aiSettingsKey = 'ai_settings';
  static const String _appSettingsKey = 'app_settings';
  static const String _themeModeKey = 'theme_mode';
  final SharedPreferences _prefs; // 保留以支持数据迁移
  final MMKVService _mmkv = MMKVService(); // 使用MMKV作为主要存储
  late AISettings _aiSettings;
  late AppSettings _appSettings;
  late ThemeMode _themeMode;
  final SecureStorageService _secureStorage = SecureStorageService();

  // 迁移标志，只执行一次数据迁移
  static const String _migrationCompleteKey = 'mmkv_migration_complete';

  AISettings get aiSettings => _aiSettings;
  AppSettings get appSettings => _appSettings;
  ThemeMode get themeMode => _themeMode;

  SettingsService(this._prefs);

  Future<void> _loadSettings() async {
    // 检查是否需要迁移数据
    await _migrateDataIfNeeded();

    // 优先从MMKV加载数据
    final String? aiSettingsJson =
        _mmkv.getString(_aiSettingsKey) ?? _prefs.getString(_aiSettingsKey);

    if (aiSettingsJson != null) {
      // 从JSON加载设置，但API密钥将从安全存储中加载
      final Map<String, dynamic> settingsMap = json.decode(aiSettingsJson);

      // 尝试从安全存储加载API密钥
      final secureApiKey = await _secureStorage.getApiKey();

      // 如果安全存储中有密钥，使用它，否则使用常规设置中的密钥（兼容旧版本）
      if (secureApiKey != null && secureApiKey.isNotEmpty) {
        settingsMap['apiKey'] = secureApiKey;

        // 清除普通存储中的API密钥（迁移到安全存储）
        if (settingsMap.containsKey('apiKey') &&
            settingsMap['apiKey'].isNotEmpty) {
          _migrateApiKeyToSecureStorage(settingsMap['apiKey']);
          settingsMap['apiKey'] = '';
          await _mmkv.setString(_aiSettingsKey, json.encode(settingsMap));
        }
      }

      _aiSettings = AISettings.fromJson(settingsMap);
    } else {
      _aiSettings = AISettings.defaultSettings();
      // 保存默认设置
      await _mmkv.setString(
        _aiSettingsKey,
        json.encode(_aiSettings.copyWith(apiKey: '').toJson()),
      );
    }

    final String? appSettingsJson =
        _mmkv.getString(_appSettingsKey) ?? _prefs.getString(_appSettingsKey);

    if (appSettingsJson != null) {
      _appSettings = AppSettings.fromJson(json.decode(appSettingsJson));

      // 确保一言类型不为空，如果为空则设置为默认全选
      if (_appSettings.hitokotoType.isEmpty) {
        _appSettings = AppSettings.defaultSettings();
        await _mmkv.setString(
          _appSettingsKey,
          json.encode(_appSettings.toJson()),
        );
        debugPrint('检测到一言类型为空，已重置为默认全选值');
      }
    } else {
      _appSettings = AppSettings.defaultSettings();
      // 首次启动时保存默认设置到存储
      await _mmkv.setString(
        _appSettingsKey,
        json.encode(_appSettings.toJson()),
      );
      debugPrint('首次启动，已初始化默认一言类型设置: ${_appSettings.hitokotoType}');
    }

    // 加载主题模式 - 优先从MMKV读取
    String? themeModeString = _mmkv.getString(_themeModeKey);

    // 如果MMKV中没有，则从SharedPreferences加载
    if (themeModeString == null || themeModeString.isEmpty) {
      dynamic themeModeValue = _prefs.get(_themeModeKey);
      themeModeString = themeModeValue?.toString();
    }

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

  // 将数据从SharedPreferences迁移到MMKV (只在首次升级后执行一次)
  Future<void> _migrateDataIfNeeded() async {
    // 检查是否已经完成迁移
    if (_mmkv.getBool(_migrationCompleteKey) == true) {
      debugPrint('数据迁移已完成，不再重复执行');
      return;
    }

    debugPrint('开始从SharedPreferences迁移数据到MMKV...');

    try {
      // 迁移AI设置
      final aiSettings = _prefs.getString(_aiSettingsKey);
      if (aiSettings != null) {
        await _mmkv.setString(_aiSettingsKey, aiSettings);
        debugPrint('AI设置已迁移到MMKV');
      }

      // 迁移应用设置
      final appSettings = _prefs.getString(_appSettingsKey);
      if (appSettings != null) {
        await _mmkv.setString(_appSettingsKey, appSettings);
        debugPrint('应用设置已迁移到MMKV');
      }

      // 迁移主题设置
      final themeMode = _prefs.getString(_themeModeKey);
      if (themeMode != null) {
        await _mmkv.setString(_themeModeKey, themeMode);
        debugPrint('主题设置已迁移到MMKV');
      }

      // 标记迁移完成
      await _mmkv.setBool(_migrationCompleteKey, true);
      debugPrint('所有设置数据已成功迁移到MMKV');
    } catch (e) {
      debugPrint('迁移数据失败: $e');
      // 失败不阻塞应用运行，下次启动会重试
    }
  }

  // 将API密钥从普通存储迁移到安全存储
  Future<void> _migrateApiKeyToSecureStorage(String apiKey) async {
    await _secureStorage.saveApiKey(apiKey);
  }

  static Future<SettingsService> create() async {
    // 保留SharedPreferences实例以便数据迁移
    final prefs = await SharedPreferences.getInstance();
    final service = SettingsService(prefs);
    // 初始化 MMKVService
    await service._mmkv.init();
    // 加载设置数据
    await service._loadSettings();
    return service;
  }

  Future<void> updateAISettings(AISettings settings) async {
    // 保存API密钥到安全存储
    if (settings.apiKey.isNotEmpty) {
      await _secureStorage.saveApiKey(settings.apiKey);
    }

    // 创建不包含API密钥的设置副本
    final settingsWithoutApiKey = settings.copyWith(apiKey: '');

    // 保存不含API密钥的设置到MMKV存储
    await _mmkv.setString(
      _aiSettingsKey,
      json.encode(settingsWithoutApiKey.toJson()),
    );

    // 更新内存中的设置（保留完整API密钥）
    _aiSettings = settings;

    notifyListeners();
  }

  Future<void> updateAppSettings(AppSettings settings) async {
    _appSettings = settings;
    await _mmkv.setString(_appSettingsKey, json.encode(settings.toJson()));
    notifyListeners();
  }

  Future<void> updateHitokotoType(String type) async {
    _appSettings = _appSettings.copyWith(hitokotoType: type);
    await _mmkv.setString(_appSettingsKey, json.encode(_appSettings.toJson()));
    notifyListeners();
  }

  Future<void> updateThemeMode(ThemeMode mode) async {
    _themeMode = mode;
    await _mmkv.setString(_themeModeKey, mode.name);
    notifyListeners();
  }
}
