part of '../smart_push_service.dart';

/// 通知显示、点击回调、每日一言缓存
extension SmartPushNotification on SmartPushService {
  /// 处理冷启动通知点击
  ///
  /// 当 App 由通知点击启动时，`onDidReceiveNotificationResponse` 回调可能未触发
  /// （因为 App 尚未初始化时的点击不会被回调捕获）。
  /// 需要通过 `getNotificationAppLaunchDetails()` 主动检查。
  Future<void> _handleLaunchNotification() async {
    try {
      final launchDetails =
          await _notificationsPlugin.getNotificationAppLaunchDetails();
      if (launchDetails == null || !launchDetails.didNotificationLaunchApp) {
        return;
      }

      final response = launchDetails.notificationResponse;
      if (response != null) {
        AppLogger.i('检测到冷启动通知点击，处理 payload: ${response.payload}');
        final parsed = await _recordNotificationTapState(response);
        unawaited(_performNotificationTapNavigation(parsed));
      }
    } catch (e) {
      AppLogger.w('处理冷启动通知失败', error: e);
    }
  }

  /// 初始化通知插件
  Future<void> _initializeNotifications() async {
    const androidSettings = AndroidInitializationSettings(
      '@mipmap/ic_launcher',
    );
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    const initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _notificationsPlugin.initialize(
      initSettings,
      onDidReceiveNotificationResponse: _onNotificationTap,
    );

    // 创建通知频道（Android 8.0+）
    if (PlatformHelper.isAndroid) {
      final androidPlugin =
          _notificationsPlugin.resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();
      if (androidPlugin != null) {
        await androidPlugin.createNotificationChannel(
          const AndroidNotificationChannel(
            SmartPushService._notificationChannelId,
            SmartPushService._notificationChannelName,
            description: '回顾过去的笔记和每日一言',
            importance: Importance.high,
          ),
        );
      }
    }
    _notificationPluginReady = true;
  }

  /// 通知点击回调 - SOTA 效果追踪
  void _onNotificationTap(NotificationResponse response) {
    unawaited(_handleNotificationTapAsync(response));
  }

  Future<void> _handleNotificationTapAsync(
    NotificationResponse response,
  ) async {
    final parsed = await _recordNotificationTapState(response);
    final shouldRearmIosDailyQuote = !_isDisposed &&
        _isIOS &&
        _settings.dailyQuotePushEnabled &&
        (parsed.notificationId == 100 ||
            (parsed.notificationId == null &&
                parsed.contentType == 'dailyQuote' &&
                parsed.noteId == null));
    int? tappedIosDailyQuoteEpochMs = parsed.scheduledEpochMs;
    String? tappedIosDailyQuoteContent;
    if (shouldRearmIosDailyQuote) {
      const targetId = 100;
      final nowMs = _now().millisecondsSinceEpoch;
      _PreScheduledEntry? matchedDailyEntry;
      for (final entry in _loadTrackedPreScheduledEntries()) {
        if (entry.id != targetId || !entry.isDailyQuote) continue;
        final matchesTappedDelivery = parsed.scheduledEpochMs != null
            ? entry.epochMs == parsed.scheduledEpochMs
            : entry.epochMs <= nowMs;
        if (!matchesTappedDelivery) continue;
        if (matchedDailyEntry == null ||
            entry.epochMs >= matchedDailyEntry.epochMs) {
          matchedDailyEntry = entry;
        }
        if (parsed.scheduledEpochMs != null) {
          break;
        }
      }
      if (matchedDailyEntry != null) {
        tappedIosDailyQuoteEpochMs ??= matchedDailyEntry.epochMs;
        tappedIosDailyQuoteContent =
            (matchedDailyEntry.dailyQuoteData?['hitokoto'] as String?)?.trim();
      }

      if (tappedIosDailyQuoteEpochMs != null &&
          tappedIosDailyQuoteEpochMs > 0) {
        try {
          tz.local;
        } catch (_) {
          await _initializeTimezone();
        }
        final nowLocal = tz.TZDateTime.from(_now(), tz.local);
        final tappedLocal = tz.TZDateTime.fromMillisecondsSinceEpoch(
          tz.local,
          tappedIosDailyQuoteEpochMs,
        );
        final isSameCalendarDay = tappedLocal.year == nowLocal.year &&
            tappedLocal.month == nowLocal.month &&
            tappedLocal.day == nowLocal.day;
        if (isSameCalendarDay) {
          var pushedContent = tappedIosDailyQuoteContent;
          if (pushedContent == null || pushedContent.isEmpty) {
            final cachedToday = await getCachedDailyQuoteForToday();
            pushedContent = (cachedToday?['hitokoto'] as String?)?.trim();
          }
          if (pushedContent != null && pushedContent.isNotEmpty) {
            tappedIosDailyQuoteContent = pushedContent;
            if (!_hasDailyQuoteContentPushed(pushedContent)) {
              _markDailyQuoteContentPushed(pushedContent);
            }
          }
        }
      }
    }

    Future<void>? rescheduleFuture;
    if (!_isDisposed &&
        _isAndroid &&
        _settings.enabled &&
        _settings.pushMode == PushMode.smart &&
        (parsed.contentType != null || parsed.noteId != null)) {
      // 点击结算会复位连续未点击计数并更新推送历史，需递增调度纪元并不受 6 小时节流限制立即主动重排，恢复此前因预计冷却而跳过的后续提醒槽位
      final epochBumpFuture = _bumpScheduleEpoch();
      rescheduleFuture = _scheduleNextPushWithPrerequisite(
        preserveDeliveredNotifications: true,
        prerequisite: epochBumpFuture,
      ).catchError((Object e, StackTrace stack) {
        AppLogger.w('通知点击后重排推送计划失败', error: e, stackTrace: stack);
      });
    }
    await _performNotificationTapNavigation(parsed);
    if (shouldRearmIosDailyQuote && !_isDisposed) {
      // 在导航消费完当前 ID=100 的追踪一言数据后再续订下一日通知，避免覆盖本次点击展示内容
      await _rearmIosDailyQuoteAfterTap(
        tappedEpochMs: tappedIosDailyQuoteEpochMs,
        previousQuoteContent: tappedIosDailyQuoteContent,
      ).catchError((Object e, StackTrace stack) {
        AppLogger.w('iOS 每日一言点击后续订下一日通知失败', error: e, stackTrace: stack);
      });
    }
    if (rescheduleFuture != null) {
      await rescheduleFuture;
    }
  }

  Future<
      ({
        String? noteId,
        String? contentType,
        String? routeTarget,
        int? notificationId,
        int? scheduledEpochMs,
      })> _recordNotificationTapState(
    NotificationResponse response,
  ) async {
    AppLogger.i('通知被点击: ${response.payload}');

    String? noteId;
    String? contentType;
    String? routeTarget;
    int? notificationId = response.id;
    int? scheduledEpochMs;
    // SOTA: 记录用户点击交互（正向反馈）
    // payload 格式: "contentType:xxx|noteId:yyy|notificationId:zzz|scheduledEpochMs:ttt" 或 "dailyQuote"
    try {
      final payload = response.payload;
      if (payload != null && payload.isNotEmpty) {
        if (payload.contains('contentType:')) {
          // 解析 contentType、noteId、notificationId 与 scheduledEpochMs
          final parts = payload.split('|');
          for (final part in parts) {
            if (part.startsWith('contentType:')) {
              contentType = part.substring('contentType:'.length);
            } else if (part.startsWith('noteId:')) {
              final id = part.substring('noteId:'.length);
              // 验证 noteId 格式 (UUID)
              if (RegExp(r'^[0-9a-fA-F-]{32,36}$').hasMatch(id)) {
                noteId = id;
              }
            } else if (part.startsWith('routeTarget:')) {
              routeTarget = part.substring('routeTarget:'.length);
            } else if (part.startsWith('notificationId:')) {
              final parsedId = int.tryParse(
                part.substring('notificationId:'.length),
              );
              if (parsedId != null) {
                notificationId = parsedId;
              }
            } else if (part.startsWith('scheduledEpochMs:')) {
              final parsedEpochMs = int.tryParse(
                part.substring('scheduledEpochMs:'.length),
              );
              if (parsedEpochMs != null && parsedEpochMs > 0) {
                scheduledEpochMs = parsedEpochMs;
              }
            }
          }
        } else if (payload == 'dailyQuote') {
          contentType = 'dailyQuote';
        } else {
          // 兼容旧版本 payload 只有 noteId 的情况，验证格式
          if (RegExp(r'^[0-9a-fA-F-]{32,36}$').hasMatch(payload)) {
            noteId = payload;
          }
        }

        await _reloadSharedStorageIfSupported();
        final tapSettingsGeneration = _settingsMutationGeneration;
        final tapEpoch = _readStoredSettingsEpoch();
        final trackedEntries = notificationId != null
            ? _loadTrackedPreScheduledEntries()
            : const <_PreScheduledEntry>[];
        final nowMs = _now().millisecondsSinceEpoch;
        _PreScheduledEntry? matchedEntry;
        if (notificationId != null) {
          for (final entry in trackedEntries) {
            if (entry.id != notificationId) continue;
            final matchesTappedDelivery = scheduledEpochMs != null
                ? entry.epochMs == scheduledEpochMs
                : (entry.epochMs <= nowMs ||
                    notificationId >=
                        SmartPushService._preScheduledNotificationBaseId);
            if (!matchesTappedDelivery) continue;
            if (matchedEntry == null || entry.epochMs >= matchedEntry.epochMs) {
              matchedEntry = entry;
            }
            if (scheduledEpochMs != null) {
              break;
            }
          }
        }

        if (matchedEntry != null &&
            matchedEntry.isDailyQuote &&
            matchedEntry.dailyQuoteData != null) {
          final matchedQuoteText =
              (matchedEntry.dailyQuoteData!['hitokoto'] as String?)?.trim() ??
                  '';
          if (matchedQuoteText.isNotEmpty) {
            try {
              tz.local;
              final nowLocal = tz.TZDateTime.from(_now(), tz.local);
              final entryLocal = tz.TZDateTime.fromMillisecondsSinceEpoch(
                tz.local,
                matchedEntry.epochMs,
              );
              if (entryLocal.year == nowLocal.year &&
                  entryLocal.month == nowLocal.month &&
                  entryLocal.day == nowLocal.day &&
                  !_hasDailyQuoteContentPushed(matchedQuoteText)) {
                _markDailyQuoteContentPushed(matchedQuoteText);
              }
            } catch (_) {}
          }
        }

        if (contentType != null && contentType.isNotEmpty) {
          final isUnaccountedSmartRegularEntry = matchedEntry != null &&
              !matchedEntry.accounted &&
              !matchedEntry.isDailyQuote &&
              _settings.pushMode == PushMode.smart;
          final isInFlightImmediateSmartNotification = notificationId != null &&
              _inFlightImmediateSmartNotificationIds.contains(notificationId);
          final effectiveEpochMs =
              (matchedEntry != null && matchedEntry.epochMs > 0)
                  ? matchedEntry.epochMs
                  : ((scheduledEpochMs != null && scheduledEpochMs > 0)
                      ? scheduledEpochMs
                      : null);
          final interactionSentAt = effectiveEpochMs != null
              ? DateTime.fromMillisecondsSinceEpoch(effectiveEpochMs)
              : null;
          await _analytics.recordInteraction(
            contentType,
            notificationId: notificationId,
            sentAt: interactionSentAt,
            deferScoreUntilAccounted: isUnaccountedSmartRegularEntry ||
                isInFlightImmediateSmartNotification,
          );
          AppLogger.d(
            'SOTA: 记录通知点击交互 - $contentType (ID: $notificationId)',
          );
        }

        if (matchedEntry != null && !matchedEntry.accounted) {
          await _accountDeliveredPreScheduledEntries(
            settingsGeneration: tapSettingsGeneration,
            expectedEpoch: tapEpoch,
            forceAccountNotificationId: notificationId,
            forceAccountEpochMs: matchedEntry.epochMs,
          );
        }
      }
    } catch (e) {
      AppLogger.w('解析通知 payload 失败', error: e);
    }

    return (
      noteId: noteId,
      contentType: contentType,
      routeTarget: routeTarget,
      notificationId: notificationId,
      scheduledEpochMs: scheduledEpochMs,
    );
  }

  Future<void> _performNotificationTapNavigation(
    ({
      String? noteId,
      String? contentType,
      String? routeTarget,
      int? notificationId,
      int? scheduledEpochMs,
    }) parsed,
  ) async {
    final noteId = parsed.noteId;
    final contentType = parsed.contentType;
    final routeTarget = parsed.routeTarget;
    final notificationId = parsed.notificationId;

    // 处理打开特定笔记的逻辑
    if (noteId != null && noteId.isNotEmpty) {
      ClipboardService.suppressNextCheckForNotificationNavigation();
      try {
        await _navigateToNoteList(noteId, routeTarget: routeTarget);
      } catch (e) {
        AppLogger.e('通知导航失败', error: e);
      }
    } else if (contentType == 'dailyQuote') {
      // 每日一言：仅标记首页展示，不直接弹出添加弹窗
      try {
        await _navigateToDailyQuote(
          notificationId: notificationId,
          scheduledEpochMs: parsed.scheduledEpochMs,
        );
      } catch (e) {
        AppLogger.e('每日一言导航失败', error: e);
      }
    }
  }

  /// 导航到记录页并定位到特定笔记
  Future<void> _navigateToNoteList(
    String noteId, {
    String? routeTarget,
  }) async {
    try {
      final note = await _databaseService.getQuoteById(noteId);
      if (note == null) {
        AppLogger.d('通知导航已取消：数据库中未找到笔记 $noteId');
        return;
      }

      // 检查笔记是否被隐藏（隐藏笔记在列表视图中不可见，无法滚动定位）
      if (await _databaseService.isQuoteHidden(noteId)) {
        AppLogger.d('通知导航已取消：笔记已隐藏，无法在列表中定位 $noteId');
        return;
      }

      // 重试机制：等待 navigatorKey.currentState 就绪 (例如冷启动场景)
      int retryCount = 0;
      const maxRetries = 15;
      while (navigatorKey.currentState == null && retryCount < maxRetries) {
        AppLogger.d('等待 navigatorKey 就绪... ($retryCount)');
        await Future.delayed(const Duration(milliseconds: 300));
        retryCount++;
      }

      if (navigatorKey.currentState == null) {
        AppLogger.w('通知导航失败：navigatorKey.currentState 在多次重试后仍为空');
        return;
      }

      // ── 暖启动（App 已在前台）：通过 pendingTargetNoteId 通知现有 HomePage
      // 原地切 tab + 定位，避免 pushAndRemoveUntil 销毁重建造成白屏闪烁。
      // ── 冷启动路径：navigator 刚就绪，路由栈仍是 MaterialApp 的初始路由，
      // 此时 canPop() == false 且路由栈仅有一个根 HomePage，
      // 直接设置 pendingTargetNoteId 即可，HomePage 的 initState 会响应。
      _pendingTargetNoteId = noteId;
      notifyListenersFromParts();
      AppLogger.i('已通过 pendingTargetNoteId 触发笔记定位: $noteId ($routeTarget)');
    } catch (e) {
      AppLogger.e('执行通知导航逻辑出错', error: e);
    }
  }

  /// 标记每日一言通知点击后的首页展示内容（一次性消费）。
  Future<void> _navigateToDailyQuote({
    int? notificationId,
    int? scheduledEpochMs,
  }) async {
    try {
      Map<String, dynamic>? hitokotoData;

      if (notificationId != null) {
        final nowMs = _now().millisecondsSinceEpoch;
        final trackedEntries = _loadTrackedPreScheduledEntries();
        _PreScheduledEntry? matchedQuoteEntry;
        for (final entry in trackedEntries) {
          if (entry.id != notificationId || entry.dailyQuoteData == null) {
            continue;
          }
          final matchesTappedDelivery = scheduledEpochMs != null
              ? entry.epochMs == scheduledEpochMs
              : (entry.epochMs <= nowMs ||
                  notificationId >=
                      SmartPushService._preScheduledNotificationBaseId);
          if (!matchesTappedDelivery) {
            continue;
          }
          if (matchedQuoteEntry == null ||
              entry.epochMs >= matchedQuoteEntry.epochMs) {
            matchedQuoteEntry = entry;
          }
          if (scheduledEpochMs != null) {
            break;
          }
        }
        if (matchedQuoteEntry != null) {
          hitokotoData = await _validateCachedDailyQuote(
            matchedQuoteEntry.dailyQuoteData!,
          );
          if (hitokotoData == null) {
            AppLogger.d(
              '每日一言通知点击处理取消：关联本地笔记已隐藏或删除 ($notificationId)',
            );
            return;
          }
        }
      }

      hitokotoData ??= await getCachedDailyQuoteForToday();
      if (hitokotoData == null) {
        AppLogger.d('通知点击时缓存为空，实时获取每日一言...');
        hitokotoData = await _loadDailyQuoteData(preferCache: false);
        if (hitokotoData == null) {
          AppLogger.w('每日一言通知点击处理取消：无法获取内容');
          return;
        }
      }

      await _mmkv.setString(
        SmartPushService._pendingHomeDailyQuoteKey,
        json.encode(hitokotoData),
      );
      notifyListenersFromParts();
      AppLogger.i('已标记每日一言通知内容用于首页展示');
    } catch (e) {
      AppLogger.e('每日一言通知点击处理出错', error: e);
    }
  }

  /// 为立即发送的每日一言通知持久化专属内容快照（即使离线回退本地一言未写入共享日缓存，点击时也能展示与通知正文一致的一言，且在源笔记被隐藏/删除时联动撤回）。
  Future<void> _persistDeliveredDailyQuoteSnapshot({
    required int notificationId,
    required Map<String, dynamic> dailyQuoteData,
    String? sourceNoteId,
    String? quoteSourceFingerprint,
    DateTime? deliveredAt,
    bool isStandaloneDailyQuote = false,
  }) {
    final normalized = SmartPushService.normalizeDailyQuoteData(dailyQuoteData);
    if (normalized == null) return Future<void>.value();
    final rawLocalId = normalized['local_quote_id'];
    final effectiveNoteId = (sourceNoteId != null && sourceNoteId.isNotEmpty)
        ? sourceNoteId
        : ((rawLocalId is String && rawLocalId.isNotEmpty) ? rawLocalId : null);
    return _withScheduleCommitLock(() async {
      final commitSeq = await _nextNotificationCommitSeq();
      final previousEntries = _loadTrackedPreScheduledEntries();
      final activeNotificationIds = previousEntries.isNotEmpty
          ? await _queryActiveLocalNotificationIds()
          : const <int>{};
      final nowMs = _now().millisecondsSinceEpoch;
      final deliveredEpochMs = (deliveredAt ?? _now()).millisecondsSinceEpoch;
      final maxRetentionMs =
          SmartPushService._deliveredEntryRetention.inMilliseconds;
      final existing = <_PreScheduledEntry>[];
      for (final e in previousEntries) {
        if (e.id == notificationId || e.epochMs <= 0) continue;
        if (e.epochMs > nowMs || nowMs - e.epochMs <= maxRetentionMs) {
          existing.add(e);
          continue;
        }
        if (activeNotificationIds != null) {
          if (activeNotificationIds.contains(e.id)) {
            existing.add(e);
          }
        } else {
          try {
            await _notificationsPlugin.cancel(e.id);
          } catch (err) {
            AppLogger.w('清理超期追踪通知失败 (ID: ${e.id})', error: err);
          }
        }
      }
      existing.add(
        _PreScheduledEntry(
          id: notificationId,
          epochMs: deliveredEpochMs,
          noteId: effectiveNoteId,
          isDailyQuote: isStandaloneDailyQuote,
          contentType: 'dailyQuote',
          accounted: true,
          dailyQuoteData: normalized,
          quoteSourceFingerprint: quoteSourceFingerprint,
          commitSeq: commitSeq,
        ),
      );
      await _saveTrackedPreScheduledEntries(
        existing,
        expectedCommitSeq: commitSeq,
      );
    });
  }

  /// 判断某条一言数据在 `useLocalQuotesOnly` 模式下是否合法：
  /// 允许真实本地笔记（`type == 'local'`），以及在非 `tagOnly` 模式下无可用本地笔记时的内置默认语录（`provider == 'default'`）。
  bool _isPermittedDailyQuoteForLocalOnlyMode(
    Map<String, dynamic> data,
    AppSettings appSettings,
  ) {
    final type = (data['type'] as String?)?.trim() ?? '';
    if (type == 'local') return true;
    final provider = (data['provider'] as String?)?.trim() ?? '';
    return appSettings.offlineQuoteSource != 'tagOnly' &&
        provider == 'default' &&
        type != 'offline' &&
        type != 'local-empty';
  }

  /// 缓存每日一言到 MMKV（供通知点击时读取）
  ///
  /// [hitokotoData] 为一言 API 的原始响应，包含 type 等标签分类信息
  void _saveDailyQuoteToCache(Map<String, dynamic> hitokotoData) {
    try {
      final normalizedData =
          SmartPushService.normalizeDailyQuoteData(hitokotoData);
      if (normalizedData == null) return;
      final existingFp =
          (normalizedData['quote_source_fingerprint'] as String?)?.trim() ?? '';
      if (existingFp.isEmpty) {
        final appSettings = _loadStoredAppSettings();
        final normalizedType =
            (normalizedData['type'] as String?)?.trim() ?? '';
        final canStampCurrentFp = appSettings.useLocalQuotesOnly
            ? _isPermittedDailyQuoteForLocalOnlyMode(
                normalizedData,
                appSettings,
              )
            : (normalizedType != 'offline' && normalizedType != 'local-empty');
        if (canStampCurrentFp) {
          normalizedData['quote_source_fingerprint'] =
              _currentDailyQuoteSourceFingerprint(appSettings);
        }
      }

      _mmkv.setString(
          SmartPushService._lastDailyQuoteKey, json.encode(normalizedData));
      _mmkv.setString(SmartPushService._lastDailyQuoteDateKey, _todayDateKey());
    } catch (e) {
      AppLogger.w('缓存每日一言失败', error: e);
    }
  }

  String _todayDateKey() => _now().toIso8601String().substring(0, 10);

  /// 读取当天缓存的一言数据，跨首页与推送共用。
  Future<Map<String, dynamic>?> getCachedDailyQuoteForToday() async {
    try {
      final cachedDate =
          _mmkv.getString(SmartPushService._lastDailyQuoteDateKey);
      if (cachedDate == null || cachedDate != _todayDateKey()) {
        return null;
      }

      final cachedJson = _mmkv.getString(SmartPushService._lastDailyQuoteKey);
      if (cachedJson == null || cachedJson.isEmpty) {
        return null;
      }

      final decoded = json.decode(cachedJson);
      if (decoded is! Map<String, dynamic>) {
        return null;
      }

      return await _validateCachedDailyQuote(
        decoded,
        verifySourceAndContentFreshness: true,
      );
    } catch (e) {
      AppLogger.w('读取每日一言缓存失败', error: e);
      return null;
    }
  }

  /// 主动写入当天一言缓存，供首页/推送共用。
  void cacheDailyQuoteForToday(Map<String, dynamic> quoteData) {
    _saveDailyQuoteToCache(quoteData);
  }

  /// 一次性消费"通知点击后首页展示"的每日一言内容。
  Future<Map<String, dynamic>?> consumePendingDailyQuoteForHomeDisplay() async {
    try {
      final pendingJson =
          _mmkv.getString(SmartPushService._pendingHomeDailyQuoteKey);
      if (pendingJson == null || pendingJson.isEmpty) {
        return null;
      }

      final decoded = json.decode(pendingJson);
      if (decoded is! Map<String, dynamic>) {
        await _mmkv.remove(SmartPushService._pendingHomeDailyQuoteKey);
        return null;
      }

      await _mmkv.remove(SmartPushService._pendingHomeDailyQuoteKey);
      return await _validateCachedDailyQuote(decoded);
    } catch (e) {
      AppLogger.w('读取待展示每日一言失败', error: e);
      return null;
    }
  }

  bool _doesDailyQuoteMatchAppSettings(
    Map<String, dynamic> data,
    AppSettings appSettings,
  ) {
    final type = (data['type'] as String?)?.trim() ?? '';
    if (appSettings.useLocalQuotesOnly &&
        !_isPermittedDailyQuoteForLocalOnlyMode(data, appSettings)) {
      return false;
    }

    final storedFp =
        (data['quote_source_fingerprint'] as String?)?.trim() ?? '';
    final expectedFp = _currentDailyQuoteSourceFingerprint(appSettings);
    if (storedFp.isNotEmpty) {
      return storedFp == expectedFp;
    }

    if (!appSettings.useLocalQuotesOnly) {
      final expectedProvider = ApiService.supportedDailyQuoteProviders.contains(
        appSettings.dailyQuoteProvider,
      )
          ? appSettings.dailyQuoteProvider
          : ApiService.hitokotoProvider;
      final cachedProvider = (data['provider'] as String?)?.trim() ?? '';
      if (cachedProvider.isNotEmpty && cachedProvider != 'offline') {
        return cachedProvider == expectedProvider;
      }
      if (cachedProvider.isEmpty && type != 'local') {
        return expectedProvider == ApiService.hitokotoProvider;
      }
    }
    return true;
  }

  /// 校验某条本地一言快照对应的源笔记当前是否仍可见、符合标签/长度规则且正文与作者出处未被修改。
  Future<bool> _isLocalDailyQuoteSnapshotCurrent(
    String noteId,
    Map<String, dynamic> rawSnapshot, {
    AppSettings? appSettings,
    bool enforceConfiguredOfflineSource = false,
  }) async {
    if (noteId.isEmpty) return false;
    final snapshot = SmartPushService.normalizeDailyQuoteData(rawSnapshot);
    if (snapshot == null) return false;

    final settings = appSettings ?? _loadStoredAppSettings();
    final snapshotOfflineSource =
        (snapshot['offline_quote_source'] as String?)?.trim() ?? '';
    final effectiveOfflineSource =
        (!enforceConfiguredOfflineSource && snapshotOfflineSource.isNotEmpty)
            ? snapshotOfflineSource
            : settings.offlineQuoteSource;

    try {
      final currentRaw = await _databaseService.getLocalDailyQuoteById(
        noteId,
        offlineQuoteSource: effectiveOfflineSource,
      );
      if (currentRaw == null) return false;
      final current = SmartPushService.normalizeDailyQuoteData(currentRaw);
      if (current == null) return false;
      return current['hitokoto'] == snapshot['hitokoto'] &&
          current['from_who'] == snapshot['from_who'] &&
          current['from'] == snapshot['from'];
    } on NoSuchMethodError {
      final visibleIds = await _databaseService.getVisibleQuoteIds([noteId]);
      if (!visibleIds.contains(noteId)) return false;
      try {
        final allVisible = await _databaseService.getAllQuotes();
        for (final note in allVisible) {
          if (note.id != noteId) continue;
          final currentText = note.content.trim();
          final currentAuthor = (note.sourceAuthor ?? '').trim();
          final currentWork = ((note.sourceWork?.isNotEmpty ?? false)
                  ? note.sourceWork!
                  : (note.source ?? ''))
              .trim();
          if (currentText != snapshot['hitokoto'] ||
              currentAuthor != snapshot['from_who'] ||
              currentWork != snapshot['from']) {
            return false;
          }
          if (effectiveOfflineSource == 'tagOnly') {
            final allowedTags = <String>{'default_hitokoto'};
            try {
              for (final t in await _databaseService.getTags()) {
                if (t.name == '每日一言' && t.id.isNotEmpty) {
                  allowedTags.add(t.id);
                }
              }
            } catch (_) {}
            if (!note.tagIds.any(allowedTags.contains)) {
              return false;
            }
          } else if (note.content.contains('\n')) {
            return false;
          }
          return currentText.isNotEmpty && note.content.length <= 100;
        }
        return false;
      } catch (_) {
        return true;
      }
    } catch (_) {
      return false;
    }
  }

  /// 本地缓存在笔记隐藏/删除、内容编辑、取消一言标签或切换一言源后可能失效，读取时按场景校验。
  Future<Map<String, dynamic>?> _validateCachedDailyQuote(
    Map<String, dynamic> rawData, {
    bool verifySourceAndContentFreshness = false,
  }) async {
    final data = SmartPushService.normalizeDailyQuoteData(rawData);
    if (data == null) return null;

    Future<Null> clearTodayCache() async {
      await _mmkv.remove(SmartPushService._lastDailyQuoteKey);
      await _mmkv.remove(SmartPushService._lastDailyQuoteDateKey);
      return null;
    }

    final appSettings =
        verifySourceAndContentFreshness ? _loadStoredAppSettings() : null;
    if (verifySourceAndContentFreshness &&
        appSettings != null &&
        !_doesDailyQuoteMatchAppSettings(data, appSettings)) {
      return clearTodayCache();
    }

    if (verifySourceAndContentFreshness &&
        appSettings != null &&
        appSettings.useLocalQuotesOnly &&
        (data['provider'] as String?)?.trim() == 'default') {
      try {
        final nowAvailableLocal = await _databaseService.getLocalDailyQuote(
          offlineQuoteSource: appSettings.offlineQuoteSource,
        );
        if (nowAvailableLocal != null) {
          return await clearTodayCache();
        }
      } catch (e) {
        AppLogger.w('校验默认每日一言缓存是否可升级为本地笔记失败', error: e);
      }
    }

    if (data['type'] != 'local') return data;

    // 旧缓存未保存笔记 ID，无法安全验证，交由调用方重新获取。
    final noteId = data['local_quote_id'];
    if (noteId is! String || noteId.isEmpty) {
      return verifySourceAndContentFreshness ? clearTodayCache() : null;
    }

    if (verifySourceAndContentFreshness) {
      final isCurrent = await _isLocalDailyQuoteSnapshotCurrent(
        noteId,
        data,
        appSettings: appSettings,
      );
      if (!isCurrent) {
        return clearTodayCache();
      }
      return data;
    }

    final visibleIds = await _databaseService.getVisibleQuoteIds([noteId]);
    if (!visibleIds.contains(noteId)) {
      return clearTodayCache();
    }
    return data;
  }

  Future<Map<String, dynamic>?> _loadDailyQuoteData({
    bool preferCache = true,
    bool updateTodayCache = true,
  }) async {
    if (preferCache) {
      final cachedData = await getCachedDailyQuoteForToday();
      if (cachedData != null) {
        return cachedData;
      }
    }

    final appSettings = _loadStoredAppSettings();
    final l10n = _resolveDailyQuoteLocalizations(appSettings);
    final normalizedData = SmartPushService.normalizeDailyQuoteData(
      await ApiService.getDailyQuote(
        l10n,
        appSettings.hitokotoType,
        useLocalOnly: appSettings.useLocalQuotesOnly,
        offlineQuoteSource: appSettings.offlineQuoteSource,
        databaseService: _databaseService,
        provider: appSettings.dailyQuoteProvider,
        apiNinjasCategories: appSettings.apiNinjasCategories,
      ),
    );
    if (normalizedData == null) {
      return null;
    }
    final normalizedType = (normalizedData['type'] as String?)?.trim() ?? '';
    final normalizedProvider =
        (normalizedData['provider'] as String?)?.trim() ?? '';
    final matchesConfiguredMode = appSettings.useLocalQuotesOnly
        ? _isPermittedDailyQuoteForLocalOnlyMode(normalizedData, appSettings)
        : (normalizedType != 'local' &&
            normalizedType != 'offline' &&
            normalizedType != 'local-empty' &&
            normalizedProvider != 'offline');
    if (matchesConfiguredMode) {
      normalizedData['quote_source_fingerprint'] =
          _currentDailyQuoteSourceFingerprint(appSettings);
    }
    if (updateTodayCache &&
        normalizedType != 'offline' &&
        normalizedType != 'local-empty' &&
        (appSettings.useLocalQuotesOnly
            ? _isPermittedDailyQuoteForLocalOnlyMode(
                normalizedData,
                appSettings,
              )
            : normalizedType != 'local')) {
      _saveDailyQuoteToCache(normalizedData);
    }
    return normalizedData;
  }

  AppSettings _loadStoredAppSettings() {
    try {
      final rawSettings = _mmkv.getString(SmartPushService._appSettingsKey);
      if (rawSettings == null || rawSettings.isEmpty) {
        return AppSettings.defaultSettings();
      }

      final decoded = json.decode(rawSettings);
      if (decoded is Map<String, dynamic>) {
        return AppSettings.fromJson(decoded);
      }
    } catch (e) {
      AppLogger.w('读取每日一言设置失败', error: e);
    }

    return AppSettings.defaultSettings();
  }

  AppLocalizations _resolveDailyQuoteLocalizations(AppSettings settings) =>
      resolveAppLocalizations(settings.localeCode);

  Future<void> _ensureNotificationReady() async {
    if (_notificationPluginReady) return;
    try {
      const androidSettings = AndroidInitializationSettings(
        '@mipmap/ic_launcher',
      );
      const iosSettings = DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
      );
      const initSettings = InitializationSettings(
        android: androidSettings,
        iOS: iosSettings,
      );
      await _notificationsPlugin.initialize(initSettings);

      if (PlatformHelper.isAndroid) {
        final androidPlugin =
            _notificationsPlugin.resolvePlatformSpecificImplementation<
                AndroidFlutterLocalNotificationsPlugin>();
        if (androidPlugin != null) {
          await androidPlugin.createNotificationChannel(
            const AndroidNotificationChannel(
              SmartPushService._notificationChannelId,
              SmartPushService._notificationChannelName,
              description: '回顾过去的笔记和每日一言',
              importance: Importance.high,
            ),
          );
        }
      }
      _notificationPluginReady = true;
      AppLogger.d('通知插件就绪（后台安全初始化）');
    } catch (e) {
      AppLogger.e('_ensureNotificationReady 失败', error: e);
    }
  }

  /// 生成与固定槽位 (0..1000) 及预调度区间 ([100000000, 199999999]) 完全隔离的单调 31 位立即通知 ID
  Future<int> _nextImmediateNotificationId() async {
    const baseId = 300000000;
    const span = 1700000000; // 最大 1,999,999,999 < 2^31 - 1
    await _reloadSharedStorageIfSupported();
    final prev = int.tryParse(
      _mmkv.getString(SmartPushService._immediateNotificationSeqKey) ?? '',
    );
    // 100ms 刻度在 17 亿空间内约 5.39 年不回绕；同刻度或固定测试时钟下按 prev + 1 严格单调递增
    final tick = (_now().millisecondsSinceEpoch ~/ 100) % span;
    final int nextOffset;
    if (prev == null) {
      nextOffset = tick;
    } else {
      final delta = (tick - prev) % span;
      nextOffset = (delta > 0 && delta < span ~/ 2) ? tick : (prev + 1) % span;
    }
    await _mmkv.setString(
      SmartPushService._immediateNotificationSeqKey,
      nextOffset.toString(),
    );
    return baseId + nextOffset;
  }

  /// 显示通知，返回实际发送的通知 ID（发送失败时返回 null）
  Future<int?> _showNotification(
    Quote note, {
    String title = '心迹',
    String contentType = '',
    int? notificationIdOverride,
  }) async {
    await _ensureNotificationReady();

    final body = _buildNotificationBody(note);

    final androidDetails = AndroidNotificationDetails(
      SmartPushService._notificationChannelId,
      SmartPushService._notificationChannelName,
      channelDescription: '回顾过去的笔记和每日一言',
      importance: Importance.max,
      priority: Priority.high,
      showWhen: true,
      styleInformation: body.length > 50
          ? BigTextStyleInformation(
              body,
              contentTitle: title,
              summaryText: _getNotificationSummary(note),
            )
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

    final notificationId =
        notificationIdOverride ?? await _nextImmediateNotificationId();

    String payload = '';
    if (contentType.isNotEmpty) {
      payload = SmartPushService.buildNotificationPayload(
            noteId: note.id,
            contentType: contentType,
            routeTarget: 'noteList',
            notificationId: notificationId,
          ) ??
          '';
    } else {
      payload = note.id ?? '';
    }

    try {
      await _notificationsPlugin.show(
        notificationId,
        title,
        body,
        details,
        payload: payload,
      );
      AppLogger.i('通知已成功发送: $title');
      return notificationId;
    } catch (e, stack) {
      AppLogger.e(
        '通知发送失败 (_notificationsPlugin.show)',
        error: e,
        stackTrace: stack,
      );
      return null;
    }
  }

  /// 构建通知正文
  String _buildNotificationBody(Quote note) {
    return SmartPushService.buildNotificationBodyForTest(note);
  }

  String? _getNotificationSummary(Quote note) {
    return null;
  }
}
