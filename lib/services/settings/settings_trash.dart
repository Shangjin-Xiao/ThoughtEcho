part of '../settings_service.dart';

extension _SettingsTrash on SettingsService {
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
}
