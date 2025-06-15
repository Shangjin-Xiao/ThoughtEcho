import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/ai_settings.dart';
import '../models/app_settings.dart';
import '../models/multi_ai_settings.dart'; // 新增 MultiAISettings 导入
import 'package:thoughtecho/utils/app_logger.dart';

import '../services/mmkv_service.dart';

class SettingsService extends ChangeNotifier {
  static const String _aiSettingsKey = 'ai_settings';
  static const String _multiAiSettingsKey = 'multi_ai_settings'; // 新增
  static const String _appSettingsKey = 'app_settings';
  static const String _themeModeKey = 'theme_mode';
  // 旧Key，用于迁移检查，迁移完成后可以考虑移除
  static const String _databaseMigrationCompleteKey =
      'database_migration_complete';
  // 新Key，表示初始数据库设置（包括首次创建或升级）是否已在引导流程中完成
  static const String _initialDatabaseSetupCompleteKey =
      'initial_database_setup_complete';
  // 使用应用安装标记替代版本号
  static const String _appInstalledKey = 'app_installed_v2';
  static const String _appUpgradedKey = 'app_upgraded_v2';
  final SharedPreferences _prefs; // 保留以支持数据迁移
  final MMKVService _mmkv = MMKVService(); // 使用MMKV作为主要存储
  late AISettings _aiSettings;
  late AppSettings _appSettings;
  late ThemeMode _themeMode;
  late MultiAISettings _multiAISettings; // 新增多provider设置

  // 迁移标志，只执行一次数据迁移
  static const String _migrationCompleteKey = 'mmkv_migration_complete';

  static const String _lastVersionKey = 'lastVersion';
  AISettings get aiSettings => _aiSettings;
  AppSettings get appSettings => _appSettings;
  ThemeMode get themeMode => _themeMode;
  MultiAISettings get multiAISettings => _multiAISettings; // 新增getter

  SettingsService(this._prefs);

  /// 创建SettingsService实例的静态工厂方法
  static Future<SettingsService> create() async {
    // 获取SharedPreferences实例
    final prefs = await SharedPreferences.getInstance();
    // 创建SettingsService实例
    final service = SettingsService(prefs);
    // 初始化 MMKVService
    await service._mmkv.init();
    // 加载设置
    await service._loadSettings();
    // 返回初始化完成的实例
    return service;
  }

  Future<void> _loadSettings() async {
    // 检查是否需要迁移数据
    await _migrateDataIfNeeded();

    // 检查应用是否是首次安装或升级
    final bool wasInstalledBefore = _mmkv.getBool(_appInstalledKey) ?? false;

    // 如果是首次安装，标记为已安装
    if (!wasInstalledBefore) {
      logDebug('检测到首次安装，将重置引导页面状态');
      await _mmkv.setBool(_appInstalledKey, true);

      // 首次安装时，载入应用默认设置
      _loadAppSettings();
      _appSettings = _appSettings.copyWith(hasCompletedOnboarding: false);
      await _mmkv.setString(
        _appSettingsKey,
        json.encode(_appSettings.toJson()),
      );
    } else {
      // 检查是否有升级标记
      final hasUpgradeTag = _mmkv.getBool(_appUpgradedKey) ?? false;

      // 如果设置了升级标记，刷新引导状态
      if (hasUpgradeTag) {
        logDebug('检测到应用升级标记，将重置引导页面状态');

        // 重置升级标记
        await _mmkv.setBool(_appUpgradedKey, false);

        // 重置引导状态，但保留其他设置
        _loadAppSettings();
        _appSettings = _appSettings.copyWith(hasCompletedOnboarding: false);
        await _mmkv.setString(
          _appSettingsKey,
          json.encode(_appSettings.toJson()),
        );
      }
    }
    // 继续加载其他设置
    await _loadAISettings();
    await _loadMultiAISettings(); // 新增
    _loadAppSettings();
    _loadThemeMode();

    notifyListeners();
  }

  // 加载AI设置（简化版，主要用于向后兼容）
  Future<void> _loadAISettings() async {
    final String? aiSettingsJson =
        _mmkv.getString(_aiSettingsKey) ?? _prefs.getString(_aiSettingsKey);

    if (aiSettingsJson != null) {
      final Map<String, dynamic> settingsMap = json.decode(aiSettingsJson);
      _aiSettings = AISettings.fromJson(settingsMap);
    } else {
      _aiSettings = AISettings.defaultSettings();
      await _mmkv.setString(_aiSettingsKey, json.encode(_aiSettings.toJson()));
    }
  }

  // 加载应用设置
  void _loadAppSettings() {
    final String? appSettingsJson =
        _mmkv.getString(_appSettingsKey) ?? _prefs.getString(_appSettingsKey);

    if (appSettingsJson != null) {
      _appSettings = AppSettings.fromJson(json.decode(appSettingsJson));

      // 确保一言类型不为空，如果为空则设置为默认全选
      if (_appSettings.hitokotoType.isEmpty) {
        _appSettings = AppSettings.defaultSettings();
        _mmkv.setString(_appSettingsKey, json.encode(_appSettings.toJson()));
        logDebug('检测到一言类型为空，已重置为默认全选值');
      }
    } else {
      _appSettings = AppSettings.defaultSettings();
      // 首次启动时保存默认设置到存储
      _mmkv.setString(_appSettingsKey, json.encode(_appSettings.toJson()));
      logDebug('首次启动，已初始化默认一言类型设置: ${_appSettings.hitokotoType}');
    }
  }

  // 加载主题模式
  void _loadThemeMode() {
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
  }

  // 将数据从SharedPreferences迁移到MMKV (只在首次升级后执行一次)
  Future<void> _migrateDataIfNeeded() async {
    // 检查是否已经完成迁移
    if (_mmkv.getBool(_migrationCompleteKey) == true) {
      logDebug('数据迁移已完成，不再重复执行');
      return;
    }

    logDebug('开始从SharedPreferences迁移数据到MMKV...');

    try {
      // 迁移AI设置
      final aiSettings = _prefs.getString(_aiSettingsKey);
      if (aiSettings != null) {
        await _mmkv.setString(_aiSettingsKey, aiSettings);
        logDebug('AI设置已迁移到MMKV');
      }

      // 迁移应用设置
      final appSettings = _prefs.getString(_appSettingsKey);
      if (appSettings != null) {
        await _mmkv.setString(_appSettingsKey, appSettings);
        logDebug('应用设置已迁移到MMKV');
      }

      // 迁移主题设置
      final themeMode = _prefs.getString(_themeModeKey);
      if (themeMode != null) {
        await _mmkv.setString(_themeModeKey, themeMode);
        logDebug('主题设置已迁移到MMKV');
      }

      // 检查旧的数据库迁移Key，如果存在且为true，则设置新的Key，但保留旧Key以保持兼容性
      if (_mmkv.containsKey(_databaseMigrationCompleteKey)) {
        final oldMigrationComplete =
            _mmkv.getBool(_databaseMigrationCompleteKey) ?? false;
        if (oldMigrationComplete) {
          await _mmkv.setBool(_initialDatabaseSetupCompleteKey, true);
          logDebug('已将旧的数据库迁移完成标记同步到新的初始设置完成标记');
        }
        // 注意：保留旧Key以保持兼容性，不移除
      }

      // 标记迁移完成
      await _mmkv.setBool(_migrationCompleteKey, true);
      logDebug('所有设置数据已成功迁移到MMKV');
    } catch (e) {
      logDebug('迁移数据失败: $e');
      // 失败不阻塞应用运行，下次启动会重试
    }
  }

  Future<void> updateAISettings(AISettings settings) async {
    _aiSettings = settings;
    await _mmkv.setString(_aiSettingsKey, json.encode(settings.toJson()));
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

  // 设置应用升级标记，用于触发显示引导页
  Future<void> setAppUpgraded() async {
    await _mmkv.setBool(_appUpgradedKey, true);
  }

  /// 设置初始数据库设置（创建/升级）已完成
  Future<void> setInitialDatabaseSetupComplete(bool isComplete) async {
    await _mmkv.setBool(_initialDatabaseSetupCompleteKey, isComplete);
    logDebug('初始数据库设置完成状态设置为: $isComplete');
    // notifyListeners(); // 根据需要决定是否通知监听器
  }

  /// 检查初始数据库设置（创建/升级）是否已完成
  bool isInitialDatabaseSetupComplete() {
    // 默认返回 false，确保只有显式设置后才为 true
    return _mmkv.getBool(_initialDatabaseSetupCompleteKey) ?? false;
  }

  // 设置数据库迁移是否完成
  Future<void> setDatabaseMigrationComplete(bool isComplete) async {
    await _mmkv.setBool(_databaseMigrationCompleteKey, isComplete);
  }

  // 检查数据库迁移是否已完成
  bool isDatabaseMigrationComplete() {
    return _mmkv.getBool(_databaseMigrationCompleteKey) ?? false;
  }

  // 通过检查应用设置中的引导完成标志判断用户是否完成了引导
  bool hasCompletedOnboarding() {
    return _appSettings.hasCompletedOnboarding;
  }

  // 设置用户是否完成了引导流程
  Future<void> setHasCompletedOnboarding(bool completed) async {
    _appSettings = _appSettings.copyWith(hasCompletedOnboarding: completed);
    await _mmkv.setString(_appSettingsKey, json.encode(_appSettings.toJson()));
    notifyListeners();
  }

  /// 获取上次记录的版本号
  String? getAppVersion() {
    return _mmkv.getString(_lastVersionKey);
  }

  /// 设置当前版本号
  Future<void> setAppVersion(String version) async {
    await _mmkv.setString(_lastVersionKey, version);
  }

  // 加载多provider AI设置
  Future<void> _loadMultiAISettings() async {
    final String? multiAiSettingsJson = _mmkv.getString(_multiAiSettingsKey);

    if (multiAiSettingsJson != null) {
      try {
        final Map<String, dynamic> settingsMap = json.decode(
          multiAiSettingsJson,
        );
        _multiAISettings = MultiAISettings.fromJson(settingsMap);
      } catch (e) {
        logDebug('加载多provider设置失败: $e');
        _multiAISettings = MultiAISettings.defaultSettings();
        await saveMultiAISettings(_multiAISettings);
      }
    } else {
      _multiAISettings = MultiAISettings.defaultSettings();
      await saveMultiAISettings(_multiAISettings);
    }
  }

  /// 保存多provider AI设置
  Future<void> saveMultiAISettings(MultiAISettings settings) async {
    _multiAISettings = settings;

    // 保存到MMKV存储
    await _mmkv.setString(_multiAiSettingsKey, json.encode(settings.toJson()));

    notifyListeners();
  }

  /// 更新多provider AI设置
  Future<void> updateMultiAISettings(MultiAISettings settings) async {
    await saveMultiAISettings(settings);
  }
}
