part of '../smart_push_service.dart';

/// 平台相关 — 时区、AlarmManager、WorkManager、本地通知调度
extension SmartPushPlatform on SmartPushService {
  /// 注册 WorkManager 周期性备用任务
  ///
  /// 当 Android 12+ 精确闹钟权限被拒绝或系统限制后台执行时，
  /// 这个周期性任务（每15分钟）会检查是否有遗漏的推送
  Future<void> _registerPeriodicFallbackTask() async {
    if (!PlatformHelper.isAndroid && !PlatformHelper.isIOS) return;

    try {
      // 注册周期性任务（最小间隔15分钟）
      await Workmanager().registerPeriodicTask(
        'smart_push_periodic_check',
        kPeriodicCheckTask,
        frequency: const Duration(minutes: 15),
      );
      AppLogger.i('已注册 WorkManager 周期性备用任务（15分钟间隔）');
    } catch (e) {
      AppLogger.w('注册周期性备用任务失败', error: e);
    }
  }

  /// 取消周期性备用任务
  Future<void> _cancelPeriodicFallbackTask() async {
    if (!PlatformHelper.isAndroid && !PlatformHelper.isIOS) return;

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
    if (!PlatformHelper.isAndroid) return true;

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

  /// WorkManager 降级方案
  ///
  /// 当精确闹钟不可用时，使用 WorkManager 一次性任务作为备用
  Future<void> _scheduleWorkManagerFallback(
    int idIndex,
    tz.TZDateTime scheduledDate,
    PushTimeSlot slot,
  ) async {
    try {
      final now = DateTime.now();
      final delay = scheduledDate.difference(now);

      // 使用 WorkManager 一次性任务
      await Workmanager().registerOneOffTask(
        'android_push_fallback_$idIndex',
        kBackgroundPushTask,
        initialDelay: delay > Duration.zero ? delay : Duration.zero,
        inputData: {'triggerKind': 'smartPush'},
        existingWorkPolicy: ExistingWorkPolicy.replace,
      );
      AppLogger.i('已使用 WorkManager 降级方案调度推送: 延迟 ${delay.inMinutes} 分钟');
    } catch (e) {
      AppLogger.e('WorkManager 降级方案也失败', error: e);
      // 最后的降级：仅本地通知
      await _scheduleLocalNotification(idIndex, scheduledDate, slot);
    }
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
    if (PlatformHelper.isAndroid) {
      // 先检查精确闹钟权限
      final canScheduleExact = await _canScheduleExactAlarms();

      if (canScheduleExact) {
        try {
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
          // 继续降级处理
        }
      } else {
        AppLogger.w('精确闹钟权限被拒绝，使用 WorkManager 降级方案');
      }

      // Android 降级方案: 使用 WorkManager 一次性任务
      await _scheduleWorkManagerFallback(idIndex, scheduledDate, slot);
    }
    // 2. iOS: 使用 WorkManager 注册后台任务
    else if (PlatformHelper.isIOS) {
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
  }) async {
    try {
      await _ensureNotificationReady();
      // 尝试预计算要推送的内容
      _PushContent? content;
      if (isDailyQuote) {
        final quote = await _fetchDailyQuote();
        if (quote != null) {
          content = _PushContent(
            title: '📖 每日一言',
            body: quote.content,
            noteId: null,
          );
        }
      } else {
        content = await _getPrecomputedContent();
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
      final canScheduleExact = await _canScheduleExactAlarms();
      final scheduleMode = canScheduleExact
          ? AndroidScheduleMode.exactAllowWhileIdle
          : AndroidScheduleMode.inexactAllowWhileIdle;

      if (!canScheduleExact) {
        AppLogger.w('精确闹钟权限不可用，使用 inexact 模式调度本地通知（时间可能有 15 分钟误差）');
      }

      // 构建 payload，确保通知点击时能正确路由
      String? payload;
      if (isDailyQuote) {
        payload = 'contentType:dailyQuote';
      } else if (content?.noteId != null) {
        payload = 'contentType:smartPush|noteId:${content!.noteId}';
      }

      await _notificationsPlugin.zonedSchedule(
        id,
        content?.title ?? (isDailyQuote ? '📖 每日一言' : '💡 回忆时刻'),
        content?.body ?? '点击查看今天的灵感',
        scheduledDate,
        details,
        androidScheduleMode: scheduleMode,
        payload: payload,
      );

      AppLogger.i(
        '已设定本地通知: $scheduledDate (模式: ${canScheduleExact ? "精确" : "非精确"})',
      );
    } catch (e) {
      AppLogger.e('设定本地通知失败', error: e);
    }
  }

  Future<void> _cancelAllSchedules() async {
    await _notificationsPlugin.cancelAll();
    if (PlatformHelper.isAndroid) {
      // 取消常规推送
      for (int i = 0; i < 10; i++) {
        await AndroidAlarmManager.cancel(SmartPushService._androidAlarmId + i);
      }
      // 取消每日一言
      await AndroidAlarmManager.cancel(SmartPushService._dailyQuoteAlarmId);
    }
    // 取消 WorkManager 周期性任务
    await _cancelPeriodicFallbackTask();
  }
}
