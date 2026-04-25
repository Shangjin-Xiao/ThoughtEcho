part of '../settings_service.dart';

extension _SettingsBackup on SettingsService {
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

  /// 获取或生成设备唯一ID（持久化）
  String getOrCreateDeviceId() {
    final existing = _mmkv.getString(_deviceIdKey);
    if (existing != null && existing.isNotEmpty) return existing;
    final newId =
        '${DateTime.now().millisecondsSinceEpoch}_${UniqueKey().hashCode.toRadixString(16)}';
    _mmkv.setString(_deviceIdKey, newId);
    return newId;
  }
}
