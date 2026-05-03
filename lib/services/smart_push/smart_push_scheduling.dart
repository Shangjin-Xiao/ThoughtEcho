part of '../smart_push_service.dart';

/// 推送调度 — 时间计算、计划编排、持久化
extension SmartPushScheduling on SmartPushService {
  /// 规划下一次推送
  ///
  /// [fromBackground] 为 true 时，仅取消 AlarmManager 定时器并重新调度，
  /// 不调用 cancelAll() 以避免清除正在显示或即将显示的通知。
  Future<void> scheduleNextPush({bool fromBackground = false}) async {
    // 只有当两个推送都关闭时才取消所有计划并返回
    if (!_settings.enabled && !_settings.dailyQuotePushEnabled) {
      await _cancelAllSchedules();
      return;
    }

    if (fromBackground) {
      // 后台只取消 AlarmManager 定时器，不取消本地通知
      if (PlatformHelper.isAndroid) {
        for (int i = 0; i < 10; i++) {
          await AndroidAlarmManager.cancel(
            SmartPushService._androidAlarmId + i,
          );
        }
        await AndroidAlarmManager.cancel(SmartPushService._dailyQuoteAlarmId);
      }
      AppLogger.d('后台重新调度：仅取消 AlarmManager 定时器');
    } else {
      await _cancelAllSchedules();
      AppLogger.d('已取消现有推送计划，准备重新规划');
    }

    // 1. 规划常规推送 (仅当 enabled 为 true 时)
    if (_settings.enabled) {
      List<PushTimeSlot> slotsToSchedule;

      if (_settings.pushMode == PushMode.smart) {
        // 智能模式：使用智能算法计算最佳推送时间
        slotsToSchedule = await _calculateSmartPushTimes();
        // 智能模式下合并相近的时间槽（间隔小于 30 分钟的只保留第一个）
        // 这是防止同一时间段推送多条的核心机制
        slotsToSchedule = _mergeCloseTimeSlots(slotsToSchedule);
        AppLogger.i(
          '智能推送时间: ${slotsToSchedule.map((s) => s.formattedTime).join(", ")}',
        );
      } else {
        // 自定义模式：使用用户设置的时间，不做合并
        slotsToSchedule = _settings.pushTimeSlots
            .where((s) => s.enabled)
            .toList();
      }

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

      if (PlatformHelper.isAndroid) {
        // 先检查精确闹钟权限
        final canScheduleExact = await _canScheduleExactAlarms();

        if (canScheduleExact) {
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
            AppLogger.e('设定每日一言 Alarm 失败', error: e);
            // 降级到 WorkManager + 本地通知
            await _scheduleDailyQuoteWorkManagerFallback(scheduledDate, slot);
          }
        } else {
          AppLogger.w('精确闹钟权限被拒绝，每日一言使用 WorkManager 降级方案');
          await _scheduleDailyQuoteWorkManagerFallback(scheduledDate, slot);
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
  }

  /// 每日一言 WorkManager 降级方案
  Future<void> _scheduleDailyQuoteWorkManagerFallback(
    tz.TZDateTime scheduledDate,
    PushTimeSlot slot,
  ) async {
    try {
      final now = DateTime.now();
      final delay = scheduledDate.difference(now);

      await Workmanager().registerOneOffTask(
        'daily_quote_fallback',
        kBackgroundPushTask,
        initialDelay: delay > Duration.zero ? delay : Duration.zero,
        inputData: {'triggerKind': 'dailyQuote'},
        existingWorkPolicy: ExistingWorkPolicy.replace,
      );
      AppLogger.i('已使用 WorkManager 调度每日一言: 延迟 ${delay.inMinutes} 分钟');
    } catch (e) {
      AppLogger.w('每日一言 WorkManager 降级失败', error: e);
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
    final hourDistribution = await _databaseService
        .getHourDistributionForSmartPush();

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
      AppLogger.i('时间槽合并：${slots.length} → ${merged.length} 个（间隔 <30 分钟的已合并）');
    }

    return merged;
  }

  /// 持久化今日实际调度的推送时间（供后台周期性检查使用）
  Future<void> _persistScheduledTimes(List<PushTimeSlot> slots) async {
    final today = DateTime.now().toIso8601String().substring(0, 10);
    final timesStr = slots.map((s) => '${s.hour}:${s.minute}').join(',');
    await _mmkv.setString(
      SmartPushService._scheduledTimesKey,
      '$today|$timesStr',
    );
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
    final now = tz.TZDateTime.now(tz.local);
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

  /// 预计算推送内容
  Future<_PushContent?> _getPrecomputedContent() async {
    try {
      final candidates = await getTypedCandidateNotes();
      if (candidates.isNotEmpty) {
        final candidate = candidates.first;
        final note = candidate.note;
        return _PushContent(
          title: candidate.title,
          body: _truncateContent(note.content),
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
}
