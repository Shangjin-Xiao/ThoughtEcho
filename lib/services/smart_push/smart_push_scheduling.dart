part of '../smart_push_service.dart';

/// 推送调度 — 时间计算、计划编排、持久化
extension SmartPushScheduling on SmartPushService {
  /// 规划下一次推送
  ///
  /// [fromBackground] 为 true 时，仅取消 AlarmManager 定时器并重新调度，
  /// 不调用 cancelAll() 以避免清除正在显示或即将显示的通知。
  /// [preserveDeliveredNotifications] 为 true 时，保留系统通知栏中已送达的通知。
  Future<void> scheduleNextPush({
    bool fromBackground = false,
    bool preserveDeliveredNotifications = false,
  }) async {
    try {
      tz.local;
    } catch (_) {
      await _initializeTimezone();
    }

    // 只有当两个推送都关闭时才取消所有计划并返回
    if (!_settings.enabled && !_settings.dailyQuotePushEnabled) {
      await _cancelAllSchedules();
      _lastScheduleRefreshAt = _now();
      return;
    }

    final canScheduleExact =
        _isAndroid ? await _canScheduleExactAlarms() : true;
    final useAndroidPreSchedule =
        await _shouldUseAndroidPreScheduledNotifications(
      canScheduleExact: canScheduleExact,
    );

    if (useAndroidPreSchedule) {
      await _scheduleAndroidPreScheduledQueue(
        canScheduleExact: canScheduleExact,
        fromBackground: fromBackground,
        preserveDeliveredNotifications: preserveDeliveredNotifications,
      );
      _lastScheduleRefreshAt = _now();
      _lastScheduledExactAlarmGranted = canScheduleExact;
      return;
    }

    // 非预调度模式（如标准渠道且拥有精确闹钟权限）：清理可能遗留的预调度本地通知
    await _reconcileTrackedPreScheduledNotifications(
      activeIds: const {},
      futureOnly: fromBackground || preserveDeliveredNotifications,
    );
    await _saveTrackedPreScheduledEntries(const []);

    if (fromBackground || preserveDeliveredNotifications) {
      // 后台或保留已送达通知场景：只取消 AlarmManager 定时器，不调用 cancelAll
      if (_isAndroid) {
        await _cancelAndroidBackgroundTasks();
      }
      AppLogger.d('重新调度：仅重置后台定时器');
    } else {
      await _cancelAllSchedules();
      AppLogger.d('已取消现有推送计划，准备重新规划');
    }

    // 1. 规划常规推送 (仅当 enabled 为 true 时)
    if (_settings.enabled) {
      final slotsToSchedule = await _resolveRegularSlotsToSchedule();

      // 持久化今日实际调度的时间（供后台周期性检查使用）
      await _persistScheduledTimes(slotsToSchedule);

      for (int i = 0; i < slotsToSchedule.length; i++) {
        final slot = slotsToSchedule[i];
        final scheduledDate = _nextInstanceOfTime(slot.hour, slot.minute);
        final id = i; // 0-9

        await _scheduleSingleAlarm(id, scheduledDate, slot);
      }
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

    _lastScheduleRefreshAt = _now();
    _lastScheduledExactAlarmGranted = canScheduleExact;
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
    required bool canScheduleExact,
    required bool fromBackground,
    required bool preserveDeliveredNotifications,
  }) async {
    await _cancelAndroidBackgroundTasks();

    final plannedItems = <_PlannedLocalNotification>[];

    // 1. 常规回顾提醒槽位（未来 3 个有效推送日）
    if (_settings.enabled) {
      final slotsToSchedule = await _resolveRegularSlotsToSchedule();
      await _persistScheduledTimes(slotsToSchedule);

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

      final precomputedContents = await _buildPrecomputedRegularContents(
        rawRegularSlots.map((item) => item.date).toList(),
      );

      for (int idx = 0; idx < rawRegularSlots.length; idx++) {
        final item = rawRegularSlots[idx];
        final id = SmartPushService.deterministicPreScheduledNotificationId(
          item.date,
          slotIndex: item.slotIndex,
        );
        plannedItems.add(
          _PlannedLocalNotification(
            id: id,
            slotIndex: item.slotIndex,
            slot: item.slot,
            scheduledDate: item.date,
            isDailyQuote: false,
            content: idx < precomputedContents.length
                ? precomputedContents[idx]
                : null,
          ),
        );
      }
    } else {
      await _persistScheduledTimes(const []);
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
        final quote = await _resolvePreScheduleDailyQuote();
        if (quote != null) {
          dailyContent = _PushContent(
            title: '📖 每日一言',
            body: _buildNotificationBody(quote),
            noteId: null,
            contentType: 'dailyQuote',
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

    // 3. 对账并清理已移除/禁用的旧预调度通知
    final activeIds = plannedItems.map((e) => e.id).toSet();
    await _reconcileTrackedPreScheduledNotifications(
      activeIds: activeIds,
      futureOnly: fromBackground || preserveDeliveredNotifications,
    );

    // 4. 逐条写入/更新系统本地通知队列（确定性 ID 原位覆盖，不产生重复通知）
    for (final item in plannedItems) {
      await _scheduleLocalNotification(
        item.id,
        item.scheduledDate,
        item.slot,
        isDailyQuote: item.isDailyQuote,
        precomputedContent: item.content,
        canScheduleExactOverride: canScheduleExact,
      );
    }

    await _saveTrackedPreScheduledEntries(
      plannedItems
          .map(
            (e) => _PreScheduledEntry(
              id: e.id,
              epochMs: e.scheduledDate.millisecondsSinceEpoch,
            ),
          )
          .toList(),
    );
  }

  /// 智能推送时间计算算法 (SOTA v2)
  ///
  /// 策略升级：
  /// 1. 优先使用用户 App 打开时间的响应性热图（比笔记创建时间更准确）
  /// 2. 结合笔记创建时间避开创作高峰
  /// 3. 应用 Thompson Sampling 的时间窗口探索
  /// 4. 周末/节假日自动调整
  Future<List<PushTimeSlot>> _calculateSmartPushTimes() async {
    final now = DateTime.now();

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

  /// 批量为多个预调度时间点准备回顾内容（单次查库，尽量避免多日内容重复）
  Future<List<_PushContent?>> _buildPrecomputedRegularContents(
    List<tz.TZDateTime> scheduledDates,
  ) async {
    if (scheduledDates.isEmpty) return const [];

    try {
      final allNotes = await _databaseService.getQuotesForSmartPush(
        limit: 5000,
      );
      if (allNotes.isEmpty) {
        if (_settings.pushMode != PushMode.custom) {
          final quote = await _resolvePreScheduleDailyQuote();
          if (quote != null) {
            final fallback = _PushContent(
              title: '📖 每日一言',
              body: _buildNotificationBody(quote),
              noteId: null,
              contentType: 'dailyQuote',
            );
            return List<_PushContent?>.filled(scheduledDates.length, fallback);
          }
        }
        return List<_PushContent?>.filled(scheduledDates.length, null);
      }

      final currentLocation = await _loadCurrentLocationForMatching();
      final currentWeather = _loadCurrentWeatherForMatching();
      final isSmartMode = _settings.pushMode == PushMode.smart;
      final enabledTypes = isSmartMode
          ? PastNoteType.values.toSet()
          : _settings.enabledPastNoteTypes;
      final requiredTagIds =
          isSmartMode ? const <String>[] : _settings.filterTagIds;
      final weatherFilters = isSmartMode
          ? const <WeatherFilterType>{}
          : _settings.filterWeatherTypes;

      final assignedIds = <String>{..._settings.recentlyPushedNoteIds};
      final results = <_PushContent?>[];

      for (final scheduledDate in scheduledDates) {
        var candidates = buildTypedCandidates(
          notes: allNotes,
          now: scheduledDate,
          enabledPastNoteTypes: enabledTypes,
          recentPushedIds: assignedIds,
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
          if (note.id != null && note.id!.isNotEmpty) {
            assignedIds.add(note.id!);
          }
          results.add(
            _PushContent(
              title: chosen.title,
              body: _buildNotificationBody(note),
              noteId: note.id,
              contentType: chosen.contentType,
            ),
          );
        } else {
          Quote? fallbackNote;
          String fallbackTitle = '💡 漫步旧时光';
          String fallbackType = 'randomMemory';

          List<Quote> applyTagFilter(List<Quote> source) {
            if (requiredTagIds.isEmpty) return source;
            return source
                .where((n) => n.tagIds.any(requiredTagIds.contains))
                .toList();
          }

          if (isSmartMode || enabledTypes.contains(PastNoteType.randomMemory)) {
            final randomPool = applyTagFilter(
              filterRandomMemory(allNotes, scheduledDate, _random),
            );
            fallbackNote = selectUnpushedNote(randomPool, assignedIds, _random);
          }

          if (fallbackNote == null && isSmartMode) {
            final sameTimePool = applyTagFilter(
              filterSameTimeOfDay(allNotes, scheduledDate),
            );
            fallbackNote = selectUnpushedNote(
              sameTimePool,
              assignedIds,
              _random,
            );
            if (fallbackNote != null) {
              fallbackTitle = '⏰ 往日此时';
              fallbackType = 'sameTimeOfDay';
            }
          }

          if (fallbackNote != null) {
            if (fallbackNote.id != null && fallbackNote.id!.isNotEmpty) {
              assignedIds.add(fallbackNote.id!);
            }
            results.add(
              _PushContent(
                title: fallbackTitle,
                body: _buildNotificationBody(fallbackNote),
                noteId: fallbackNote.id,
                contentType: fallbackType,
              ),
            );
          } else if (isSmartMode) {
            final dailyQuote = await _resolvePreScheduleDailyQuote();
            results.add(
              dailyQuote != null
                  ? _PushContent(
                      title: '📖 每日一言',
                      body: _buildNotificationBody(dailyQuote),
                      noteId: null,
                      contentType: 'dailyQuote',
                    )
                  : null,
            );
          } else {
            results.add(null);
          }
        }
      }

      return results;
    } catch (e) {
      AppLogger.w('批量预计算推送内容失败', error: e);
      return List<_PushContent?>.filled(scheduledDates.length, null);
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
          contentType: candidate.contentType,
        );
      }
      return null;
    } catch (e) {
      AppLogger.w('预计算推送内容失败', error: e);
      return null;
    }
  }

  /// 预调度专用的本地一言解析：仅读取本地缓存或本地数据库，绝不在保存设置/启动恢复时发起外网请求阻塞 UI
  Future<Quote?> _resolvePreScheduleDailyQuote() async {
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
      return Quote(
        content: content,
        date: _now().toIso8601String(),
        sourceAuthor: fromWho.isNotEmpty ? fromWho : null,
        source: from.isNotEmpty ? from : null,
      );
    } catch (e) {
      AppLogger.w('解析预调度每日一言失败', error: e);
      return null;
    }
  }
}
