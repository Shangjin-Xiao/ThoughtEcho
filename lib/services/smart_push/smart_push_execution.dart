part of '../smart_push_service.dart';

/// 推送执行 — checkAndPush、performSmartPush、performDailyQuotePush
extension SmartPushExecution on SmartPushService {
  /// 检查并触发推送（核心逻辑）
  ///
  /// [triggerKind] 标识触发来源：
  /// - 'dailyQuote': 由每日一言闹钟/任务触发
  /// - 'smartPush': 由智能推送闹钟/任务触发
  /// - null: 来源未知（周期性检查或前台手动调用），使用时间推断
  Future<void> checkAndPush({
    bool isBackground = false,
    String? triggerKind,
  }) async {
    final now = DateTime.now();
    AppLogger.i(
      '开始检查推送条件 (isBackground: $isBackground, triggerKind: $triggerKind, time: ${now.hour}:${now.minute})',
    );

    // 如果是前台手动调用（非后台），默认执行智能推送检查
    if (!isBackground) {
      AppLogger.d('前台手动触发，检查智能推送是否启用');
      if (_settings.enabled) {
        AppLogger.i('执行前台智能推送...');
        await _performSmartPush();
      } else {
        AppLogger.w('智能推送未启用，忽略前台触发');
      }
      return;
    }

    // 后台逻辑：由 AlarmManager/WorkManager 触发
    AppLogger.w(
      '后台推送触发 (triggerKind: $triggerKind, time: ${now.hour}:${now.minute})',
    );

    // 智能模式防重复：距上次推送不足 30 分钟则跳过（同一时间段只推一条）
    // 自定义模式不做此限制，用户自己控制推送时间间隔
    if (_settings.pushMode == PushMode.smart &&
        _settings.lastPushTime != null) {
      final sinceLastPush = now.difference(_settings.lastPushTime!);
      if (sinceLastPush.inMinutes < 30) {
        AppLogger.i('智能推送跳过：距上次推送仅 ${sinceLastPush.inMinutes} 分钟（需间隔 30 分钟）');
        return;
      }
    }

    // 根据 triggerKind 精确路由
    if (triggerKind == 'dailyQuote') {
      // 明确由每日一言闹钟触发
      if (_settings.dailyQuotePushEnabled) {
        AppLogger.w('后台触发每日一言推送 (triggerKind: dailyQuote)');
        await _performDailyQuotePush(isBackground: true);
      } else {
        AppLogger.d('每日一言推送已禁用，忽略 dailyQuote 触发');
      }
    } else if (triggerKind == 'smartPush') {
      // 明确由智能推送闹钟触发
      if (_settings.enabled && _settings.shouldPushToday()) {
        AppLogger.w('后台触发智能推送 (triggerKind: smartPush)');
        await _performSmartPush(isBackground: true);
      } else {
        AppLogger.d('智能推送未启用或今日不活跃，忽略 smartPush 触发');
      }
    } else {
      // triggerKind 未知（周期性检查等），使用时间推断（保守窗口 ±10 分钟）
      AppLogger.d('triggerKind 未知，使用时间推断路由');

      bool handled = false;

      // 尝试每日一言推送
      if (_settings.dailyQuotePushEnabled) {
        final slot = _settings.dailyQuotePushTime;
        if (SmartPushService.isWithinPushWindow(now, slot)) {
          final diff = now
              .difference(DateTime(
                now.year,
                now.month,
                now.day,
                slot.hour,
                slot.minute,
              ))
              .inMinutes;
          AppLogger.w('时间推断：触发每日一言推送 (已到设定时间后 $diff 分钟)');
          await _performDailyQuotePush(isBackground: true);
          handled = true;
        }
      }

      // 尝试常规智能推送（即使已推送每日一言，也允许智能推送，避免遗漏）
      if (!handled && _settings.enabled && _settings.shouldPushToday()) {
        final scheduledSlots = getScheduledTimesForToday();
        final slotsToCheck = scheduledSlots.isNotEmpty
            ? scheduledSlots
            : _settings.pushTimeSlots.where((slot) => slot.enabled).toList();

        if (SmartPushService.isWithinAnyPushWindow(now, slotsToCheck)) {
          AppLogger.w('时间推断：触发智能推送');
          await _performSmartPush(isBackground: true);
        } else {
          AppLogger.d('时间推断：当前不在智能推送时间窗口内');
        }
      }
    }

    AppLogger.i('推送条件检查结束');
  }

  /// 手动触发推送（用于测试，绕过 enabled 检查）
  Future<void> triggerPush() async {
    // 测试时强制执行一次智能推送
    await _performSmartPush(isTest: true);
  }

  /// 执行每日一言推送
  ///
  /// 独立的每日一言推送通道，允许一天多次推送但不重复推送相同内容。
  Future<void> _performDailyQuotePush({bool isBackground = false}) async {
    try {
      // 每日一言是用户期望的每日固定内容，不受 SOTA 疲劳预防系统限制。
      // 允许一天多次推送，但使用内容哈希去重避免推送相同一言。
      final dailyQuote = await _fetchDailyQuote();
      if (dailyQuote == null) {
        AppLogger.w('每日一言推送：获取内容失败');
        return;
      }

      // 检查是否已推送过相同内容
      if (_hasDailyQuoteContentPushed(dailyQuote.content)) {
        AppLogger.i('每日一言推送：该内容已推送过，跳过 '
            '("${dailyQuote.content.substring(0, min(30, dailyQuote.content.length))}...")');
        return;
      }

      await _showNotification(
        dailyQuote,
        title: '📖 每日一言',
        contentType: 'dailyQuote',
      );

      // 记录已推送的内容哈希，防止重复
      _markDailyQuoteContentPushed(dailyQuote.content);

      // 更新 lastPushTime，让 3 分钟防重复机制对后续推送生效
      final updatedSettings = _settings.copyWith(
        lastPushTime: DateTime.now(),
      );
      await _saveSettingsQuietly(updatedSettings);

      // 记录推送效果（不消费疲劳预算，每日一言不参与疲劳系统）
      await _analytics.updateContentScore('dailyQuote', false);

      AppLogger.i('每日一言推送成功');

      // 重新调度
      if (!isBackground) {
        await scheduleNextPush();
      }
    } catch (e, stack) {
      AppLogger.e('每日一言推送失败', error: e, stackTrace: stack);
    }
  }

  /// 执行智能推送的核心逻辑 (SOTA v2)
  ///
  /// 增强功能：
  /// - 疲劳预防检查（虚拟预算 + 冷却期）
  /// - Thompson Sampling 内容选择
  /// - 推送效果追踪
  Future<void> _performSmartPush({
    bool isTest = false,
    bool isBackground = false,
  }) async {
    try {
      // 测试模式不检查 enabled 和频率
      if (!isTest) {
        if (!_settings.enabled) return;
        if (!_settings.shouldPushToday()) {
          AppLogger.d('根据频率设置，今天不推送');
          return;
        }

        // SOTA: 疲劳预防检查
        // 使用 'monthAgoToday'（成本 2.5）作为预检类型，这是智能推送中
        // 较高成本的内容类型，确保预算检查保守一致。
        // 实际内容类型在内容选择后确定，用于 consumeBudget。
        final preCheckType = _settings.pushMode == PushMode.dailyQuote
            ? 'dailyQuote'
            : 'monthAgoToday';
        final smartSkipReason = await _analytics.getSkipReason(preCheckType);
        if (smartSkipReason != null) {
          AppLogger.w('智能推送被跳过: $smartSkipReason');
          // 仍然重新调度下次推送
          if (!isBackground) {
            await scheduleNextPush();
          }
          return;
        }
      }

      // 根据推送模式获取内容
      Quote? noteToShow;
      String title = '💭 心迹';
      bool isDailyQuote = false;
      String contentType = 'dailyQuote';

      AppLogger.w('执行智能推送，模式: ${_settings.pushMode.name}');

      switch (_settings.pushMode) {
        case PushMode.smart:
          // 智能模式：使用 SOTA 智能算法选择最佳内容（笔记优先）
          final result = await _smartSelectContent();
          noteToShow = result.note;
          title = result.title;
          isDailyQuote = result.isDailyQuote;
          contentType = result.contentType;
          break;

        case PushMode.dailyQuote:
          // 推送模式选了"仅每日一言" — 与独立每日一言推送是两条通道
          final dailyQuote = await _fetchDailyQuote();
          if (dailyQuote != null) {
            if (!_hasDailyQuoteContentPushed(dailyQuote.content)) {
              noteToShow = dailyQuote;
              title = '📖 每日一言';
              isDailyQuote = true;
              contentType = 'dailyQuote';
            } else {
              AppLogger.i('PushMode.dailyQuote：该内容已推送过，跳过');
            }
          }
          break;

        case PushMode.pastNotes:
          // 仅推送过去的笔记
          final typedCandidates = await getTypedCandidateNotes();
          AppLogger.i('PushMode.pastNotes：候选笔记数 ${typedCandidates.length}');
          if (typedCandidates.isNotEmpty) {
            final candidate = typedCandidates.first;
            noteToShow = candidate.note;
            title = candidate.title;
            contentType = candidate.contentType;
          }
          break;

        case PushMode.both:
          // 两者都推送：优先尝试笔记，无笔记时回退每日一言
          final candidates = await getCandidateNotes();
          if (candidates.isNotEmpty && _random.nextBool()) {
            noteToShow = _selectUnpushedNote(candidates);
            if (noteToShow != null) {
              title = _generateTitle(noteToShow);
              contentType = 'pastNote';
            }
          }
          if (noteToShow == null) {
            final dailyQuote = await _fetchDailyQuote();
            if (dailyQuote != null &&
                !_hasDailyQuoteContentPushed(dailyQuote.content)) {
              noteToShow = dailyQuote;
              title = '📖 每日一言';
              isDailyQuote = true;
              contentType = 'dailyQuote';
            }
          }
          break;

        case PushMode.custom:
          // 自定义模式：根据用户选择的类型获取内容
          final typedCandidates = await getTypedCandidateNotes();
          AppLogger.i('PushMode.custom：候选笔记数 ${typedCandidates.length}');
          if (typedCandidates.isNotEmpty) {
            final candidate = typedCandidates.first;
            noteToShow = candidate.note;
            title = candidate.title;
            contentType = candidate.contentType;
          }
          // 自定义模式不主动回退到每日一言 — 用户选了自定义就只推自定义内容
          break;
      }

      if (noteToShow != null) {
        await _showNotification(
          noteToShow,
          title: title,
          contentType: contentType,
        );

        // ==== 向树莓派 Pico 发送蓝牙广播 ====
        try {
          // 不阻塞推送主流程，火忘式发送
          unawaited(
            PicoBleService.instance.sendQuoteToPico(noteToShow).catchError(
              (e) {
                AppLogger.w('蓝牙发送到水墨屏异步失败', error: e);
                return false;
              },
            ),
          );
        } catch (bleErr) {
          AppLogger.w('蓝牙发送到水墨屏失败', error: bleErr);
        }
        // ===================================

        AppLogger.w(
          '推送成功 [${_settings.pushMode.name}] (contentType: $contentType): '
          '${noteToShow.content.substring(0, min(50, noteToShow.content.length))}...',
        );

        // 标记今日已推送（用于「此时此刻」兜底判断）
        if (!isTest) {
          _markPushedToday();
        }

        // 记录推送历史（避免重复推送，测试模式也不记录）
        if (!isDailyQuote && noteToShow.id != null && !isTest) {
          final updatedSettings = _settings.addPushedNoteId(noteToShow.id!);
          await _saveSettingsQuietly(updatedSettings);
        }

        // 如果推送的是每日一言（来自 PushMode.dailyQuote / PushMode.both 的回退 / PushMode.smart），
        // 标记内容哈希并更新 lastPushTime，同时标记今日智能推送已推每日一言
        if (isDailyQuote && !isTest) {
          _markDailyQuoteContentPushed(noteToShow.content);
          _markDailyQuotePushedTodayInSmartPush();
          final updatedSettings = _settings.copyWith(
            lastPushTime: DateTime.now(),
          );
          await _saveSettingsQuietly(updatedSettings);
        }

        // SOTA: 消费疲劳预算并记录推送（用于效果追踪）
        if (!isTest && contentType.isNotEmpty) {
          await _analytics.consumeBudget(contentType);
          await _analytics.updateContentScore(contentType, false);
        }

        AppLogger.i(
          '推送成功 [${_settings.pushMode.name}]: '
          '${noteToShow.content.substring(0, min(50, noteToShow.content.length))}...',
        );
      } else {
        AppLogger.w('智能推送：没有内容可推送 (模式: ${_settings.pushMode.name})');
      }

      // 7天无新笔记额外触发一次每日一言（与每日一言独立开关无关）
      if (!isTest) {
        await _checkAndPushInactivityQuote(isBackground: isBackground);
      }

      // 重新调度下一次推送
      if (!isBackground && !isTest) {
        await scheduleNextPush();
      }
    } catch (e, stack) {
      AppLogger.e('智能推送失败', error: e, stackTrace: stack);
      if (isTest) rethrow; // 测试模式抛出异常以便 UI 显示错误
    }
  }

  /// 检查是否满足「7天无新笔记」条件，满足则额外推送一次每日一言。
  ///
  /// 使用 [_inactivityQuoteDateKey] MMKV 键记录当天是否已因此触发，
  /// 避免同一天重复推送。
  /// [isBackground] 透传给 _performDailyQuotePush，防止产生额外的 scheduleNextPush。
  Future<void> _checkAndPushInactivityQuote({
    bool isBackground = false,
  }) async {
    try {
      final today = DateTime.now().toIso8601String().substring(0, 10);
      final lastTriggered =
          _mmkv.getString(SmartPushService._inactivityQuoteDateKey);
      if (lastTriggered == today) {
        // 今天已经因无新笔记触发过一言，跳过
        return;
      }

      // 查询最近一条笔记的创建时间
      final recentNotes =
          await _databaseService.getQuotesForSmartPush(limit: 1);
      if (recentNotes.isEmpty) return;
      final recentNote = recentNotes.first;

      final noteDate = DateTime.tryParse(recentNote.date);
      if (noteDate == null) return;

      final daysSinceLastNote = DateTime.now().difference(noteDate).inDays;
      if (daysSinceLastNote < 7) return;

      AppLogger.i('7天无新笔记（最近笔记: ${recentNote.date}），额外推送每日一言');
      _mmkv.setString(SmartPushService._inactivityQuoteDateKey, today);
      await _performDailyQuotePush(isBackground: isBackground);
    } catch (e) {
      AppLogger.w('_checkAndPushInactivityQuote 失败', error: e);
    }
  }
}
