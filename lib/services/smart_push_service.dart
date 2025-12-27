import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:android_alarm_manager_plus/android_alarm_manager_plus.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz;

import '../models/smart_push_settings.dart';
import '../models/quote_model.dart';
import 'database_service.dart';
import 'mmkv_service.dart';
import 'location_service.dart';
import '../utils/app_logger.dart';
import 'background_push_handler.dart'; // 引入后台回调

/// 智能推送服务
/// 
/// 负责根据用户设置筛选笔记并触发推送通知
/// 支持混合模式：静态定时推送（跨平台）和动态后台检查（Android）
class SmartPushService extends ChangeNotifier {
  final DatabaseService _databaseService;
  final MMKVService _mmkv;
  final LocationService _locationService;
  final FlutterLocalNotificationsPlugin _notificationsPlugin;
  
  static const String _settingsKey = 'smart_push_settings';
  static const int _androidAlarmId = 888; // 唯一的 Alarm ID
  
  SmartPushSettings _settings = SmartPushSettings.defaultSettings();
  SmartPushSettings get settings => _settings;
  
  bool _isInitialized = false;
  bool get isInitialized => _isInitialized;

  SmartPushService({
    required DatabaseService databaseService,
    required LocationService locationService,
    MMKVService? mmkvService,
    FlutterLocalNotificationsPlugin? notificationsPlugin,
  })  : _databaseService = databaseService,
        _locationService = locationService,
        _mmkv = mmkvService ?? MMKVService(),
        _notificationsPlugin = notificationsPlugin ?? FlutterLocalNotificationsPlugin();

  /// 初始化服务
  Future<void> initialize() async {
    try {
      tz.initializeTimeZones(); // 初始化时区数据
      await _loadSettings();
      await _initializeNotifications();

      // Android 平台特定初始化
      if (!kIsWeb && Platform.isAndroid) {
        await AndroidAlarmManager.initialize();
      }

      // 每次启动时重新规划下一次推送
      await scheduleNextPush();

      _isInitialized = true;
      AppLogger.i('SmartPushService 初始化完成');
    } catch (e, stack) {
      AppLogger.e('SmartPushService 初始化失败', error: e, stackTrace: stack);
    }
  }

  /// 仅供后台 Isolate 使用：加载设置
  Future<void> loadSettingsForBackground() async {
    await _loadSettings();
    await _initializeNotifications(); // 后台也需要发通知，所以初始化通知插件
  }

  /// 加载设置
  Future<void> _loadSettings() async {
    try {
      final jsonStr = _mmkv.getString(_settingsKey);
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
      await scheduleNextPush();
    } catch (e, stack) {
      AppLogger.e('保存智能推送设置失败', error: e, stackTrace: stack);
      rethrow;
    }
  }

  /// 初始化通知插件
  Future<void> _initializeNotifications() async {
    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
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
  }

  /// 通知点击回调
  void _onNotificationTap(NotificationResponse response) {
    AppLogger.i('通知被点击: ${response.payload}');
    // 可以在这里处理打开特定笔记的逻辑
  }

  /// 请求通知权限
  Future<bool> requestNotificationPermission() async {
    try {
      final androidPlugin = _notificationsPlugin
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      if (androidPlugin != null) {
        final granted = await androidPlugin.requestNotificationsPermission();
        // Android 12+ 需要额外请求精准闹钟权限，如果使用了 alarm manager
        if (!kIsWeb && Platform.isAndroid) {
          // 这里可以顺便检查 SCHEDULE_EXACT_ALARM，但它通常不是运行时权限对话框，
          // 而是跳转设置。暂时简化。
        }
        return granted ?? false;
      }
      
      final iosPlugin = _notificationsPlugin
          .resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>();
      if (iosPlugin != null) {
        final granted = await iosPlugin.requestPermissions(
          alert: true,
          badge: true,
          sound: true,
        );
        return granted ?? false;
      }
      
      return true; // 其他平台默认允许
    } catch (e) {
      AppLogger.e('请求通知权限失败', error: e);
      return false;
    }
  }

  /// 规划下一次推送
  ///
  /// 根据平台和设置选择：
  /// - Android & 动态设置：使用 AndroidAlarmManager (Plan A)
  /// - 其他情况：使用 FlutterLocalNotifications 的 zonedSchedule (Plan B)
  Future<void> scheduleNextPush() async {
    if (!_settings.enabled || _settings.pushTimeSlots.isEmpty) {
      await _cancelAllSchedules();
      return;
    }

    // 取消现有的计划
    await _cancelAllSchedules();

    // 找到所有启用的时间槽
    final enabledSlots = _settings.pushTimeSlots.where((s) => s.enabled).toList();
    if (enabledSlots.isEmpty) return;

    // 简单起见，我们为每个时间槽都设定计划
    for (int i = 0; i < enabledSlots.length; i++) {
      final slot = enabledSlots[i];
      final scheduledDate = _nextInstanceOfTime(slot.hour, slot.minute);
      final id = i; // 使用索引作为 ID

      // 检查是否需要动态功能 (Android Only)
      bool needsDynamic = !kIsWeb && Platform.isAndroid &&
          (_settings.enabledPastNoteTypes.contains(PastNoteType.sameWeather) ||
           _settings.enabledPastNoteTypes.contains(PastNoteType.sameLocation));

      if (needsDynamic) {
        // Plan A: Android AlarmManager
        // 注意：AlarmManager 的 ID 最好固定或有规律。这里我们只支持单一主要的唤醒，
        // 或者为每个 slot 分配不同的 alarm ID。
        // 为简化，我们暂时只处理第一个有效的时间槽作为 Alarm，或者使用 index + baseID
        try {
          await AndroidAlarmManager.oneShotAt(
            scheduledDate,
            _androidAlarmId + id,
            backgroundPushCallback,
            exact: true,
            wakeup: true,
            rescheduleOnReboot: true,
          );
          AppLogger.i('已设定 Android Alarm: $scheduledDate (ID: ${_androidAlarmId + id})');
        } catch (e) {
          AppLogger.e('设定 Android Alarm 失败 (可能是缺少精确闹钟权限)', error: e);
          // 降级处理：尝试使用非精确闹钟或仅提示用户
        }
      } else {
        // Plan B: Static Scheduled Notification
        // 尝试预计算内容 (例如"那年今日")
        final quote = await _precomputeStaticContent(scheduledDate);
        if (quote != null) {
          // 如果找到了特定日期的回顾，直接设定通知
          await _scheduleNotification(id, '📝 回忆', quote.content, scheduledDate, payload: quote.id);
          AppLogger.i('已设定静态通知: $scheduledDate - ${quote.content.substring(0, 10)}...');
        } else if (_settings.enabledContentTypes.contains(PushContentType.dailyQuote)) {
             // 如果没找到回顾，但开启了每日一言，可以推送一条随机语录 (模拟)
             // 实际项目中可能需要预先存好每日一言。这里简化为"点击查看"
             // 或者我们暂时不推送，或者推送一个通用的。
             // 为了用户体验，我们设定一个通用通知
             await _scheduleNotification(
               id,
               'Daily Inspiration',
               '点击查看今天的每日一言',
               scheduledDate
             );
        }
      }
    }
  }

  Future<void> _cancelAllSchedules() async {
    await _notificationsPlugin.cancelAll();
    if (!kIsWeb && Platform.isAndroid) {
      // 假设我们最多支持 10 个时间槽
      for (int i = 0; i < 10; i++) {
        await AndroidAlarmManager.cancel(_androidAlarmId + i);
      }
    }
  }

  /// 计算下一个时间点
  tz.TZDateTime _nextInstanceOfTime(int hour, int minute) {
    final now = tz.TZDateTime.now(tz.local);
    var scheduledDate = tz.TZDateTime(tz.local, now.year, now.month, now.day, hour, minute);
    if (scheduledDate.isBefore(now)) {
      scheduledDate = scheduledDate.add(const Duration(days: 1));
    }
    return scheduledDate;
  }

  /// 预计算静态内容 (用于 Plan B)
  Future<Quote?> _precomputeStaticContent(DateTime date) async {
    // 检查"那年今日"
    if (_settings.enabledPastNoteTypes.contains(PastNoteType.yearAgoToday)) {
      final allNotes = await _databaseService.getUserQuotes();
      final candidates = _filterYearAgoToday(allNotes, date);
      if (candidates.isNotEmpty) return candidates.first;
    }
    return null;
  }

  /// 检查并触发推送 (核心逻辑，前后台通用)
  /// [isBackground] 标记是否在后台调用，如果是，可能会有不同的日志或错误处理
  Future<void> checkAndPush({bool isBackground = false}) async {
    if (!_settings.enabled) return;

    try {
      final now = DateTime.now();
      
      // 检查是否已经推送过今天 (可选，防止重复，但如果用户设置了多个时间点可能需要放开)
      // 这里简化逻辑：如果是手动测试或不同时间段，允许推送
      // 实际生产中可以检查 _settings.lastPushTime

      // 获取候选笔记
      final notes = await getCandidateNotes();

      Quote? noteToShow;
      String title = '💡 灵感';

      if (notes.isNotEmpty) {
        // 优先显示动态匹配的 (天气/地点)
        // 简单的优先级策略：同天气 > 同地点 > 那年今日 > 随机
        noteToShow = notes.first;

        // 生成标题
        final noteDate = DateTime.parse(noteToShow.date);
        if (noteDate.year < now.year && noteDate.month == now.month && noteDate.day == now.day) {
          title = '📅 ${now.year - noteDate.year}年前的今天';
        } else if (_settings.enabledPastNoteTypes.contains(PastNoteType.sameLocation) &&
                   notes.any((n) => n.id == noteToShow!.id && (n.location?.isNotEmpty ?? false))) {
           // 这里判断稍微粗糙，实际应标记来源
           title = '📍 熟悉的地点';
        } else if (_settings.enabledPastNoteTypes.contains(PastNoteType.sameWeather)) {
           title = '🌤️ 此情此景';
        }
      } else if (_settings.enabledContentTypes.contains(PushContentType.dailyQuote)) {
        // 如果没有回顾，但开启了每日一言，尝试获取每日一言 (这里模拟，因为 DatabaseService 可能没这个接口)
        // 假设 getUserQuotes 包含所有，如果没有特定的，随机取一条作为每日一言
        final allNotes = await _databaseService.getUserQuotes();
        if (allNotes.isNotEmpty) {
          noteToShow = (allNotes..shuffle()).first;
          title = '📖 每日回顾';
        }
      }

      if (noteToShow != null) {
        await _showNotificationInternal(noteToShow, title: title);

        // 如果是在后台唤醒的，说明这是一个新的周期，可以更新 lastPushTime
        if (isBackground) {
           // 注意：后台无法直接更新 MMKV 并通知 UI，只能写入文件
           // 但下次启动时会重新加载
           // 这里暂不处理复杂的跨进程状态同步
        }
        AppLogger.i('推送成功: ${noteToShow.content}');
      } else {
        AppLogger.d('没有内容可推送');
      }
    } catch (e, stack) {
      AppLogger.e('智能推送失败', error: e, stackTrace: stack);
    }
  }

  /// 内部显示通知方法
  Future<void> _showNotificationInternal(Quote note, {String title = '通知'}) async {
    const androidDetails = AndroidNotificationDetails(
      'smart_push_channel',
      '智能推送',
      channelDescription: '回顾过去的笔记和每日一言',
      importance: Importance.high,
      priority: Priority.high,
      showWhen: true,
    );

    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    const details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    String body = note.content;
    if (body.length > 100) {
      body = '${body.substring(0, 100)}...';
    }

    await _notificationsPlugin.show(
      DateTime.now().millisecondsSinceEpoch % 100000,
      title,
      body,
      details,
      payload: note.id,
    );
  }

  /// 设定定时通知 (Plan B)
  Future<void> _scheduleNotification(int id, String title, String body, tz.TZDateTime scheduledDate, {String? payload}) async {
    const androidDetails = AndroidNotificationDetails(
      'smart_push_channel',
      '智能推送',
      channelDescription: '回顾过去的笔记和每日一言',
      importance: Importance.high,
      priority: Priority.high,
    );

    const details = NotificationDetails(android: androidDetails);

    await _notificationsPlugin.zonedSchedule(
      id,
      title,
      body,
      scheduledDate,
      details,
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
      payload: payload,
      matchDateTimeComponents: DateTimeComponents.time, // 每天同一时间触发
    );
  }

  /// 获取候选推送笔记
  Future<List<Quote>> getCandidateNotes() async {
    final candidates = <Quote>[];
    final allNotes = await _databaseService.getUserQuotes();
    final now = DateTime.now();

    for (final noteType in _settings.enabledPastNoteTypes) {
      switch (noteType) {
        case PastNoteType.yearAgoToday:
          candidates.addAll(_filterYearAgoToday(allNotes, now));
          break;
        case PastNoteType.monthAgoToday:
          candidates.addAll(_filterMonthAgoToday(allNotes, now));
          break;
        case PastNoteType.sameLocation:
          // 此操作可能涉及异步定位
          candidates.addAll(await _filterSameLocation(allNotes));
          break;
        case PastNoteType.sameWeather:
          candidates.addAll(_filterSameWeather(allNotes));
          break;
      }
    }

    // 如果设置了标签筛选，进一步过滤
    if (_settings.filterTagIds.isNotEmpty) {
      candidates.removeWhere((note) =>
          !note.tagIds.any((tagId) => _settings.filterTagIds.contains(tagId)));
    }

    // 去重
    final uniqueIds = <String>{};
    candidates.removeWhere((note) {
      if (note.id == null || uniqueIds.contains(note.id)) return true;
      uniqueIds.add(note.id!);
      return false;
    });

    return candidates;
  }

  /// 筛选去年今日的笔记
  List<Quote> _filterYearAgoToday(List<Quote> notes, DateTime now) {
    return notes.where((note) {
      try {
        final noteDate = DateTime.parse(note.date);
        // 检查是否是往年的今天（同月同日，但不同年）
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
        // 检查是否是上个月（或更早月份）的同一天
        return noteDate.day == now.day &&
               (noteDate.year < now.year ||
                (noteDate.year == now.year && noteDate.month < now.month));
      } catch (e) {
        return false;
      }
    }).toList();
  }

  /// 筛选相同地点的笔记（区级别匹配）
  Future<List<Quote>> _filterSameLocation(List<Quote> notes) async {
    try {
      // 获取当前位置
      final currentLocation = _locationService.getFormattedLocation();
      if (currentLocation.isEmpty) {
        // 如果缓存为空，尝试刷新（注意：后台定位可能失败）
        await _locationService.init();
        if (_locationService.getFormattedLocation().isEmpty) return [];
      }
      final validLocation = _locationService.getFormattedLocation();

      // 提取区名（假设格式为"城市·区"或包含区名）
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

  /// 从位置字符串提取区名
  String? _extractDistrict(String location) {
    // 处理"城市·区"格式
    if (location.contains('·')) {
      final parts = location.split('·');
      if (parts.length >= 2) {
        return parts[1].trim();
      }
    }
    
    // 处理包含"区"字的情况
    final districtMatch = RegExp(r'([^省市县]+(?:区|县|市))').firstMatch(location);
    if (districtMatch != null) {
      return districtMatch.group(1);
    }
    
    return location;
  }

  /// 筛选相同天气的笔记
  List<Quote> _filterSameWeather(List<Quote> notes) {
    if (_settings.filterWeatherTypes.isEmpty) return [];

    // 注意：WeatherService 在后台可能需要额外初始化或 API 调用
    // 这里暂时依赖 WeatherService 的缓存或同步接口，实际可能需要异步
    // 假设 WeatherService 暂无同步获取当前天气的接口，我们略过实时天气获取逻辑，
    // 仅当 Note 包含 Weather 字段时进行匹配（伪逻辑：这里需要 Real Weather API）
    // 由于 WeatherService 复杂性，我们暂时跳过"获取当前天气"的步骤，
    // 实际应调用 WeatherService.fetchCurrentWeather()

    final weatherKeywords = <String>[];
    for (final weatherType in _settings.filterWeatherTypes) {
      switch (weatherType) {
        case WeatherFilterType.clear:
          weatherKeywords.addAll(['晴', 'clear', 'sunny']);
          break;
        case WeatherFilterType.cloudy:
          weatherKeywords.addAll(['多云', 'cloudy', '阴']);
          break;
        case WeatherFilterType.rain:
          weatherKeywords.addAll(['雨', 'rain', '阵雨']);
          break;
        case WeatherFilterType.snow:
          weatherKeywords.addAll(['雪', 'snow']);
          break;
        case WeatherFilterType.fog:
          weatherKeywords.addAll(['雾', 'fog', '霾']);
          break;
      }
    }

    return notes.where((note) {
      if (note.weather == null || note.weather!.isEmpty) return false;
      final lowerWeather = note.weather!.toLowerCase();
      return weatherKeywords.any((keyword) =>
          lowerWeather.contains(keyword.toLowerCase()));
    }).toList();
  }

  /// 预览推送内容（用于设置页面测试）
  Future<Quote?> previewPush() async {
    final candidates = await getCandidateNotes();
    return candidates.isNotEmpty ? candidates.first : null;
  }

  /// 手动触发推送（用于测试）
  Future<void> triggerPush() async {
    await checkAndPush();
  }
}
