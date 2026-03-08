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

    // 防重复：距上次推送不足 3 分钟则跳过
    if (_settings.lastPushTime != null) {
      final sinceLastPush = now.difference(_settings.lastPushTime!);
      if (sinceLastPush.inMinutes < 3) {
        AppLogger.i('跳过推送：距上次推送仅 ${sinceLastPush.inSeconds} 秒');
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
        final slotTime = DateTime(
          now.year,
          now.month,
          now.day,
          slot.hour,
          slot.minute,
        );
        final diff = now.difference(slotTime).inMinutes.abs();

        if (diff <= 10) {
          AppLogger.w('时间推断：触发每日一言推送 (距设定时间 $diff 分钟)');
          await _performDailyQuotePush(isBackground: true);
          handled = true;
        }
      }

      // 尝试常规智能推送（即使已推送每日一言，也允许智能推送，避免遗漏）
      if (!handled && _settings.enabled && _settings.shouldPushToday()) {
        AppLogger.w('时间推断：触发智能推送');
        await _performSmartPush(isBackground: true);
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
  Future<void> _performDailyQuotePush({bool isBackground = false}) async {
    try {
      // 每日一言是用户期望的每日固定内容，不受 SOTA 疲劳预防系统限制。
      // 仅检查防重复：距上次推送不足 3 分钟的逻辑已在 checkAndPush 中处理。

      final dailyQuote = await _fetchDailyQuote();
      if (dailyQuote != null) {
        await _showNotification(
          dailyQuote,
          title: '📖 每日一言',
          contentType: 'dailyQuote',
        );

        // 记录推送效果（不消费疲劳预算，每日一言不参与疲劳系统）
        await _analytics.updateContentScore('dailyQuote', false);

        AppLogger.i('每日一言推送成功');
      }

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
        // 使用 'randomMemory'（成本 3.0）作为预检类型，这是智能推送中
        // 最高成本的内容类型，确保预算检查保守一致。
        // 实际内容类型在内容选择后确定，用于 consumeBudget。
        final preCheckType = _settings.pushMode == PushMode.dailyQuote
            ? 'dailyQuote'
            : 'randomMemory';
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
      String contentType = 'randomMemory';

      switch (_settings.pushMode) {
        case PushMode.smart:
          // 智能模式：使用 SOTA 智能算法选择最佳内容
          final result = await _smartSelectContent();
          noteToShow = result.note;
          title = result.title;
          isDailyQuote = result.isDailyQuote;
          contentType = result.contentType;
          break;

        case PushMode.dailyQuote:
          // 注意：这里的 PushMode.dailyQuote 是指"回顾推送"模式选了"仅每日一言"
          // 与独立的每日一言推送是两码事
          final dailyQuote = await _fetchDailyQuote();
          if (dailyQuote != null) {
            noteToShow = dailyQuote;
            title = '📖 每日一言';
            isDailyQuote = true;
          }
          break;

        case PushMode.pastNotes:
          final candidates = await getCandidateNotes();
          if (candidates.isNotEmpty) {
            noteToShow = _selectUnpushedNote(candidates);
            if (noteToShow != null) {
              title = _generateTitle(noteToShow);
            }
          }
          break;

        case PushMode.both:
          // 随机选择推送类型
          if (_random.nextBool()) {
            final candidates = await getCandidateNotes();
            if (candidates.isNotEmpty) {
              noteToShow = _selectUnpushedNote(candidates);
              if (noteToShow != null) {
                title = _generateTitle(noteToShow);
              }
            }
          }
          if (noteToShow == null) {
            final dailyQuote = await _fetchDailyQuote();
            if (dailyQuote != null) {
              noteToShow = dailyQuote;
              title = '📖 每日一言';
              isDailyQuote = true;
            }
          }
          break;

        case PushMode.custom:
          // 自定义模式：根据用户选择的类型获取内容
          final candidates = await getCandidateNotes();
          if (candidates.isNotEmpty) {
            noteToShow = _selectUnpushedNote(candidates);
            if (noteToShow != null) {
              title = _generateTitle(noteToShow);
            }
          } else {
            // 如果没有匹配的笔记，尝试获取每日一言
            final dailyQuote = await _fetchDailyQuote();
            if (dailyQuote != null) {
              noteToShow = dailyQuote;
              title = '📖 每日一言';
              isDailyQuote = true;
            }
          }
          break;
      }

      if (noteToShow != null) {
        await _showNotification(
          noteToShow,
          title: title,
          contentType: contentType,
        );

        // 记录推送历史（避免重复推送，测试模式也不记录）
        if (!isDailyQuote && noteToShow.id != null && !isTest) {
          final updatedSettings = _settings.addPushedNoteId(noteToShow.id!);
          // 后台推送时使用静默保存，避免 saveSettings 中的
          // scheduleNextPush → _cancelAllSchedules → cancelAll()
          // 意外取消刚刚通过 _showNotification 显示的通知
          if (isBackground) {
            await _saveSettingsQuietly(updatedSettings);
          } else {
            await saveSettings(updatedSettings);
          }
        }

        // SOTA: 消费疲劳预算并记录推送（用于效果追踪）
        if (!isTest && contentType.isNotEmpty) {
          await _analytics.consumeBudget(contentType);
          // 推送成功，但尚未确定用户是否交互，先记录为未交互
          // 用户点击通知时会调用 recordInteraction 更新得分
          await _analytics.updateContentScore(contentType, false);
        }

        AppLogger.i(
          '推送成功: ${noteToShow.content.substring(0, min(50, noteToShow.content.length))}...',
        );
      } else {
        AppLogger.d('没有内容可推送');
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
}
