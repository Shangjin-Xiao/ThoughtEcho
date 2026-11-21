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
      })> _recordNotificationTapState(
    NotificationResponse response,
  ) async {
    AppLogger.i('通知被点击: ${response.payload}');

    String? noteId;
    String? contentType;
    String? routeTarget;
    int? notificationId = response.id;
    // SOTA: 记录用户点击交互（正向反馈）
    // payload 格式: "contentType:xxx|noteId:yyy|notificationId:zzz" 或 "dailyQuote"
    try {
      final payload = response.payload;
      if (payload != null && payload.isNotEmpty) {
        if (payload.contains('contentType:')) {
          // 解析 contentType、noteId 与 notificationId
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
        _PreScheduledEntry? matchedEntry;
        if (notificationId != null) {
          for (final entry in trackedEntries) {
            if (entry.id == notificationId) {
              matchedEntry = entry;
              break;
            }
          }
        }

        if (contentType != null && contentType.isNotEmpty) {
          final isUnaccountedSmartRegularEntry = matchedEntry != null &&
              !matchedEntry.accounted &&
              !matchedEntry.isDailyQuote &&
              _settings.pushMode == PushMode.smart;
          final isInFlightImmediateSmartNotification = notificationId != null &&
              _inFlightImmediateSmartNotificationIds.contains(notificationId);
          await _analytics.recordInteraction(
            contentType,
            notificationId: notificationId,
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
    );
  }

  Future<void> _performNotificationTapNavigation(
    ({
      String? noteId,
      String? contentType,
      String? routeTarget,
      int? notificationId,
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
        await _navigateToDailyQuote(notificationId: notificationId);
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
  Future<void> _navigateToDailyQuote({int? notificationId}) async {
    try {
      Map<String, dynamic>? hitokotoData;

      if (notificationId != null) {
        final trackedEntries = _loadTrackedPreScheduledEntries();
        for (final entry in trackedEntries) {
          if (entry.id == notificationId && entry.dailyQuoteData != null) {
            hitokotoData =
                await _validateCachedDailyQuote(entry.dailyQuoteData!);
            if (hitokotoData == null) {
              AppLogger.d(
                '每日一言通知点击处理取消：关联本地笔记已隐藏或删除 ($notificationId)',
              );
              return;
            }
            break;
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

  /// 缓存每日一言到 MMKV（供通知点击时读取）
  ///
  /// [hitokotoData] 为一言 API 的原始响应，包含 type 等标签分类信息
  void _saveDailyQuoteToCache(Map<String, dynamic> hitokotoData) {
    try {
      final normalizedData =
          SmartPushService.normalizeDailyQuoteData(hitokotoData);
      if (normalizedData == null) return;

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

      return await _validateCachedDailyQuote(decoded);
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

  /// 本地缓存可能在笔记隐藏/删除后仍然存在，读取时重新校验可见性。
  Future<Map<String, dynamic>?> _validateCachedDailyQuote(
    Map<String, dynamic> rawData,
  ) async {
    final data = SmartPushService.normalizeDailyQuoteData(rawData);
    if (data == null || data['type'] != 'local') return data;

    // 旧缓存未保存笔记 ID，无法安全验证，交由调用方重新获取。
    final noteId = data['local_quote_id'];
    if (noteId is! String || noteId.isEmpty) return null;

    final visibleIds = await _databaseService.getVisibleQuoteIds([noteId]);
    if (!visibleIds.contains(noteId)) {
      await _mmkv.remove(SmartPushService._lastDailyQuoteKey);
      await _mmkv.remove(SmartPushService._lastDailyQuoteDateKey);
      return null;
    }
    return data;
  }

  Future<Map<String, dynamic>?> _loadDailyQuoteData({
    bool preferCache = true,
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
    if (normalizedType != 'offline' && normalizedType != 'local-empty') {
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
