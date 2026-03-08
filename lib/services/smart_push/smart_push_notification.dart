part of '../smart_push_service.dart';

/// 通知显示、点击回调、每日一言缓存
extension SmartPushNotification on SmartPushService {
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
            _notificationChannelId,
            _notificationChannelName,
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
    AppLogger.i('通知被点击: ${response.payload}');

    String? noteId;
    String? contentType;
    // SOTA: 记录用户点击交互（正向反馈）
    // payload 格式: "contentType:xxx|noteId:yyy" 或 "dailyQuote"
    try {
      final payload = response.payload;
      if (payload != null && payload.isNotEmpty) {
        if (payload.contains('contentType:')) {
          // 解析 contentType 和 noteId
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

        if (contentType != null && contentType.isNotEmpty) {
          // 记录交互（异步执行，不阻塞 UI）
          _analytics.recordInteraction(contentType);
          AppLogger.d('SOTA: 记录通知点击交互 - $contentType');
        }
      }
    } catch (e) {
      AppLogger.w('解析通知 payload 失败', error: e);
    }

    // 处理打开特定笔记的逻辑
    if (noteId != null && noteId.isNotEmpty) {
      _navigateToNote(noteId).catchError((e) {
        AppLogger.e('通知导航失败', error: e);
      });
    } else if (contentType == 'dailyQuote') {
      // 每日一言：仅标记首页展示，不直接弹出添加弹窗
      _navigateToDailyQuote().catchError((e) {
        AppLogger.e('每日一言导航失败', error: e);
      });
    }
  }

  /// 导航到特定笔记
  Future<void> _navigateToNote(String noteId) async {
    try {
      // 获取笔记详情
      final note = await _databaseService.getQuoteById(noteId);
      if (note == null) {
        AppLogger.d('通知导航已取消：数据库中未找到笔记 $noteId');
        return;
      }

      // 获取所有标签，供编辑器使用
      final categories = await _databaseService.getCategories();

      // 重试机制：等待 navigatorKey.currentState 就绪 (例如冷启动场景)
      int retryCount = 0;
      const maxRetries = 15;
      while (navigatorKey.currentState == null && retryCount < maxRetries) {
        AppLogger.d('等待 navigatorKey 就绪... ($retryCount)');
        await Future.delayed(const Duration(milliseconds: 300));
        retryCount++;
      }

      if (navigatorKey.currentState != null) {
        navigatorKey.currentState!.push(
          MaterialPageRoute(
            builder: (context) => NoteFullEditorPage(
              initialContent: note.content,
              initialQuote: note,
              allTags: categories,
            ),
          ),
        );
        AppLogger.i('已成功触发导航至笔记: $noteId');
      } else {
        AppLogger.w('通知导航失败：navigatorKey.currentState 在多次重试后仍为空');
      }
    } catch (e) {
      AppLogger.e('执行通知导航逻辑出错', error: e);
    }
  }

  /// 标记每日一言通知点击后的首页展示内容（一次性消费）。
  Future<void> _navigateToDailyQuote() async {
    try {
      var hitokotoData = getCachedDailyQuoteForToday();
      if (hitokotoData == null) {
        AppLogger.d('通知点击时缓存为空，实时获取每日一言...');
        hitokotoData = await _loadDailyQuoteData(preferCache: false);
        if (hitokotoData == null) {
          AppLogger.w('每日一言通知点击处理取消：无法获取内容');
          return;
        }
      }

      await _mmkv.setString(
        _pendingHomeDailyQuoteKey,
        json.encode(hitokotoData),
      );
      notifyListeners();
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
      final normalizedData = normalizeDailyQuoteData(hitokotoData);
      if (normalizedData == null) return;

      _mmkv.setString(_lastDailyQuoteKey, json.encode(normalizedData));
      _mmkv.setString(_lastDailyQuoteDateKey, _todayDateKey());
    } catch (e) {
      AppLogger.w('缓存每日一言失败', error: e);
    }
  }

  String _todayDateKey() => DateTime.now().toIso8601String().substring(0, 10);

  /// 读取当天缓存的一言数据，跨首页与推送共用。
  Map<String, dynamic>? getCachedDailyQuoteForToday() {
    try {
      final cachedDate = _mmkv.getString(_lastDailyQuoteDateKey);
      if (cachedDate == null || cachedDate != _todayDateKey()) {
        return null;
      }

      final cachedJson = _mmkv.getString(_lastDailyQuoteKey);
      if (cachedJson == null || cachedJson.isEmpty) {
        return null;
      }

      final decoded = json.decode(cachedJson);
      if (decoded is! Map<String, dynamic>) {
        return null;
      }

      return normalizeDailyQuoteData(decoded);
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
      final pendingJson = _mmkv.getString(_pendingHomeDailyQuoteKey);
      if (pendingJson == null || pendingJson.isEmpty) {
        return null;
      }

      final decoded = json.decode(pendingJson);
      if (decoded is! Map<String, dynamic>) {
        await _mmkv.remove(_pendingHomeDailyQuoteKey);
        return null;
      }

      final normalizedData = normalizeDailyQuoteData(decoded);
      await _mmkv.remove(_pendingHomeDailyQuoteKey);
      return normalizedData;
    } catch (e) {
      AppLogger.w('读取待展示每日一言失败', error: e);
      return null;
    }
  }

  Future<Map<String, dynamic>?> _loadDailyQuoteData({
    bool preferCache = true,
  }) async {
    if (preferCache) {
      final cachedData = getCachedDailyQuoteForToday();
      if (cachedData != null) {
        return cachedData;
      }
    }

    final response = await NetworkService.instance.get(
      'https://v1.hitokoto.cn/?c=d&c=e&c=i&c=k',
      timeoutSeconds: 10,
    );

    if (response.statusCode != 200) {
      return null;
    }

    final data = json.decode(response.body) as Map<String, dynamic>?;
    final normalizedData = normalizeDailyQuoteData(data);
    if (normalizedData == null) {
      return null;
    }

    _saveDailyQuoteToCache(normalizedData);
    return normalizedData;
  }

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
              _notificationChannelId,
              _notificationChannelName,
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

  /// 显示通知
  Future<void> _showNotification(
    Quote note, {
    String title = '心迹',
    String contentType = '',
  }) async {
    await _ensureNotificationReady();

    final body = _buildNotificationBody(note);

    final androidDetails = AndroidNotificationDetails(
      _notificationChannelId,
      _notificationChannelName,
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

    String payload = '';
    if (contentType.isNotEmpty) {
      payload = 'contentType:$contentType';
      if (note.id != null) {
        payload += '|noteId:${note.id}';
      }
    } else {
      payload = note.id ?? '';
    }

    try {
      await _notificationsPlugin.show(
        DateTime.now().millisecondsSinceEpoch % 100000,
        title,
        body,
        details,
        payload: payload,
      );
      AppLogger.i('通知已成功发送: $title');
    } catch (e, stack) {
      AppLogger.e(
        '通知发送失败 (_notificationsPlugin.show)',
        error: e,
        stackTrace: stack,
      );
    }
  }

  /// 构建通知正文
  String _buildNotificationBody(Quote note) {
    final content = _truncateContent(note.content);

    // 如果有来源信息，添加引用格式
    if (note.sourceAuthor != null && note.sourceAuthor!.isNotEmpty) {
      return '"$content"\n—— ${note.sourceAuthor}';
    }

    if (note.source != null && note.source!.isNotEmpty) {
      return '"$content"\n—— 《${note.source}》';
    }

    return content;
  }

  /// 获取通知摘要文本
  String? _getNotificationSummary(Quote note) {
    final noteDate = DateTime.tryParse(note.date);
    if (noteDate != null) {
      final now = DateTime.now();
      final diff = now.difference(noteDate);

      if (diff.inDays == 0) {
        return '今天';
      } else if (diff.inDays == 1) {
        return '昨天';
      } else if (diff.inDays < 7) {
        return '${diff.inDays}天前';
      } else if (diff.inDays < 30) {
        return '${(diff.inDays / 7).floor()}周前';
      } else if (diff.inDays < 365) {
        return '${(diff.inDays / 30).floor()}个月前';
      } else {
        return '${(diff.inDays / 365).floor()}年前';
      }
    }
    return null;
  }
}
