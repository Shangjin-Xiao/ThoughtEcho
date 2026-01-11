import 'dart:convert';
import 'dart:io';
import 'dart:math';
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
import 'weather_service.dart';
import 'network_service.dart';
import '../utils/app_logger.dart';
import 'background_push_handler.dart';

/// 智能推送服务
/// 
/// 负责根据用户设置筛选笔记并触发推送通知
/// 支持混合模式：
/// - Android: 使用 WorkManager/AlarmManager 实现精确定时
/// - iOS: 使用本地通知调度
/// - 所有平台: 支持前台即时推送
class SmartPushService extends ChangeNotifier {
  final DatabaseService _databaseService;
  final MMKVService _mmkv;
  final LocationService _locationService;
  final FlutterLocalNotificationsPlugin _notificationsPlugin;
  WeatherService? _weatherService;
  
  static const String _settingsKey = 'smart_push_settings_v2';
  static const String _legacySettingsKey = 'smart_push_settings';
  static const int _androidAlarmId = 888;
  static const String _notificationChannelId = 'smart_push_channel';
  static const String _notificationChannelName = '智能推送';
  
  SmartPushSettings _settings = SmartPushSettings.defaultSettings();
  SmartPushSettings get settings => _settings;
  
  bool _isInitialized = false;
  bool get isInitialized => _isInitialized;

  final Random _random = Random();

  SmartPushService({
    required DatabaseService databaseService,
    required LocationService locationService,
    MMKVService? mmkvService,
    FlutterLocalNotificationsPlugin? notificationsPlugin,
    WeatherService? weatherService,
  })  : _databaseService = databaseService,
        _locationService = locationService,
        _mmkv = mmkvService ?? MMKVService(),
        _notificationsPlugin = notificationsPlugin ?? FlutterLocalNotificationsPlugin(),
        _weatherService = weatherService;

  /// 设置天气服务（延迟注入）
  void setWeatherService(WeatherService service) {
    _weatherService = service;
  }

  /// 初始化服务
  Future<void> initialize() async {
    try {
      tz.initializeTimeZones();
      await _loadSettings();
      await _initializeNotifications();

      // Android 平台特定初始化
      if (!kIsWeb && Platform.isAndroid) {
        await AndroidAlarmManager.initialize();
      }

      // 每次启动时重新规划下一次推送
      if (_settings.enabled) {
        await scheduleNextPush();
      }

      _isInitialized = true;
      AppLogger.i('SmartPushService 初始化完成');
    } catch (e, stack) {
      AppLogger.e('SmartPushService 初始化失败', error: e, stackTrace: stack);
    }
  }

  /// 仅供后台 Isolate 使用：加载设置
  Future<void> loadSettingsForBackground() async {
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
      if (_settings.enabled) {
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

    // 创建通知频道（Android 8.0+）
    if (!kIsWeb && Platform.isAndroid) {
      final androidPlugin = _notificationsPlugin
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
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
  }

  /// 通知点击回调
  void _onNotificationTap(NotificationResponse response) {
    AppLogger.i('通知被点击: ${response.payload}');
    // TODO: 可以在这里处理打开特定笔记的逻辑
  }

  /// 请求通知权限
  Future<bool> requestNotificationPermission() async {
    try {
      if (!kIsWeb && Platform.isAndroid) {
        final androidPlugin = _notificationsPlugin
            .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
        if (androidPlugin != null) {
          final granted = await androidPlugin.requestNotificationsPermission();
          return granted ?? false;
        }
      }
      
      if (!kIsWeb && Platform.isIOS) {
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
      }
      
      return true;
    } catch (e) {
      AppLogger.e('请求通知权限失败', error: e);
      return false;
    }
  }

  /// 检查是否有精确闹钟权限（Android 12+）
  Future<bool> checkExactAlarmPermission() async {
    if (kIsWeb || !Platform.isAndroid) return true;
    
    try {
      final androidPlugin = _notificationsPlugin
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      if (androidPlugin != null) {
        // Android 12+ 需要检查 SCHEDULE_EXACT_ALARM 权限
        // 这个权限不是运行时权限，而是需要用户在设置中手动开启
        return await androidPlugin.areNotificationsEnabled() ?? false;
      }
      return true;
    } catch (e) {
      AppLogger.w('检查精确闹钟权限失败', error: e);
      return false;
    }
  }

  /// 规划下一次推送
  Future<void> scheduleNextPush() async {
    if (!_settings.enabled || _settings.pushTimeSlots.isEmpty) {
      await _cancelAllSchedules();
      return;
    }

    // 检查今天是否应该推送
    if (!_settings.shouldPushToday()) {
      AppLogger.d('根据频率设置，今天不推送');
      return;
    }

    // 取消现有的计划
    await _cancelAllSchedules();

    // 找到所有启用的时间槽
    final enabledSlots = _settings.pushTimeSlots.where((s) => s.enabled).toList();
    if (enabledSlots.isEmpty) return;

    for (int i = 0; i < enabledSlots.length; i++) {
      final slot = enabledSlots[i];
      final scheduledDate = _nextInstanceOfTime(slot.hour, slot.minute);
      final id = i;

      if (!kIsWeb && Platform.isAndroid) {
        // Android: 使用 AlarmManager 实现精确定时
        try {
          await AndroidAlarmManager.oneShotAt(
            scheduledDate,
            _androidAlarmId + id,
            backgroundPushCallback,
            exact: true,
            wakeup: true,
            rescheduleOnReboot: true,
            allowWhileIdle: true,
          );
          AppLogger.i('已设定 Android Alarm: $scheduledDate (ID: ${_androidAlarmId + id})');
        } catch (e) {
          AppLogger.e('设定 Android Alarm 失败', error: e);
          // 降级到普通通知调度
          await _scheduleLocalNotification(id, scheduledDate, slot);
        }
      } else {
        // iOS 和其他平台：使用本地通知调度
        await _scheduleLocalNotification(id, scheduledDate, slot);
      }
    }
  }

  /// 使用本地通知调度（降级方案）
  Future<void> _scheduleLocalNotification(int id, tz.TZDateTime scheduledDate, PushTimeSlot slot) async {
    try {
      // 尝试预计算要推送的内容
      final content = await _getPrecomputedContent();
      
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

      await _notificationsPlugin.zonedSchedule(
        id,
        content?.title ?? '💡 回忆时刻',
        content?.body ?? '点击查看今天的灵感',
        scheduledDate,
        details,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        payload: content?.noteId,
        matchDateTimeComponents: DateTimeComponents.time,
      );
      
      AppLogger.i('已设定本地通知: $scheduledDate');
    } catch (e) {
      AppLogger.e('设定本地通知失败', error: e);
    }
  }

  Future<void> _cancelAllSchedules() async {
    await _notificationsPlugin.cancelAll();
    if (!kIsWeb && Platform.isAndroid) {
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
  Future<void> checkAndPush({bool isBackground = false}) async {
    if (!_settings.enabled) return;

    try {
      // 检查今天是否应该推送
      if (!_settings.shouldPushToday()) {
        AppLogger.d('根据频率设置，今天不推送');
        return;
      }

      // 根据推送模式获取内容
      Quote? noteToShow;
      String title = '💡 灵感';
      bool isDailyQuote = false;

      switch (_settings.pushMode) {
        case PushMode.smart:
          // 智能模式：优先推送有意义的回忆，否则推送每日一言
          final candidates = await getCandidateNotes();
          if (candidates.isNotEmpty) {
            noteToShow = _selectBestNote(candidates);
            title = _generateTitle(noteToShow);
          } else {
            // 尝试获取每日一言
            final dailyQuote = await _fetchDailyQuote();
            if (dailyQuote != null) {
              noteToShow = dailyQuote;
              title = '📖 每日一言';
              isDailyQuote = true;
            }
          }
          break;

        case PushMode.dailyQuote:
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
            noteToShow = _selectBestNote(candidates);
            title = _generateTitle(noteToShow);
          }
          break;

        case PushMode.both:
          // 随机选择推送类型
          if (_random.nextBool()) {
            final candidates = await getCandidateNotes();
            if (candidates.isNotEmpty) {
              noteToShow = _selectBestNote(candidates);
              title = _generateTitle(noteToShow);
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
      }

      if (noteToShow != null) {
        await _showNotification(noteToShow, title: title);

        // 记录推送历史（避免重复推送）
        if (!isDailyQuote && noteToShow.id != null) {
          final updatedSettings = _settings.addPushedNoteId(noteToShow.id!);
          await saveSettings(updatedSettings);
        }

        AppLogger.i('推送成功: ${noteToShow.content.substring(0, min(50, noteToShow.content.length))}...');
      } else {
        AppLogger.d('没有内容可推送');
      }

      // 重新调度下一次推送
      if (!isBackground) {
        await scheduleNextPush();
      }
    } catch (e, stack) {
      AppLogger.e('智能推送失败', error: e, stackTrace: stack);
    }
  }

  /// 选择最佳笔记（避免重复）
  Quote _selectBestNote(List<Quote> candidates) {
    // 过滤掉最近已推送的笔记
    final filtered = candidates.where((note) => 
      note.id == null || !_settings.recentlyPushedNoteIds.contains(note.id)
    ).toList();

    // 如果过滤后没有候选，使用原始列表
    final pool = filtered.isNotEmpty ? filtered : candidates;

    // 优先级排序：那年今日 > 往月今日 > 同地点 > 同天气 > 随机
    pool.sort((a, b) {
      final now = DateTime.now();
      final aDate = DateTime.tryParse(a.date) ?? now;
      final bDate = DateTime.tryParse(b.date) ?? now;

      // 那年今日优先
      final aIsYearAgo = aDate.month == now.month && aDate.day == now.day && aDate.year < now.year;
      final bIsYearAgo = bDate.month == now.month && bDate.day == now.day && bDate.year < now.year;
      if (aIsYearAgo && !bIsYearAgo) return -1;
      if (bIsYearAgo && !aIsYearAgo) return 1;

      // 年份越久越优先
      if (aIsYearAgo && bIsYearAgo) {
        return aDate.year - bDate.year;
      }

      return 0;
    });

    return pool.first;
  }

  /// 生成推送标题
  String _generateTitle(Quote note) {
    final now = DateTime.now();
    final noteDate = DateTime.tryParse(note.date);
    
    if (noteDate != null) {
      // 那年今日
      if (noteDate.month == now.month && noteDate.day == now.day && noteDate.year < now.year) {
        final years = now.year - noteDate.year;
        return '📅 $years年前的今天';
      }
      
      // 往月今日
      if (noteDate.day == now.day && noteDate.year == now.year && noteDate.month < now.month) {
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
        final data = json.decode(response.body);
        if (data != null && data['hitokoto'] != null) {
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

  /// 显示通知
  Future<void> _showNotification(Quote note, {String title = '通知'}) async {
    final androidDetails = AndroidNotificationDetails(
      _notificationChannelId,
      _notificationChannelName,
      channelDescription: '回顾过去的笔记和每日一言',
      importance: Importance.high,
      priority: Priority.high,
      showWhen: true,
      styleInformation: note.content.length > 50
          ? BigTextStyleInformation(
              _truncateContent(note.content),
              contentTitle: title,
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

    await _notificationsPlugin.show(
      DateTime.now().millisecondsSinceEpoch % 100000,
      title,
      _truncateContent(note.content),
      details,
      payload: note.id,
    );
  }

  /// 获取候选推送笔记
  Future<List<Quote>> getCandidateNotes() async {
    final candidates = <Quote>[];
    final allNotes = await _databaseService.getUserQuotes();
    
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

  /// 从位置字符串提取区名
  String? _extractDistrict(String location) {
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
        return weatherKeywords.any((keyword) =>
            lowerWeather.contains(keyword.toLowerCase()));
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
    final coreWeatherTerms = ['晴', '阴', '云', '雨', '雪', '雾', '霾', 
                              'clear', 'cloudy', 'rain', 'snow', 'fog'];
    
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
      case PushMode.dailyQuote:
        return await _fetchDailyQuote();
      case PushMode.pastNotes:
      case PushMode.smart:
      case PushMode.both:
        final candidates = await getCandidateNotes();
        if (candidates.isNotEmpty) {
          return _selectBestNote(candidates);
        }
        if (_settings.pushMode == PushMode.smart || _settings.pushMode == PushMode.both) {
          return await _fetchDailyQuote();
        }
        return null;
    }
  }

  /// 手动触发推送
  Future<void> triggerPush() async {
    await checkAndPush();
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
