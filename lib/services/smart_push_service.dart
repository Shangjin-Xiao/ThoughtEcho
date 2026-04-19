import 'dart:async';
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

import '../gen_l10n/app_localizations.dart';
import '../models/app_settings.dart';
import '../models/smart_push_settings.dart';
import '../models/quote_model.dart';
import '../pages/home_page.dart';
import '../main.dart' show navigatorKey;
import 'api_service.dart';
import 'database_service.dart';
import 'mmkv_service.dart';
import 'location_service.dart';
import 'weather_service.dart';
import '../utils/app_logger.dart';
import '../utils/platform_helper.dart';
import '../utils/string_utils.dart';
import 'background_push_handler.dart';
import 'smart_push_analytics.dart';
import 'smart_push_computation.dart';
import 'pico_ble_service.dart'; // 引入以支持自动推送到硬件

part 'smart_push/smart_push_scheduling.dart';
part 'smart_push/smart_push_platform.dart';
part 'smart_push/smart_push_notification.dart';
part 'smart_push/smart_push_execution.dart';
part 'smart_push/smart_push_content.dart';
part 'smart_push/smart_push_permissions.dart';

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
  static const String _lastDailyQuoteDateKey =
      'smart_push_last_daily_quote_date';
  static const String _pendingHomeDailyQuoteKey =
      'smart_push_pending_home_daily_quote';
  static const String _dailyQuotePushedDateKey =
      'smart_push_daily_quote_pushed_date';
  static const String _inactivityQuoteDateKey =
      'smart_push_inactivity_quote_date';
  static const String _appSettingsKey = 'app_settings';

  /// 今日智能推送是否已执行过（任意内容类型）
  static const String _todayPushedDateKey = 'smart_push_today_pushed_date';

  /// 今日是否已推送过每日一言（智能推送流程内）
  static const String _todayDailyQuotePushedKey =
      'smart_push_today_daily_quote_pushed';

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

  bool _notificationPluginReady = false;

  @protected
  void notifyListenersFromParts() {
    notifyListeners();
  }

  // ================================================================
  // 每日一言内容去重（基于内容哈希，允许一天多条不同内容）
  // 放在主类中以便所有 extension part 文件共享访问
  // ================================================================

  /// 检查某条每日一言内容是否已在今天推送过
  bool _hasDailyQuoteContentPushed(String content) {
    final pushedData = _mmkv.getString(_dailyQuotePushedDateKey);
    if (pushedData == null) return false;

    final today = DateTime.now().toIso8601String().substring(0, 10);
    // 格式: "2026-03-13|hash1,hash2,hash3"
    if (!pushedData.startsWith('$today|')) return false;

    final contentHash = _contentHash(content);
    final hashesStr = pushedData.substring(today.length + 1);
    final pushedHashes = hashesStr.split(',').toSet();
    return pushedHashes.contains(contentHash);
  }

  /// 标记某条每日一言内容已推送
  void _markDailyQuoteContentPushed(String content) {
    final today = DateTime.now().toIso8601String().substring(0, 10);
    final contentHash = _contentHash(content);

    final pushedData = _mmkv.getString(_dailyQuotePushedDateKey);
    String newData;

    if (pushedData != null && pushedData.startsWith('$today|')) {
      newData = '$pushedData,$contentHash';
    } else {
      newData = '$today|$contentHash';
    }

    _mmkv.setString(_dailyQuotePushedDateKey, newData);
  }

  /// 生成内容的简短哈希（用前 50 字符的 hashCode）
  String _contentHash(String content) {
    final key = content.length > 50 ? content.substring(0, 50) : content;
    return key.hashCode.toRadixString(36);
  }

  // ================================================================
  // 今日推送状态追踪（用于优化推送算法）
  // ================================================================

  /// 检查今日是否已有任何推送
  bool _hasPushedToday() {
    final today = DateTime.now().toIso8601String().substring(0, 10);
    return _mmkv.getString(_todayPushedDateKey) == today;
  }

  /// 标记今日已推送
  void _markPushedToday() {
    final today = DateTime.now().toIso8601String().substring(0, 10);
    _mmkv.setString(_todayPushedDateKey, today);
  }

  /// 检查今日在智能推送流程中是否已推送每日一言
  bool _hasDailyQuotePushedTodayInSmartPush() {
    final today = DateTime.now().toIso8601String().substring(0, 10);
    return _mmkv.getString(_todayDailyQuotePushedKey) == today;
  }

  /// 标记今日智能推送流程中已推送每日一言
  void _markDailyQuotePushedTodayInSmartPush() {
    final today = DateTime.now().toIso8601String().substring(0, 10);
    _mmkv.setString(_todayDailyQuotePushedKey, today);
  }

  /// 统一每日一言数据格式，确保首页与推送使用同一结构。
  static Map<String, dynamic>? normalizeDailyQuoteData(
    Map<String, dynamic>? rawData,
  ) {
    if (rawData == null) return null;

    final content =
        (rawData['hitokoto'] ?? rawData['content'])?.toString().trim() ?? '';
    if (content.isEmpty) return null;

    final fromWho =
        (rawData['from_who'] ?? rawData['author'] ?? '').toString().trim();
    final from = (rawData['from'] ?? rawData['source'] ?? '').toString().trim();
    final type = (rawData['type'] ?? '').toString().trim();
    final provider = (rawData['provider'] ?? '').toString().trim();

    return {
      'hitokoto': content,
      'from_who': fromWho,
      'from': from,
      if (type.isNotEmpty) 'type': type,
      if (provider.isNotEmpty) 'provider': provider,
    };
  }

  static bool isWithinPushWindow(
    DateTime now,
    PushTimeSlot slot, {
    int toleranceMinutes = 10,
  }) {
    final slotTime = DateTime(
      now.year,
      now.month,
      now.day,
      slot.hour,
      slot.minute,
    );
    final diff = now.difference(slotTime).inMinutes;
    return diff >= 0 && diff <= toleranceMinutes;
  }

  static bool isWithinAnyPushWindow(
    DateTime now,
    Iterable<PushTimeSlot> slots, {
    int toleranceMinutes = 10,
  }) {
    return slots.any(
      (slot) => isWithinPushWindow(
        now,
        slot,
        toleranceMinutes: toleranceMinutes,
      ),
    );
  }

  static String? buildNotificationPayload({
    String? noteId,
    required String contentType,
    String? routeTarget,
  }) {
    if (contentType.isEmpty) return null;
    final parts = <String>['contentType:$contentType'];
    if (noteId != null && noteId.isNotEmpty) {
      parts.add('noteId:$noteId');
    }
    if (routeTarget != null && routeTarget.isNotEmpty) {
      parts.add('routeTarget:$routeTarget');
    }
    return parts.join('|');
  }

  @visibleForTesting
  static String? notificationSummaryForTest(Quote note) => null;

  static void replaceAppStackForNotification<T extends Object?>({
    required NavigatorState navigator,
    required Route<T> route,
  }) {
    navigator.pushAndRemoveUntil(route, (existingRoute) => false);
  }

  static DateTime nextScheduledDate({
    required DateTime now,
    required int hour,
    required int minute,
    required SmartPushSettings settings,
    bool respectsFrequency = true,
  }) {
    var scheduledDate = DateTime(
      now.year,
      now.month,
      now.day,
      hour,
      minute,
    );

    if (scheduledDate.isBefore(now)) {
      scheduledDate = scheduledDate.add(const Duration(days: 1));
    }

    if (!respectsFrequency) {
      return scheduledDate;
    }

    final nextAllowedDate = settings.nextPushDateFrom(scheduledDate);
    return DateTime(
      nextAllowedDate.year,
      nextAllowedDate.month,
      nextAllowedDate.day,
      hour,
      minute,
    );
  }

  /// 设置天气服务（延迟注入）
  void setWeatherService(WeatherService service) {
    _weatherService = service;
    notifyListeners();
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

      // 处理冷启动场景：检查 App 是否由通知点击启动
      await _handleLaunchNotification();

      AppLogger.i(
        'SmartPushService settings: enabled=${_settings.enabled}, dailyQuoteEnabled=${_settings.dailyQuotePushEnabled}',
      );

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

        if (PlatformHelper.isAndroid) {
          final canScheduleExact = await _canScheduleExactAlarms();
          if (canScheduleExact) {
            await _cancelPeriodicFallbackTask();
          } else {
            await _registerPeriodicFallbackTask();
          }
        }
      } else {
        await _cancelAllSchedules();
      }
    } catch (e, stack) {
      AppLogger.e('保存智能推送设置失败', error: e, stackTrace: stack);
      rethrow;
    }
  }

  /// 仅持久化设置到 MMKV，不触发重新调度
  ///
  /// 用于后台推送成功后记录已推送笔记 ID 等场景，
  /// 避免 [saveSettings] 中的 [scheduleNextPush] / [_cancelAllSchedules]
  /// 意外取消刚刚显示的通知。
  Future<void> _saveSettingsQuietly(SmartPushSettings newSettings) async {
    try {
      _settings = newSettings;
      final jsonStr = jsonEncode(newSettings.toJson());
      await _mmkv.setString(_settingsKey, jsonStr);
      AppLogger.i('智能推送设置已静默保存（不触发重新调度）');
    } catch (e, stack) {
      AppLogger.e('静默保存智能推送设置失败', error: e, stackTrace: stack);
    }
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
        final candidates = await getTypedCandidateNotes();
        if (candidates.isNotEmpty) {
          return candidates.first.note;
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
  final String? contentType;

  _PushContent({
    required this.title,
    required this.body,
    this.noteId,
    this.contentType,
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
    this.contentType = 'dailyQuote',
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
  final bool isDailyQuote;

  _ContentCandidate({
    required this.note,
    required this.title,
    required this.priority,
    this.isDailyQuote = false,
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
