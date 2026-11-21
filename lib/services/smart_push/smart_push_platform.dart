part of '../smart_push_service.dart';

/// 平台相关 — 时区、AlarmManager、WorkManager、本地通知调度
extension SmartPushPlatform on SmartPushService {
  /// 取消周期性备用任务
  Future<void> _cancelPeriodicFallbackTask() async {
    if (!_isAndroid && !_isIOS) return;

    try {
      await Workmanager().cancelByUniqueName('smart_push_periodic_check');
      AppLogger.d('已取消 WorkManager 周期性备用任务');
    } catch (e) {
      AppLogger.w('取消周期性备用任务失败', error: e);
    }
  }

  /// 检查是否可以调度精确闹钟
  ///
  /// Android 12+ 需要 SCHEDULE_EXACT_ALARM 权限，Android 14+ 默认不授予
  Future<bool> _canScheduleExactAlarms() async {
    final override = _canScheduleExactAlarmsOverride;
    if (override != null) {
      return override();
    }
    if (!_isAndroid) return true;

    try {
      final androidPlugin =
          _notificationsPlugin.resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();
      if (androidPlugin != null) {
        final canSchedule =
            await androidPlugin.canScheduleExactNotifications() ?? false;
        return canSchedule;
      }
      return true; // 无法确定时默认允许
    } catch (e) {
      AppLogger.w('检查精确闹钟权限失败', error: e);
      return false; // 失败时保守处理，使用降级方案
    }
  }

  /// 判断 Android 是否应使用系统本地通知预调度队列（无需后台冷启动 Dart Isolate）
  Future<bool> shouldUseAndroidPreScheduledNotifications() {
    return _shouldUseAndroidPreScheduledNotifications();
  }

  Future<bool> _shouldUseAndroidPreScheduledNotifications({
    bool? canScheduleExact,
  }) async {
    if (!_isAndroid) return false;
    if (DistributionConfig.isPlayStore) return true;
    final exactGranted = canScheduleExact ?? await _canScheduleExactAlarms();
    return !exactGranted;
  }

  /// 注册低频周期性预调度续期任务（每 24 小时由系统 JobScheduler 滚动续期未来 3 天本地通知队列，不使用前台服务）
  Future<void> _registerPreScheduleRenewalTask() async {
    final override = _registerPreScheduleRenewalOverride;
    if (override != null) {
      await override();
      return;
    }
    if (!_isAndroid) return;

    try {
      await Workmanager().registerPeriodicTask(
        SmartPushService._preScheduleRenewalUniqueName,
        kPreScheduleRenewTask,
        frequency: SmartPushService._preScheduleRenewalFrequency,
        initialDelay: SmartPushService._preScheduleRenewalFrequency,
        existingWorkPolicy: ExistingPeriodicWorkPolicy.update,
      );
      AppLogger.d('已注册预调度通知队列后台续期任务 (24h)');
    } catch (e) {
      AppLogger.w('注册预调度通知队列后台续期任务失败', error: e);
    }
  }

  /// 取消预调度续期后台任务
  Future<void> _cancelPreScheduleRenewalTask() async {
    final override = _cancelPreScheduleRenewalOverride;
    if (override != null) {
      await override();
      return;
    }
    if (!_isAndroid) return;

    try {
      await Workmanager().cancelByUniqueName(
        SmartPushService._preScheduleRenewalUniqueName,
      );
      AppLogger.d('已取消预调度通知队列后台续期任务');
    } catch (e) {
      AppLogger.w('取消预调度通知队列后台续期任务失败', error: e);
    }
  }

  /// 取消旧版 Android AlarmManager 与一次性/高频 WorkManager 后台推送任务（保留预调度续期任务，避免后台续期执行时自取消）
  Future<void> _cancelLegacyAndroidPushTasks({bool force = false}) async {
    if (!_isAndroid) return;
    if (_legacyAndroidTasksCleared && !force) return;

    for (int i = 0; i < 10; i++) {
      try {
        await AndroidAlarmManager.cancel(SmartPushService._androidAlarmId + i);
      } catch (_) {}
      try {
        await Workmanager().cancelByUniqueName('android_push_fallback_$i');
      } catch (_) {}
    }
    try {
      await AndroidAlarmManager.cancel(SmartPushService._dailyQuoteAlarmId);
    } catch (_) {}
    try {
      await Workmanager().cancelByUniqueName('daily_quote_fallback');
    } catch (_) {}
    await _cancelPeriodicFallbackTask();
    _legacyAndroidTasksCleared = true;
  }

  /// 取消所有 Android AlarmManager 与 WorkManager 后台调度任务
  Future<void> _cancelAndroidBackgroundTasks() async {
    if (!_isAndroid) return;
    await _cancelLegacyAndroidPushTasks(force: true);
    await _cancelPreScheduleRenewalTask();
  }

  List<_PreScheduledEntry> _loadTrackedPreScheduledEntries() {
    try {
      final raw = _mmkv.getString(SmartPushService._preScheduledEntriesKey);
      if (raw == null || raw.isEmpty) return const [];
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return decoded
          .whereType<Map>()
          .map(
            (item) => _PreScheduledEntry.fromJson(
              Map<String, dynamic>.from(item),
            ),
          )
          .where((entry) => entry.id > 0)
          .toList();
    } catch (e) {
      AppLogger.w('读取已追踪预调度通知列表失败', error: e);
      return const [];
    }
  }

  Future<void> _saveTrackedPreScheduledEntries(
    List<_PreScheduledEntry> entries, {
    int? expectedGeneration,
    int? expectedSettingsGeneration,
    int? expectedEpoch,
    bool fromBackground = false,
  }) async {
    try {
      if (expectedGeneration != null &&
          !_isScheduleGenerationCurrent(expectedGeneration)) {
        return;
      }
      if (expectedSettingsGeneration != null &&
          !_isSettingsMutationGenerationCurrent(expectedSettingsGeneration)) {
        return;
      }
      if (expectedEpoch != null) {
        await _reloadSharedStorageIfSupported();
        if (expectedGeneration != null &&
            !_isScheduleGenerationCurrent(expectedGeneration)) {
          return;
        }
        if (expectedSettingsGeneration != null &&
            !_isSettingsMutationGenerationCurrent(expectedSettingsGeneration)) {
          return;
        }
        if (_readStoredSettingsEpoch() != expectedEpoch ||
            (fromBackground && _areStoredSettingsAllDisabled())) {
          return;
        }
      }
      if (entries.isEmpty) {
        await _mmkv.remove(SmartPushService._preScheduledEntriesKey);
        return;
      }
      final encoded = jsonEncode(entries.map((e) => e.toJson()).toList());
      await _mmkv.setString(SmartPushService._preScheduledEntriesKey, encoded);
    } catch (e) {
      AppLogger.w('保存预调度通知追踪列表失败', error: e);
    }
  }

  /// 查询系统本地通知队列中仍处于待触发状态（尚未由 ScheduledNotificationReceiver 送达）的通知 ID 集合。
  ///
  /// 在无精确闹钟权限（inexactAllowWhileIdle）场景下，即使当前时间已过计划时间点（epochMs <= nowMs），
  /// 只要系统尚未送达该通知，其 ID 仍会保留在 pendingNotificationRequests 中。
  Future<Set<int>?> _queryPendingLocalNotificationIds() async {
    try {
      final pending = await _notificationsPlugin.pendingNotificationRequests();
      return pending.map((request) => request.id).toSet();
    } catch (_) {
      return null;
    }
  }

  bool _isEntryDisabledByCurrentSettings(_PreScheduledEntry entry) {
    if (entry.isDailyQuote) {
      return !_settings.dailyQuotePushEnabled;
    }
    if (!_settings.enabled) {
      return true;
    }
    if (_settings.pushMode != PushMode.smart) {
      if (!_settings.pushTimeSlots.any((s) => s.enabled)) {
        return true;
      }
      if (entry.slotHour != null && entry.slotMinute != null) {
        return !_settings.pushTimeSlots.any(
          (s) =>
              s.enabled &&
              s.hour == entry.slotHour &&
              s.minute == entry.slotMinute,
        );
      }
    }
    return false;
  }

  /// 对账并取消不再处于当前有效计划内、或关联笔记已被隐藏/删除的预调度通知。
  ///
  /// 返回实际被取消的通知 ID 集合与因关联笔记被隐藏/删除而失效的通知 ID 集合。
  Future<({Set<int> cancelledIds, Set<int> invalidatedIds})>
      _reconcileTrackedPreScheduledNotifications({
    required Set<int> activeIds,
    required bool futureOnly,
    Set<String>? visibleNoteIds,
    List<_PreScheduledEntry>? entriesOverride,
    Set<int>? pendingRequestIds,
    bool alreadyQueriedPendingIds = false,
    bool canScheduleExact = true,
    Set<int> retainedOverduePendingIds = const <int>{},
  }) async {
    final previousEntries =
        entriesOverride ?? _loadTrackedPreScheduledEntries();
    if (previousEntries.isEmpty) {
      return (cancelledIds: const <int>{}, invalidatedIds: const <int>{});
    }

    final effectivePendingIds = alreadyQueriedPendingIds
        ? pendingRequestIds
        : (pendingRequestIds ?? await _queryPendingLocalNotificationIds());

    final cancelledIds = <int>{};
    final invalidatedIds = <int>{};
    final nowMs = _now().millisecondsSinceEpoch;
    for (final entry in previousEntries) {
      final hasInvalidatedNote = visibleNoteIds != null &&
          entry.noteId != null &&
          !visibleNoteIds.contains(entry.noteId);
      if (hasInvalidatedNote) {
        invalidatedIds.add(entry.id);
      } else {
        if (activeIds.contains(entry.id)) continue;
        if (entry.epochMs <= nowMs) {
          final isStillPending = effectivePendingIds != null
              ? effectivePendingIds.contains(entry.id)
              : (!canScheduleExact && !entry.accounted);
          if (isStillPending) {
            if (futureOnly || retainedOverduePendingIds.contains(entry.id)) {
              continue;
            }
          } else {
            if (futureOnly || !_isEntryDisabledByCurrentSettings(entry)) {
              continue;
            }
          }
        }
      }
      cancelledIds.add(entry.id);
      try {
        await _notificationsPlugin.cancel(entry.id);
      } catch (e) {
        AppLogger.w('取消过期预调度通知失败 (ID: ${entry.id})', error: e);
      }
    }
    return (cancelledIds: cancelledIds, invalidatedIds: invalidatedIds);
  }

  /// 初始化时区 - 正确设置设备本地时区
  Future<void> _initializeTimezone() async {
    tz_data.initializeTimeZones();

    // 获取设备时区并设置为本地时区
    try {
      final String timeZoneName = await _getDeviceTimeZone();
      final location = tz.getLocation(timeZoneName);
      tz.setLocalLocation(location);
      AppLogger.d('时区设置为: $timeZoneName');
    } catch (e) {
      // 降级：使用 UTC 偏移量估算时区
      AppLogger.w('获取设备时区失败，使用偏移量估算: $e');
      final now = DateTime.now();
      final offset = now.timeZoneOffset;
      final hours = offset.inHours;

      // 尝试找到匹配的时区
      String fallbackZone = 'Asia/Shanghai'; // 默认
      if (hours >= 8) {
        fallbackZone = 'Asia/Shanghai';
      } else if (hours >= 5 && hours < 8) {
        fallbackZone = 'Asia/Kolkata';
      } else if (hours >= 0 && hours < 5) {
        fallbackZone = 'Europe/London';
      } else if (hours >= -5 && hours < 0) {
        fallbackZone = 'America/New_York';
      } else {
        fallbackZone = 'America/Los_Angeles';
      }

      try {
        tz.setLocalLocation(tz.getLocation(fallbackZone));
        AppLogger.d('使用降级时区: $fallbackZone');
      } catch (_) {
        // 最终降级：使用 UTC
        tz.setLocalLocation(tz.UTC);
        AppLogger.w('无法设置时区，使用 UTC');
      }
    }
  }

  /// 获取设备时区名称
  Future<String> _getDeviceTimeZone() async {
    final override = _timeZoneOverride;
    if (override != null && override.isNotEmpty) {
      return override;
    }
    if (kIsWeb) {
      return 'UTC';
    }

    try {
      // Android: 通过 MethodChannel 获取系统时区
      if (PlatformHelper.isAndroid) {
        const channel = MethodChannel('com.shangjin.thoughtecho/timezone');
        try {
          final String? timeZone = await channel.invokeMethod('getTimeZone');
          if (timeZone != null && timeZone.isNotEmpty) {
            return timeZone;
          }
        } catch (_) {
          // MethodChannel 不可用，使用 DateTime 估算
        }
      }

      // iOS/降级: 使用 DateTime.now().timeZoneName
      final timeZoneName = DateTime.now().timeZoneName;

      // 处理常见缩写
      final zoneMapping = {
        'CST': 'Asia/Shanghai',
        'EST': 'America/New_York',
        'PST': 'America/Los_Angeles',
        'GMT': 'Europe/London',
        'UTC': 'UTC',
        'JST': 'Asia/Tokyo',
        'KST': 'Asia/Seoul',
      };

      if (zoneMapping.containsKey(timeZoneName)) {
        return zoneMapping[timeZoneName]!;
      }

      // 尝试直接使用时区名称
      try {
        tz.getLocation(timeZoneName);
        return timeZoneName;
      } catch (_) {
        return 'Asia/Shanghai'; // 默认
      }
    } catch (e) {
      AppLogger.w('获取设备时区失败: $e');
      return 'Asia/Shanghai';
    }
  }

  /// 调度单个 Alarm
  Future<void> _scheduleSingleAlarm(
    int idIndex,
    tz.TZDateTime scheduledDate,
    PushTimeSlot slot,
  ) async {
    // 1. Android: 优先使用 AlarmManager 实现精确定时
    if (_isAndroid) {
      // 先检查精确闹钟权限
      final canScheduleExact = await _canScheduleExactAlarms();

      if (canScheduleExact && !DistributionConfig.isPlayStore) {
        try {
          _legacyAndroidTasksCleared = false;
          await AndroidAlarmManager.oneShotAt(
            scheduledDate,
            SmartPushService._androidAlarmId + idIndex,
            backgroundPushCallback,
            exact: true,
            wakeup: true,
            rescheduleOnReboot: true,
            allowWhileIdle: true,
          );
          AppLogger.i(
            '已设定常规 Alarm: $scheduledDate (ID: ${SmartPushService._androidAlarmId + idIndex})',
          );
          return; // 成功，直接返回
        } catch (e) {
          AppLogger.e('设定常规 Alarm 失败', error: e);
          // 继续降级到本地通知
        }
      }

      final notificationId =
          SmartPushService.deterministicPreScheduledNotificationId(
        scheduledDate,
        slotIndex: idIndex,
      );
      await _scheduleLocalNotification(
        notificationId,
        scheduledDate,
        slot,
        canScheduleExactOverride: canScheduleExact,
      );
    }
    // 2. iOS: 使用 WorkManager 注册后台任务
    else if (_isIOS) {
      // iOS 使用本地通知作为用户可见的提醒
      await _scheduleLocalNotification(idIndex, scheduledDate, slot);

      // 同时注册 WorkManager 任务以执行后台逻辑（如数据刷新）
      // 注意：iOS 不支持精确定时执行代码，这里注册的是一次性任务，
      // 系统会在"合适的时候"运行。为了周期性检查，我们使用 registerOneOffTask
      // 并在执行完后重新注册。
      try {
        // 计算初始延迟
        final now = DateTime.now();
        final delay = scheduledDate.difference(now);

        await Workmanager().registerOneOffTask(
          'ios_push_check_$idIndex', // 唯一ID
          'com.shangjin.thoughtecho.backgroundPush', // 任务名称
          initialDelay: delay > Duration.zero ? delay : Duration.zero,
          constraints: Constraints(
            networkType: NetworkType.connected, // 需要网络来获取天气/一言
          ),
          existingWorkPolicy: ExistingWorkPolicy.replace,
          inputData: {'triggerKind': 'smartPush'},
        );
        AppLogger.i('已注册 iOS 后台任务: 延迟 ${delay.inMinutes} 分钟');
      } catch (e) {
        AppLogger.w('注册 iOS 后台任务失败', error: e);
      }
    }
    // 3. 其他平台：仅本地通知
    else {
      await _scheduleLocalNotification(idIndex, scheduledDate, slot);
    }
  }

  /// 使用本地通知调度（降级方案）
  ///
  /// Android 12+ 需要精确闹钟权限才能使用 exactAllowWhileIdle 模式。
  /// 当权限不可用时，自动降级到 inexactAllowWhileIdle 模式（时间可能有 15 分钟误差）。
  Future<void> _scheduleLocalNotification(
    int id,
    tz.TZDateTime scheduledDate,
    PushTimeSlot slot, {
    bool isDailyQuote = false,
    _PushContent? precomputedContent,
    bool allowContentLookup = true,
    bool? canScheduleExactOverride,
    bool persistSingleTrackedEntry = true,
  }) async {
    try {
      await _ensureNotificationReady();
      // 优先复用批量预计算好的内容；即使需要回退查询也仅使用本地缓存/数据库，绝不在调度阶段请求外网
      _PushContent? content = precomputedContent;
      if (content == null && allowContentLookup) {
        if (isDailyQuote) {
          final resolved = await _resolvePreScheduleDailyQuote();
          if (resolved != null) {
            content = _PushContent(
              title: '📖 每日一言',
              body: _buildNotificationBody(resolved.quote),
              noteId: null,
              sourceNoteId: resolved.sourceNoteId,
              contentType: 'dailyQuote',
              dailyQuoteData: resolved.quoteData,
            );
          }
        } else {
          content = await _getPrecomputedContent();
        }
      }

      final androidDetails = AndroidNotificationDetails(
        SmartPushService._notificationChannelId,
        SmartPushService._notificationChannelName,
        channelDescription: '回顾过去的笔记和每日一言',
        importance: Importance.high,
        priority: Priority.high,
        styleInformation: content != null && content.body.length > 50
            ? BigTextStyleInformation(content.body)
            : null,
      );

      const iosDetails = DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      );

      final details = NotificationDetails(
        android: androidDetails,
        iOS: iosDetails,
      );

      // 检查精确闹钟权限，决定使用哪种调度模式
      final canScheduleExact =
          canScheduleExactOverride ?? await _canScheduleExactAlarms();
      final scheduleMode = canScheduleExact
          ? AndroidScheduleMode.exactAllowWhileIdle
          : AndroidScheduleMode.inexactAllowWhileIdle;

      if (!canScheduleExact) {
        AppLogger.w('精确闹钟权限不可用，使用 inexact 模式调度本地通知（时间可能有 15 分钟误差）');
      }

      final isDailyQuoteContent = isDailyQuote ||
          (content?.contentType == 'dailyQuote' && content?.noteId == null);

      // 构建 payload，确保通知点击时能正确路由并定位到该通知对应的展示内容与通知 ID
      String? payload;
      if (isDailyQuoteContent) {
        payload = SmartPushService.buildNotificationPayload(
          contentType: 'dailyQuote',
          notificationId: id,
        );
      } else if (content?.noteId != null) {
        payload = SmartPushService.buildNotificationPayload(
          noteId: content!.noteId,
          contentType: content.contentType ?? 'dailyQuote',
          routeTarget: 'noteList',
          notificationId: id,
        );
      } else {
        payload = SmartPushService.buildNotificationPayload(
          contentType: content?.contentType ?? 'pastNote',
          notificationId: id,
        );
      }

      await _notificationsPlugin.zonedSchedule(
        id,
        content?.title ?? (isDailyQuoteContent ? '📖 每日一言' : '💡 回忆时刻'),
        content?.body ?? '点击查看今天的灵感',
        scheduledDate,
        details,
        androidScheduleMode: scheduleMode,
        payload: payload,
      );

      if (persistSingleTrackedEntry &&
          (content?.dailyQuoteData != null || content?.sourceNoteId != null)) {
        final existing =
            _loadTrackedPreScheduledEntries().where((e) => e.id != id).toList();
        existing.add(
          _PreScheduledEntry(
            id: id,
            epochMs: scheduledDate.millisecondsSinceEpoch,
            noteId: content?.sourceNoteId ?? content?.noteId,
            isDailyQuote: isDailyQuote,
            contentType:
                content?.contentType ?? (isDailyQuote ? 'dailyQuote' : null),
            slotHour: slot.hour,
            slotMinute: slot.minute,
            dailyQuoteData: content?.dailyQuoteData,
          ),
        );
        await _saveTrackedPreScheduledEntries(existing);
      }

      AppLogger.i(
        '已设定本地通知: $scheduledDate (ID: $id, 模式: ${canScheduleExact ? "精确" : "非精确"})',
      );
    } catch (e) {
      AppLogger.e('设定本地通知失败', error: e);
    }
  }

  Future<void> _cancelAllSchedules() {
    return _enqueueScheduleOperation(
      (_) => _cancelAllSchedulesInternal(),
    );
  }

  Future<void> _cancelAllSchedulesInternal() async {
    await _reconcileTrackedPreScheduledNotifications(
      activeIds: const {},
      futureOnly: false,
    );
    await _saveTrackedPreScheduledEntries(const []);
    await _notificationsPlugin.cancelAll();
    if (_isAndroid) {
      await _cancelAndroidBackgroundTasks();
    } else {
      await _cancelPeriodicFallbackTask();
    }
  }
}
