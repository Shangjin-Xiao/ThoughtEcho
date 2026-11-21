part of '../smart_push_service.dart';

/// 推送调度 — 时间计算、计划编排、持久化
extension SmartPushScheduling on SmartPushService {
  /// 仅供后台续期任务调用：校验共享设置与调度纪元后滚动续期未来 3 天预调度队列，
  /// 若续期过程中前台关闭、修改了提醒配置或隐藏了笔记，自动执行回滚与按需重排。
  Future<void> renewPreScheduledQueueFromBackground() async {
    const maxAttempts = 4;
    for (var attempt = 0; attempt < maxAttempts; attempt++) {
      await _reloadSharedStorageIfSupported();
      final observedEpochAtStart = _readStoredSettingsEpoch();
      await _loadSettings();
      if (!_hasActiveReminderScheduleConfig(_settings) ||
          _areStoredSettingsAllDisabled()) {
        await _cancelAllSchedulesInternal(
          expectedSettingsEpoch: observedEpochAtStart,
          requireDisabledInStorage: true,
        );
        return;
      }

      final startEpoch = _readStoredSettingsEpoch();
      final startScheduleEpoch = _readStoredScheduleEpoch();
      await scheduleNextPush(
        fromBackground: true,
        preserveDeliveredNotifications: true,
      );

      await _reloadSharedStorageIfSupported();
      final settingsChanged = _readStoredSettingsEpoch() != startEpoch;
      final scheduleChanged = _readStoredScheduleEpoch() != startScheduleEpoch;
      if (settingsChanged ||
          scheduleChanged ||
          _areStoredSettingsAllDisabled()) {
        final observedEpochAfterRun = _readStoredSettingsEpoch();
        await _loadSettings();
        if (!_hasActiveReminderScheduleConfig(_settings) ||
            _areStoredSettingsAllDisabled()) {
          await _cancelAllSchedulesInternal(
            expectedSettingsEpoch: observedEpochAfterRun,
            requireDisabledInStorage: true,
          );
          return;
        }
        // 若后台续期期间前台发生了笔记隐藏/修改并触发了回滚，基于最新可见笔记补做干净续期
        if (attempt + 1 < maxAttempts) {
          continue;
        }
      }
      return;
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
    return _scheduleNextPushWithPrerequisite(
      fromBackground: fromBackground,
      preserveDeliveredNotifications: preserveDeliveredNotifications,
    );
  }

  Future<void> _scheduleNextPushWithPrerequisite({
    bool fromBackground = false,
    bool preserveDeliveredNotifications = false,
    Future<Object?>? prerequisite,
  }) {
    return _enqueueScheduleOperation(
      (generation) => _scheduleNextPushInternal(
        generation: generation,
        fromBackground: fromBackground,
        preserveDeliveredNotifications: preserveDeliveredNotifications,
      ),
      prerequisite: prerequisite,
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
    } else {
      await _reloadSharedStorageIfSupported();
      if (!_isScheduleGenerationCurrent(generation)) return;
      _settings = _mergeStoredDeliveryHistoryInto(_settings);
    }

    final expectedEpoch = _readStoredSettingsEpoch();
    final expectedScheduleEpoch = _readStoredScheduleEpoch();

    // 只有当两个推送都关闭时才取消所有计划并返回
    if (!_settings.enabled && !_settings.dailyQuotePushEnabled) {
      await _cancelAllSchedulesInternal(
        expectedSettingsEpoch: expectedEpoch,
        requireDisabledInStorage: fromBackground,
      );
      _lastScheduleRefreshAt = _now();
      return;
    }

    final canScheduleExact =
        _isAndroid ? await _canScheduleExactAlarms() : true;
    if (!await _isScheduleContextStillValid(
      generation: generation,
      expectedEpoch: expectedEpoch,
      expectedScheduleEpoch: expectedScheduleEpoch,
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
      expectedScheduleEpoch: expectedScheduleEpoch,
      fromBackground: fromBackground,
    )) {
      return;
    }

    if (useAndroidPreSchedule) {
      await _scheduleAndroidPreScheduledQueue(
        generation: generation,
        expectedEpoch: expectedEpoch,
        expectedScheduleEpoch: expectedScheduleEpoch,
        canScheduleExact: canScheduleExact,
        fromBackground: fromBackground,
        preserveDeliveredNotifications: preserveDeliveredNotifications,
      );
      if (!_isScheduleGenerationCurrent(generation)) return;
      if (_readStoredSettingsEpoch() != expectedEpoch ||
          _readStoredScheduleEpoch() != expectedScheduleEpoch) {
        return;
      }
      _lastScheduleRefreshAt = _now();
      _lastScheduledExactAlarmGranted = canScheduleExact;
      return;
    }

    // 非预调度模式（如标准渠道且拥有精确闹钟权限）：在跨 Isolate 调度提交锁内清理遗留通知并注册闹钟
    final slotsToSchedule = _settings.enabled
        ? await _resolveRegularSlotsToSchedule()
        : const <PushTimeSlot>[];
    if (!await _isScheduleContextStillValid(
      generation: generation,
      expectedEpoch: expectedEpoch,
      expectedScheduleEpoch: expectedScheduleEpoch,
      fromBackground: fromBackground,
    )) {
      return;
    }

    var committedNonPreSchedule = false;
    await _withScheduleCommitLock(() async {
      if (!await _isScheduleContextStillValid(
        generation: generation,
        expectedEpoch: expectedEpoch,
        expectedScheduleEpoch: expectedScheduleEpoch,
        fromBackground: fromBackground,
        reloadStorage: true,
      )) {
        return;
      }

      final preservedDailyQuoteEntry =
          await _findPreservableStandaloneDailyQuoteEntry();
      if (!await _isScheduleContextStillValid(
        generation: generation,
        expectedEpoch: expectedEpoch,
        expectedScheduleEpoch: expectedScheduleEpoch,
        fromBackground: fromBackground,
      )) {
        return;
      }

      final keepPendingDailyQuoteInQueue = preservedDailyQuoteEntry != null &&
          (fromBackground || preserveDeliveredNotifications);

      final commitSeq = await _nextNotificationCommitSeq();
      final preserveDeliveredSnapshots =
          fromBackground || preserveDeliveredNotifications;
      final existingBeforeReconcile = preserveDeliveredSnapshots
          ? _loadTrackedPreScheduledEntries()
          : const <_PreScheduledEntry>[];
      final deliveredNoteIdsToVerify = <String>{
        for (final e in existingBeforeReconcile)
          if (e.noteId != null && e.noteId!.isNotEmpty) e.noteId!,
      };
      final visibleDeliveredNoteIds = deliveredNoteIdsToVerify.isNotEmpty
          ? await _resolveVisibleTrackedNoteIds(deliveredNoteIdsToVerify)
          : null;
      final reconcileResult = await _reconcileTrackedPreScheduledNotifications(
        activeIds: keepPendingDailyQuoteInQueue ? const <int>{100} : const {},
        futureOnly: preserveDeliveredSnapshots,
        visibleNoteIds: visibleDeliveredNoteIds,
      );
      final effectiveKeepPendingDailyQuoteInQueue =
          keepPendingDailyQuoteInQueue &&
              !reconcileResult.cancelledIds.contains(100);
      if (!await _isScheduleContextStillValid(
        generation: generation,
        expectedEpoch: expectedEpoch,
        expectedScheduleEpoch: expectedScheduleEpoch,
        expectedCommitSeq: commitSeq,
        fromBackground: fromBackground,
      )) {
        return;
      }
      final nowMsForRetained = _now().millisecondsSinceEpoch;
      final maxRetentionMs =
          SmartPushService._deliveredEntryRetention.inMilliseconds;
      final retainedDeliveredEntries = <_PreScheduledEntry>[
        if (preserveDeliveredSnapshots)
          for (final prev in existingBeforeReconcile)
            if (prev.epochMs > 0 &&
                prev.epochMs <= nowMsForRetained &&
                nowMsForRetained - prev.epochMs <= maxRetentionMs &&
                (prev.noteId == null ||
                    visibleDeliveredNoteIds == null ||
                    visibleDeliveredNoteIds.contains(prev.noteId)) &&
                (!effectiveKeepPendingDailyQuoteInQueue ||
                    prev.id != 100 ||
                    prev.epochMs != preservedDailyQuoteEntry.epochMs))
              prev,
        if (effectiveKeepPendingDailyQuoteInQueue)
          preservedDailyQuoteEntry.copyWith(commitSeq: commitSeq),
      ];
      await _saveTrackedPreScheduledEntries(
        retainedDeliveredEntries,
        expectedCommitSeq: commitSeq,
      );

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
        expectedScheduleEpoch: expectedScheduleEpoch,
        fromBackground: fromBackground,
      )) {
        return;
      }

      // 1. 规划常规推送 (仅当 enabled 为 true 时)
      if (_settings.enabled) {
        // 持久化今日实际调度的时间（供后台周期性检查使用）
        await _persistScheduledTimes(slotsToSchedule);

        for (int i = 0; i < slotsToSchedule.length; i++) {
          if (!await _isScheduleContextStillValid(
            generation: generation,
            expectedEpoch: expectedEpoch,
            expectedScheduleEpoch: expectedScheduleEpoch,
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
        expectedScheduleEpoch: expectedScheduleEpoch,
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
        } else if (!effectiveKeepPendingDailyQuoteInQueue) {
          _PushContent? preservedPrecomputed;
          if (preservedDailyQuoteEntry?.dailyQuoteData != null) {
            final data = preservedDailyQuoteEntry!.dailyQuoteData!;
            final text = (data['hitokoto'] as String?)?.trim() ?? '';
            if (text.isNotEmpty) {
              final fromWho = (data['from_who'] as String?)?.trim() ?? '';
              final from = (data['from'] as String?)?.trim() ?? '';
              final rawLocalId = data['local_quote_id'];
              final sourceNoteId =
                  (rawLocalId is String && rawLocalId.isNotEmpty)
                      ? rawLocalId
                      : preservedDailyQuoteEntry.noteId;
              final quote = Quote(
                id: sourceNoteId,
                content: text,
                date: _now().toIso8601String(),
                sourceAuthor: fromWho.isNotEmpty ? fromWho : null,
                source: from.isNotEmpty ? from : null,
              );
              preservedPrecomputed = _PushContent(
                title: '📖 每日一言',
                body: _buildNotificationBody(quote),
                noteId: null,
                sourceNoteId: sourceNoteId,
                contentType: 'dailyQuote',
                dailyQuoteData: Map<String, dynamic>.from(data),
                quoteSourceFingerprint:
                    preservedDailyQuoteEntry.quoteSourceFingerprint,
              );
            }
          }
          await _scheduleLocalNotification(
            100,
            scheduledDate,
            slot,
            isDailyQuote: true,
            precomputedContent: preservedPrecomputed,
            allowContentLookup: preservedPrecomputed == null,
          );
        }
      }

      if (!await _isScheduleContextStillValid(
        generation: generation,
        expectedEpoch: expectedEpoch,
        expectedScheduleEpoch: expectedScheduleEpoch,
        fromBackground: fromBackground,
      )) {
        return;
      }
      committedNonPreSchedule = true;
    });
    if (!committedNonPreSchedule) {
      return;
    }
    _lastScheduleRefreshAt = _now();
    _lastScheduledExactAlarmGranted = canScheduleExact;
  }

  /// 撤回后台任务已写入但已失效的通知；若共享确定性槽位 ID 已被更新提交（`fg.commitSeq > entry.commitSeq`）
  /// 用合法新提醒覆盖，则保留系统队列中的新通知，避免旧任务误删新提醒。
  Future<void> _rollbackStaleBackgroundEntries(
    List<_PreScheduledEntry> writtenEntries,
  ) {
    return _withScheduleCommitLock(() async {
      await _reloadSharedStorageIfSupported();
      final observedEpoch = _readStoredSettingsEpoch();
      await _loadSettings();
      if (!_hasActiveReminderScheduleConfig(_settings) ||
          _areStoredSettingsAllDisabled()) {
        if (!_hasActiveReminderInStoredSettings() &&
            _readStoredSettingsEpoch() == observedEpoch) {
          for (final entry in writtenEntries) {
            try {
              await _notificationsPlugin.cancel(entry.id);
            } catch (_) {}
          }
          await _cancelAllSchedulesInternal(
            expectedSettingsEpoch: observedEpoch,
            requireDisabledInStorage: true,
          );
        }
        return;
      }

      if (writtenEntries.isEmpty) {
        return;
      }

      final foregroundEntriesById = <int, _PreScheduledEntry>{
        for (final e in _loadTrackedPreScheduledEntries()) e.id: e,
      };
      final latestCommitSeq = _readStoredNotificationCommitSeq();
      final candidateNoteIds = <String>{
        for (final e in writtenEntries)
          if (e.noteId != null && e.noteId!.isNotEmpty) e.noteId!,
        for (final fg in foregroundEntriesById.values)
          if (fg.noteId != null && fg.noteId!.isNotEmpty) fg.noteId!,
      };
      final visibleNoteIds = candidateNoteIds.isNotEmpty
          ? await _resolveVisibleTrackedNoteIds(candidateNoteIds)
          : null;

      for (final entry in writtenEntries) {
        final fg = foregroundEntriesById[entry.id];
        final supersededByNewerCommit =
            fg != null && fg.commitSeq > entry.commitSeq;
        if (supersededByNewerCommit) {
          final fgNoteHidden = fg.noteId != null &&
              visibleNoteIds != null &&
              !visibleNoteIds.contains(fg.noteId);
          if (!fgNoteHidden && !_isEntryDisabledByCurrentSettings(fg)) {
            // 前台更新提交已覆盖同一确定性通知 ID，绝不能按共享 ID 取消新通知
            continue;
          }
          try {
            await _notificationsPlugin.cancel(entry.id);
          } catch (_) {}
          continue;
        }

        if (latestCommitSeq > entry.commitSeq && fg == null) {
          try {
            await _notificationsPlugin.cancel(entry.id);
          } catch (_) {}
          continue;
        }

        final noteHidden = entry.noteId != null &&
            visibleNoteIds != null &&
            !visibleNoteIds.contains(entry.noteId);
        final mismatchedWithForeground = fg == null ||
            fg.epochMs != entry.epochMs ||
            fg.noteId != entry.noteId ||
            fg.isDailyQuote != entry.isDailyQuote ||
            fg.contentType != entry.contentType ||
            (fg.dailyQuoteData?['hitokoto'] !=
                entry.dailyQuoteData?['hitokoto']);
        if (noteHidden ||
            mismatchedWithForeground ||
            _isEntryDisabledByCurrentSettings(entry)) {
          try {
            await _notificationsPlugin.cancel(entry.id);
          } catch (_) {}
        }
      }
    });
  }

  /// 校验当前调度操作在实例内及跨 Isolate 层面是否仍然有效。
  ///
  /// 若后台任务执行期间前台已关闭提醒、修改了设置或隐藏/修改了笔记，会自动回滚后台刚写入的旧通知并保留前台新写入的通知。
  Future<bool> _isScheduleContextStillValid({
    required int generation,
    required int expectedEpoch,
    int? expectedScheduleEpoch,
    int? expectedCommitSeq,
    required bool fromBackground,
    bool reloadStorage = false,
    List<_PreScheduledEntry> writtenEntries = const [],
  }) async {
    if (!_isScheduleGenerationCurrent(generation)) {
      return false;
    }

    if (fromBackground || reloadStorage) {
      await _reloadSharedStorageIfSupported();
      if (!_isScheduleGenerationCurrent(generation)) {
        return false;
      }
    }

    final currentEpoch = _readStoredSettingsEpoch();
    final currentScheduleEpoch = _readStoredScheduleEpoch();
    final commitChanged = expectedCommitSeq != null &&
        _readStoredNotificationCommitSeq() != expectedCommitSeq;
    final disabledInStorage = fromBackground &&
        (_settings.enabled || _settings.dailyQuotePushEnabled) &&
        _areStoredSettingsAllDisabled();

    if (currentEpoch != expectedEpoch ||
        (expectedScheduleEpoch != null &&
            currentScheduleEpoch != expectedScheduleEpoch) ||
        commitChanged ||
        disabledInStorage) {
      if (fromBackground) {
        await _rollbackStaleBackgroundEntries(writtenEntries);
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
    int? forceAccountEpochMs,
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
          forceAccountEpochMs: forceAccountEpochMs,
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
    int? forceAccountEpochMs,
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
    final hasCandidateElapsedEntries = entries.any(
      (e) =>
          !e.accounted &&
          e.epochMs <= nowMs &&
          !(forceAccountNotificationId != null &&
              e.id == forceAccountNotificationId &&
              (forceAccountEpochMs == null ||
                  e.epochMs == forceAccountEpochMs)),
    );
    Set<int>? pendingRequestIds;
    if (hasCandidateElapsedEntries) {
      pendingRequestIds = await _queryPendingLocalNotificationIds();
      if (!await _isAccountingContextStillValid(
        settingsGeneration: settingsGeneration,
        expectedEpoch: expectedEpoch,
        fromBackground: fromBackground,
        reloadStorage: fromBackground,
      )) {
        return _loadTrackedPreScheduledEntries();
      }
    }

    bool isEntryDue(_PreScheduledEntry e) {
      if (e.accounted) return false;
      if (forceAccountNotificationId != null &&
          e.id == forceAccountNotificationId &&
          (forceAccountEpochMs == null || e.epochMs == forceAccountEpochMs)) {
        return true;
      }
      if (e.epochMs > nowMs) return false;
      final hasNewerPendingSibling = entries.any(
        (other) => other.id == e.id && other.epochMs > nowMs,
      );
      if (!hasNewerPendingSibling &&
          pendingRequestIds != null &&
          pendingRequestIds.contains(e.id)) {
        return false;
      }
      return true;
    }

    final dueRegularEntries = entries
        .where((e) => isEntryDue(e) && !e.isDailyQuote)
        .toList()
      ..sort((a, b) => a.epochMs.compareTo(b.epochMs));

    final hasAnyUnaccountedDue = entries.any(isEntryDue);
    if (!hasAnyUnaccountedDue) {
      return entries;
    }

    for (final entry in entries) {
      if (!isEntryDue(entry) || entry.dailyQuoteData == null) continue;
      final quoteText =
          (entry.dailyQuoteData!['hitokoto'] as String?)?.trim() ?? '';
      if (quoteText.isEmpty) continue;
      try {
        final nowLocal = tz.TZDateTime.from(_now(), tz.local);
        final entryLocal = tz.TZDateTime.fromMillisecondsSinceEpoch(
          tz.local,
          entry.epochMs,
        );
        if (entryLocal.year == nowLocal.year &&
            entryLocal.month == nowLocal.month &&
            entryLocal.day == nowLocal.day &&
            !_hasDailyQuoteContentPushed(quoteText)) {
          _markDailyQuoteContentPushed(quoteText);
        }
      } catch (_) {}
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
          await _analytics.recordDeliveredNotification(
            entry.contentType ?? 'pastNote',
            notificationId: entry.id,
            sentAt: deliveredAt,
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

      await _persistDeliveryHistory(
        lastPushTime: mergedLastPushTime,
        pushedNoteIds: recentIds,
        expectedSettingsGeneration: settingsGeneration,
        expectedEpoch: expectedEpoch,
      );
    }

    return _withScheduleCommitLock(() async {
      if (!await _isAccountingContextStillValid(
        settingsGeneration: settingsGeneration,
        expectedEpoch: expectedEpoch,
        fromBackground: fromBackground,
        reloadStorage: true,
      )) {
        return _loadTrackedPreScheduledEntries();
      }

      final dueKeys = <String>{
        for (final e in entries)
          if (isEntryDue(e)) '${e.id}@${e.epochMs}',
      };
      final latestEntries = _loadTrackedPreScheduledEntries();
      final baseEntries = latestEntries.isNotEmpty ? latestEntries : entries;
      final updatedEntries = baseEntries
          .map(
            (e) => dueKeys.contains('${e.id}@${e.epochMs}')
                ? e.copyWith(accounted: true)
                : e,
          )
          .toList();
      await _saveTrackedPreScheduledEntries(
        updatedEntries,
        expectedSettingsGeneration: settingsGeneration,
        expectedEpoch: expectedEpoch,
        fromBackground: fromBackground,
      );
      return updatedEntries;
    });
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
    required int expectedScheduleEpoch,
    required bool canScheduleExact,
    required bool fromBackground,
    required bool preserveDeliveredNotifications,
  }) async {
    await _cancelLegacyAndroidPushTasks();
    if (!await _isScheduleContextStillValid(
      generation: generation,
      expectedEpoch: expectedEpoch,
      expectedScheduleEpoch: expectedScheduleEpoch,
      fromBackground: fromBackground,
    )) {
      return;
    }

    final previousEntries = await _accountDeliveredPreScheduledEntries(
      settingsGeneration: _settingsMutationGeneration,
      expectedEpoch: expectedEpoch,
      fromBackground: fromBackground,
    );
    final planningCommitSeq = _readStoredNotificationCommitSeq();
    final futureOnly = fromBackground || preserveDeliveredNotifications;
    final pendingRequestIds = previousEntries.isNotEmpty
        ? await _queryPendingLocalNotificationIds()
        : const <int>{};
    if (!await _isScheduleContextStillValid(
      generation: generation,
      expectedEpoch: expectedEpoch,
      expectedScheduleEpoch: expectedScheduleEpoch,
      fromBackground: fromBackground,
    )) {
      return;
    }

    final activeNotificationIds = previousEntries.isNotEmpty
        ? await _queryActiveLocalNotificationIds()
        : const <int>{};
    if (!await _isScheduleContextStillValid(
      generation: generation,
      expectedEpoch: expectedEpoch,
      expectedScheduleEpoch: expectedScheduleEpoch,
      fromBackground: fromBackground,
    )) {
      return;
    }

    // 整轮规划至多查询一次缓存/本地每日一言与标签表，禁止在槽位循环中重复查库；
    // 同时维护按日期隔离的一言内容哈希预留表，防止常规回退与独立每日一言在同一天重复推送同一句话
    Future<
        ({
          Quote quote,
          String? sourceNoteId,
          Map<String, dynamic> quoteData,
          String? quoteSourceFingerprint,
        })?>? memoizedPrimaryDailyQuoteFuture;
    Future<
            ({
              Quote quote,
              String? sourceNoteId,
              Map<String, dynamic> quoteData,
              String? quoteSourceFingerprint,
            })?>
        resolvePrimaryDailyQuoteOnce() =>
            memoizedPrimaryDailyQuoteFuture ??= _resolvePreScheduleDailyQuote();

    Future<Set<String>>? memoizedDailyQuoteTagIdsFuture;
    Future<Set<String>> resolveDailyQuoteTagIdsOnce() {
      return memoizedDailyQuoteTagIdsFuture ??= () async {
        final ids = <String>{'default_hitokoto'};
        try {
          final tags = await _databaseService.getTags();
          for (final tag in tags) {
            if (tag.name == '每日一言' && tag.id.isNotEmpty) {
              ids.add(tag.id);
            }
          }
        } catch (_) {}
        return ids;
      }();
    }

    final appSettingsForQuotes = _loadStoredAppSettings();
    final useLocalQuotesOnly = appSettingsForQuotes.useLocalQuotesOnly;
    final offlineQuoteSource = appSettingsForQuotes.offlineQuoteSource;
    final allowDefaultQuoteInLocalOnly =
        useLocalQuotesOnly && offlineQuoteSource != 'tagOnly';
    final todayKeyForQuotes =
        tz.TZDateTime.from(_now(), tz.local).toIso8601String().substring(0, 10);
    final reservedQuoteHashesByDay = <String, Set<String>>{
      if (_getDailyQuotePushedHashesForDate(todayKeyForQuotes).isNotEmpty)
        todayKeyForQuotes: Set<String>.from(
          _getDailyQuotePushedHashesForDate(todayKeyForQuotes),
        ),
    };
    final nowMsForQuotes = _now().millisecondsSinceEpoch;
    for (final prev in previousEntries) {
      if (prev.epochMs <= 0 || prev.epochMs > nowMsForQuotes) continue;
      final prevQuoteText =
          (prev.dailyQuoteData?['hitokoto'] as String?)?.trim() ?? '';
      if (prevQuoteText.isEmpty) continue;
      final prevDayKey =
          tz.TZDateTime.fromMillisecondsSinceEpoch(tz.local, prev.epochMs)
              .toIso8601String()
              .substring(0, 10);
      reservedQuoteHashesByDay
          .putIfAbsent(prevDayKey, () => <String>{})
          .add(_contentHash(prevQuoteText));
    }

    final batchedQuoteCandidates = <({
      Quote quote,
      String? sourceNoteId,
      Map<String, dynamic> quoteData,
      String? quoteSourceFingerprint,
    })>[];
    final seenCandidateHashes = <String>{};
    void addCandidateIfDistinct(
      ({
        Quote quote,
        String? sourceNoteId,
        Map<String, dynamic> quoteData,
        String? quoteSourceFingerprint,
      })? candidate,
    ) {
      if (candidate == null) return;
      final text = candidate.quote.content.trim();
      if (text.isEmpty) return;
      final hash = _contentHash(text);
      if (seenCandidateHashes.add(hash)) {
        batchedQuoteCandidates.add(candidate);
      }
    }

    var primaryQuoteLoaded = false;
    var notesCandidatesLoaded = false;
    Future<void> ensureQuoteCandidatesLoaded({List<Quote>? loadedNotes}) async {
      if (!primaryQuoteLoaded) {
        primaryQuoteLoaded = true;
        addCandidateIfDistinct(await resolvePrimaryDailyQuoteOnce());
      }
      if (!notesCandidatesLoaded &&
          loadedNotes != null &&
          loadedNotes.isNotEmpty) {
        notesCandidatesLoaded = true;
        final allowedTagIds = offlineQuoteSource == 'tagOnly'
            ? await resolveDailyQuoteTagIdsOnce()
            : const <String>{};
        final nowIso = _now().toIso8601String();
        for (final note in loadedNotes) {
          final content = note.content.trim();
          if (content.isEmpty || note.content.length > 100) continue;
          if (offlineQuoteSource == 'tagOnly') {
            if (!note.tagIds.any(allowedTagIds.contains)) continue;
          } else {
            if (note.content.contains('\n')) continue;
          }
          final localFingerprint = useLocalQuotesOnly
              ? _currentDailyQuoteSourceFingerprint(appSettingsForQuotes)
              : null;
          final normalized = SmartPushService.normalizeDailyQuoteData(
            <String, dynamic>{
              'content': content,
              'source': note.sourceWork ?? note.source ?? '',
              'author': note.sourceAuthor ?? '',
              'type': 'local',
              'local_quote_id': note.id,
              'offline_quote_source': offlineQuoteSource,
              if (localFingerprint != null)
                'quote_source_fingerprint': localFingerprint,
              'from_who': note.sourceAuthor ?? '',
              'from': note.sourceWork ?? note.source ?? '',
            },
          );
          if (normalized == null) continue;
          addCandidateIfDistinct((
            quote: Quote(
              id: note.id,
              content: content,
              date: nowIso,
              sourceAuthor: (note.sourceAuthor?.isNotEmpty ?? false)
                  ? note.sourceAuthor
                  : null,
              source: (note.sourceWork?.isNotEmpty ?? false)
                  ? note.sourceWork
                  : ((note.source?.isNotEmpty ?? false) ? note.source : null),
            ),
            sourceNoteId: note.id,
            quoteData: normalized,
            quoteSourceFingerprint: localFingerprint,
          ));
        }
      }
    }

    ({
      Quote quote,
      String? sourceNoteId,
      Map<String, dynamic> quoteData,
      String? quoteSourceFingerprint,
    })? claimQuoteForDate(String dayKey,
        {bool allowReuseWhenSoleChannel = false}) {
      final reserved = reservedQuoteHashesByDay.putIfAbsent(
        dayKey,
        () => <String>{},
      );
      for (final candidate in batchedQuoteCandidates) {
        final hash = _contentHash(candidate.quote.content.trim());
        if (!reserved.contains(hash)) {
          reserved.add(hash);
          return candidate;
        }
      }
      if (allowReuseWhenSoleChannel && batchedQuoteCandidates.isNotEmpty) {
        return batchedQuoteCandidates.first;
      }
      return null;
    }

    final plannedItems = <_PlannedLocalNotification>[];
    final retainedOverduePendingIds = <int>{};
    final suppressedDuplicateRegularFallbackDays = <String>{};

    // 预先计算独立每日一言覆盖的日期集合，确保同日独立一言优先获得唯一语录，避免常规兜底与之撞车
    final dailySlot = _settings.dailyQuotePushTime;
    final dailyDates = _settings.dailyQuotePushEnabled
        ? _upcomingScheduledDates(
            dailySlot.hour,
            dailySlot.minute,
            days: SmartPushService.kAndroidPreScheduleDays,
            respectsFrequency: false,
          )
        : const <tz.TZDateTime>[];
    final independentDailyQuoteDays = <String>{
      for (final d in dailyDates) d.toIso8601String().substring(0, 10),
    };
    if (_settings.dailyQuotePushEnabled) {
      final nowMsForDaily = _now().millisecondsSinceEpoch;
      for (final prev in previousEntries) {
        if (!prev.isDailyQuote ||
            prev.epochMs <= 0 ||
            prev.epochMs > nowMsForDaily) {
          continue;
        }
        final prevDayKey =
            tz.TZDateTime.fromMillisecondsSinceEpoch(tz.local, prev.epochMs)
                .toIso8601String()
                .substring(0, 10);
        independentDailyQuoteDays.add(prevDayKey);
        final isStillPending = pendingRequestIds != null
            ? pendingRequestIds.contains(prev.id)
            : (!canScheduleExact && !prev.accounted);
        if (!isStillPending) continue;
        final prevProvider =
            (prev.dailyQuoteData?['provider'] as String?)?.trim() ?? '';
        if (useLocalQuotesOnly &&
            (prev.noteId == null || prev.noteId!.isEmpty) &&
            !(allowDefaultQuoteInLocalOnly && prevProvider == 'default')) {
          continue;
        }
        final prevLocal = tz.TZDateTime.fromMillisecondsSinceEpoch(
          tz.local,
          prev.epochMs,
        );
        final effHour = prev.slotHour ?? prevLocal.hour;
        final effMinute = prev.slotMinute ?? prevLocal.minute;
        if (effHour == dailySlot.hour && effMinute == dailySlot.minute) {
          retainedOverduePendingIds.add(prev.id);
        }
      }
    }

    final preClaimedIndependentDailyQuotes = <String,
        ({
      Quote quote,
      String? sourceNoteId,
      Map<String, dynamic> quoteData,
      String? quoteSourceFingerprint,
    })?>{};
    var independentDailyQuotesClaimed = false;
    Future<void> ensureIndependentDailyQuotesClaimed({
      List<Quote>? loadedNotes,
    }) async {
      await ensureQuoteCandidatesLoaded(loadedNotes: loadedNotes);
      if (independentDailyQuotesClaimed) return;
      independentDailyQuotesClaimed = true;
      for (final scheduledDate in dailyDates) {
        final dayKey = scheduledDate.toIso8601String().substring(0, 10);
        preClaimedIndependentDailyQuotes[dayKey] = claimQuoteForDate(
          dayKey,
          allowReuseWhenSoleChannel: true,
        );
      }
    }

    Future<
        ({
          Quote quote,
          String? sourceNoteId,
          Map<String, dynamic> quoteData,
          String? quoteSourceFingerprint,
        })?> resolveRegularFallbackQuoteForDate(
      String dayKey, {
      List<Quote>? loadedNotes,
    }) async {
      if (independentDailyQuoteDays.isNotEmpty) {
        await ensureIndependentDailyQuotesClaimed(loadedNotes: loadedNotes);
      } else {
        await ensureQuoteCandidatesLoaded(loadedNotes: loadedNotes);
      }
      final hasIndependentOnDay = independentDailyQuoteDays.contains(dayKey);
      final distinct = claimQuoteForDate(
        dayKey,
        allowReuseWhenSoleChannel: !hasIndependentOnDay &&
            !(reservedQuoteHashesByDay[dayKey]?.isNotEmpty ?? false),
      );
      if (distinct == null && hasIndependentOnDay) {
        suppressedDuplicateRegularFallbackDays.add(dayKey);
      }
      return distinct;
    }

    final trackedNoteIds = previousEntries
        .map((e) => e.noteId)
        .whereType<String>()
        .where((id) => id.isNotEmpty)
        .toSet();
    final trackedVisibleNoteIds = trackedNoteIds.isNotEmpty
        ? await _resolveVisibleTrackedNoteIds(trackedNoteIds)
        : null;
    if (!await _isScheduleContextStillValid(
      generation: generation,
      expectedEpoch: expectedEpoch,
      expectedScheduleEpoch: expectedScheduleEpoch,
      fromBackground: fromBackground,
    )) {
      return;
    }
    Set<String>? loadedVisibleNoteIds;
    List<Quote>? loadedNotesForQuotes;
    var regularPrecomputationFailed = false;
    var scheduledRegularSlotsToPersist = const <PushTimeSlot>[];

    // 1. 常规回顾提醒槽位（未来 3 个有效推送日）
    if (_settings.enabled) {
      final slotsToSchedule = await _resolveRegularSlotsToSchedule();
      if (!await _isScheduleContextStillValid(
        generation: generation,
        expectedEpoch: expectedEpoch,
        expectedScheduleEpoch: expectedScheduleEpoch,
        expectedCommitSeq: fromBackground ? planningCommitSeq : null,
        fromBackground: fromBackground,
      )) {
        return;
      }
      scheduledRegularSlotsToPersist = slotsToSchedule;

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
        slotsToSchedule: slotsToSchedule,
        rawRegularSlots: rawRegularSlots,
        resolveDailyQuoteForDate: resolveRegularFallbackQuoteForDate,
        suppressedDuplicateRegularFallbackDays:
            suppressedDuplicateRegularFallbackDays,
        previousEntries: previousEntries,
        pendingRequestIds: pendingRequestIds,
        trackedVisibleNoteIds: trackedVisibleNoteIds,
        canScheduleExact: canScheduleExact,
        futureOnly: futureOnly,
        useLocalQuotesOnly: useLocalQuotesOnly,
        allowDefaultQuoteInLocalOnly: allowDefaultQuoteInLocalOnly,
      );
      if (!await _isScheduleContextStillValid(
        generation: generation,
        expectedEpoch: expectedEpoch,
        expectedScheduleEpoch: expectedScheduleEpoch,
        expectedCommitSeq: fromBackground ? planningCommitSeq : null,
        fromBackground: fromBackground,
      )) {
        return;
      }
      loadedVisibleNoteIds = plannedRegular.visibleNoteIds;
      loadedNotesForQuotes = plannedRegular.loadedNotes;
      regularPrecomputationFailed = plannedRegular.precomputationFailed;
      retainedOverduePendingIds.addAll(
        plannedRegular.retainedOverduePendingIds,
      );
      plannedItems.addAll(plannedRegular.items);
    }

    // 2. 每日一言独立槽位（未来 3 天，不受常规 frequency 限制）
    if (_settings.dailyQuotePushEnabled) {
      if (dailyDates.isNotEmpty) {
        await ensureIndependentDailyQuotesClaimed(
          loadedNotes: loadedNotesForQuotes,
        );
        if (!await _isScheduleContextStillValid(
          generation: generation,
          expectedEpoch: expectedEpoch,
          expectedScheduleEpoch: expectedScheduleEpoch,
          expectedCommitSeq: fromBackground ? planningCommitSeq : null,
          fromBackground: fromBackground,
        )) {
          return;
        }
      }

      for (int idx = 0; idx < dailyDates.length; idx++) {
        final scheduledDate = dailyDates[idx];
        final dayKey = scheduledDate.toIso8601String().substring(0, 10);
        final resolved = preClaimedIndependentDailyQuotes[dayKey];
        final dailyContent = resolved != null
            ? _PushContent(
                title: '📖 每日一言',
                body: _buildNotificationBody(resolved.quote),
                noteId: null,
                sourceNoteId: resolved.sourceNoteId,
                contentType: 'dailyQuote',
                dailyQuoteData: resolved.quoteData,
                quoteSourceFingerprint: resolved.quoteSourceFingerprint,
              )
            : null;
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

    // 3 & 4. 在跨 Isolate 调度提交锁内完成对账清理、通知写入、写后可见性复核与追踪表提交，
    // 确保前后台不会并发竞争同一确定性槽位 ID。
    await _withScheduleCommitLock(() async {
      if (!await _isScheduleContextStillValid(
        generation: generation,
        expectedEpoch: expectedEpoch,
        expectedScheduleEpoch: expectedScheduleEpoch,
        expectedCommitSeq: fromBackground ? planningCommitSeq : null,
        fromBackground: fromBackground,
        reloadStorage: true,
      )) {
        return;
      }

      var effectivePreviousEntries = previousEntries;
      var effectiveTrackedVisibleNoteIds = trackedVisibleNoteIds;
      if (!fromBackground &&
          _readStoredNotificationCommitSeq() != planningCommitSeq) {
        final latestStored = _loadTrackedPreScheduledEntries();
        final byId = <int, _PreScheduledEntry>{
          for (final e in previousEntries) e.id: e,
          for (final e in latestStored) e.id: e,
        };
        effectivePreviousEntries = byId.values.toList();
        final mergedTrackedNoteIds = effectivePreviousEntries
            .map((e) => e.noteId)
            .whereType<String>()
            .where((id) => id.isNotEmpty)
            .toSet();
        if (mergedTrackedNoteIds.isNotEmpty) {
          effectiveTrackedVisibleNoteIds =
              await _resolveVisibleTrackedNoteIds(mergedTrackedNoteIds);
        }
      }

      await _persistScheduledTimes(scheduledRegularSlotsToPersist);

      final visibleNoteIds = effectivePreviousEntries.any(
        (e) => e.noteId != null && e.noteId!.isNotEmpty,
      )
          ? (effectiveTrackedVisibleNoteIds ?? loadedVisibleNoteIds)
          : loadedVisibleNoteIds;

      final isNoteOnlyMode = _settings.pushMode == PushMode.custom ||
          _settings.pushMode == PushMode.pastNotes;
      final invalidatedIds = <int>{
        if (visibleNoteIds != null)
          for (final prev in effectivePreviousEntries)
            if (prev.noteId != null && !visibleNoteIds.contains(prev.noteId))
              prev.id,
      };
      final invalidatedRegularDays = <String>{
        if (visibleNoteIds != null)
          for (final prev in effectivePreviousEntries)
            if (!prev.isDailyQuote &&
                prev.epochMs > 0 &&
                prev.noteId != null &&
                !visibleNoteIds.contains(prev.noteId))
              tz.TZDateTime.fromMillisecondsSinceEpoch(tz.local, prev.epochMs)
                  .toIso8601String()
                  .substring(0, 10),
      };

      final itemsToWrite = plannedItems.where((item) {
        if (item.content != null) return true;
        final itemDayKey =
            item.scheduledDate.toIso8601String().substring(0, 10);
        if (item.isDailyQuote) {
          if (useLocalQuotesOnly || invalidatedIds.contains(item.id)) {
            return false;
          }
          return true;
        }
        if (suppressedDuplicateRegularFallbackDays.contains(itemDayKey)) {
          return false;
        }
        if (invalidatedIds.contains(item.id) ||
            invalidatedRegularDays.contains(itemDayKey)) {
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

      final batchCommitSeq = await _nextNotificationCommitSeq();

      final activeIds = itemsToWrite.map((e) => e.id).toSet();
      final reconcileResult = await _reconcileTrackedPreScheduledNotifications(
        activeIds: activeIds,
        futureOnly: futureOnly,
        visibleNoteIds: visibleNoteIds,
        entriesOverride: effectivePreviousEntries,
        pendingRequestIds: pendingRequestIds,
        alreadyQueriedPendingIds: true,
        canScheduleExact: canScheduleExact,
        retainedOverduePendingIds: retainedOverduePendingIds,
      );
      final remainingPreviousEntries = effectivePreviousEntries
          .where((e) => !reconcileResult.cancelledIds.contains(e.id))
          .toList();
      if (reconcileResult.cancelledIds.isNotEmpty &&
          !fromBackground &&
          _readStoredSettingsEpoch() == expectedEpoch &&
          _readStoredScheduleEpoch() == expectedScheduleEpoch &&
          _readStoredNotificationCommitSeq() == batchCommitSeq) {
        await _saveTrackedPreScheduledEntries(
          remainingPreviousEntries,
          expectedGeneration: generation,
          expectedEpoch: expectedEpoch,
          expectedScheduleEpoch: expectedScheduleEpoch,
          expectedCommitSeq: batchCommitSeq,
        );
      }

      Future<List<_PreScheduledEntry>> mergeWithRetained(
        List<_PreScheduledEntry> currentScheduled,
      ) async {
        final scheduledIds = currentScheduled.map((e) => e.id).toSet();
        final nowMs = _now().millisecondsSinceEpoch;
        final maxRetentionMs =
            SmartPushService._deliveredEntryRetention.inMilliseconds;
        final retained = <_PreScheduledEntry>[...currentScheduled];
        for (final prev in remainingPreviousEntries) {
          if (scheduledIds.contains(prev.id) || prev.epochMs <= 0) {
            continue;
          }
          if (prev.epochMs > nowMs &&
              pendingRequestIds != null &&
              !pendingRequestIds.contains(prev.id)) {
            continue;
          }
          final withinRetention =
              prev.epochMs > nowMs || nowMs - prev.epochMs <= maxRetentionMs;
          if (withinRetention) {
            retained.add(prev);
            continue;
          }
          // 超出 7 天保留期时：若系统通知栏中该通知仍可见，继续保留 noteId 追踪记录以便后续隐藏/删除笔记时撤回；
          // 若平台无法查询活动通知，则在移除追踪记录前主动取消系统通知，防止隐私笔记预览残留。
          if (activeNotificationIds != null) {
            if (activeNotificationIds.contains(prev.id)) {
              retained.add(prev);
            }
          } else {
            try {
              await _notificationsPlugin.cancel(prev.id);
            } catch (e) {
              AppLogger.w('清理超期预调度通知失败 (ID: ${prev.id})', error: e);
            }
          }
        }
        return retained;
      }

      if (!await _isScheduleContextStillValid(
        generation: generation,
        expectedEpoch: expectedEpoch,
        expectedScheduleEpoch: expectedScheduleEpoch,
        expectedCommitSeq: batchCommitSeq,
        fromBackground: fromBackground,
      )) {
        if (!fromBackground &&
            _readStoredSettingsEpoch() == expectedEpoch &&
            _readStoredScheduleEpoch() == expectedScheduleEpoch &&
            _readStoredNotificationCommitSeq() == batchCommitSeq) {
          await _saveTrackedPreScheduledEntries(
            await mergeWithRetained(const <_PreScheduledEntry>[]),
            expectedGeneration: generation,
            expectedEpoch: expectedEpoch,
            expectedScheduleEpoch: expectedScheduleEpoch,
            expectedCommitSeq: batchCommitSeq,
          );
        }
        return;
      }

      // 4. 逐条写入系统本地通知队列；若中途被新设置或笔记变更打断，自动撤销未被新提交覆盖的旧通知
      final scheduledEntries = <_PreScheduledEntry>[];
      try {
        for (final item in itemsToWrite) {
          if (!await _isScheduleContextStillValid(
            generation: generation,
            expectedEpoch: expectedEpoch,
            expectedScheduleEpoch: expectedScheduleEpoch,
            expectedCommitSeq: batchCommitSeq,
            fromBackground: fromBackground,
            writtenEntries: scheduledEntries,
          )) {
            if (!fromBackground) {
              await _saveTrackedPreScheduledEntries(
                await mergeWithRetained(scheduledEntries),
                expectedCommitSeq: batchCommitSeq,
              );
            }
            return;
          }

          final newEpochMs = item.scheduledDate.millisecondsSinceEpoch;
          final isNewNotificationInstance = effectivePreviousEntries
              .where((e) => e.id == item.id)
              .every((e) => e.epochMs != newEpochMs);

          final scheduled = await _scheduleLocalNotification(
            item.id,
            item.scheduledDate,
            item.slot,
            isDailyQuote: item.isDailyQuote,
            precomputedContent: item.content,
            allowContentLookup: false,
            canScheduleExactOverride: canScheduleExact,
            persistSingleTrackedEntry: false,
          );
          if (!scheduled) {
            continue;
          }
          if (isNewNotificationInstance) {
            await _analytics.resetTrackedNotificationState(item.id);
          }
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
              quoteSourceFingerprint: item.content?.quoteSourceFingerprint,
              commitSeq: batchCommitSeq,
            ),
          );
        }
      } catch (e) {
        if (!fromBackground && scheduledEntries.isNotEmpty) {
          await _saveTrackedPreScheduledEntries(
            await mergeWithRetained(scheduledEntries),
            expectedCommitSeq: batchCommitSeq,
          );
        }
        rethrow;
      }

      // 写入后再次核验关联笔记在数据库中的可见性；若某槽位已被更新提交合法覆盖则保留新通知，仅撤回未被新提交接管的隐藏旧通知
      final writtenNoteIds = scheduledEntries
          .map((e) => e.noteId)
          .whereType<String>()
          .where((id) => id.isNotEmpty)
          .toSet();
      if (writtenNoteIds.isNotEmpty) {
        await _reloadSharedStorageIfSupported();
        final latestForegroundById = <int, _PreScheduledEntry>{
          for (final e in _loadTrackedPreScheduledEntries()) e.id: e,
        };
        final candidateIdsToCheck = <String>{
          ...writtenNoteIds,
          for (final fg in latestForegroundById.values)
            if (fg.noteId != null && fg.noteId!.isNotEmpty) fg.noteId!,
        };
        final postWriteVisibleIds =
            await _resolveVisibleTrackedNoteIds(candidateIdsToCheck);
        if (postWriteVisibleIds != null) {
          final hiddenWritten = scheduledEntries
              .where(
                (e) =>
                    e.noteId != null && !postWriteVisibleIds.contains(e.noteId),
              )
              .toList();
          if (hiddenWritten.isNotEmpty) {
            for (final stale in hiddenWritten) {
              final fg = latestForegroundById[stale.id];
              final supersededByValidCommit = fg != null &&
                  fg.commitSeq > stale.commitSeq &&
                  (fg.noteId == null ||
                      postWriteVisibleIds.contains(fg.noteId)) &&
                  !_isEntryDisabledByCurrentSettings(fg);
              if (!supersededByValidCommit) {
                try {
                  await _notificationsPlugin.cancel(stale.id);
                } catch (_) {}
              }
            }
            scheduledEntries.removeWhere(
              (e) =>
                  e.noteId != null && !postWriteVisibleIds.contains(e.noteId),
            );
          }
        }
      }

      final mergedEntries = await mergeWithRetained(scheduledEntries);

      if (!await _isScheduleContextStillValid(
        generation: generation,
        expectedEpoch: expectedEpoch,
        expectedScheduleEpoch: expectedScheduleEpoch,
        expectedCommitSeq: batchCommitSeq,
        fromBackground: fromBackground,
        reloadStorage: true,
        writtenEntries: scheduledEntries,
      )) {
        if (!fromBackground) {
          await _saveTrackedPreScheduledEntries(
            mergedEntries,
            expectedCommitSeq: batchCommitSeq,
          );
        }
        return;
      }

      await _saveTrackedPreScheduledEntries(
        mergedEntries,
        expectedGeneration: generation,
        expectedEpoch: expectedEpoch,
        expectedScheduleEpoch: expectedScheduleEpoch,
        expectedCommitSeq: batchCommitSeq,
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
          expectedScheduleEpoch: expectedScheduleEpoch,
          expectedCommitSeq: batchCommitSeq,
          fromBackground: true,
          reloadStorage: true,
          writtenEntries: scheduledEntries,
        );
      }
    });
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
      cursor = tz.TZDateTime(
        tz.local,
        nextDate.year,
        nextDate.month,
        nextDate.day + 1,
      );
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
        List<Quote>? loadedNotes,
        Set<String>? visibleNoteIds,
        bool? hasAnyVisibleNotes,
        bool precomputationFailed,
        Set<int> retainedOverduePendingIds,
      })> _planRegularPreScheduledNotifications({
    required List<PushTimeSlot> slotsToSchedule,
    required List<({int slotIndex, PushTimeSlot slot, tz.TZDateTime date})>
        rawRegularSlots,
    required Future<
                ({
                  Quote quote,
                  String? sourceNoteId,
                  Map<String, dynamic> quoteData,
                  String? quoteSourceFingerprint,
                })?>
            Function(String dayKey, {List<Quote>? loadedNotes})
        resolveDailyQuoteForDate,
    Set<String> suppressedDuplicateRegularFallbackDays = const <String>{},
    List<_PreScheduledEntry> previousEntries = const [],
    Set<int>? pendingRequestIds,
    Set<String>? trackedVisibleNoteIds,
    bool canScheduleExact = true,
    bool futureOnly = false,
    bool useLocalQuotesOnly = false,
    bool allowDefaultQuoteInLocalOnly = false,
  }) async {
    final isSmartMode = _settings.pushMode == PushMode.smart;
    final allowsDailyQuoteFallback = _settings.pushMode != PushMode.custom &&
        _settings.pushMode != PushMode.pastNotes;

    bool matchesBasicRegularSettings(
      _PreScheduledEntry prev,
      tz.TZDateTime prevLocal,
    ) {
      if (!_settings.enabled) return false;
      if (!_settings.shouldPushOnDate(prevLocal)) return false;
      final effHour = prev.slotHour ?? prevLocal.hour;
      final effMinute = prev.slotMinute ?? prevLocal.minute;
      final matchesSlot = isSmartMode
          ? slotsToSchedule.any((s) => s.hour == effHour)
          : slotsToSchedule.any(
              (s) => s.hour == effHour && s.minute == effMinute,
            );
      if (!matchesSlot) return false;
      final prevNoteId = prev.noteId;
      final prevProvider =
          (prev.dailyQuoteData?['provider'] as String?)?.trim() ?? '';
      if (useLocalQuotesOnly &&
          prev.contentType == 'dailyQuote' &&
          (prevNoteId == null || prevNoteId.isEmpty) &&
          !(allowDefaultQuoteInLocalOnly && prevProvider == 'default')) {
        return false;
      }
      if (_settings.pushMode == PushMode.dailyQuote) {
        return prev.contentType == null || prev.contentType == 'dailyQuote';
      }
      if (!allowsDailyQuoteFallback) {
        if (prev.contentType == 'dailyQuote' ||
            prevNoteId == null ||
            prevNoteId.isEmpty) {
          return false;
        }
      }
      return true;
    }

    if (rawRegularSlots.isEmpty) {
      final visibleIds = await _loadVisibleNoteIdsForReconciliation();
      return (
        items: const <_PlannedLocalNotification>[],
        loadedNotes: null,
        visibleNoteIds: visibleIds,
        hasAnyVisibleNotes: visibleIds?.isNotEmpty,
        precomputationFailed: false,
        retainedOverduePendingIds: const <int>{},
      );
    }

    try {
      final allNotes = await _databaseService.getQuotesForSmartPush(
        limit: 5000,
      );
      final notesById = <String, Quote>{
        for (final n in allNotes)
          if (n.id != null && n.id!.isNotEmpty) n.id!: n,
      };
      final visibleNoteIds = notesById.keys.toSet();
      final hasAnyVisibleNotes = allNotes.isNotEmpty;

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
      int projectedUnengagedStreak = 0;
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
        projectedUnengagedStreak =
            await _analytics.getProjectedUnengagedStreak();
        habituationCooldown = SmartPushAnalytics.cooldownForStreak(
          projectedUnengagedStreak,
        );
        lastOpen = await _analytics.getLastAppOpen();
        dismissalCooldownEnd = _analytics.getDismissalCooldownEnd();
        contentTypeScores = await _analytics.getContentTypeScores();
      }

      // 按日维护已分配的笔记 ID（严格排除集合），确保同一自然日多个槽位或刷新后绝不重复推送同一条笔记
      final sameDayAssignedIds = <String, Set<String>>{};
      final retainedOverduePendingIds = <int>{};
      final retainedPendingNoteIds = <String>{};
      final todayPushedIds = _getTodayPushedNoteIds(now: currentNow);
      if (todayPushedIds.isNotEmpty) {
        sameDayAssignedIds
            .putIfAbsent(todayKey, () => <String>{})
            .addAll(todayPushedIds);
      }

      final sortedPrevious = List<_PreScheduledEntry>.from(previousEntries)
        ..sort((a, b) => a.epochMs.compareTo(b.epochMs));
      for (final prev in sortedPrevious) {
        if (prev.isDailyQuote || prev.epochMs <= 0 || prev.epochMs > nowMs) {
          continue;
        }
        final prevNoteId = prev.noteId;
        final isPrevNoteVisible = prevNoteId == null ||
            prevNoteId.isEmpty ||
            (trackedVisibleNoteIds != null
                ? trackedVisibleNoteIds.contains(prevNoteId)
                : visibleNoteIds.contains(prevNoteId));
        if (!isPrevNoteVisible) {
          continue;
        }
        final isStillPending = pendingRequestIds != null
            ? pendingRequestIds.contains(prev.id)
            : (!canScheduleExact && !prev.accounted);
        final deliveredTime = tz.TZDateTime.fromMillisecondsSinceEpoch(
          tz.local,
          prev.epochMs,
        );
        final deliveredDayKey =
            deliveredTime.toIso8601String().substring(0, 10);

        if (!isStillPending) {
          if (prev.contentType != 'dailyQuote' &&
              prevNoteId != null &&
              prevNoteId.isNotEmpty) {
            sameDayAssignedIds
                .putIfAbsent(deliveredDayKey, () => <String>{})
                .add(prevNoteId);
          }
          if (isSmartMode && !prev.accounted) {
            perDayCount[deliveredDayKey] =
                (perDayCount[deliveredDayKey] ?? 0) + 1;
            if (simulatedLastPushTime == null ||
                deliveredTime.isAfter(simulatedLastPushTime)) {
              simulatedLastPushTime = deliveredTime;
            }
            if (!_analytics.hasRecordedSentNotification(
              prev.id,
              sentAt: deliveredTime,
            )) {
              projectedUnengagedStreak = _analytics.hasClickedNotification(
                prev.id,
                sentAt: deliveredTime,
              )
                  ? 0
                  : projectedUnengagedStreak + 1;
              habituationCooldown = SmartPushAnalytics.cooldownForStreak(
                projectedUnengagedStreak,
              );
            }
          }
          continue;
        }

        bool shouldRetain = futureOnly;
        if (!futureOnly) {
          shouldRetain = matchesBasicRegularSettings(prev, deliveredTime);
          if (shouldRetain &&
              !isSmartMode &&
              _settings.pushMode != PushMode.dailyQuote &&
              prev.contentType != 'dailyQuote') {
            final note = prevNoteId != null ? notesById[prevNoteId] : null;
            if (prev.contentType == 'sameTimeOfDay') {
              shouldRetain = false;
            } else if (prev.contentType != null &&
                prev.contentType!.isNotEmpty) {
              PastNoteType? matchedType;
              for (final t in PastNoteType.values) {
                if (t.name == prev.contentType) {
                  matchedType = t;
                  break;
                }
              }
              if (matchedType != null && !enabledTypes.contains(matchedType)) {
                shouldRetain = false;
              } else if (matchedType == PastNoteType.sameWeather &&
                  (note == null ||
                      filterSameWeatherNotes(
                        <Quote>[note],
                        deliveredTime,
                        currentWeather: currentWeather,
                        weatherFilters: weatherFilters,
                      ).isEmpty)) {
                shouldRetain = false;
              }
            }
            if (shouldRetain &&
                requiredTagIds.isNotEmpty &&
                (note == null || !note.tagIds.any(requiredTagIds.contains))) {
              shouldRetain = false;
            }
          }
          if (shouldRetain &&
              isSmartMode &&
              smartProfile != null &&
              !prev.accounted) {
            final dayCount = perDayCount[deliveredDayKey] ?? 0;
            final gapSinceLast = simulatedLastPushTime != null
                ? deliveredTime.difference(simulatedLastPushTime).abs()
                : null;
            if (dayCount >= smartProfile.dailyCap) {
              shouldRetain = false;
            } else if (smartProfile.minGapDays > 0 &&
                gapSinceLast != null &&
                gapSinceLast.inDays < smartProfile.minGapDays) {
              shouldRetain = false;
            } else if (habituationCooldown > Duration.zero &&
                gapSinceLast != null &&
                gapSinceLast < habituationCooldown) {
              shouldRetain = false;
            } else if (lastOpen != null &&
                !deliveredTime.isBefore(lastOpen) &&
                deliveredTime.difference(lastOpen) <
                    const Duration(
                      hours: SmartPushAnalytics.recentOpenSuppressHours,
                    )) {
              shouldRetain = false;
            } else if (dismissalCooldownEnd != null &&
                deliveredTime.isBefore(dismissalCooldownEnd)) {
              shouldRetain = false;
            } else if (dayCount > 0 && smartProfile.extraQualityFloor > 0) {
              double prevPriority = 0;
              if (prev.contentType != 'dailyQuote' && prevNoteId != null) {
                final note = notesById[prevNoteId];
                if (note != null) {
                  final typeKey = prev.contentType ?? 'randomMemory';
                  final basePriority = switch (typeKey) {
                    'yearAgoToday' => 100,
                    'monthAgoToday' => 70,
                    'weekAgoToday' => 55,
                    'sameLocation' => calcLocationPriority(
                        filterSameLocationNotes(
                          allNotes,
                          deliveredTime,
                          currentLocation,
                        ).length,
                        allNotes.length,
                      ),
                    'sameWeather' => 40,
                    'sameTimeOfDay' => 20,
                    _ => 40,
                  };
                  prevPriority = scoreSmartPushCandidate(
                    basePriority: basePriority,
                    note: note,
                    contentTypeScore: contentTypeScores[typeKey] ?? 0.5,
                  );
                }
              }
              if (prevPriority < smartProfile.extraQualityFloor) {
                shouldRetain = false;
              }
            }
          }
        }

        if (!shouldRetain) {
          continue;
        }

        retainedOverduePendingIds.add(prev.id);
        if (prev.contentType != 'dailyQuote' &&
            prevNoteId != null &&
            prevNoteId.isNotEmpty) {
          sameDayAssignedIds
              .putIfAbsent(deliveredDayKey, () => <String>{})
              .add(prevNoteId);
          retainedPendingNoteIds.add(prevNoteId);
        }
        if (isSmartMode && !prev.accounted) {
          perDayCount[deliveredDayKey] =
              (perDayCount[deliveredDayKey] ?? 0) + 1;
          if (simulatedLastPushTime == null ||
              deliveredTime.isAfter(simulatedLastPushTime)) {
            simulatedLastPushTime = deliveredTime;
          }
          projectedUnengagedStreak = _analytics.hasClickedNotification(
            prev.id,
            sentAt: deliveredTime,
          )
              ? 0
              : projectedUnengagedStreak + 1;
          habituationCooldown = SmartPushAnalytics.cooldownForStreak(
            projectedUnengagedStreak,
          );
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
        final dayKey = scheduledDate.toIso8601String().substring(0, 10);
        if (_settings.pushMode == PushMode.dailyQuote) {
          final resolved = await resolveDailyQuoteForDate(
            dayKey,
            loadedNotes: allNotes,
          );
          if (resolved != null) {
            return _PushContent(
              title: '📖 每日一言',
              body: _buildNotificationBody(resolved.quote),
              noteId: null,
              sourceNoteId: resolved.sourceNoteId,
              contentType: 'dailyQuote',
              priority: 0,
              dailyQuoteData: resolved.quoteData,
              quoteSourceFingerprint: resolved.quoteSourceFingerprint,
            );
          }
          return null;
        }
        if (allNotes.isEmpty) {
          if (allowsDailyQuoteFallback) {
            final resolved = await resolveDailyQuoteForDate(
              dayKey,
              loadedNotes: allNotes,
            );
            if (resolved != null) {
              return _PushContent(
                title: '📖 每日一言',
                body: _buildNotificationBody(resolved.quote),
                noteId: null,
                sourceNoteId: resolved.sourceNoteId,
                contentType: 'dailyQuote',
                priority: 0,
                dailyQuoteData: resolved.quoteData,
                quoteSourceFingerprint: resolved.quoteSourceFingerprint,
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
          smartContentTypeScores: isSmartMode ? contentTypeScores : null,
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
            smartContentTypeScores: isSmartMode ? contentTypeScores : null,
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

        if (allowsDailyQuoteFallback) {
          final resolved = await resolveDailyQuoteForDate(
            dayKey,
            loadedNotes: allNotes,
          );
          if (resolved != null) {
            return _PushContent(
              title: '📖 每日一言',
              body: _buildNotificationBody(resolved.quote),
              noteId: null,
              sourceNoteId: resolved.sourceNoteId,
              contentType: 'dailyQuote',
              priority: 0,
              dailyQuoteData: resolved.quoteData,
              quoteSourceFingerprint: resolved.quoteSourceFingerprint,
            );
          }
        }

        return null;
      }

      final assignedIds = <String>{
        ..._settings.recentlyPushedNoteIds,
        ...retainedPendingNoteIds,
      };
      final effectiveVisibleForInvalidated =
          trackedVisibleNoteIds ?? visibleNoteIds;
      final invalidatedPreviousDays = <String>{
        for (final prev in previousEntries)
          if (!prev.isDailyQuote &&
              prev.epochMs > 0 &&
              prev.noteId != null &&
              !effectiveVisibleForInvalidated.contains(prev.noteId))
            tz.TZDateTime.fromMillisecondsSinceEpoch(tz.local, prev.epochMs)
                .toIso8601String()
                .substring(0, 10),
      };
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

        final id = SmartPushService.deterministicPreScheduledNotificationId(
          rawSlot.date,
          slotIndex: rawSlot.slotIndex,
        );
        final effectiveVisibleForSlot = trackedVisibleNoteIds ?? visibleNoteIds;
        final hadInvalidatedPreviousNote =
            invalidatedPreviousDays.contains(dayKey) ||
                previousEntries.any(
                  (prev) =>
                      prev.id == id &&
                      prev.noteId != null &&
                      !effectiveVisibleForSlot.contains(prev.noteId),
                );
        final isSuppressedEmptyFallback = candidateContent == null &&
            (useLocalQuotesOnly ||
                hadInvalidatedPreviousNote ||
                suppressedDuplicateRegularFallbackDays.contains(dayKey));
        if ((candidateContent == null && !allowsDailyQuoteFallback) ||
            isSuppressedEmptyFallback) {
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
          projectedUnengagedStreak += 1;
          habituationCooldown = SmartPushAnalytics.cooldownForStreak(
            projectedUnengagedStreak,
          );
        }
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
        loadedNotes: allNotes,
        visibleNoteIds: visibleNoteIds,
        hasAnyVisibleNotes: hasAnyVisibleNotes,
        precomputationFailed: false,
        retainedOverduePendingIds: retainedOverduePendingIds,
      );
    } catch (e) {
      AppLogger.w('批量预计算推送内容失败', error: e);
      final fallbackNowMs = _now().millisecondsSinceEpoch;
      final fallbackRetainedIds = <int>{
        for (final prev in previousEntries)
          if (!prev.isDailyQuote &&
              prev.epochMs > 0 &&
              prev.epochMs <= fallbackNowMs &&
              (pendingRequestIds != null
                  ? pendingRequestIds.contains(prev.id)
                  : (!canScheduleExact && !prev.accounted)) &&
              (futureOnly ||
                  matchesBasicRegularSettings(
                    prev,
                    tz.TZDateTime.fromMillisecondsSinceEpoch(
                      tz.local,
                      prev.epochMs,
                    ),
                  )))
            prev.id,
      };
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
        loadedNotes: null,
        visibleNoteIds: null,
        hasAnyVisibleNotes: null,
        precomputationFailed: true,
        retainedOverduePendingIds: fallbackRetainedIds,
      );
    }
  }

  /// 预计算推送内容
  Future<_PushContent?> _getPrecomputedContent({
    DateTime? referenceTime,
  }) async {
    try {
      final candidates = await getTypedCandidateNotes(
        nowOverride: referenceTime,
      );
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
  Future<
      ({
        Quote quote,
        String? sourceNoteId,
        Map<String, dynamic> quoteData,
        String? quoteSourceFingerprint,
      })?> _resolvePreScheduleDailyQuote() async {
    try {
      final appSettings = _loadStoredAppSettings();
      final currentFp = _currentDailyQuoteSourceFingerprint(appSettings);
      var data = await getCachedDailyQuoteForToday();
      var fromVerifiedCache = data != null;
      if (data != null && !_doesDailyQuoteMatchAppSettings(data, appSettings)) {
        data = null;
        fromVerifiedCache = false;
      }
      if (data == null) {
        try {
          final localData = await _databaseService.getLocalDailyQuote(
            offlineQuoteSource: appSettings.offlineQuoteSource,
          );
          if (localData != null) {
            data = SmartPushService.normalizeDailyQuoteData(localData);
          }
        } catch (_) {}
      }
      if (data == null &&
          appSettings.useLocalQuotesOnly &&
          appSettings.offlineQuoteSource != 'tagOnly') {
        final fallbackData = await _loadDailyQuoteData(
          preferCache: false,
          updateTodayCache: false,
        );
        if (fallbackData != null &&
            _isPermittedDailyQuoteForLocalOnlyMode(fallbackData, appSettings)) {
          data = fallbackData;
        }
      }
      if (data == null) return null;

      final content = data['hitokoto'] as String? ?? '';
      if (content.trim().isEmpty) return null;
      final fromWho = data['from_who'] as String? ?? '';
      final from = data['from'] as String? ?? '';
      final rawLocalId = data['local_quote_id'];
      final sourceNoteId =
          (rawLocalId is String && rawLocalId.isNotEmpty) ? rawLocalId : null;
      final verifiedFp = (fromVerifiedCache || appSettings.useLocalQuotesOnly)
          ? currentFp
          : null;
      final quoteMap = Map<String, dynamic>.from(data);
      if (verifiedFp != null) {
        quoteMap['quote_source_fingerprint'] = verifiedFp;
      }
      return (
        quote: Quote(
          id: sourceNoteId,
          content: content,
          date: _now().toIso8601String(),
          sourceAuthor: fromWho.isNotEmpty ? fromWho : null,
          source: from.isNotEmpty ? from : null,
        ),
        sourceNoteId: sourceNoteId,
        quoteData: quoteMap,
        quoteSourceFingerprint: verifiedFp,
      );
    } catch (e) {
      AppLogger.w('解析预调度每日一言失败', error: e);
      return null;
    }
  }

  /// 检查非 Android 独立每日一言（ID=100）是否已存在与当前时间、一言源配置及本地笔记内容/标签可见性完全匹配的未来待触发项。
  Future<_PreScheduledEntry?>
      _findPreservableStandaloneDailyQuoteEntry() async {
    if (_isAndroid || !_settings.dailyQuotePushEnabled) {
      return null;
    }
    final nowMs = _now().millisecondsSinceEpoch;
    final tracked = _loadTrackedPreScheduledEntries();
    _PreScheduledEntry? existing;
    for (final entry in tracked) {
      if (entry.id == 100 && entry.isDailyQuote && entry.epochMs > nowMs) {
        existing = entry;
        break;
      }
    }
    if (existing == null || existing.dailyQuoteData == null) {
      return null;
    }

    final slot = _settings.dailyQuotePushTime;
    final targetDate = _nextInstanceOfTime(
      slot.hour,
      slot.minute,
      respectsFrequency: false,
    );
    if (existing.epochMs != targetDate.millisecondsSinceEpoch ||
        existing.slotHour != slot.hour ||
        existing.slotMinute != slot.minute) {
      return null;
    }

    final appSettings = _loadStoredAppSettings();
    if (existing.quoteSourceFingerprint == null ||
        existing.quoteSourceFingerprint !=
            _currentDailyQuoteSourceFingerprint(appSettings)) {
      return null;
    }

    final quoteText =
        (existing.dailyQuoteData!['hitokoto'] as String?)?.trim() ?? '';
    if (quoteText.isEmpty) {
      return null;
    }

    final pendingIds = await _queryPendingLocalNotificationIds();
    if (pendingIds == null || !pendingIds.contains(100)) {
      return null;
    }

    final rawLocalId = existing.dailyQuoteData!['local_quote_id'];
    final sourceNoteId = (rawLocalId is String && rawLocalId.isNotEmpty)
        ? rawLocalId
        : existing.noteId;
    final isLocalQuote = existing.dailyQuoteData!['type'] == 'local' ||
        (sourceNoteId != null && sourceNoteId.isNotEmpty);
    if (isLocalQuote) {
      if (sourceNoteId == null || sourceNoteId.isEmpty) {
        return null;
      }
      final isSnapshotCurrent = await _isLocalDailyQuoteSnapshotCurrent(
        sourceNoteId,
        existing.dailyQuoteData!,
        appSettings: appSettings,
        enforceConfiguredOfflineSource: true,
      );
      if (!isSnapshotCurrent) {
        return null;
      }
    } else if (appSettings.useLocalQuotesOnly) {
      if (!_isPermittedDailyQuoteForLocalOnlyMode(
        existing.dailyQuoteData!,
        appSettings,
      )) {
        return null;
      }
      if ((existing.dailyQuoteData!['provider'] as String?)?.trim() ==
          'default') {
        try {
          final nowAvailableLocal = await _databaseService.getLocalDailyQuote(
            offlineQuoteSource: appSettings.offlineQuoteSource,
          );
          if (nowAvailableLocal != null) {
            return null;
          }
        } catch (e) {
          AppLogger.w('检查待发默认每日一言是否可升级为本地笔记失败', error: e);
        }
      }
    }

    return existing;
  }

  /// iOS 单次每日一言（ID=100）在暖启动点击后单独续订下一次触发，
  /// 不受 `handleAppResumed` 同日 6 小时节流限制，也不递增 `_scheduleGeneration` 打断并发常规提醒重排。
  Future<void> _rearmIosDailyQuoteAfterTap({
    int? tappedEpochMs,
    String? previousQuoteContent,
  }) {
    return _enqueueNonInvalidatingScheduleOperation(
      (observedGeneration, observedSettingsGeneration) async {
        try {
          tz.local;
        } catch (_) {
          await _initializeTimezone();
        }
        if (!_isScheduleGenerationCurrent(observedGeneration) ||
            !_isSettingsMutationGenerationCurrent(observedSettingsGeneration)) {
          return;
        }

        await _reloadSharedStorageIfSupported();
        if (!_isScheduleGenerationCurrent(observedGeneration) ||
            !_isSettingsMutationGenerationCurrent(observedSettingsGeneration)) {
          return;
        }
        if (!_isIOS ||
            !_settings.dailyQuotePushEnabled ||
            _areStoredSettingsAllDisabled()) {
          return;
        }

        final expectedEpoch = _readStoredSettingsEpoch();
        final expectedScheduleEpoch = _readStoredScheduleEpoch();

        tz.TZDateTime computeNextIosDailyQuoteDate(PushTimeSlot slot) {
          var candidate = _nextInstanceOfTime(
            slot.hour,
            slot.minute,
            respectsFrequency: false,
          );
          final nowLocal = tz.TZDateTime.from(_now(), tz.local);
          final tappedTodaySlot = tappedEpochMs != null &&
              tappedEpochMs > 0 &&
              (() {
                final tappedLocal = tz.TZDateTime.fromMillisecondsSinceEpoch(
                  tz.local,
                  tappedEpochMs,
                );
                return tappedLocal.year == nowLocal.year &&
                    tappedLocal.month == nowLocal.month &&
                    tappedLocal.day == nowLocal.day;
              })();
          final isSameDayAsNow = candidate.year == nowLocal.year &&
              candidate.month == nowLocal.month &&
              candidate.day == nowLocal.day;
          if (isSameDayAsNow &&
              (tappedTodaySlot || !nowLocal.isBefore(candidate))) {
            candidate = tz.TZDateTime(
              tz.local,
              nowLocal.year,
              nowLocal.month,
              nowLocal.day + 1,
              slot.hour,
              slot.minute,
            );
          }
          return candidate;
        }

        final excludedTrimmed = previousQuoteContent?.trim() ?? '';
        Future<bool> hasValidPendingTarget(
          Set<int>? pendingIds,
          tz.TZDateTime targetDate, {
          required bool isFutureDay,
        }) async {
          if (pendingIds == null || !pendingIds.contains(100)) {
            return false;
          }
          final appSettings = _loadStoredAppSettings();
          final expectedFingerprint =
              _currentDailyQuoteSourceFingerprint(appSettings);
          for (final entry in _loadTrackedPreScheduledEntries()) {
            if (entry.id != 100 ||
                entry.epochMs < targetDate.millisecondsSinceEpoch) {
              continue;
            }
            if (entry.quoteSourceFingerprint == null ||
                entry.quoteSourceFingerprint != expectedFingerprint) {
              continue;
            }
            final data = entry.dailyQuoteData;
            final rawLocalId = data?['local_quote_id'];
            final sourceNoteId = (rawLocalId is String && rawLocalId.isNotEmpty)
                ? rawLocalId
                : entry.noteId;
            final isLocalQuote = data?['type'] == 'local' ||
                (sourceNoteId != null && sourceNoteId.isNotEmpty);
            if (isLocalQuote) {
              if (data == null ||
                  sourceNoteId == null ||
                  sourceNoteId.isEmpty ||
                  !await _isLocalDailyQuoteSnapshotCurrent(
                    sourceNoteId,
                    data,
                    appSettings: appSettings,
                    enforceConfiguredOfflineSource: true,
                  )) {
                continue;
              }
            } else if (appSettings.useLocalQuotesOnly) {
              if (data == null ||
                  !_isPermittedDailyQuoteForLocalOnlyMode(data, appSettings)) {
                continue;
              }
              if ((data['provider'] as String?)?.trim() == 'default') {
                try {
                  final nowAvailableLocal =
                      await _databaseService.getLocalDailyQuote(
                    offlineQuoteSource: appSettings.offlineQuoteSource,
                  );
                  if (nowAvailableLocal != null) {
                    continue;
                  }
                } catch (_) {}
              }
            }
            if (!isFutureDay) {
              return true;
            }
            final existingQuote = (data?['hitokoto'] as String?)?.trim() ?? '';
            final repeatsTapped =
                excludedTrimmed.isNotEmpty && existingQuote == excludedTrimmed;
            if (!repeatsTapped && existingQuote.isNotEmpty) {
              return true;
            }
          }
          return false;
        }

        final initialSlot = _settings.dailyQuotePushTime;
        final previewDate = computeNextIosDailyQuoteDate(initialSlot);
        final nowLocalForCache = tz.TZDateTime.from(_now(), tz.local);
        final isFutureCalendarDay = previewDate.year != nowLocalForCache.year ||
            previewDate.month != nowLocalForCache.month ||
            previewDate.day != nowLocalForCache.day;

        final initialPendingIds = await _queryPendingLocalNotificationIds();
        if (!_isSettingsMutationGenerationCurrent(observedSettingsGeneration)) {
          return;
        }
        if (await hasValidPendingTarget(
          initialPendingIds,
          previewDate,
          isFutureDay: isFutureCalendarDay,
        )) {
          return;
        }

        final resolved = await _resolveStandaloneDailyQuote(
          excludeQuoteContent: previousQuoteContent,
          updateTodayCache: !isFutureCalendarDay,
        );
        if (!_isSettingsMutationGenerationCurrent(observedSettingsGeneration) ||
            !await _isScheduleContextStillValid(
              generation: observedGeneration,
              expectedEpoch: expectedEpoch,
              expectedScheduleEpoch: expectedScheduleEpoch,
              fromBackground: false,
            )) {
          return;
        }
        final precomputedContent = resolved != null
            ? _PushContent(
                title: '📖 每日一言',
                body: _buildNotificationBody(resolved.quote),
                noteId: null,
                sourceNoteId: resolved.sourceNoteId,
                contentType: 'dailyQuote',
                dailyQuoteData: resolved.quoteData,
                quoteSourceFingerprint: resolved.quoteSourceFingerprint,
              )
            : null;

        await _withScheduleCommitLock(() async {
          if (!_isSettingsMutationGenerationCurrent(
                observedSettingsGeneration,
              ) ||
              !await _isScheduleContextStillValid(
                generation: observedGeneration,
                expectedEpoch: expectedEpoch,
                expectedScheduleEpoch: expectedScheduleEpoch,
                fromBackground: false,
                reloadStorage: true,
              )) {
            return;
          }
          if (!_settings.dailyQuotePushEnabled) {
            return;
          }

          final slot = _settings.dailyQuotePushTime;
          final scheduledDate = computeNextIosDailyQuoteDate(slot);
          final nowInLock = tz.TZDateTime.from(_now(), tz.local);
          final futureDayInLock = scheduledDate.year != nowInLock.year ||
              scheduledDate.month != nowInLock.month ||
              scheduledDate.day != nowInLock.day;
          final pendingIds = await _queryPendingLocalNotificationIds();
          if (await hasValidPendingTarget(
            pendingIds,
            scheduledDate,
            isFutureDay: futureDayInLock,
          )) {
            return;
          }

          await _scheduleLocalNotification(
            100,
            scheduledDate,
            slot,
            isDailyQuote: true,
            precomputedContent: precomputedContent,
            allowContentLookup: false,
          );
        });
      },
    );
  }

  /// 非 Android 单条独立每日一言调度解析：遵循用户一言源配置（仅本地或在线提供商，离线时回退本地）
  Future<
      ({
        Quote quote,
        String? sourceNoteId,
        Map<String, dynamic> quoteData,
        String? quoteSourceFingerprint,
      })?> _resolveStandaloneDailyQuote({
    String? excludeQuoteContent,
    bool updateTodayCache = true,
  }) async {
    try {
      final appSettings = _loadStoredAppSettings();
      final currentFp = _currentDailyQuoteSourceFingerprint(appSettings);
      final excluded = excludeQuoteContent?.trim() ?? '';
      bool isExcludedContent(String candidate) {
        final trimmed = candidate.trim();
        if (trimmed.isEmpty) return false;
        if (excluded.isNotEmpty && trimmed == excluded) return true;
        return _hasDailyQuoteContentPushed(trimmed);
      }

      ({
        Quote quote,
        String? sourceNoteId,
        Map<String, dynamic> quoteData,
        String? quoteSourceFingerprint,
      })? buildResolvedFromMap(
        Map<String, dynamic> map, {
        required bool verifiedForCurrentSettings,
      }) {
        final content = (map['hitokoto'] as String?)?.trim() ?? '';
        if (content.isEmpty) return null;
        final fromWho = (map['from_who'] as String?)?.trim() ?? '';
        final from = (map['from'] as String?)?.trim() ?? '';
        final rawLocalId = map['local_quote_id'];
        final sourceNoteId =
            (rawLocalId is String && rawLocalId.isNotEmpty) ? rawLocalId : null;
        final fp = verifiedForCurrentSettings ? currentFp : null;
        final copied = Map<String, dynamic>.from(map);
        if (fp != null) {
          copied['quote_source_fingerprint'] = fp;
        }
        return (
          quote: Quote(
            id: sourceNoteId,
            content: content,
            date: _now().toIso8601String(),
            sourceAuthor: fromWho.isNotEmpty ? fromWho : null,
            source: from.isNotEmpty ? from : null,
          ),
          sourceNoteId: sourceNoteId,
          quoteData: copied,
          quoteSourceFingerprint: fp,
        );
      }

      if (appSettings.useLocalQuotesOnly) {
        final localPrimary = await _resolvePreScheduleDailyQuote();
        if (localPrimary != null &&
            !isExcludedContent(localPrimary.quote.content)) {
          if (updateTodayCache) {
            _saveDailyQuoteToCache(localPrimary.quoteData);
          }
          return localPrimary;
        }
        final retryLocal = await _loadDailyQuoteData(
          preferCache: false,
          updateTodayCache: updateTodayCache,
        );
        if (retryLocal != null &&
            _isPermittedDailyQuoteForLocalOnlyMode(retryLocal, appSettings)) {
          final built = buildResolvedFromMap(
            retryLocal,
            verifiedForCurrentSettings: true,
          );
          if (built != null) return built;
        }
        if (localPrimary != null && updateTodayCache) {
          _saveDailyQuoteToCache(localPrimary.quoteData);
        }
        return localPrimary;
      }

      final cachedToday = await getCachedDailyQuoteForToday();
      final cachedFallback = cachedToday != null
          ? buildResolvedFromMap(
              cachedToday,
              verifiedForCurrentSettings:
                  _doesDailyQuoteMatchAppSettings(cachedToday, appSettings),
            )
          : null;
      if (cachedFallback != null &&
          !isExcludedContent(cachedFallback.quote.content)) {
        return cachedFallback;
      }

      var data = await _loadDailyQuoteData(
        preferCache: false,
        updateTodayCache: updateTodayCache,
      );
      if (data != null) {
        final firstContent = (data['hitokoto'] as String?)?.trim() ?? '';
        if (firstContent.isNotEmpty && isExcludedContent(firstContent)) {
          final secondAttempt = await _loadDailyQuoteData(
            preferCache: false,
            updateTodayCache: updateTodayCache,
          );
          if (secondAttempt != null) {
            data = secondAttempt;
          }
        }
      }

      if (data != null) {
        final type = (data['type'] as String?)?.trim() ?? '';
        final provider = (data['provider'] as String?)?.trim() ?? '';
        if (type != 'offline' &&
            type != 'local-empty' &&
            provider != 'offline') {
          final verifiedOnline = type != 'local' &&
              _doesDailyQuoteMatchAppSettings(data, appSettings);
          final built = buildResolvedFromMap(
            data,
            verifiedForCurrentSettings: verifiedOnline,
          );
          if (built != null) {
            return built;
          }
        }
      }

      return cachedFallback ?? await _resolvePreScheduleDailyQuote();
    } catch (e) {
      AppLogger.w('解析独立每日一言失败', error: e);
      return null;
    }
  }
}
