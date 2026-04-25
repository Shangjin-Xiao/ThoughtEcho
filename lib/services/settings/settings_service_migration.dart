part of '../settings_service.dart';

extension _SettingsServiceMigrationExtension on SettingsService {
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

  /// 迁移遗留的明文API密钥到安全存储
  Future<void> _secureLegacyApiKey() async {
    if (_aiSettings.apiKey.isEmpty) return;

    bool shouldClear = false;

    // 如果我们有当前选中的服务商
    if (_multiAISettings.currentProviderId != null) {
      final apiKeyManager = APIKeyManager();
      final providerId = _multiAISettings.currentProviderId!;

      try {
        // 检查安全存储中是否已有密钥
        final hasSecureKey = await apiKeyManager.hasValidProviderApiKey(
          providerId,
        );

        if (hasSecureKey) {
          // 安全存储中已有密钥，遗留的明文密钥是冗余的，可以直接清除
          shouldClear = true;
          logDebug(
              'Found redundant plaintext API key in AISettings. Clearing.');
        } else {
          // 安全存储中没有密钥，尝试迁移
          await apiKeyManager.saveProviderApiKey(
            providerId,
            _aiSettings.apiKey,
          );
          shouldClear = true;
          logDebug(
            'Migrated legacy plaintext API key to SecureStorage for provider: $providerId',
          );
        }
      } catch (e) {
        logDebug('Error securing legacy API key: $e');
        // 出错时不清除，避免数据丢失
      }
    } else {
      // 如果没有选中的服务商，暂时不清除，因为无法确定归属
      // 但这种情况很少见，因为通常会有默认或已配置的服务商
      logDebug(
        'Legacy API key found but no current provider selected. Skipping migration.',
      );
    }

    if (shouldClear) {
      _aiSettings = _aiSettings.copyWith(apiKey: '');
      await _mmkv.setString(_aiSettingsKey, json.encode(_aiSettings.toJson()));
      logDebug('Legacy plaintext API key cleared from AISettings.');
    }
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

  /// 获取上次记录的版本号
  String? getAppVersion() {
    return _mmkv.getString(_lastVersionKey);
  }

  /// 设置当前版本号
  Future<void> setAppVersion(String version) async {
    await _mmkv.setString(_lastVersionKey, version);
  }

  /// 获取或生成设备唯一ID（持久化）
  String getOrCreateDeviceId() {
    final existing = _mmkv.getString(_deviceIdKey);
    if (existing != null && existing.isNotEmpty) return existing;
    final newId =
        '${DateTime.now().millisecondsSinceEpoch}_${UniqueKey().hashCode.toRadixString(16)}';
    _mmkv.setString(_deviceIdKey, newId);
    return newId;
  }

  /// 获取自定义字符串设置
  Future<String?> getCustomString(String key) async {
    await _mmkv.init();
    return _mmkv.getString(key);
  }

  /// 设置自定义字符串设置
  Future<void> setCustomString(String key, String value) async {
    await _mmkv.init();
    await _mmkv.setString(key, value);
  }

  /// 获取所有设置数据用于备份
  Map<String, dynamic> getAllSettingsForBackup() {
    return {
      'ai_settings': _aiSettings.toJson(),
      'multi_ai_settings': _multiAISettings.toJson(),
      'local_ai_settings': _localAISettings.toJson(),
      'app_settings': _appSettings.toJson(),
      'theme_mode': _themeMode.index,
      'device_id': getOrCreateDeviceId(),
    };
  }

  /// 从备份数据恢复所有设置
  Future<void> restoreAllSettingsFromBackup(
    Map<String, dynamic> backupData,
  ) async {
    try {
      // 恢复AI设置
      if (backupData.containsKey('ai_settings')) {
        final aiSettingsJson =
            backupData['ai_settings'] as Map<String, dynamic>;
        final aiSettings = AISettings.fromJson(aiSettingsJson);
        await updateAISettings(aiSettings);
      }

      // 恢复多provider AI设置
      if (backupData.containsKey('multi_ai_settings')) {
        final multiAiSettingsJson =
            backupData['multi_ai_settings'] as Map<String, dynamic>;
        final multiAiSettings = MultiAISettings.fromJson(multiAiSettingsJson);
        await saveMultiAISettings(multiAiSettings);
      }

      // 恢复本地AI设置
      if (backupData.containsKey('local_ai_settings')) {
        final localAiSettingsJson =
            backupData['local_ai_settings'] as Map<String, dynamic>;
        final localAiSettings = LocalAISettings.fromJson(localAiSettingsJson);
        await saveLocalAISettings(localAiSettings);
      }

      // 恢复应用设置
      if (backupData.containsKey('app_settings')) {
        final appSettingsJson =
            backupData['app_settings'] as Map<String, dynamic>;
        final appSettings = AppSettings.fromJson(appSettingsJson);
        await updateAppSettings(appSettings);
      }

      // 恢复主题模式
      if (backupData.containsKey('theme_mode')) {
        final themeModeIndex = backupData['theme_mode'] as int;
        final themeMode = ThemeMode.values[themeModeIndex];
        await updateThemeMode(themeMode);
      }

      // 恢复/记录 device_id（不覆盖本地已有，仅在本地不存在时写入，保持源ID可用于审计）
      if (backupData.containsKey('device_id')) {
        final remoteId = backupData['device_id'];
        if ((_mmkv.getString(_deviceIdKey) ?? '').isEmpty &&
            remoteId is String &&
            remoteId.isNotEmpty) {
          await _mmkv.setString(_deviceIdKey, remoteId);
        }
      }

      logDebug('设置数据恢复完成');
    } catch (e) {
      AppLogger.e('设置数据恢复失败', error: e, source: 'SettingsService');
      rethrow;
    }
  }
}
