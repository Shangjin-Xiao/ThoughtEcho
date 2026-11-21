part of '../smart_push_service.dart';

/// 推送调度 — 时间计算、计划编排、持久化
extension SmartPushScheduling on SmartPushService {
  /// 仅供后台续期任务调用：校验共享设置纪元与开关状态后滚动续期未来 3 天预调度队列，
  /// 若续期过程中前台关闭或修改了提醒配置，自动执行回滚与清理。
  Future<void> renewPreScheduledQueueFromBackground() async {
    await _reloadSharedStorageIfSupported();
    await _loadSettings();
    if (!_hasActiveReminderScheduleConfig(_settings) ||
        _areStoredSettingsAllDisabled()) {
      await _cancelAllSchedulesInternal();
      return;
    }

    final startEpoch = _readStoredSettingsEpoch();
    await scheduleNextPush(
      fromBackground: true,
      preserveDeliveredNotifications: true,
    );

    await _reloadSharedStorageIfSupported();
    if (_readStoredSettingsEpoch() != startEpoch ||
        _areStoredSettingsAllDisabled()) {
      await _loadSettings();
      if (!_hasActiveReminderScheduleConfig(_settings)) {
        await _cancelAllSchedulesInternal();
      }
    }
  }

  bool _hasActiveReminderScheduleConfig(SmartPushSettings settings) {
    final hasRegular = settings.enabled &&
        (settings.pushMode == PushMode.smart ||
            settings.pushTimeSlots.any((s) => s.enabled));
    return hasRegular || settings.dailyQuotePushEnabled;
  }

  /// 规划下一次推送
  ///
  /// [fromBackground] 为 true 时，仅取消 AlarmManager 定时器并重新调度，
  /// 不调用 cancelAll() 以避免清除正在显示或即将显示的通知。
  /// [preserveDeliveredNotifications] 为 true 时，保留系统通知栏中已送达的通知。
  Future<void> scheduleNextPush({
    bool fromBackground = false,
    bool preserveDeliveredNotifications = false,
  }) {
    return _enqueueScheduleOperation(
      (generation) => _scheduleNextPushInternal(
        generation: generation,
        fromBackground: fromBackground,
        preserveDeliveredNotifications: preserveDeliveredNotifications,
      ),
    );
  }

  Future<void> _scheduleNextPushInternal({
    required int generation,
    required bool fromBackground,
    required bool preserveDeliveredNotifications,
  }) async {
    try {
      tz.local;
    } catch (_) {
      await _initializeTimezone();
    }
    if (!_isScheduleGenerationCurrent(generation)) return;

    if (fromBackground) {
      await _reloadSharedStorageIfSupported();
      await _loadSettings();
      if (!_isScheduleGenerationCurrent(generation)) return;
    }

    final expectedEpoch = _readStoredSettingsEpoch();

    // 只有当两个推送都关闭时才取消所有计划并返回
    if (!_settings.enabled && !_settings.dailyQuotePushEnabled) {
      await _cancelAllSchedulesInternal();
      _lastScheduleRefreshAt = _now();
      return;
    }

    final canScheduleExact =
        _isAndroid ? await _canScheduleExactAlarms() : true;
    if (!await _isScheduleContextStillValid(
      generation: generation,
      expectedEpoch: expectedEpoch,
      fromBackground: fromBackground,
    )) {
      return;
    }

    final useAndroidPreSchedule =
        await _shouldUseAndroidPreScheduledNotifications(
      canScheduleExact: canScheduleExact,
    );
    if (!await _isScheduleContextStillValid(
      generation: generation,
      expectedEpoch: expectedEpoch,
      fromBackground: fromBackground,
    )) {
      return;
    }

    if (useAndroidPreSchedule) {
      await _scheduleAndroidPreScheduledQueue(
        generation: generation,
        expectedEpoch: expectedEpoch,
        canScheduleExact: canScheduleExact,
        fromBackground: fromBackground,
        preserveDeliveredNotifications: preserveDeliveredNotifications,
      );
      if (!_isScheduleGenerationCurrent(generation)) return;
      if (_readStoredSettingsEpoch() != expectedEpoch) return;
      _lastScheduleRefreshAt = _now();
      _lastScheduledExactAlarmGranted = canScheduleExact;
      return;
    }

    // 非预调度模式（如标准渠道且拥有精确闹钟权限）：清理可能遗留的预调度本地通知
    await _reconcileTrackedPreScheduledNotifications(
      activeIds: const {},
      futureOnly: fromBackground || preserveDeliveredNotifications,
    );
    if (!await _isScheduleContextStillValid(
      generation: generation,
      expectedEpoch: expectedEpoch,
      fromBackground: fromBackground,
    )) {
      return;
    }
    await _saveTrackedPreScheduledEntries(const []);

    if (fromBackground || preserveDeliveredNotifications) {
      // 后台或保留已送达通知场景：只取消 AlarmManager 定时器，不调用 cancelAll
      if (_isAndroid) {
        await _cancelAndroidBackgroundTasks();
      }
      AppLogger.d('重新调度：仅重置后台定时器');
    } else {
      await _cancelAllSchedulesInternal();
      AppLogger.d('已取消现有推送计划，准备重新规划');
    }
    if (!await _isScheduleContextStillValid(
      generation: generation,
      expectedEpoch: expectedEpoch,
      fromBackground: fromBackground,
    )) {
      return;
    }

    // 1. 规划常规推送 (仅当 enabled 为 true 时)
    if (_settings.enabled) {
      final slotsToSchedule = await _resolveRegularSlotsToSchedule();
      if (!await _isScheduleContextStillValid(
        generation: generation,
        expectedEpoch: expectedEpoch,
        fromBackground: fromBackground,
      )) {
        return;
      }

      // 持久化今日实际调度的时间（供后台周期性检查使用）
      await _persistScheduledTimes(slotsToSchedule);

      for (int i = 0; i < slotsToSchedule.length; i++) {
        if (!await _isScheduleContextStillValid(
          generation: generation,
          expectedEpoch: expectedEpoch,
          fromBackground: fromBackground,
        )) {
          return;
        }
        final slot = slotsToSchedule[i];
        final scheduledDate = _nextInstanceOfTime(slot.hour, slot.minute);
        final id = i; // 0-9

        await _scheduleSingleAlarm(id, scheduledDate, slot);
      }
    }

    if (!await _isScheduleContextStillValid(
      generation: generation,
      expectedEpoch: expectedEpoch,
      fromBackground: fromBackground,
    )) {
      return;
    }

    // 2. 规划每日一言独立推送
    if (_settings.dailyQuotePushEnabled) {
      AppLogger.d('正在规划每日一言独立推送...');
      final slot = _settings.dailyQuotePushTime;
      // 每日一言每天都推，不受 frequency 限制
      final scheduledDate = _nextInstanceOfTime(
        slot.hour,
        slot.minute,
        respectsFrequency: false,
      );

      if (_isAndroid) {
        try {
          _legacyAndroidTasksCleared = false;
          await AndroidAlarmManager.oneShotAt(
            scheduledDate,
            SmartPushService._dailyQuoteAlarmId,
            backgroundPushCallback,
            exact: true,
            wakeup: true,
            rescheduleOnReboot: true,
            allowWhileIdle: true,
          );
          AppLogger.i(
            '已设定每日一言 Alarm: $scheduledDate (ID: ${SmartPushService._dailyQuoteAlarmId})',
          );
        } catch (e) {
          AppLogger.e('设定每日一言 Alarm 失败，降级到本地预调度通知', error: e);
          await _scheduleLocalNotification(
            SmartPushService.deterministicPreScheduledNotificationId(
              scheduledDate,
              isDailyQuote: true,
            ),
            scheduledDate,
            slot,
            isDailyQuote: true,
            canScheduleExactOverride: canScheduleExact,
          );
        }
      } else {
        await _scheduleLocalNotification(
          100,
          scheduledDate,
          slot,
          isDailyQuote: true,
        );
      }
    }

    if (!await _isScheduleContextStillValid(
      generation: generation,
      expectedEpoch: expectedEpoch,
      fromBackground: fromBackground,
    )) {
      return;
    }
    _lastScheduleRefreshAt = _now();
    _lastScheduledExactAlarmGranted = canScheduleExact;
  }

  /// 校验当前调度操作在实例内及跨 Isolate 层面是否仍然有效。
  ///
  /// 若后台任务执行期间前台已关闭全部提醒或修改了设置，会自动回滚后台刚写入的通知并清理任务。
  Future<bool> _isScheduleContextStillValid({
    required int generation,
    required int expectedEpoch,
    required bool fromBackground,
    bool reloadStorage = false,
    List<_PreScheduledEntry> writtenEntries = const [],
  }) async {
    if (!_isScheduleGenerationCurrent(generation)) {
      return false;
    }

    if (fromBackground || reloadStorage) {
      await _reloadSharedStorageIfSupported();
    }

    final currentEpoch = _readStoredSettingsEpoch();
    final disabledInStorage = fromBackground &&
        (_settings.enabled || _settings.dailyQuotePushEnabled) &&
        _areStoredSettingsAllDisabled();

    if (currentEpoch != expectedEpoch || disabledInStorage) {
      if (fromBackground) {
        await _loadSettings();
        if (!_hasActiveReminderScheduleConfig(_settings)) {
          for (final entry in writtenEntries) {
            try {
              await _notificationsPlugin.cancel(entry.id);
            } catch (_) {}
          }
          await _cancelAllSchedulesInternal();
        } else if (writtenEntries.isNotEmpty) {
          final foregroundTrackedIds =
              _loadTrackedPreScheduledEntries().map((e) => e.id).toSet();
          for (final entry in writtenEntries) {
            if (!foregroundTrackedIds.contains(entry.id) ||
                _isEntryDisabledByCurrentSettings(entry)) {
              try {
                await _notificationsPlugin.cancel(entry.id);
              } catch (_) {}
            }
          }
        }
      }
      return false;
    }

    return true;
  }

  /// 校验预调度补记上下文是否仍然有效（仅受设置修改、配置重载、实例销毁及跨 Isolate 纪元变化影响，不受普通数据库变更重排打断）
  Future<bool> _isAccountingContextStillValid({
    required int settingsGeneration,
    required int expectedEpoch,
    required bool fromBackground,
    bool reloadStorage = false,
  }) async {
    if (!_isSettingsMutationGenerationCurrent(settingsGeneration)) {
      return false;
    }

    if (fromBackground || reloadStorage) {
      await _reloadSharedStorageIfSupported();
      if (!_isSettingsMutationGenerationCurrent(settingsGeneration)) {
        return false;
      }
    }

    final currentEpoch = _readStoredSettingsEpoch();
    final disabledInStorage = fromBackground &&
        (_settings.enabled || _settings.dailyQuotePushEnabled) &&
        _areStoredSettingsAllDisabled();

    return currentEpoch == expectedEpoch && !disabledInStorage;
  }

  /// 结算已过触发时间的预调度常规通知，更新推送计数、最近推送笔记历史与上次推送时间
  Future<List<_PreScheduledEntry>> _accountDeliveredPreScheduledEntries({
    int? settingsGeneration,
    int? expectedEpoch,
    bool fromBackground = false,
    int? forceAccountNotificationId,
  }) {
    final effectiveSettingsGen =
        settingsGeneration ?? _settingsMutationGeneration;
    final effectiveEpoch = expectedEpoch ?? _readStoredSettingsEpoch();
    final completer = Completer<List<_PreScheduledEntry>>();
    final next = _pendingAccountingOp.then((_) async {
      try {
        final result = await _accountDeliveredPreScheduledEntriesInternal(
          settingsGeneration: effectiveSettingsGen,
          expectedEpoch: effectiveEpoch,
          fromBackground: fromBackground,
          forceAccountNotificationId: forceAccountNotificationId,
        );
        completer.complete(result);
      } catch (e, stack) {
        completer.completeError(e, stack);
      }
    });
    _pendingAccountingOp = next.catchError((_) {});
    return completer.future;
  }

  Future<List<_PreScheduledEntry>>
      _accountDeliveredPreScheduledEntriesInternal({
    required int settingsGeneration,
    required int expectedEpoch,
    bool fromBackground = false,
    int? forceAccountNotificationId,
  }) async {
    if (!await _isAccountingContextStillValid(
      settingsGeneration: settingsGeneration,
      expectedEpoch: expectedEpoch,
      fromBackground: fromBackground,
      reloadStorage: true,
    )) {
      return _loadTrackedPreScheduledEntries();
    }

    final entries = _loadTrackedPreScheduledEntries();
    if (entries.isEmpty) return entries;

    final nowMs = _now().millisecondsSinceEpoch;
    bool isEntryDue(_PreScheduledEntry e) =>
        !e.accounted &&
        (e.epochMs <= nowMs ||
            (forceAccountNotificationId != null &&
                e.id == forceAccountNotificationId));

    final dueRegularEntries = entries
        .where((e) => isEntryDue(e) && !e.isDailyQuote)
        .toList()
      ..sort((a, b) => a.epochMs.compareTo(b.epochMs));

    final hasAnyUnaccountedDue = entries.any(isEntryDue);
    if (!hasAnyUnaccountedDue) {
      return entries;
    }

    if (dueRegularEntries.isNotEmpty) {
      final addedNoteIds = <String>[];
      DateTime? latestPushTime = _settings.lastPushTime;

      for (final entry in dueRegularEntries) {
        if (!await _isAccountingContextStillValid(
          settingsGeneration: settingsGeneration,
          expectedEpoch: expectedEpoch,
          fromBackground: fromBackground,
          reloadStorage: fromBackground,
        )) {
          return entries;
        }

        DateTime deliveredAt;
        try {
          deliveredAt = tz.TZDateTime.fromMillisecondsSinceEpoch(
            tz.local,
            entry.epochMs,
          );
        } catch (_) {
          deliveredAt = DateTime.fromMillisecondsSinceEpoch(entry.epochMs);
        }
        if (_settings.pushMode == PushMode.smart) {
          final alreadyRecorded = _analytics.hasRecordedSentNotification(
            entry.id,
            sentAt: deliveredAt,
          );
          if (!alreadyRecorded) {
            await _analytics.settlePendingSend();
          }
          final wasClicked =
              await _analytics.consumeClickedNotification(entry.id);
          await _analytics.markSent(
            entry.contentType ?? 'pastNote',
            sentAt: deliveredAt,
            notificationId: entry.id,
            alreadyEngaged: wasClicked,
          );
        }

        if (latestPushTime == null || deliveredAt.isAfter(latestPushTime)) {
          latestPushTime = deliveredAt;
        }

        final noteId = entry.noteId;
        if (noteId != null &&
            noteId.isNotEmpty &&
            entry.contentType != 'dailyQuote' &&
            !addedNoteIds.contains(noteId)) {
          addedNoteIds.add(noteId);
        }
      }

      if (!await _isAccountingContextStillValid(
        settingsGeneration: settingsGeneration,
        expectedEpoch: expectedEpoch,
        fromBackground: fromBackground,
        reloadStorage: true,
      )) {
        return entries;
      }

      final recentIds = List<String>.from(_settings.recentlyPushedNoteIds);
      for (final noteId in addedNoteIds) {
        if (!recentIds.contains(noteId)) {
          recentIds.add(noteId);
          while (recentIds.length > SmartPushSettings.maxRecentPushedCount) {
            recentIds.removeAt(0);
          }
        }
      }
      DateTime? mergedLastPushTime = _settings.lastPushTime;
      if (latestPushTime != null &&
          (mergedLastPushTime == null ||
              latestPushTime.isAfter(mergedLastPushTime))) {
        mergedLastPushTime = latestPushTime;
      }

      final updatedSettings = _settings.copyWith(
        lastPushTime: mergedLastPushTime,
        recentlyPushedNoteIds: recentIds,
      );
      await _saveSettingsQuietly(
        updatedSettings,
        expectedSettingsGeneration: settingsGeneration,
        expectedEpoch: expectedEpoch,
      );
    }

    if (!await _isAccountingContextStillValid(
      settingsGeneration: settingsGeneration,
      expectedEpoch: expectedEpoch,
      fromBackground: fromBackground,
      reloadStorage: true,
    )) {
      return entries;
    }

    final updatedEntries = entries
        .map(
          (e) => isEntryDue(e) ? e.copyWith(accounted: true) : e,
        )
        .toList();
    await _saveTrackedPreScheduledEntries(
      updatedEntries,
      expectedSettingsGeneration: settingsGeneration,
      expectedEpoch: expectedEpoch,
      fromBackground: fromBackground,
    );
    return updatedEntries;
  }

  /// 解析当前有效的常规推送时间槽
  Future<List<PushTimeSlot>> _resolveRegularSlotsToSchedule() async {
    if (_settings.pushMode == PushMode.smart) {
      final calculated = await _calculateSmartPushTimes();
      final merged = _mergeCloseTimeSlots(calculated);
      AppLogger.i(
        '智能推送时间: ${merged.map((s) => s.formattedTime).join(", ")}',
      );
      return merged;
    }
    return _settings.pushTimeSlots.where((s) => s.enabled).toList();
  }

  /// Android 未来 3 天本地通知预调度队列（Play 渠道或无精确闹钟权限时启用）
  Future<void> _scheduleAndroidPreScheduledQueue({
    required int generation,
    required int expectedEpoch,
    required bool canScheduleExact,
    required bool fromBackground,
    required bool preserveDeliveredNotifications,
  }) async {
    await _cancelLegacyAndroidPushTasks();
    if (!await _isScheduleContextStillValid(
      generation: generation,
      expectedEpoch: expectedEpoch,
      fromBackground: fromBackground,
    )) {
      return;
    }

    final previousEntries = await _accountDeliveredPreScheduledEntries(
      settingsGeneration: _settingsMutationGeneration,
      expectedEpoch: expectedEpoch,
      fromBackground: fromBackground,
    );
    if (!await _isScheduleContextStillValid(
      generation: generation,
      expectedEpoch: expectedEpoch,
      fromBackground: fromBackground,
    )) {
      return;
    }

    // 整轮规划只解析一次本地/缓存每日一言（包括 null 结果），禁止在槽位循环中重复查询数据库
    Future<
        ({
          Quote quote,
          String? sourceNoteId,
          Map<String, dynamic> quoteData,
        })?>? memoizedDailyQuoteFuture;
    Future<
            ({
              Quote quote,
              String? sourceNoteId,
              Map<String, dynamic> quoteData,
            })?>
        resolveDailyQuoteOnce() =>
            memoizedDailyQuoteFuture ??= _resolvePreScheduleDailyQuote();

    final plannedItems = <_PlannedLocalNotification>[];
    Set<String>? loadedVisibleNoteIds;
    var regularPrecomputationFailed = false;

    // 1. 常规回顾提醒槽位（未来 3 个有效推送日）
    if (_settings.enabled) {
      final slotsToSchedule = await _resolveRegularSlotsToSchedule();
      if (!await _isScheduleContextStillValid(
        generation: generation,
        expectedEpoch: expectedEpoch,
        fromBackground: fromBackground,
      )) {
        return;
      }
      await _persistScheduledTimes(slotsToSchedule);
      if (!await _isScheduleContextStillValid(
        generation: generation,
        expectedEpoch: expectedEpoch,
        fromBackground: fromBackground,
      )) {
        return;
      }

      final rawRegularSlots =
          <({int slotIndex, PushTimeSlot slot, tz.TZDateTime date})>[];
      for (int i = 0; i < slotsToSchedule.length; i++) {
        final slot = slotsToSchedule[i];
        final dates = _upcomingScheduledDates(
          slot.hour,
          slot.minute,
          days: SmartPushService.kAndroidPreScheduleDays,
          respectsFrequency: true,
        );
        for (final date in dates) {
          rawRegularSlots.add((slotIndex: i, slot: slot, date: date));
        }
      }

      rawRegularSlots.sort((a, b) => a.date.compareTo(b.date));

      final plannedRegular = await _planRegularPreScheduledNotifications(
        rawRegularSlots: rawRegularSlots,
        resolveDailyQuoteOnce: resolveDailyQuoteOnce,
        previousEntries: previousEntries,
      );
      if (!await _isScheduleContextStillValid(
        generation: generation,
        expectedEpoch: expectedEpoch,
        fromBackground: fromBackground,
      )) {
        return;
      }
      loadedVisibleNoteIds = plannedRegular.visibleNoteIds;
      regularPrecomputationFailed = plannedRegular.precomputationFailed;
      plannedItems.addAll(plannedRegular.items);
    } else {
      await _persistScheduledTimes(const []);
      if (!await _isScheduleContextStillValid(
        generation: generation,
        expectedEpoch: expectedEpoch,
        fromBackground: fromBackground,
      )) {
        return;
      }
    }

    // 2. 每日一言独立槽位（未来 3 天，不受常规 frequency 限制）
    if (_settings.dailyQuotePushEnabled) {
      final dailySlot = _settings.dailyQuotePushTime;
      final dailyDates = _upcomingScheduledDates(
        dailySlot.hour,
        dailySlot.minute,
        days: SmartPushService.kAndroidPreScheduleDays,
        respectsFrequency: false,
      );

      _PushContent? dailyContent;
      if (dailyDates.isNotEmpty) {
        final resolved = await resolveDailyQuoteOnce();
        if (!await _isScheduleContextStillValid(
          generation: generation,
          expectedEpoch: expectedEpoch,
          fromBackground: fromBackground,
        )) {
          return;
        }
        if (resolved != null) {
          dailyContent = _PushContent(
            title: '📖 每日一言',
            body: _buildNotificationBody(resolved.quote),
            noteId: null,
            sourceNoteId: resolved.sourceNoteId,
            contentType: 'dailyQuote',
            dailyQuoteData: resolved.quoteData,
          );
        }
      }

      for (int idx = 0; idx < dailyDates.length; idx++) {
        final scheduledDate = dailyDates[idx];
        final id = SmartPushService.deterministicPreScheduledNotificationId(
          scheduledDate,
          isDailyQuote: true,
        );
        plannedItems.add(
          _PlannedLocalNotification(
            id: id,
            slotIndex: SmartPushService._dailyQuoteSlotCode,
            slot: dailySlot,
            scheduledDate: scheduledDate,
            isDailyQuote: true,
            content: dailyContent,
          ),
        );
      }
    }

    // 3. 对账并清理已移除/禁用或关联笔记（含本地每日一言来源笔记）已被隐藏/删除的预调度通知
    final trackedNoteIds = previousEntries
        .map((e) => e.noteId)
        .whereType<String>()
        .where((id) => id.isNotEmpty)
        .toSet();
    final visibleNoteIds = trackedNoteIds.isNotEmpty
        ? await _resolveVisibleTrackedNoteIds(
            trackedNoteIds,
            fallbackVisibleIds: loadedVisibleNoteIds,
          )
        : loadedVisibleNoteIds;
    if (!await _isScheduleContextStillValid(
      generation: generation,
      expectedEpoch: expectedEpoch,
      fromBackground: fromBackground,
    )) {
      return;
    }

    final futureOnly = fromBackground || preserveDeliveredNotifications;
    final isNoteOnlyMode = _settings.pushMode == PushMode.custom ||
        _settings.pushMode == PushMode.pastNotes;
    final useLocalQuotesOnly = _loadStoredAppSettings().useLocalQuotesOnly;
    final invalidatedIds = <int>{
      if (visibleNoteIds != null)
        for (final prev in previousEntries)
          if (prev.noteId != null && !visibleNoteIds.contains(prev.noteId))
            prev.id,
    };

    final itemsToWrite = plannedItems.where((item) {
      if (item.content != null) return true;
      if (item.isDailyQuote) {
        if (useLocalQuotesOnly || invalidatedIds.contains(item.id)) {
          return false;
        }
        return true;
      }
      if (invalidatedIds.contains(item.id)) {
        return false;
      }
      if (isNoteOnlyMode && !regularPrecomputationFailed) {
        return false;
      }
      if (useLocalQuotesOnly && !regularPrecomputationFailed) {
        return false;
      }
      return true;
    }).toList();

    final activeIds = itemsToWrite.map((e) => e.id).toSet();
    final reconcileResult = await _reconcileTrackedPreScheduledNotifications(
      activeIds: activeIds,
      futureOnly: futureOnly,
      visibleNoteIds: visibleNoteIds,
      entriesOverride: previousEntries,
    );
    final remainingPreviousEntries = previousEntries
        .where((e) => !reconcileResult.cancelledIds.contains(e.id))
        .toList();
    if (reconcileResult.cancelledIds.isNotEmpty &&
        !fromBackground &&
        _readStoredSettingsEpoch() == expectedEpoch) {
      await _saveTrackedPreScheduledEntries(remainingPreviousEntries);
    }

    List<_PreScheduledEntry> mergeWithRetained(
      List<_PreScheduledEntry> currentScheduled,
    ) {
      final scheduledIds = currentScheduled.map((e) => e.id).toSet();
      final nowMs = _now().millisecondsSinceEpoch;
      final maxRetentionMs =
          SmartPushService._deliveredEntryRetention.inMilliseconds;
      return <_PreScheduledEntry>[
        ...currentScheduled,
        for (final prev in remainingPreviousEntries)
          if (!scheduledIds.contains(prev.id) &&
              prev.epochMs > 0 &&
              (prev.epochMs > nowMs || nowMs - prev.epochMs <= maxRetentionMs))
            prev,
      ];
    }

    if (!await _isScheduleContextStillValid(
      generation: generation,
      expectedEpoch: expectedEpoch,
      fromBackground: fromBackground,
    )) {
      if (!fromBackground && _readStoredSettingsEpoch() == expectedEpoch) {
        await _saveTrackedPreScheduledEntries(
          mergeWithRetained(const <_PreScheduledEntry>[]),
        );
      }
      return;
    }

    // 4. 逐条写入系统本地通知队列；若中途被新设置打断，持久化已写入的局部结果以保证下一轮对账能够完整撤回
    final scheduledEntries = <_PreScheduledEntry>[];
    try {
      for (final item in itemsToWrite) {
        if (!await _isScheduleContextStillValid(
          generation: generation,
          expectedEpoch: expectedEpoch,
          fromBackground: fromBackground,
          writtenEntries: scheduledEntries,
        )) {
          if (!fromBackground) {
            await _saveTrackedPreScheduledEntries(
              mergeWithRetained(scheduledEntries),
            );
          }
          return;
        }

        final newEpochMs = item.scheduledDate.millisecondsSinceEpoch;
        final isNewNotificationInstance = previousEntries
            .where((e) => e.id == item.id)
            .every((e) => e.epochMs != newEpochMs);
        if (isNewNotificationInstance) {
          await _analytics.resetTrackedNotificationState(item.id);
        }

        await _scheduleLocalNotification(
          item.id,
          item.scheduledDate,
          item.slot,
          isDailyQuote: item.isDailyQuote,
          precomputedContent: item.content,
          allowContentLookup: false,
          canScheduleExactOverride: canScheduleExact,
          persistSingleTrackedEntry: false,
        );
        scheduledEntries.add(
          _PreScheduledEntry(
            id: item.id,
            epochMs: newEpochMs,
            noteId: item.content?.sourceNoteId ?? item.content?.noteId,
            isDailyQuote: item.isDailyQuote,
            contentType: item.content?.contentType ??
                (item.isDailyQuote ? 'dailyQuote' : null),
            accounted: false,
            slotHour: item.slot.hour,
            slotMinute: item.slot.minute,
            dailyQuoteData: item.content?.dailyQuoteData,
          ),
        );
      }
    } catch (e) {
      if (!fromBackground && scheduledEntries.isNotEmpty) {
        await _saveTrackedPreScheduledEntries(
          mergeWithRetained(scheduledEntries),
        );
      }
      rethrow;
    }

    final mergedEntries = mergeWithRetained(scheduledEntries);

    if (!await _isScheduleContextStillValid(
      generation: generation,
      expectedEpoch: expectedEpoch,
      fromBackground: fromBackground,
      reloadStorage: true,
      writtenEntries: scheduledEntries,
    )) {
      if (!fromBackground) {
        await _saveTrackedPreScheduledEntries(mergedEntries);
      }
      return;
    }

    await _saveTrackedPreScheduledEntries(
      mergedEntries,
      expectedGeneration: generation,
      expectedEpoch: expectedEpoch,
      fromBackground: fromBackground,
    );

    if (_hasActiveReminderScheduleConfig(_settings)) {
      await _registerPreScheduleRenewalTask();
    } else {
      await _cancelPreScheduleRenewalTask();
    }

    if (fromBackground) {
      await _isScheduleContextStillValid(
        generation: generation,
        expectedEpoch: expectedEpoch,
        fromBackground: true,
        reloadStorage: true,
        writtenEntries: scheduledEntries,
      );
    }
  }

  /// 智能推送时间计算算法 (SOTA v2)
  ///
  /// 策略升级：
  /// 1. 优先使用用户 App 打开时间的响应性热图（比笔记创建时间更准确）
  /// 2. 结合笔记创建时间避开创作高峰
  /// 3. 应用 Thompson Sampling 的时间窗口探索
  /// 4. 周末/节假日自动调整
  Future<List<PushTimeSlot>> _calculateSmartPushTimes() async {
    final now = _now();

    // 默认黄金时间点（经过验证的高效推送时间）
    const defaultSlots = [
      PushTimeSlot(hour: 8, minute: 30, label: '早晨灵感'),
      PushTimeSlot(hour: 20, minute: 0, label: '晚间回顾'),
    ];

    try {
      // 1. 首先尝试使用 SOTA 响应性热图（基于用户 App 打开时间）
      final optimalWindows = await _analytics.getOptimalPushWindows(
        count: 3,
        minScore: 0.15,
      );

      if (optimalWindows.isNotEmpty) {
        // 有足够的用户行为数据
        final selectedSlots = <PushTimeSlot>[];

        for (final window in optimalWindows) {
          if (selectedSlots.length >= 2) break;

          final hour = window.key;
          final label = _getTimeSlotLabel(hour);

          // 添加少量随机分钟数，避免总是整点推送
          final minute = (now.millisecond % 4) * 15; // 0, 15, 30, 45

          selectedSlots.add(
            PushTimeSlot(hour: hour, minute: minute, label: label),
          );
        }

        if (selectedSlots.isNotEmpty) {
          selectedSlots.sort((a, b) => a.hour.compareTo(b.hour));
          AppLogger.d(
            'SOTA 智能推送时间: ${selectedSlots.map((s) => s.formattedTime).join(", ")}',
          );
          return selectedSlots;
        }
      }
    } catch (e) {
      AppLogger.w('SOTA 时间计算失败，降级到传统算法', error: e);
    }

    // 2. 降级：使用传统的笔记创建时间分析（SQL 聚合，不加载内容）
    final hourDistribution =
        await _databaseService.getHourDistributionForSmartPush();

    final totalNotes = hourDistribution.reduce((a, b) => a + b);
    if (totalNotes < 10) {
      return defaultSlots;
    }

    // 定义时间段及其权重
    final timeSlotCandidates = <_TimeSlotCandidate>[
      _TimeSlotCandidate(
        hour: 8,
        minute: 0,
        label: '早晨灵感',
        baseScore: 80,
        avoidCreationPeak: true,
      ),
      _TimeSlotCandidate(
        hour: 12,
        minute: 30,
        label: '午间小憩',
        baseScore: 60,
        avoidCreationPeak: true,
      ),
      _TimeSlotCandidate(
        hour: 18,
        minute: 0,
        label: '傍晚时光',
        baseScore: 70,
        avoidCreationPeak: true,
      ),
      _TimeSlotCandidate(
        hour: 20,
        minute: 30,
        label: '晚间回顾',
        baseScore: 85,
        avoidCreationPeak: false,
      ),
    ];

    // 计算每个时段的得分
    for (final candidate in timeSlotCandidates) {
      final hour = candidate.hour;
      final hourActivity = hourDistribution[hour];
      final activityRatio = hourActivity / totalNotes;

      if (candidate.avoidCreationPeak && activityRatio > 0.15) {
        candidate.score = candidate.baseScore - 30;
      } else if (activityRatio > 0.05) {
        candidate.score = candidate.baseScore + 10;
      } else {
        candidate.score = candidate.baseScore;
      }

      // 周末调整
      if (now.weekday == 6 || now.weekday == 7) {
        if (hour >= 9 && hour <= 10) {
          candidate.score += 15;
        }
        if (hour == 8) {
          candidate.score -= 10;
        }
      }
    }

    timeSlotCandidates.sort((a, b) => b.score.compareTo(a.score));

    final selectedSlots = <PushTimeSlot>[];
    for (final candidate in timeSlotCandidates) {
      if (selectedSlots.length >= 2) break;

      bool hasConflict = false;
      for (final selected in selectedSlots) {
        final hourDiff = (candidate.hour - selected.hour).abs();
        if (hourDiff < 4) {
          hasConflict = true;
          break;
        }
      }

      if (!hasConflict) {
        selectedSlots.add(
          PushTimeSlot(
            hour: candidate.hour,
            minute: candidate.minute,
            label: candidate.label,
          ),
        );
      }
    }

    selectedSlots.sort((a, b) => a.hour.compareTo(b.hour));

    return selectedSlots.isEmpty ? defaultSlots : selectedSlots;
  }

  /// 获取时段标签
  String _getTimeSlotLabel(int hour) {
    if (hour >= 5 && hour < 9) return '早晨灵感';
    if (hour >= 9 && hour < 12) return '上午时光';
    if (hour >= 12 && hour < 14) return '午间小憩';
    if (hour >= 14 && hour < 18) return '下午时光';
    if (hour >= 18 && hour < 21) return '傍晚时光';
    return '晚间回顾';
  }

  /// 合并相近的时间槽（间隔小于 30 分钟的只保留第一个）
  ///
  /// 这是防止同一时间段推送多条笔记的核心机制。
  /// 例如用户设置了 8:00, 8:15, 8:30 三个时间，合并后只保留 8:00。
  List<PushTimeSlot> _mergeCloseTimeSlots(List<PushTimeSlot> slots) {
    if (slots.length <= 1) return slots;

    // 按时间排序
    final sorted = List<PushTimeSlot>.from(slots)
      ..sort((a, b) {
        final aMinutes = a.hour * 60 + a.minute;
        final bMinutes = b.hour * 60 + b.minute;
        return aMinutes.compareTo(bMinutes);
      });

    final merged = <PushTimeSlot>[sorted.first];

    for (int i = 1; i < sorted.length; i++) {
      final current = sorted[i];
      final last = merged.last;

      final lastMinutes = last.hour * 60 + last.minute;
      final currentMinutes = current.hour * 60 + current.minute;
      final gap = currentMinutes - lastMinutes;

      // 间隔大于等于 30 分钟才保留
      if (gap >= 30) {
        merged.add(current);
      } else {
        AppLogger.d(
          '合并时间槽：${current.formattedTime} 与 ${last.formattedTime} 间隔仅 $gap 分钟，跳过',
        );
      }
    }

    if (merged.length < slots.length) {
      AppLogger.i(
        '时间槽合并：${slots.length} → ${merged.length} 个（间隔 <30 分钟的已合并）',
      );
    }

    return merged;
  }

  /// 持久化今日实际调度的推送时间（供后台周期性检查使用）
  Future<void> _persistScheduledTimes(List<PushTimeSlot> slots) async {
    final today = DateTime.now().toIso8601String().substring(0, 10);
    final timesStr = slots.map((s) => '${s.hour}:${s.minute}').join(',');
    await _mmkv.setString(
        SmartPushService._scheduledTimesKey, '$today|$timesStr');
    AppLogger.d('已持久化今日推送时间: $timesStr');
  }

  /// 获取今日实际调度的推送时间（后台周期性检查用）
  List<PushTimeSlot> getScheduledTimesForToday() {
    try {
      final data = _mmkv.getString(SmartPushService._scheduledTimesKey);
      if (data == null || data.isEmpty) return [];

      final parts = data.split('|');
      if (parts.length != 2) return [];

      final today = DateTime.now().toIso8601String().substring(0, 10);
      if (parts[0] != today) return [];

      return parts[1].split(',').map((timeStr) {
        final timeParts = timeStr.split(':');
        return PushTimeSlot(
          hour: int.tryParse(timeParts[0]) ?? 8,
          minute: int.tryParse(timeParts.length > 1 ? timeParts[1] : '0') ?? 0,
        );
      }).toList();
    } catch (e) {
      AppLogger.w('读取今日推送时间失败', error: e);
      return [];
    }
  }

  /// 计算下一个时间点
  tz.TZDateTime _nextInstanceOfTime(
    int hour,
    int minute, {
    bool respectsFrequency = true,
  }) {
    final now = tz.TZDateTime.from(_now(), tz.local);
    final nextDate = SmartPushService.nextScheduledDate(
      now: now,
      hour: hour,
      minute: minute,
      settings: _settings,
      respectsFrequency: respectsFrequency,
    );
    return tz.TZDateTime(
      tz.local,
      nextDate.year,
      nextDate.month,
      nextDate.day,
      hour,
      minute,
    );
  }

  /// 计算未来连续 [days] 个有效推送时间点
  List<tz.TZDateTime> _upcomingScheduledDates(
    int hour,
    int minute, {
    int days = SmartPushService.kAndroidPreScheduleDays,
    bool respectsFrequency = true,
  }) {
    final results = <tz.TZDateTime>[];
    DateTime cursor = tz.TZDateTime.from(_now(), tz.local);

    for (int i = 0; i < days; i++) {
      final nextDate = SmartPushService.nextScheduledDate(
        now: cursor,
        hour: hour,
        minute: minute,
        settings: _settings,
        respectsFrequency: respectsFrequency,
      );
      if (respectsFrequency && !_settings.shouldPushOnDate(nextDate)) {
        break;
      }
      final tzScheduled = tz.TZDateTime(
        tz.local,
        nextDate.year,
        nextDate.month,
        nextDate.day,
        hour,
        minute,
      );
      results.add(tzScheduled);
      cursor = DateTime(
        nextDate.year,
        nextDate.month,
        nextDate.day,
        hour,
        minute,
      ).add(const Duration(minutes: 1));
    }

    return results;
  }

  Future<Set<String>?> _loadVisibleNoteIdsForReconciliation() async {
    try {
      final notes = await _databaseService.getQuotesForSmartPush(limit: 5000);
      return notes
          .map((n) => n.id)
          .whereType<String>()
          .where((id) => id.isNotEmpty)
          .toSet();
    } catch (e) {
      AppLogger.w('查询可见笔记集合用于预调度对账失败', error: e);
      return null;
    }
  }

  /// 批量校验已追踪通知所关联笔记的当前可见性（优先走精确主键集合查询，避免 5000 条截断）
  Future<Set<String>?> _resolveVisibleTrackedNoteIds(
    Set<String> trackedNoteIds, {
    Set<String>? fallbackVisibleIds,
  }) async {
    if (trackedNoteIds.isEmpty) return fallbackVisibleIds;
    try {
      return await _databaseService.getVisibleQuoteIds(trackedNoteIds);
    } catch (e) {
      AppLogger.w('批量查询预调度关联笔记可见性失败，回退至常规集合对账', error: e);
      return fallbackVisibleIds ?? await _loadVisibleNoteIdsForReconciliation();
    }
  }

  /// 批量规划常规预调度槽位（单次查库 + 同日严禁重复选文 + 智能模式配额/冷却/质量门槛裁剪 + 记忆化本地一言兜底）
  Future<
      ({
        List<_PlannedLocalNotification> items,
        Set<String>? visibleNoteIds,
        bool? hasAnyVisibleNotes,
        bool precomputationFailed,
      })> _planRegularPreScheduledNotifications({
    required List<({int slotIndex, PushTimeSlot slot, tz.TZDateTime date})>
        rawRegularSlots,
    required Future<
                ({
                  Quote quote,
                  String? sourceNoteId,
                  Map<String, dynamic> quoteData,
                })?>
            Function()
        resolveDailyQuoteOnce,
    List<_PreScheduledEntry> previousEntries = const [],
  }) async {
    if (rawRegularSlots.isEmpty) {
      final visibleIds = await _loadVisibleNoteIdsForReconciliation();
      return (
        items: const <_PlannedLocalNotification>[],
        visibleNoteIds: visibleIds,
        hasAnyVisibleNotes: visibleIds?.isNotEmpty,
        precomputationFailed: false,
      );
    }

    try {
      final allNotes = await _databaseService.getQuotesForSmartPush(
        limit: 5000,
      );
      final visibleNoteIds = allNotes
          .map((n) => n.id)
          .whereType<String>()
          .where((id) => id.isNotEmpty)
          .toSet();
      final hasAnyVisibleNotes = allNotes.isNotEmpty;

      final isSmartMode = _settings.pushMode == PushMode.smart;
      final allowsDailyQuoteFallback = _settings.pushMode != PushMode.custom &&
          _settings.pushMode != PushMode.pastNotes;

      final currentLocation =
          allNotes.isNotEmpty ? await _loadCurrentLocationForMatching() : null;
      final currentWeather =
          allNotes.isNotEmpty ? _loadCurrentWeatherForMatching() : null;
      final enabledTypes = isSmartMode
          ? PastNoteType.values.toSet()
          : _settings.enabledPastNoteTypes;
      final requiredTagIds =
          isSmartMode ? const <String>[] : _settings.filterTagIds;
      final weatherFilters = isSmartMode
          ? const <WeatherFilterType>{}
          : _settings.filterWeatherTypes;

      final currentNow = tz.TZDateTime.from(_now(), tz.local);
      final nowMs = currentNow.millisecondsSinceEpoch;
      final todayKey = currentNow.toIso8601String().substring(0, 10);

      PushQuotaProfile? smartProfile;
      Duration habituationCooldown = Duration.zero;
      DateTime? lastOpen;
      DateTime? dismissalCooldownEnd;
      Map<String, double> contentTypeScores = const {};
      final perDayCount = <String, int>{};
      DateTime? simulatedLastPushTime = _settings.lastPushTime;

      if (isSmartMode) {
        final tier = await _analytics.getEngagementTier(now: currentNow);
        smartProfile = _settings.pushIntensity.quotaFor(tier);
        perDayCount[todayKey] = await _analytics.getTodayPushCount(
          now: currentNow,
        );
        habituationCooldown = await _analytics.getHabituationCooldown();
        lastOpen = await _analytics.getLastAppOpen();
        dismissalCooldownEnd = _analytics.getDismissalCooldownEnd();
        contentTypeScores = await _analytics.getContentTypeScores();
      }

      // 按日维护已分配的笔记 ID（严格排除集合），确保同一自然日多个槽位或刷新后绝不重复推送同一条笔记
      final sameDayAssignedIds = <String, Set<String>>{};
      final todayPushedIds = _getTodayPushedNoteIds(now: currentNow);
      if (todayPushedIds.isNotEmpty) {
        sameDayAssignedIds
            .putIfAbsent(todayKey, () => <String>{})
            .addAll(todayPushedIds);
      }
      for (final prev in previousEntries) {
        final prevNoteId = prev.noteId;
        if (!prev.isDailyQuote &&
            prev.contentType != 'dailyQuote' &&
            prev.epochMs > 0 &&
            prev.epochMs <= nowMs &&
            prevNoteId != null &&
            prevNoteId.isNotEmpty &&
            visibleNoteIds.contains(prevNoteId)) {
          final deliveredDayKey = tz.TZDateTime.fromMillisecondsSinceEpoch(
            tz.local,
            prev.epochMs,
          ).toIso8601String().substring(0, 10);
          sameDayAssignedIds
              .putIfAbsent(deliveredDayKey, () => <String>{})
              .add(prevNoteId);
        }
      }

      List<Quote> applyTagFilter(List<Quote> source) {
        if (requiredTagIds.isEmpty) return source;
        return source
            .where((n) => n.tagIds.any(requiredTagIds.contains))
            .toList();
      }

      Future<_PushContent?> selectCandidateForDate(
        tz.TZDateTime scheduledDate,
        Set<String> assignedIds,
        Set<String> sameDayExcludedIds,
      ) async {
        if (allNotes.isEmpty) {
          if (allowsDailyQuoteFallback) {
            final resolved = await resolveDailyQuoteOnce();
            if (resolved != null) {
              return _PushContent(
                title: '📖 每日一言',
                body: _buildNotificationBody(resolved.quote),
                noteId: null,
                sourceNoteId: resolved.sourceNoteId,
                contentType: 'dailyQuote',
                priority: 0,
                dailyQuoteData: resolved.quoteData,
              );
            }
          }
          return null;
        }

        var candidates = buildTypedCandidates(
          notes: allNotes,
          now: scheduledDate,
          enabledPastNoteTypes: enabledTypes,
          recentPushedIds: assignedIds,
          strictExcludedIds: sameDayExcludedIds,
          random: _random,
          requiredTagIds: requiredTagIds,
          currentLocation: currentLocation,
          currentWeather: currentWeather,
          weatherFilters: weatherFilters,
        );

        if (candidates.isEmpty) {
          candidates = buildTypedCandidates(
            notes: allNotes,
            now: scheduledDate,
            enabledPastNoteTypes: enabledTypes,
            recentPushedIds: const {},
            strictExcludedIds: sameDayExcludedIds,
            random: _random,
            requiredTagIds: requiredTagIds,
            currentLocation: currentLocation,
            currentWeather: currentWeather,
            weatherFilters: weatherFilters,
          );
        }

        if (candidates.isNotEmpty) {
          final chosen = candidates.first;
          final note = chosen.note;
          final priority = scoreSmartPushCandidate(
            basePriority: chosen.priority,
            note: note,
            contentTypeScore: contentTypeScores[chosen.contentType] ?? 0.5,
          );
          return _PushContent(
            title: chosen.title,
            body: _buildNotificationBody(note),
            noteId: note.id,
            sourceNoteId: note.id,
            contentType: chosen.contentType,
            priority: priority,
          );
        }

        Quote? fallbackNote;
        String fallbackTitle = '💡 漫步旧时光';
        String fallbackType = 'randomMemory';
        int fallbackBasePriority = 40;

        if (isSmartMode || enabledTypes.contains(PastNoteType.randomMemory)) {
          final randomPool = applyTagFilter(
            filterRandomMemory(allNotes, scheduledDate, _random),
          );
          fallbackNote = selectUnpushedNote(
            randomPool,
            assignedIds,
            _random,
            strictExcludedIds: sameDayExcludedIds,
          );
        }

        if (fallbackNote == null && isSmartMode) {
          final sameTimePool = applyTagFilter(
            filterSameTimeOfDay(allNotes, scheduledDate),
          );
          fallbackNote = selectUnpushedNote(
            sameTimePool,
            assignedIds,
            _random,
            strictExcludedIds: sameDayExcludedIds,
          );
          if (fallbackNote != null) {
            fallbackTitle = '⏰ 往日此时';
            fallbackType = 'sameTimeOfDay';
            fallbackBasePriority = 20;
          }
        }

        if (fallbackNote != null) {
          final priority = scoreSmartPushCandidate(
            basePriority: fallbackBasePriority,
            note: fallbackNote,
            contentTypeScore: contentTypeScores[fallbackType] ?? 0.5,
          );
          return _PushContent(
            title: fallbackTitle,
            body: _buildNotificationBody(fallbackNote),
            noteId: fallbackNote.id,
            sourceNoteId: fallbackNote.id,
            contentType: fallbackType,
            priority: priority,
          );
        }

        if (isSmartMode) {
          final resolved = await resolveDailyQuoteOnce();
          if (resolved != null) {
            return _PushContent(
              title: '📖 每日一言',
              body: _buildNotificationBody(resolved.quote),
              noteId: null,
              sourceNoteId: resolved.sourceNoteId,
              contentType: 'dailyQuote',
              priority: 0,
              dailyQuoteData: resolved.quoteData,
            );
          }
        }

        return null;
      }

      final assignedIds = <String>{..._settings.recentlyPushedNoteIds};
      final items = <_PlannedLocalNotification>[];

      for (final rawSlot in rawRegularSlots) {
        final slotTime = rawSlot.date;
        final dayKey = slotTime.toIso8601String().substring(0, 10);
        final dayCount = perDayCount[dayKey] ?? 0;

        if (isSmartMode && smartProfile != null) {
          if (dayCount >= smartProfile.dailyCap) {
            continue;
          }
          if (smartProfile.minGapDays > 0 && simulatedLastPushTime != null) {
            final gapDays = slotTime.difference(simulatedLastPushTime).inDays;
            if (gapDays < smartProfile.minGapDays) {
              continue;
            }
          }
          if (habituationCooldown > Duration.zero &&
              simulatedLastPushTime != null) {
            if (slotTime.difference(simulatedLastPushTime) <
                habituationCooldown) {
              continue;
            }
          }
          if (lastOpen != null && !slotTime.isBefore(lastOpen)) {
            if (slotTime.difference(lastOpen) <
                const Duration(
                  hours: SmartPushAnalytics.recentOpenSuppressHours,
                )) {
              continue;
            }
          }
          if (dismissalCooldownEnd != null &&
              slotTime.isBefore(dismissalCooldownEnd)) {
            continue;
          }
        }

        final sameDayExcludedIds =
            sameDayAssignedIds[dayKey] ?? const <String>{};
        final candidateContent = await selectCandidateForDate(
          rawSlot.date,
          assignedIds,
          sameDayExcludedIds,
        );

        if (candidateContent == null && !allowsDailyQuoteFallback) {
          continue;
        }

        if (isSmartMode && smartProfile != null && dayCount > 0) {
          final qualityFloor = smartProfile.extraQualityFloor;
          final candidatePriority = candidateContent?.priority ?? 0;
          if (qualityFloor > 0 && candidatePriority < qualityFloor) {
            continue;
          }
        }

        final noteId = candidateContent?.noteId;
        if (noteId != null && noteId.isNotEmpty) {
          assignedIds.add(noteId);
          sameDayAssignedIds.putIfAbsent(dayKey, () => <String>{}).add(noteId);
        }

        if (isSmartMode) {
          perDayCount[dayKey] = dayCount + 1;
          simulatedLastPushTime = slotTime;
        }

        final id = SmartPushService.deterministicPreScheduledNotificationId(
          rawSlot.date,
          slotIndex: rawSlot.slotIndex,
        );
        items.add(
          _PlannedLocalNotification(
            id: id,
            slotIndex: rawSlot.slotIndex,
            slot: rawSlot.slot,
            scheduledDate: rawSlot.date,
            isDailyQuote: false,
            content: candidateContent,
          ),
        );
      }

      return (
        items: items,
        visibleNoteIds: visibleNoteIds,
        hasAnyVisibleNotes: hasAnyVisibleNotes,
        precomputationFailed: false,
      );
    } catch (e) {
      AppLogger.w('批量预计算推送内容失败', error: e);
      return (
        items: rawRegularSlots
            .map(
              (item) => _PlannedLocalNotification(
                id: SmartPushService.deterministicPreScheduledNotificationId(
                  item.date,
                  slotIndex: item.slotIndex,
                ),
                slotIndex: item.slotIndex,
                slot: item.slot,
                scheduledDate: item.date,
                isDailyQuote: false,
                content: null,
              ),
            )
            .toList(),
        visibleNoteIds: null,
        hasAnyVisibleNotes: null,
        precomputationFailed: true,
      );
    }
  }

  /// 预计算推送内容
  Future<_PushContent?> _getPrecomputedContent() async {
    try {
      final candidates = await getTypedCandidateNotes();
      if (candidates.isNotEmpty) {
        final candidate = candidates.first;
        final note = candidate.note;
        return _PushContent(
          title: candidate.title,
          body: _buildNotificationBody(note),
          noteId: note.id,
          sourceNoteId: note.id,
          contentType: candidate.contentType,
          priority: candidate.priority.toDouble(),
        );
      }
      return null;
    } catch (e) {
      AppLogger.w('预计算推送内容失败', error: e);
      return null;
    }
  }

  /// 预调度专用的本地一言解析：仅读取本地缓存或本地数据库，绝不在保存设置/启动恢复时发起外网请求阻塞 UI
  Future<({Quote quote, String? sourceNoteId, Map<String, dynamic> quoteData})?>
      _resolvePreScheduleDailyQuote() async {
    try {
      var data = await getCachedDailyQuoteForToday();
      if (data == null) {
        try {
          final appSettings = _loadStoredAppSettings();
          final localData = await _databaseService.getLocalDailyQuote(
            offlineQuoteSource: appSettings.offlineQuoteSource,
          );
          if (localData != null) {
            data = SmartPushService.normalizeDailyQuoteData(localData);
          }
        } catch (_) {}
      }
      if (data == null) return null;

      final content = data['hitokoto'] as String? ?? '';
      if (content.trim().isEmpty) return null;
      final fromWho = data['from_who'] as String? ?? '';
      final from = data['from'] as String? ?? '';
      final rawLocalId = data['local_quote_id'];
      final sourceNoteId =
          (rawLocalId is String && rawLocalId.isNotEmpty) ? rawLocalId : null;
      return (
        quote: Quote(
          id: sourceNoteId,
          content: content,
          date: _now().toIso8601String(),
          sourceAuthor: fromWho.isNotEmpty ? fromWho : null,
          source: from.isNotEmpty ? from : null,
        ),
        sourceNoteId: sourceNoteId,
        quoteData: Map<String, dynamic>.from(data),
      );
    } catch (e) {
      AppLogger.w('解析预调度每日一言失败', error: e);
      return null;
    }
  }
}
