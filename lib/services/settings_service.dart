import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/ai_settings.dart';
import '../models/app_settings.dart';
import '../models/multi_ai_settings.dart'; // 新增 MultiAISettings 导入
import '../models/local_ai_settings.dart'; // 新增 LocalAISettings 导入
import 'package:thoughtecho/utils/app_logger.dart';
import 'package:thoughtecho/services/api_key_manager.dart';
import '../utils/lww_utils.dart';

import '../services/mmkv_service.dart';
import 'excerpt_intent_service.dart';

part 'settings/settings_service_app.dart';
part 'settings/settings_service_migration.dart';

class SettingsService extends ChangeNotifier {
  static const ExcerptIntentService _excerptIntentService =
      ExcerptIntentService();
  static const String _aiSettingsKey = 'ai_settings';
  static const String _multiAiSettingsKey = 'multi_ai_settings'; // 新增
  static const String _localAiSettingsKey = 'local_ai_settings'; // 新增本地AI设置
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
  late LocalAISettings _localAISettings; // 新增本地AI设置

  // 迁移标志，只执行一次数据迁移
  static const String _migrationCompleteKey = 'mmkv_migration_complete';

  static const String _lastVersionKey = 'lastVersion';
  static const String _deviceIdKey = 'device_id_v1'; // 新增：设备唯一ID缓存键
  static const String _syncSkipConfirmKey = 'sync_skip_confirm';
  static const String _syncDefaultIncludeMediaKey =
      'sync_default_include_media';
  AISettings get aiSettings => _aiSettings;
  AppSettings get appSettings => _appSettings;
  ThemeMode get themeMode => _themeMode;
  MultiAISettings get multiAISettings => _multiAISettings; // 新增getter
  LocalAISettings get localAISettings => _localAISettings; // 新增本地AI设置getter
  bool get syncSkipConfirm => _mmkv.getBool(_syncSkipConfirmKey) ?? false;
  bool get syncDefaultIncludeMedia =>
      _mmkv.getBool(_syncDefaultIncludeMediaKey) ?? true;

  int get trashRetentionDays => _appSettings.trashRetentionDays;
  String? get trashRetentionLastModified =>
      _appSettings.trashRetentionLastModified;

  Future<void> setTrashRetentionDays(
    int days, {
    DateTime? modifiedAt,
  }) async {
    final normalizedDays = AppSettings.normalizeTrashRetentionDays(days);
    final modified = (modifiedAt ?? DateTime.now()).toUtc().toIso8601String();
    _appSettings = _appSettings.copyWith(
      trashRetentionDays: normalizedDays,
      trashRetentionLastModified: modified,
    );
    await _mmkv.setString(_appSettingsKey, json.encode(_appSettings.toJson()));
    notifyListeners();
  }

  Future<bool> applyIncomingTrashSettings(
    Map<String, dynamic>? incoming,
  ) async {
    if (incoming == null) {
      return false;
    }

    if (!incoming.containsKey('retention_days')) {
      return false;
    }

    final dynamic rawDays = incoming['retention_days'];
    int? parsedDays;
    if (rawDays is int) {
      parsedDays = rawDays;
    } else if (rawDays is num) {
      parsedDays = rawDays.toInt();
    } else if (rawDays is String) {
      parsedDays = int.tryParse(rawDays);
    }

    if (parsedDays == null) {
      return false;
    }

    final incomingDays = AppSettings.normalizeTrashRetentionDays(parsedDays);
    final incomingLastModified = incoming['last_modified']?.toString();
    String? normalizedIncomingTimestamp;
    if (incomingLastModified != null && incomingLastModified.isNotEmpty) {
      if (!LWWUtils.isValidTimestamp(incomingLastModified)) {
        logWarning(
          '忽略无效的回收站保留期时间戳: $incomingLastModified',
          source: 'SettingsService',
        );
        return false;
      }
      normalizedIncomingTimestamp =
          LWWUtils.normalizeTimestamp(incomingLastModified);
    } else {
      // 输入无时间戳：只有本地也无时间戳时才接受（直接赋值），否则跳过
      final localLastModified = _appSettings.trashRetentionLastModified;
      final hasLocalTimestamp =
          localLastModified != null && localLastModified.isNotEmpty;
      if (hasLocalTimestamp) {
        // 本地有时间戳，远端无时间戳 → 跳过导入
        return false;
      }
      // 本地也无时间戳 → 直接接受输入值，不设置时间戳
      _appSettings = _appSettings.copyWith(trashRetentionDays: incomingDays);
      await _mmkv.setString(
          _appSettingsKey, json.encode(_appSettings.toJson()));
      notifyListeners();
      return true;
    }

    final decision = LWWDecisionMaker.makeDecision(
      localTimestamp: _appSettings.trashRetentionLastModified,
      remoteTimestamp: normalizedIncomingTimestamp,
    );

    if (!decision.shouldUseRemote) {
      return false;
    }

    _appSettings = _appSettings.copyWith(
      trashRetentionDays: incomingDays,
      trashRetentionLastModified: normalizedIncomingTimestamp,
    );
    await _mmkv.setString(_appSettingsKey, json.encode(_appSettings.toJson()));
    notifyListeners();
    return true;
  }

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

  Future<void> setSyncSkipConfirm(bool value) async {
    await _mmkv.setBool(_syncSkipConfirmKey, value);
    notifyListeners();
  }

  Future<void> setSyncDefaultIncludeMedia(bool value) async {
    await _mmkv.setBool(_syncDefaultIncludeMediaKey, value);
    notifyListeners();
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
    await _loadLocalAISettings(); // 新增本地AI设置加载
    _loadAppSettings();
    _loadThemeMode();

    await _secureLegacyApiKey();
    await _syncExcerptIntentEntryPoint();

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

  Future<void> updateAISettings(AISettings settings) async {
    // Security: Ensure we don't persist API key in plaintext in legacy AISettings
    if (settings.apiKey.isNotEmpty) {
      _aiSettings = settings.copyWith(apiKey: '');
    } else {
      _aiSettings = settings;
    }
    await _mmkv.setString(_aiSettingsKey, json.encode(_aiSettings.toJson()));
    notifyListeners();
  }

  Future<void> updateThemeMode(ThemeMode mode) async {
    _themeMode = mode;
    await _mmkv.setString(_themeModeKey, mode.name);
    notifyListeners();
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

  /// 加载本地AI设置
  Future<void> _loadLocalAISettings() async {
    final String? localAiSettingsJson = _mmkv.getString(_localAiSettingsKey);

    if (localAiSettingsJson != null) {
      try {
        final Map<String, dynamic> settingsMap = json.decode(
          localAiSettingsJson,
        );
        _localAISettings = LocalAISettings.fromJson(settingsMap);
      } catch (e) {
        logDebug('加载本地AI设置失败: $e');
        _localAISettings = LocalAISettings.defaultSettings();
        await saveLocalAISettings(_localAISettings);
      }
    } else {
      _localAISettings = LocalAISettings.defaultSettings();
      await saveLocalAISettings(_localAISettings);
    }
  }

  /// 保存本地AI设置
  Future<void> saveLocalAISettings(LocalAISettings settings) async {
    _localAISettings = settings;
    await _mmkv.setString(_localAiSettingsKey, json.encode(settings.toJson()));
    notifyListeners();
  }

  /// 更新本地AI设置
  Future<void> updateLocalAISettings(LocalAISettings settings) async {
    await saveLocalAISettings(settings);
  }
}
