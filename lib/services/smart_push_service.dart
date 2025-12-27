import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../models/smart_push_settings.dart';
import '../models/quote_model.dart';
import 'database_service.dart';
import 'mmkv_service.dart';
import 'location_service.dart';
import '../utils/app_logger.dart';

/// 智能推送服务
/// 
/// 负责根据用户设置筛选笔记并触发推送通知
class SmartPushService extends ChangeNotifier {
  final DatabaseService _databaseService;
  final MMKVService _mmkv;
  final LocationService _locationService;
  final FlutterLocalNotificationsPlugin _notificationsPlugin;
  
  static const String _settingsKey = 'smart_push_settings';
  
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
      await _loadSettings();
      await _initializeNotifications();
      _isInitialized = true;
      AppLogger.i('SmartPushService 初始化完成');
    } catch (e, stack) {
      AppLogger.e('SmartPushService 初始化失败', error: e, stackTrace: stack);
    }
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

  /// 保存设置
  Future<void> saveSettings(SmartPushSettings newSettings) async {
    try {
      _settings = newSettings;
      final jsonStr = jsonEncode(newSettings.toJson());
      await _mmkv.setString(_settingsKey, jsonStr);
      notifyListeners();
      AppLogger.i('智能推送设置已保存');
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

  /// 检查并触发今日推送
  Future<void> checkAndPush() async {
    if (!_settings.enabled) return;

    try {
      final now = DateTime.now();
      
      // 检查是否已经推送过今天
      if (_settings.lastPushTime != null) {
        final lastPush = _settings.lastPushTime!;
        if (lastPush.year == now.year &&
            lastPush.month == now.month &&
            lastPush.day == now.day) {
          AppLogger.d('今日已推送，跳过');
          return;
        }
      }

      // 获取候选笔记
      final notes = await getCandidateNotes();
      if (notes.isEmpty) {
        AppLogger.d('没有符合条件的笔记可推送');
        return;
      }

      // 选择一条笔记推送
      final noteToShow = notes.first;
      await _showNotification(noteToShow);

      // 更新最后推送时间
      await saveSettings(_settings.copyWith(lastPushTime: now));
      
      AppLogger.i('智能推送完成: ${noteToShow.content.substring(0, noteToShow.content.length.clamp(0, 50))}...');
    } catch (e, stack) {
      AppLogger.e('智能推送失败', error: e, stackTrace: stack);
    }
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
    // 获取当前位置
    final currentLocation = _locationService.getFormattedLocation();
    if (currentLocation.isEmpty) {
      return [];
    }

    // 提取区名（假设格式为"城市·区"或包含区名）
    final currentDistrict = _extractDistrict(currentLocation);
    if (currentDistrict == null) return [];

    return notes.where((note) {
      if (note.location == null || note.location!.isEmpty) return false;
      final noteDistrict = _extractDistrict(note.location!);
      return noteDistrict != null &&
             noteDistrict.toLowerCase() == currentDistrict.toLowerCase();
    }).toList();
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

  /// 显示推送通知
  Future<void> _showNotification(Quote note) async {
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

    // 生成通知标题
    String title = '📝 回忆';
    try {
      final noteDate = DateTime.parse(note.date);
      final now = DateTime.now();
      if (noteDate.year < now.year && noteDate.month == now.month && noteDate.day == now.day) {
        title = '📅 ${now.year - noteDate.year}年前的今天';
      } else if (note.location != null && note.location!.isNotEmpty) {
        title = '📍 ${note.location}的记忆';
      } else if (note.weather != null && note.weather!.isNotEmpty) {
        title = '🌤️ 同样的${note.weather}';
      }
    } catch (_) {}

    // 截取内容
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

  /// 预览推送内容（用于设置页面测试）
  Future<Quote?> previewPush() async {
    final candidates = await getCandidateNotes();
    return candidates.isNotEmpty ? candidates.first : null;
  }

  /// 手动触发推送（用于测试）
  Future<void> triggerPush() async {
    final note = await previewPush();
    if (note != null) {
      await _showNotification(note);
    }
  }
}
