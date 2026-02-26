import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:android_alarm_manager_plus/android_alarm_manager_plus.dart';
import 'package:workmanager/workmanager.dart'; // Add this import
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:permission_handler/permission_handler.dart';
import 'package:device_info_plus/device_info_plus.dart';

import '../models/smart_push_settings.dart';
import '../models/quote_model.dart';
import '../pages/note_full_editor_page.dart';
import '../widgets/add_note_dialog.dart';
import '../main.dart' show navigatorKey;
import 'database_service.dart';
import 'mmkv_service.dart';
import 'location_service.dart';
import 'weather_service.dart';
import 'network_service.dart';
import '../utils/app_logger.dart';
import '../utils/platform_helper.dart';
import 'background_push_handler.dart';
import 'smart_push_analytics.dart';

/// 智能推送服务
///
/// 负责根据用户设置筛选笔记并触发推送通知
/// 支持混合模式：
/// - Android: 使用 WorkManager/AlarmManager 实现精确定时
/// - iOS: 使用本地通知调度
/// - 所有平台: 支持前台即时推送
///
/// SOTA 功能 (v2):
/// - 响应性热图：基于用户 App 打开时间自动优化推送时段
/// - 疲劳预防：虚拟预算系统 + 冷却机制
/// - Thompson Sampling：内容选择的探索-利用平衡
/// - 效果追踪：Time-to-Open, 交互反馈学习
class SmartPushService extends ChangeNotifier {
  final DatabaseService _databaseService;
  final MMKVService _mmkv;
  final LocationService _locationService;
  final FlutterLocalNotificationsPlugin _notificationsPlugin;
  WeatherService? _weatherService;

  /// SOTA 智能推送分析器
  late final SmartPushAnalytics _analytics;

  static const String _settingsKey = 'smart_push_settings_v2';
  static const String _legacySettingsKey = 'smart_push_settings';
  static const String _autoStartGrantedKey = 'smart_push_auto_start_granted';
  static const int _androidAlarmId = 888;
  static const int _dailyQuoteAlarmId = 988;
  static const String _notificationChannelId = 'smart_push_channel';
  static const String _notificationChannelName = '智能推送';
  static const String _scheduledTimesKey = 'smart_push_scheduled_times_today';
  static const String _lastDailyQuoteKey = 'smart_push_last_daily_quote';

  SmartPushSettings _settings = SmartPushSettings.defaultSettings();
  SmartPushSettings get settings => _settings;

  /// 获取分析器实例
  SmartPushAnalytics get analytics => _analytics;

  bool _isInitialized = false;
  bool get isInitialized => _isInitialized;

  final Random _random = Random();

  SmartPushService({
    required DatabaseService databaseService,
    required LocationService locationService,
    MMKVService? mmkvService,
    FlutterLocalNotificationsPlugin? notificationsPlugin,
    WeatherService? weatherService,
    SmartPushAnalytics? analytics,
  })  : _databaseService = databaseService,
        _locationService = locationService,
        _mmkv = mmkvService ?? MMKVService(),
        _notificationsPlugin =
            notificationsPlugin ?? FlutterLocalNotificationsPlugin(),
        _weatherService = weatherService {
    _analytics = analytics ?? SmartPushAnalytics(mmkvService: _mmkv);
  }

  /// 设置天气服务（延迟注入）
  void setWeatherService(WeatherService service) {
    _weatherService = service;
  }

  /// 获取自启动权限是否已手动授予（仅用于持久化状态，因为 Android 无法检测该权限）
  Future<bool> getAutoStartGranted() async {
    return _mmkv.getBool(_autoStartGrantedKey) ?? false;
  }

  /// 设置自启动权限已手动授予
  Future<void> setAutoStartGranted(bool granted) async {
    await _mmkv.setBool(_autoStartGrantedKey, granted);
    notifyListeners();
  }

  /// 初始化服务
  Future<void> initialize() async {
    try {
      await _initializeTimezone();
      await _loadSettings();
      await _initializeNotifications();

      AppLogger.i(
          'SmartPushService settings: enabled=${_settings.enabled}, dailyQuoteEnabled=${_settings.dailyQuotePushEnabled}');

      // 请求精确闹钟权限（Android 12+）
      // 移除自动请求，改为在 UI 层（SmartPushSettingsPage）引导用户开启
      if (PlatformHelper.isAndroid) {
        final canScheduleExact = await _canScheduleExactAlarms();
        if (!canScheduleExact) {
          AppLogger.i('精确闹钟权限不可用，将使用 WorkManager 降级方案');
        }
      }

      // 每次启动时重新规划下一次推送
      if (_settings.enabled || _settings.dailyQuotePushEnabled) {
        await scheduleNextPush();

        // 仅当精确闹钟权限不可用时，才注册周期性备用任务（省电）
        if (PlatformHelper.isAndroid) {
          final canScheduleExact = await _canScheduleExactAlarms();
          if (!canScheduleExact) {
            await _registerPeriodicFallbackTask();
          } else {
            // 有精确闹钟权限，取消周期性任务节省电量
            await _cancelPeriodicFallbackTask();
          }
        }
      } else {
        // 如果都禁用了，确保取消所有计划
        await _cancelAllSchedules();
      }

      _isInitialized = true;
      AppLogger.i('SmartPushService 初始化完成');
    } catch (e, stack) {
      AppLogger.e('SmartPushService 初始化失败', error: e, stackTrace: stack);
    }
  }

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
      int idIndex, tz.TZDateTime scheduledDate, PushTimeSlot slot) async {
    try {
      final now = DateTime.now();
      final delay = scheduledDate.difference(now);

      // 使用 WorkManager 一次性任务
      await Workmanager().registerOneOffTask(
        'android_push_fallback_$idIndex',
        kBackgroundPushTask,
        initialDelay: delay > Duration.zero ? delay : Duration.zero,
        inputData: {'triggerKind': 'smartPush'},
      );
      AppLogger.i('已使用 WorkManager 降级方案调度推送: 延迟 ${delay.inMinutes} 分钟');

      // 同时调度本地通知作为用户可见的提醒
      await _scheduleLocalNotification(idIndex, scheduledDate, slot);
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

  /// 仅供后台 Isolate 使用：加载设置
  ///
  /// 后台 Isolate 与前台主 Isolate 不共享状态，因此必须重新初始化时区、设置、通知等。
  /// 时区初始化是必须的，否则 `_nextInstanceOfTime` 中使用的 `tz.local` 会抛出
  /// `LateInitializationError`。
  Future<void> loadSettingsForBackground() async {
    await _initializeTimezone();
    await _loadSettings();
    await _initializeNotifications();
  }

  /// 加载设置（支持版本迁移）
  Future<void> _loadSettings() async {
    try {
      // 先尝试加载新版本设置
      var jsonStr = _mmkv.getString(_settingsKey);

      // 如果没有新版本，尝试迁移旧版本
      if (jsonStr == null || jsonStr.isEmpty) {
        jsonStr = _mmkv.getString(_legacySettingsKey);
        if (jsonStr != null && jsonStr.isNotEmpty) {
          AppLogger.i('迁移旧版智能推送设置');
          // 迁移后保存到新 key
          await _mmkv.setString(_settingsKey, jsonStr);
        }
      }

      if (jsonStr != null && jsonStr.isNotEmpty) {
        final json = jsonDecode(jsonStr) as Map<String, dynamic>;
        _settings = SmartPushSettings.fromJson(json);
      }
    } catch (e) {
      AppLogger.w('加载智能推送设置失败，使用默认设置', error: e);
      _settings = SmartPushSettings.defaultSettings();
    }
  }

  /// 保存设置并更新推送计划
  Future<void> saveSettings(SmartPushSettings newSettings) async {
    try {
      _settings = newSettings;
      final jsonStr = jsonEncode(newSettings.toJson());
      await _mmkv.setString(_settingsKey, jsonStr);
      notifyListeners();
      AppLogger.i('智能推送设置已保存');

      // 更新计划任务
      if (_settings.enabled || _settings.dailyQuotePushEnabled) {
        await scheduleNextPush();
      } else {
        await _cancelAllSchedules();
      }
    } catch (e, stack) {
      AppLogger.e('保存智能推送设置失败', error: e, stackTrace: stack);
      rethrow;
    }
  }

  /// 初始化通知插件
  Future<void> _initializeNotifications() async {
    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
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
      // 每日一言：从 MMKV 读取缓存的每日一言内容并打开编辑器
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

  /// 导航到每日一言（从 MMKV 缓存读取，使用 AddNoteDialog 底部弹窗）
  ///
  /// 行为与首页双击每日一言一致：打开非全屏编辑器，自动填充来源和标签信息
  Future<void> _navigateToDailyQuote() async {
    try {
      final cachedJson = _mmkv.getString(_lastDailyQuoteKey);
      if (cachedJson == null || cachedJson.isEmpty) {
        AppLogger.w('每日一言导航已取消：缓存中无数据');
        return;
      }

      final hitokotoData = json.decode(cachedJson) as Map<String, dynamic>;
      final content = hitokotoData['hitokoto'] as String?;
      if (content == null || content.isEmpty) {
        AppLogger.w('每日一言导航已取消：缓存内容为空');
        return;
      }

      final fromWho = hitokotoData['from_who'] as String? ?? '';
      final from = hitokotoData['from'] as String? ?? '';
      final categories = await _databaseService.getCategories();

      // 等待 navigatorKey 就绪（冷启动场景）
      int retryCount = 0;
      const maxRetries = 15;
      while (navigatorKey.currentState == null && retryCount < maxRetries) {
        AppLogger.d('等待 navigatorKey 就绪... ($retryCount)');
        await Future.delayed(const Duration(milliseconds: 300));
        retryCount++;
      }

      final navContext = navigatorKey.currentContext;
      if (navContext == null) {
        AppLogger.w('每日一言导航失败：navigatorKey.currentContext 在多次重试后仍为空');
        return;
      }

      showModalBottomSheet(
        context: navContext,
        isScrollControlled: true,
        backgroundColor:
            Theme.of(navContext).colorScheme.surfaceContainerLowest,
        builder: (context) => AddNoteDialog(
          prefilledContent: content,
          prefilledAuthor: fromWho.isNotEmpty ? fromWho : null,
          prefilledWork: from.isNotEmpty ? from : null,
          hitokotoData: hitokotoData,
          tags: categories,
        ),
      );
      AppLogger.i('已成功触发每日一言添加弹窗');
    } catch (e) {
      AppLogger.e('每日一言导航逻辑出错', error: e);
    }
  }

  /// 缓存每日一言到 MMKV（供通知点击时读取）
  ///
  /// [hitokotoData] 为一言 API 的原始响应，包含 type 等标签分类信息
  void _saveDailyQuoteToCache(Map<String, dynamic> hitokotoData) {
    try {
      _mmkv.setString(
        _lastDailyQuoteKey,
        json.encode(hitokotoData),
      );
    } catch (e) {
      AppLogger.w('缓存每日一言失败', error: e);
    }
  }

  /// 请求通知权限
  Future<bool> requestNotificationPermission() async {
    try {
      if (PlatformHelper.isAndroid) {
        final androidPlugin =
            _notificationsPlugin.resolvePlatformSpecificImplementation<
                AndroidFlutterLocalNotificationsPlugin>();
        if (androidPlugin != null) {
          final granted = await androidPlugin.requestNotificationsPermission();
          return granted ?? false;
        }
      }

      if (PlatformHelper.isIOS) {
        final iosPlugin =
            _notificationsPlugin.resolvePlatformSpecificImplementation<
                IOSFlutterLocalNotificationsPlugin>();
        if (iosPlugin != null) {
          final granted = await iosPlugin.requestPermissions(
            alert: true,
            badge: true,
            sound: true,
          );
          return granted ?? false;
        }
      }

      return true;
    } catch (e) {
      AppLogger.e('请求通知权限失败', error: e);
      return false;
    }
  }

  /// 检查是否有精确闹钟权限（Android 12+）
  ///
  /// 注意：SCHEDULE_EXACT_ALARM 不是运行时权限，需要用户在设置中手动开启
  /// Android 14+ 默认拒绝此权限
  Future<bool> checkExactAlarmPermission() async {
    if (!PlatformHelper.isAndroid) return true;

    try {
      final androidPlugin =
          _notificationsPlugin.resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();
      if (androidPlugin != null) {
        // 1. 首先检查通知权限
        final notificationsEnabled =
            await androidPlugin.areNotificationsEnabled() ?? false;
        if (!notificationsEnabled) {
          AppLogger.w('通知权限未授予');
          return false;
        }

        // 2. 检查精确闹钟权限 (Android 12+)
        // 使用 canScheduleExactNotifications() 检查
        final canScheduleExact =
            await androidPlugin.canScheduleExactNotifications() ?? false;
        if (!canScheduleExact) {
          AppLogger.w('精确闹钟权限未授予 (SCHEDULE_EXACT_ALARM)');
          // 返回 true 但记录警告 - 我们仍会尝试调度，系统会降级处理
          // 用户可以手动在设置中开启
        }

        // 精确闹钟权限需要通知权限作为前提
        return canScheduleExact && notificationsEnabled;
      }
      return true;
    } catch (e) {
      AppLogger.w('检查精确闹钟权限失败', error: e);
      return false;
    }
  }

  /// 请求精确闹钟权限（引导用户到设置页面）
  Future<bool> requestExactAlarmPermission() async {
    if (!PlatformHelper.isAndroid) return true;

    try {
      final androidPlugin =
          _notificationsPlugin.resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();
      if (androidPlugin != null) {
        // 检查是否已有权限
        final canSchedule =
            await androidPlugin.canScheduleExactNotifications() ?? false;
        if (canSchedule) return true;

        // 尝试请求权限（会打开系统设置页面）
        await androidPlugin.requestExactAlarmsPermission();

        // 再次检查
        return await androidPlugin.canScheduleExactNotifications() ?? false;
      }
      return true;
    } catch (e) {
      AppLogger.e('请求精确闹钟权限失败', error: e);
      return false;
    }
  }

  /// 检查电池优化是否已豁免
  ///
  /// 返回 true 表示已豁免电池优化（推送可以正常工作）
  /// 返回 false 表示未豁免（可能导致推送被系统杀死）
  Future<bool> checkBatteryOptimizationExempted() async {
    if (!PlatformHelper.isAndroid) return true;

    try {
      final status = await Permission.ignoreBatteryOptimizations.status;
      final isExempted = status.isGranted;
      AppLogger.d('电池优化豁免状态: $isExempted');
      return isExempted;
    } catch (e) {
      AppLogger.w('检查电池优化状态失败', error: e);
      return false;
    }
  }

  /// 请求电池优化豁免
  ///
  /// 会弹出系统对话框让用户确认
  Future<bool> requestBatteryOptimizationExemption() async {
    if (!PlatformHelper.isAndroid) return true;

    try {
      final status = await Permission.ignoreBatteryOptimizations.request();
      final isExempted = status.isGranted;
      AppLogger.i('请求电池优化豁免结果: $isExempted');
      return isExempted;
    } catch (e) {
      AppLogger.e('请求电池优化豁免失败', error: e);
      return false;
    }
  }

  /// 获取设备制造商
  Future<String> getDeviceManufacturer() async {
    if (!PlatformHelper.isAndroid) return '';

    try {
      final deviceInfo = DeviceInfoPlugin();
      final androidInfo = await deviceInfo.androidInfo;
      return androidInfo.manufacturer.toLowerCase();
    } catch (e) {
      AppLogger.w('获取设备制造商失败', error: e);
      return '';
    }
  }

  /// 获取 Android SDK 版本
  Future<int> getAndroidSdkVersion() async {
    if (!PlatformHelper.isAndroid) return 0;

    try {
      final deviceInfo = DeviceInfoPlugin();
      final androidInfo = await deviceInfo.androidInfo;
      return androidInfo.version.sdkInt;
    } catch (e) {
      AppLogger.w('获取 Android SDK 版本失败', error: e);
      return 0;
    }
  }

  /// 打开应用设置页面（用于手动设置自启动等）
  Future<void> openSystemAppSettings() async {
    try {
      await openAppSettings();
    } catch (e) {
      AppLogger.w('打开应用设置失败', error: e);
    }
  }

  /// 检查通知权限
  Future<bool> checkNotificationPermission() async {
    if (!PlatformHelper.isAndroid) return true;

    try {
      final androidPlugin =
          _notificationsPlugin.resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();
      if (androidPlugin != null) {
        return await androidPlugin.areNotificationsEnabled() ?? false;
      }
      return true;
    } catch (e) {
      AppLogger.w('检查通知权限失败', error: e);
      return false;
    }
  }

  /// 获取完整的推送权限状态
  ///
  /// 返回一个包含所有权限状态的 Map，用于 UI 展示
  Future<PushPermissionStatus> getPushPermissionStatus() async {
    if (kIsWeb) {
      return PushPermissionStatus(
        notificationEnabled: true,
        exactAlarmEnabled: true,
        batteryOptimizationExempted: true,
        manufacturer: '',
        sdkVersion: 0,
        needsAutoStartPermission: false,
        autoStartGranted: true,
      );
    }

    final notificationEnabled = await checkNotificationPermission();
    final exactAlarmEnabled = await checkExactAlarmPermission();
    final batteryExempted = await checkBatteryOptimizationExempted();
    final manufacturer = await getDeviceManufacturer();
    final sdkVersion = await getAndroidSdkVersion();
    final autoStartGranted = await getAutoStartGranted();

    // 这些厂商的 ROM 通常需要额外的自启动权限
    final autoStartManufacturers = [
      'xiaomi',
      'redmi',
      'oppo',
      'realme',
      'vivo',
      'huawei',
      'honor',
      'oneplus',
      'meizu',
      'samsung',
      'asus',
      'letv',
      'leeco',
    ];

    final needsAutoStart = autoStartManufacturers.any(
      (m) => manufacturer.contains(m),
    );

    return PushPermissionStatus(
      notificationEnabled: notificationEnabled,
      exactAlarmEnabled: exactAlarmEnabled,
      batteryOptimizationExempted: batteryExempted,
      manufacturer: manufacturer,
      sdkVersion: sdkVersion,
      needsAutoStartPermission: needsAutoStart,
      autoStartGranted: autoStartGranted,
    );
  }

  /// 获取厂商特定的自启动设置指引
  String getAutoStartInstructions(String manufacturer) {
    final m = manufacturer.toLowerCase();

    if (m.contains('xiaomi') || m.contains('redmi')) {
      return '设置 → 应用设置 → 应用管理 → 心迹 → 自启动';
    } else if (m.contains('huawei') || m.contains('honor')) {
      return '设置 → 应用 → 应用启动管理 → 心迹 → 手动管理 → 开启自启动';
    } else if (m.contains('oppo') || m.contains('realme')) {
      return '设置 → 应用管理 → 应用列表 → 心迹 → 自启动';
    } else if (m.contains('vivo')) {
      return '设置 → 更多设置 → 应用程序 → 自启动管理 → 心迹';
    } else if (m.contains('oneplus')) {
      return '设置 → 应用 → 应用管理 → 心迹 → 电池 → 允许后台运行';
    } else if (m.contains('samsung')) {
      return '设置 → 应用程序 → 心迹 → 电池 → 允许后台活动';
    } else if (m.contains('meizu')) {
      return '设置 → 应用管理 → 心迹 → 权限管理 → 后台管理 → 允许后台运行';
    } else if (m.contains('asus')) {
      return '设置 → 电池管理 → 自启动管理 → 心迹';
    } else if (m.contains('letv') || m.contains('leeco')) {
      return '设置 → 权限管理 → 自启动管理 → 心迹';
    }

    return '请在系统设置中找到应用管理，然后允许心迹自启动和后台运行';
  }

  /// 持久化今日实际调度的推送时间（供后台周期性检查使用）
  Future<void> _persistScheduledTimes(List<PushTimeSlot> slots) async {
    final today = DateTime.now().toIso8601String().substring(0, 10);
    final timesStr = slots.map((s) => '${s.hour}:${s.minute}').join(',');
    await _mmkv.setString(_scheduledTimesKey, '$today|$timesStr');
    AppLogger.d('已持久化今日推送时间: $timesStr');
  }

  /// 获取今日实际调度的推送时间（后台周期性检查用）
  List<PushTimeSlot> getScheduledTimesForToday() {
    try {
      final data = _mmkv.getString(_scheduledTimesKey);
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
          await AndroidAlarmManager.cancel(_androidAlarmId + i);
        }
        await AndroidAlarmManager.cancel(_dailyQuoteAlarmId);
      }
      AppLogger.d('后台重新调度：仅取消 AlarmManager 定时器');
    } else {
      await _cancelAllSchedules();
      AppLogger.d('已取消现有推送计划，准备重新规划');
    }

    // 1. 规划常规推送 (仅当 enabled 为 true 时)
    if (_settings.enabled && _settings.shouldPushToday()) {
      List<PushTimeSlot> slotsToSchedule;

      if (_settings.pushMode == PushMode.smart) {
        // 智能模式：使用智能算法计算最佳推送时间
        slotsToSchedule = await _calculateSmartPushTimes();
        AppLogger.i(
            '智能推送时间: ${slotsToSchedule.map((s) => s.formattedTime).join(", ")}');
      } else {
        // 自定义模式：使用用户设置的时间
        slotsToSchedule =
            _settings.pushTimeSlots.where((s) => s.enabled).toList();
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
      final scheduledDate = _nextInstanceOfTime(slot.hour, slot.minute);

      if (PlatformHelper.isAndroid) {
        // 先检查精确闹钟权限
        final canScheduleExact = await _canScheduleExactAlarms();

        if (canScheduleExact) {
          try {
            await AndroidAlarmManager.oneShotAt(
              scheduledDate,
              _dailyQuoteAlarmId,
              backgroundPushCallback,
              exact: true,
              wakeup: true,
              rescheduleOnReboot: true,
              allowWhileIdle: true,
            );
            AppLogger.i(
                '已设定每日一言 Alarm: $scheduledDate (ID: $_dailyQuoteAlarmId)');
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
        await _scheduleLocalNotification(100, scheduledDate, slot,
            isDailyQuote: true);
      }
    }
  }

  /// 每日一言 WorkManager 降级方案
  Future<void> _scheduleDailyQuoteWorkManagerFallback(
      tz.TZDateTime scheduledDate, PushTimeSlot slot) async {
    try {
      final now = DateTime.now();
      final delay = scheduledDate.difference(now);

      await Workmanager().registerOneOffTask(
        'daily_quote_fallback',
        kBackgroundPushTask,
        initialDelay: delay > Duration.zero ? delay : Duration.zero,
        inputData: {'triggerKind': 'dailyQuote'},
      );
      AppLogger.i('已使用 WorkManager 调度每日一言: 延迟 ${delay.inMinutes} 分钟');
    } catch (e) {
      AppLogger.w('每日一言 WorkManager 降级失败', error: e);
    }

    // 同时调度本地通知作为用户可见的提醒
    await _scheduleLocalNotification(100, scheduledDate, slot,
        isDailyQuote: true);
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

          selectedSlots.add(PushTimeSlot(
            hour: hour,
            minute: minute,
            label: label,
          ));
        }

        if (selectedSlots.isNotEmpty) {
          selectedSlots.sort((a, b) => a.hour.compareTo(b.hour));
          AppLogger.d(
              'SOTA 智能推送时间: ${selectedSlots.map((s) => s.formattedTime).join(", ")}');
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
          avoidCreationPeak: true),
      _TimeSlotCandidate(
          hour: 12,
          minute: 30,
          label: '午间小憩',
          baseScore: 60,
          avoidCreationPeak: true),
      _TimeSlotCandidate(
          hour: 18,
          minute: 0,
          label: '傍晚时光',
          baseScore: 70,
          avoidCreationPeak: true),
      _TimeSlotCandidate(
          hour: 20,
          minute: 30,
          label: '晚间回顾',
          baseScore: 85,
          avoidCreationPeak: false),
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
        selectedSlots.add(PushTimeSlot(
          hour: candidate.hour,
          minute: candidate.minute,
          label: candidate.label,
        ));
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

  /// 调度单个 Alarm
  Future<void> _scheduleSingleAlarm(
      int idIndex, tz.TZDateTime scheduledDate, PushTimeSlot slot) async {
    // 1. Android: 优先使用 AlarmManager 实现精确定时
    if (PlatformHelper.isAndroid) {
      // 先检查精确闹钟权限
      final canScheduleExact = await _canScheduleExactAlarms();

      if (canScheduleExact) {
        try {
          await AndroidAlarmManager.oneShotAt(
            scheduledDate,
            _androidAlarmId + idIndex,
            backgroundPushCallback,
            exact: true,
            wakeup: true,
            rescheduleOnReboot: true,
            allowWhileIdle: true,
          );
          AppLogger.i(
              '已设定常规 Alarm: $scheduledDate (ID: ${_androidAlarmId + idIndex})');
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
      int id, tz.TZDateTime scheduledDate, PushTimeSlot slot,
      {bool isDailyQuote = false}) async {
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
        _notificationChannelId,
        _notificationChannelName,
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
          '已设定本地通知: $scheduledDate (模式: ${canScheduleExact ? "精确" : "非精确"})');
    } catch (e) {
      AppLogger.e('设定本地通知失败', error: e);
    }
  }

  Future<void> _cancelAllSchedules() async {
    await _notificationsPlugin.cancelAll();
    if (PlatformHelper.isAndroid) {
      // 取消常规推送
      for (int i = 0; i < 10; i++) {
        await AndroidAlarmManager.cancel(_androidAlarmId + i);
      }
      // 取消每日一言
      await AndroidAlarmManager.cancel(_dailyQuoteAlarmId);
    }
    // 取消 WorkManager 周期性任务
    await _cancelPeriodicFallbackTask();
  }

  /// 计算下一个时间点
  tz.TZDateTime _nextInstanceOfTime(int hour, int minute) {
    final now = tz.TZDateTime.now(tz.local);
    var scheduledDate =
        tz.TZDateTime(tz.local, now.year, now.month, now.day, hour, minute);
    if (scheduledDate.isBefore(now)) {
      scheduledDate = scheduledDate.add(const Duration(days: 1));
    }
    return scheduledDate;
  }

  /// 预计算推送内容
  Future<_PushContent?> _getPrecomputedContent() async {
    try {
      final candidates = await getCandidateNotes();
      if (candidates.isNotEmpty) {
        final note = candidates.first;
        return _PushContent(
          title: _generateTitle(note),
          body: _truncateContent(note.content),
          noteId: note.id,
        );
      }
      return null;
    } catch (e) {
      AppLogger.w('预计算推送内容失败', error: e);
      return null;
    }
  }

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
        '开始检查推送条件 (isBackground: $isBackground, triggerKind: $triggerKind, time: ${now.hour}:${now.minute})');

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
        '后台推送触发 (triggerKind: $triggerKind, time: ${now.hour}:${now.minute})');

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
        final slotTime =
            DateTime(now.year, now.month, now.day, slot.hour, slot.minute);
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
      // SOTA: 疲劳预防检查
      final skipReason = await _analytics.getSkipReason('dailyQuote');
      if (skipReason != null) {
        AppLogger.w('每日一言推送被跳过: $skipReason');
        if (!isBackground) {
          await scheduleNextPush();
        }
        return;
      }

      final dailyQuote = await _fetchDailyQuote();
      if (dailyQuote != null) {
        await _showNotification(
          dailyQuote,
          title: '📖 每日一言',
          contentType: 'dailyQuote',
        );

        // SOTA: 消费预算并记录推送
        await _analytics.consumeBudget('dailyQuote');
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
  Future<void> _performSmartPush(
      {bool isTest = false, bool isBackground = false}) async {
    try {
      // 测试模式不检查 enabled 和频率
      if (!isTest) {
        if (!_settings.enabled) return;
        if (!_settings.shouldPushToday()) {
          AppLogger.d('根据频率设置，今天不推送');
          return;
        }

        // SOTA: 疲劳预防检查
        final contentType = _settings.pushMode == PushMode.dailyQuote
            ? 'dailyQuote'
            : 'smartContent';
        final smartSkipReason = await _analytics.getSkipReason(contentType);
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
        await _showNotification(noteToShow,
            title: title, contentType: contentType);

        // 记录推送历史（避免重复推送，测试模式也不记录）
        if (!isDailyQuote && noteToShow.id != null && !isTest) {
          final updatedSettings = _settings.addPushedNoteId(noteToShow.id!);
          await saveSettings(updatedSettings);
        }

        // SOTA: 消费疲劳预算并记录推送（用于效果追踪）
        if (!isTest && contentType.isNotEmpty) {
          await _analytics.consumeBudget(contentType);
          // 推送成功，但尚未确定用户是否交互，先记录为未交互
          // 用户点击通知时会调用 recordInteraction 更新得分
          await _analytics.updateContentScore(contentType, false);
        }

        AppLogger.i(
            '推送成功: ${noteToShow.content.substring(0, min(50, noteToShow.content.length))}...');
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

  /// 智能内容选择 - SOTA 核心算法
  ///
  /// SOTA v2 策略：
  /// 1. 收集所有可用内容类型及其候选笔记
  /// 2. 使用 Thompson Sampling 选择最佳内容类型（探索-利用平衡）
  /// 3. 从选中类型中随机选择未推送的笔记
  /// 4. 返回选中内容及其类型（用于效果追踪）
  Future<_SmartSelectResult> _smartSelectContent() async {
    final now = DateTime.now();
    final allNotes = await _databaseService.getQuotesForSmartPush(limit: 500);

    if (allNotes.isEmpty) {
      // 没有笔记时，返回每日一言
      final dailyQuote = await _fetchDailyQuote();
      if (dailyQuote != null) {
        return _SmartSelectResult(
          note: dailyQuote,
          title: '📖 每日一言',
          isDailyQuote: true,
          contentType: 'dailyQuote',
        );
      }
      return _SmartSelectResult.empty();
    }

    // SOTA: 收集所有可用的内容类型及其候选笔记
    final availableContent = <String, _ContentCandidate>{};

    // 1. 那年今日（最高优先级 - 有纪念意义）
    final yearAgoNotes = _filterYearAgoToday(allNotes, now);
    if (yearAgoNotes.isNotEmpty) {
      final note = _selectUnpushedNote(yearAgoNotes);
      if (note != null) {
        final noteDate = DateTime.tryParse(note.date);
        final years = noteDate != null ? now.year - noteDate.year : 1;
        availableContent['yearAgoToday'] = _ContentCandidate(
          note: note,
          title: '📅 $years年前的今天',
          priority: 100, // 最高优先级
        );
      }
    }

    // 2. 同一时刻创建的笔记（±30分钟）
    final sameTimeNotes = _filterSameTimeOfDay(allNotes, now);
    if (sameTimeNotes.isNotEmpty) {
      final note = _selectUnpushedNote(sameTimeNotes);
      if (note != null) {
        availableContent['sameTimeOfDay'] = _ContentCandidate(
          note: note,
          title: '⏰ 此刻的回忆',
          priority: 80,
        );
      }
    }

    // 3. 相同地点的笔记
    final sameLocationNotes = await _filterSameLocation(allNotes);
    if (sameLocationNotes.isNotEmpty) {
      final note = _selectUnpushedNote(sameLocationNotes);
      if (note != null) {
        availableContent['sameLocation'] = _ContentCandidate(
          note: note,
          title: '📍 熟悉的地方',
          priority: 70,
        );
      }
    }

    // 4. 相同天气的笔记
    final sameWeatherNotes = await _filterSameWeather(allNotes);
    if (sameWeatherNotes.isNotEmpty) {
      final note = _selectUnpushedNote(sameWeatherNotes);
      if (note != null) {
        availableContent['sameWeather'] = _ContentCandidate(
          note: note,
          title: '🌤️ 此情此景',
          priority: 60,
        );
      }
    }

    // 5. 往月今日
    final monthAgoNotes = _filterMonthAgoToday(allNotes, now);
    if (monthAgoNotes.isNotEmpty) {
      final note = _selectUnpushedNote(monthAgoNotes);
      if (note != null) {
        final noteDate = DateTime.tryParse(note.date);
        String title = '📅 往月今日';
        if (noteDate != null) {
          final monthsDiff =
              (now.year - noteDate.year) * 12 + (now.month - noteDate.month);
          if (monthsDiff > 0) {
            title = '📅 $monthsDiff个月前的今天';
          }
        }
        availableContent['monthAgoToday'] = _ContentCandidate(
          note: note,
          title: title,
          priority: 50,
        );
      }
    }

    // 6. 随机回忆（兜底）
    final randomNotes = _filterRandomMemory(allNotes, now);
    if (randomNotes.isNotEmpty) {
      final note = _selectUnpushedNote(randomNotes);
      if (note != null) {
        availableContent['randomMemory'] = _ContentCandidate(
          note: note,
          title: '💭 往日回忆',
          priority: 30,
        );
      }
    }

    // SOTA: 使用 Thompson Sampling 选择内容类型
    if (availableContent.isNotEmpty) {
      final availableTypes = availableContent.keys.toList();

      // 那年今日始终优先（高纪念价值）
      if (availableContent.containsKey('yearAgoToday')) {
        final candidate = availableContent['yearAgoToday']!;
        return _SmartSelectResult(
          note: candidate.note,
          title: candidate.title,
          isDailyQuote: false,
          contentType: 'yearAgoToday',
        );
      }

      // 其他类型使用 Thompson Sampling 选择
      final selectedType = await _analytics.selectContentType(availableTypes);
      final candidate = availableContent[selectedType];

      if (candidate != null) {
        return _SmartSelectResult(
          note: candidate.note,
          title: candidate.title,
          isDailyQuote: false,
          contentType: selectedType,
        );
      }
    }

    // 7. 所有筛选器均未命中，记录诊断日志以便排查
    if (allNotes.isNotEmpty) {
      AppLogger.w(
        '智能选择：所有筛选器均未命中，回退到每日一言 '
        '(总笔记数: ${allNotes.length}, '
        'yearAgo: ${yearAgoNotes.length}, '
        'sameTime: ${sameTimeNotes.length}, '
        'sameLocation: ${sameLocationNotes.length}, '
        'sameWeather: ${sameWeatherNotes.length}, '
        'monthAgo: ${monthAgoNotes.length}, '
        'random7d: ${randomNotes.length})',
      );
    }

    // 8. 尝试每日一言
    final dailyQuote = await _fetchDailyQuote();
    if (dailyQuote != null) {
      return _SmartSelectResult(
        note: dailyQuote,
        title: '📖 每日一言',
        isDailyQuote: true,
        contentType: 'dailyQuote',
      );
    }

    return _SmartSelectResult.empty();
  }

  /// 筛选同一时刻（±30分钟）创建的笔记
  List<Quote> _filterSameTimeOfDay(List<Quote> notes, DateTime now) {
    final currentMinutes = now.hour * 60 + now.minute;

    return notes.where((note) {
      try {
        final noteDate = DateTime.parse(note.date);
        final noteMinutes = noteDate.hour * 60 + noteDate.minute;
        final diff = (currentMinutes - noteMinutes).abs();
        // 允许 ±30 分钟的时间差，并且不是今天的笔记
        return diff <= 30 &&
            !(noteDate.year == now.year &&
                noteDate.month == now.month &&
                noteDate.day == now.day);
      } catch (e) {
        return false;
      }
    }).toList();
  }

  /// 从候选列表中选择未被推送过的笔记
  Quote? _selectUnpushedNote(List<Quote> candidates) {
    // 优先选择未推送过的
    final unpushed = candidates
        .where((note) =>
            note.id == null ||
            !_settings.recentlyPushedNoteIds.contains(note.id))
        .toList();

    if (unpushed.isNotEmpty) {
      unpushed.shuffle(_random);
      return unpushed.first;
    }

    // 如果都推送过了，随机选一个
    if (candidates.isNotEmpty) {
      candidates.shuffle(_random);
      return candidates.first;
    }

    return null;
  }

  /// 生成推送标题
  String _generateTitle(Quote note) {
    final now = DateTime.now();
    final noteDate = DateTime.tryParse(note.date);

    if (noteDate != null) {
      // 那年今日
      if (noteDate.month == now.month &&
          noteDate.day == now.day &&
          noteDate.year < now.year) {
        final years = now.year - noteDate.year;
        return '📅 $years年前的今天';
      }

      // 往月今日
      if (noteDate.day == now.day &&
          noteDate.year == now.year &&
          noteDate.month < now.month) {
        final months = now.month - noteDate.month;
        return '📅 $months个月前的今天';
      }

      // 上周今日
      final weekAgo = now.subtract(const Duration(days: 7));
      if (noteDate.year == weekAgo.year &&
          noteDate.month == weekAgo.month &&
          noteDate.day == weekAgo.day) {
        return '📅 一周前的今天';
      }
    }

    // 同地点
    if (note.location != null && note.location!.isNotEmpty) {
      return '📍 熟悉的地方';
    }

    // 同天气
    if (note.weather != null && note.weather!.isNotEmpty) {
      return '🌤️ 此情此景';
    }

    return '💭 回忆时刻';
  }

  /// 截断内容
  String _truncateContent(String content) {
    if (content.length <= 100) return content;
    return '${content.substring(0, 100)}...';
  }

  /// 获取每日一言
  Future<Quote?> _fetchDailyQuote() async {
    try {
      final response = await NetworkService.instance.get(
        'https://v1.hitokoto.cn/?c=d&c=e&c=i&c=k',
        timeoutSeconds: 10,
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>?;
        if (data != null && data['hitokoto'] != null) {
          // 缓存原始 API 数据，供通知点击时构建 AddNoteDialog
          _saveDailyQuoteToCache(data);

          final fromWho = data['from_who'] as String? ?? '';
          final from = data['from'] as String? ?? '';
          return Quote(
            content: data['hitokoto'] as String,
            date: DateTime.now().toIso8601String(),
            sourceAuthor: fromWho,
            source: from.isNotEmpty ? from : null,
          );
        }
      }
      return null;
    } catch (e) {
      AppLogger.w('获取每日一言失败', error: e);
      return null;
    }
  }

  bool _notificationPluginReady = false;

  Future<void> _ensureNotificationReady() async {
    if (_notificationPluginReady) return;
    try {
      const androidSettings =
          AndroidInitializationSettings('@mipmap/ic_launcher');
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
      AppLogger.e('通知发送失败 (_notificationsPlugin.show)',
          error: e, stackTrace: stack);
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

  /// 获取候选推送笔记
  Future<List<Quote>> getCandidateNotes() async {
    final candidates = <Quote>[];
    final allNotes = await _databaseService.getQuotesForSmartPush(limit: 500);

    if (allNotes.isEmpty) return candidates;

    final now = DateTime.now();

    // 根据启用的类型筛选
    for (final noteType in _settings.enabledPastNoteTypes) {
      switch (noteType) {
        case PastNoteType.yearAgoToday:
          candidates.addAll(_filterYearAgoToday(allNotes, now));
          break;
        case PastNoteType.monthAgoToday:
          candidates.addAll(_filterMonthAgoToday(allNotes, now));
          break;
        case PastNoteType.weekAgoToday:
          candidates.addAll(_filterWeekAgoToday(allNotes, now));
          break;
        case PastNoteType.randomMemory:
          candidates.addAll(_filterRandomMemory(allNotes, now));
          break;
        case PastNoteType.sameLocation:
          candidates.addAll(await _filterSameLocation(allNotes));
          break;
        case PastNoteType.sameWeather:
          candidates.addAll(await _filterSameWeather(allNotes));
          break;
      }
    }

    // 应用标签筛选（如果配置了）
    if (_settings.filterTagIds.isNotEmpty) {
      candidates.removeWhere((note) =>
          !note.tagIds.any((tagId) => _settings.filterTagIds.contains(tagId)));
    }

    // 去重
    final uniqueIds = <String>{};
    candidates.removeWhere((note) {
      if (note.id == null) return true;
      if (uniqueIds.contains(note.id)) return true;
      uniqueIds.add(note.id!);
      return false;
    });

    // 打乱顺序增加随机性
    candidates.shuffle(_random);

    return candidates;
  }

  /// 筛选去年今日的笔记
  List<Quote> _filterYearAgoToday(List<Quote> notes, DateTime now) {
    return notes.where((note) {
      try {
        final noteDate = DateTime.parse(note.date);
        return noteDate.month == now.month &&
            noteDate.day == now.day &&
            noteDate.year < now.year;
      } catch (e) {
        return false;
      }
    }).toList();
  }

  /// 筛选往月今日的笔记
  List<Quote> _filterMonthAgoToday(List<Quote> notes, DateTime now) {
    return notes.where((note) {
      try {
        final noteDate = DateTime.parse(note.date);
        return noteDate.day == now.day &&
            (noteDate.year < now.year ||
                (noteDate.year == now.year && noteDate.month < now.month));
      } catch (e) {
        return false;
      }
    }).toList();
  }

  /// 筛选上周今日的笔记
  List<Quote> _filterWeekAgoToday(List<Quote> notes, DateTime now) {
    final weekAgo = now.subtract(const Duration(days: 7));
    return notes.where((note) {
      try {
        final noteDate = DateTime.parse(note.date);
        return noteDate.year == weekAgo.year &&
            noteDate.month == weekAgo.month &&
            noteDate.day == weekAgo.day;
      } catch (e) {
        return false;
      }
    }).toList();
  }

  /// 筛选随机回忆（7天前的笔记）
  List<Quote> _filterRandomMemory(List<Quote> notes, DateTime now) {
    final sevenDaysAgo = now.subtract(const Duration(days: 7));
    final filtered = notes.where((note) {
      try {
        final noteDate = DateTime.parse(note.date);
        return noteDate.isBefore(sevenDaysAgo);
      } catch (e) {
        return false;
      }
    }).toList();

    // 随机选择最多5条
    filtered.shuffle(_random);
    return filtered.take(5).toList();
  }

  /// 筛选相同地点的笔记
  Future<List<Quote>> _filterSameLocation(List<Quote> notes) async {
    try {
      final currentLocation = _locationService.getFormattedLocation();
      if (currentLocation.isEmpty) {
        await _locationService.init();
        if (_locationService.getFormattedLocation().isEmpty) return [];
      }

      final validLocation = _locationService.getFormattedLocation();
      final currentDistrict = _extractDistrict(validLocation);
      if (currentDistrict == null) return [];

      return notes.where((note) {
        if (note.location == null || note.location!.isEmpty) return false;
        final noteDistrict = _extractDistrict(note.location!);
        return noteDistrict != null &&
            noteDistrict.toLowerCase() == currentDistrict.toLowerCase();
      }).toList();
    } catch (e) {
      AppLogger.w('位置筛选失败: $e');
      return [];
    }
  }

  /// 从位置字符串提取区/城市名，用于同地点比较
  /// 支持 CSV 格式 ("国家,省份,城市,区县") 和显示格式 ("城市·区县")
  String? _extractDistrict(String location) {
    if (location.contains(',')) {
      final parts = location.split(',');
      if (parts.length >= 4 && parts[3].trim().isNotEmpty) {
        return parts[3].trim();
      }
      if (parts.length >= 3 && parts[2].trim().isNotEmpty) {
        return parts[2].trim();
      }
    }

    if (location.contains('·')) {
      final parts = location.split('·');
      if (parts.length >= 2) {
        return parts[1].trim();
      }
    }

    final districtMatch = RegExp(r'([^省市县]+(?:区|县|市))').firstMatch(location);
    if (districtMatch != null) {
      return districtMatch.group(1);
    }

    return location;
  }

  /// 筛选相同天气的笔记
  Future<List<Quote>> _filterSameWeather(List<Quote> notes) async {
    // 获取当前天气
    String? currentWeather;
    if (_weatherService != null) {
      try {
        currentWeather = _weatherService!.currentWeather;
      } catch (e) {
        AppLogger.w('获取当前天气失败', error: e);
      }
    }

    if (currentWeather == null || currentWeather.isEmpty) {
      // 如果没有当前天气，使用用户配置的天气筛选
      if (_settings.filterWeatherTypes.isEmpty) return [];

      final weatherKeywords = <String>[];
      for (final weatherType in _settings.filterWeatherTypes) {
        weatherKeywords.addAll(_getWeatherKeywords(weatherType));
      }

      return notes.where((note) {
        if (note.weather == null || note.weather!.isEmpty) return false;
        final lowerWeather = note.weather!.toLowerCase();
        return weatherKeywords
            .any((keyword) => lowerWeather.contains(keyword.toLowerCase()));
      }).toList();
    }

    // 基于当前天气匹配
    final currentWeatherLower = currentWeather.toLowerCase();
    return notes.where((note) {
      if (note.weather == null || note.weather!.isEmpty) return false;
      final noteWeatherLower = note.weather!.toLowerCase();
      // 简单的相似度匹配
      return _weatherMatches(currentWeatherLower, noteWeatherLower);
    }).toList();
  }

  /// 获取天气类型关键词
  List<String> _getWeatherKeywords(WeatherFilterType type) {
    switch (type) {
      case WeatherFilterType.clear:
        return ['晴', 'clear', 'sunny', '阳光'];
      case WeatherFilterType.cloudy:
        return ['多云', 'cloudy', '阴', '云'];
      case WeatherFilterType.rain:
        return ['雨', 'rain', '阵雨', '小雨', '大雨'];
      case WeatherFilterType.snow:
        return ['雪', 'snow', '小雪', '大雪'];
      case WeatherFilterType.fog:
        return ['雾', 'fog', '霾', 'haze'];
    }
  }

  /// 天气匹配
  bool _weatherMatches(String current, String target) {
    // 提取核心天气词
    final coreWeatherTerms = [
      '晴',
      '阴',
      '云',
      '雨',
      '雪',
      '雾',
      '霾',
      'clear',
      'cloudy',
      'rain',
      'snow',
      'fog'
    ];

    for (final term in coreWeatherTerms) {
      if (current.contains(term) && target.contains(term)) {
        return true;
      }
    }
    return false;
  }

  /// 预览推送内容
  Future<Quote?> previewPush() async {
    switch (_settings.pushMode) {
      case PushMode.smart:
        final result = await _smartSelectContent();
        return result.note;
      case PushMode.dailyQuote:
        return await _fetchDailyQuote();
      case PushMode.pastNotes:
      case PushMode.custom:
        final candidates = await getCandidateNotes();
        if (candidates.isNotEmpty) {
          return _selectUnpushedNote(candidates);
        }
        return null;
      case PushMode.both:
        final candidates = await getCandidateNotes();
        if (candidates.isNotEmpty) {
          return _selectUnpushedNote(candidates);
        }
        return await _fetchDailyQuote();
    }
  }

  /// 获取推送统计信息
  Map<String, dynamic> getStatistics() {
    return {
      'enabled': _settings.enabled,
      'mode': _settings.pushMode.name,
      'frequency': _settings.frequency.name,
      'lastPushTime': _settings.lastPushTime?.toIso8601String(),
      'recentPushCount': _settings.recentlyPushedNoteIds.length,
      'timeSlots': _settings.pushTimeSlots
          .where((s) => s.enabled)
          .map((s) => s.formattedTime)
          .toList(),
    };
  }
}

/// 推送内容辅助类
class _PushContent {
  final String title;
  final String body;
  final String? noteId;

  _PushContent({
    required this.title,
    required this.body,
    this.noteId,
  });
}

/// 智能选择结果辅助类
class _SmartSelectResult {
  final Quote? note;
  final String title;
  final bool isDailyQuote;
  final String contentType; // 用于 SOTA 效果追踪

  _SmartSelectResult({
    required this.note,
    required this.title,
    required this.isDailyQuote,
    this.contentType = 'randomMemory',
  });

  factory _SmartSelectResult.empty() => _SmartSelectResult(
        note: null,
        title: '',
        isDailyQuote: false,
        contentType: '',
      );
}

/// 智能时间候选辅助类
class _TimeSlotCandidate {
  final int hour;
  final int minute;
  final String label;
  final int baseScore;
  final bool avoidCreationPeak;
  int score;

  _TimeSlotCandidate({
    required this.hour,
    required this.minute,
    required this.label,
    required this.baseScore,
    this.avoidCreationPeak = true,
  }) : score = baseScore;
}

/// SOTA 内容候选辅助类
///
/// 用于 Thompson Sampling 选择时存储候选内容信息
class _ContentCandidate {
  final Quote note;
  final String title;
  final int priority;

  _ContentCandidate({
    required this.note,
    required this.title,
    required this.priority,
  });
}

/// 推送权限状态
///
/// 用于 UI 展示所有推送相关权限的状态
class PushPermissionStatus {
  /// 通知权限是否已授予
  final bool notificationEnabled;

  /// 精确闹钟权限是否已授予 (Android 12+)
  final bool exactAlarmEnabled;

  /// 是否已豁免电池优化
  final bool batteryOptimizationExempted;

  /// 设备制造商
  final String manufacturer;

  /// Android SDK 版本
  final int sdkVersion;

  /// 是否需要自启动权限（基于厂商判断）
  final bool needsAutoStartPermission;

  /// 自启动权限是否已手动授予
  final bool autoStartGranted;

  const PushPermissionStatus({
    required this.notificationEnabled,
    required this.exactAlarmEnabled,
    required this.batteryOptimizationExempted,
    required this.manufacturer,
    required this.sdkVersion,
    required this.needsAutoStartPermission,
    required this.autoStartGranted,
  });

  /// 检查所有关键权限是否都已授予
  bool get allPermissionsGranted =>
      notificationEnabled &&
      exactAlarmEnabled &&
      batteryOptimizationExempted &&
      (!needsAutoStartPermission || autoStartGranted);

  /// 是否需要显示权限引导
  bool get needsPermissionGuide =>
      !notificationEnabled ||
      !exactAlarmEnabled ||
      !batteryOptimizationExempted ||
      (needsAutoStartPermission && !autoStartGranted);

  /// 获取未授权的权限数量
  int get missingPermissionCount {
    int count = 0;
    if (!notificationEnabled) count++;
    if (!exactAlarmEnabled) count++;
    if (!batteryOptimizationExempted) count++;
    if (needsAutoStartPermission && !autoStartGranted) count++;
    return count;
  }
}
