/// 智能推送设置数据模型
/// 
/// 用于配置笔记智能推送功能，包括推送类型、时间、筛选条件等

/// 推送内容类型
enum PushContentType {
  dailyQuote,        // 每日一言
  pastNotes,         // 过去的笔记
}

/// 过去笔记的推送类型
enum PastNoteType {
  yearAgoToday,      // 去年今日
  monthAgoToday,     // 往月今日（上个月的今天）
  sameLocation,      // 相同地点
  sameWeather,       // 相同天气
}

/// 天气类型（用于筛选）
enum WeatherFilterType {
  clear,             // 晴
  cloudy,            // 多云
  rain,              // 雨
  snow,              // 雪
  fog,               // 雾
}

/// 推送时间段
class PushTimeSlot {
  final int hour;      // 小时 (0-23)
  final int minute;    // 分钟 (0-59)
  final bool enabled;  // 是否启用

  const PushTimeSlot({
    required this.hour,
    required this.minute,
    this.enabled = true,
  });

  factory PushTimeSlot.fromJson(Map<String, dynamic> json) {
    return PushTimeSlot(
      hour: json['hour'] as int? ?? 8,
      minute: json['minute'] as int? ?? 0,
      enabled: json['enabled'] as bool? ?? true,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'hour': hour,
      'minute': minute,
      'enabled': enabled,
    };
  }

  PushTimeSlot copyWith({
    int? hour,
    int? minute,
    bool? enabled,
  }) {
    return PushTimeSlot(
      hour: hour ?? this.hour,
      minute: minute ?? this.minute,
      enabled: enabled ?? this.enabled,
    );
  }

  String get formattedTime {
    return '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PushTimeSlot &&
          runtimeType == other.runtimeType &&
          hour == other.hour &&
          minute == other.minute &&
          enabled == other.enabled;

  @override
  int get hashCode => hour.hashCode ^ minute.hashCode ^ enabled.hashCode;
}

/// 智能推送设置
class SmartPushSettings {
  /// 是否启用智能推送
  final bool enabled;

  /// 启用的推送内容类型
  final Set<PushContentType> enabledContentTypes;

  /// 启用的过去笔记类型
  final Set<PastNoteType> enabledPastNoteTypes;

  /// 筛选的标签ID列表
  final List<String> filterTagIds;

  /// 筛选的天气类型
  final Set<WeatherFilterType> filterWeatherTypes;

  /// 推送时间段列表
  final List<PushTimeSlot> pushTimeSlots;

  /// 是否启用AI智能推送（预留）
  final bool aiPushEnabled;

  /// 上次推送时间
  final DateTime? lastPushTime;

  const SmartPushSettings({
    this.enabled = false,
    this.enabledContentTypes = const {PushContentType.dailyQuote, PushContentType.pastNotes},
    this.enabledPastNoteTypes = const {PastNoteType.yearAgoToday},
    this.filterTagIds = const [],
    this.filterWeatherTypes = const {},
    this.pushTimeSlots = const [
      PushTimeSlot(hour: 8, minute: 0),  // 默认早上8点
    ],
    this.aiPushEnabled = false,
    this.lastPushTime,
  });

  factory SmartPushSettings.defaultSettings() => const SmartPushSettings();

  factory SmartPushSettings.fromJson(Map<String, dynamic> json) {
    return SmartPushSettings(
      enabled: json['enabled'] as bool? ?? false,
      enabledContentTypes: (json['enabledContentTypes'] as List<dynamic>?)
              ?.map((e) => PushContentType.values.firstWhere(
                    (type) => type.name == e,
                    orElse: () => PushContentType.dailyQuote,
                  ))
              .toSet() ??
          {PushContentType.dailyQuote, PushContentType.pastNotes},
      enabledPastNoteTypes: (json['enabledPastNoteTypes'] as List<dynamic>?)
              ?.map((e) => PastNoteType.values.firstWhere(
                    (type) => type.name == e,
                    orElse: () => PastNoteType.yearAgoToday,
                  ))
              .toSet() ??
          {PastNoteType.yearAgoToday},
      filterTagIds: (json['filterTagIds'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
      filterWeatherTypes: (json['filterWeatherTypes'] as List<dynamic>?)
              ?.map((e) => WeatherFilterType.values.firstWhere(
                    (type) => type.name == e,
                    orElse: () => WeatherFilterType.clear,
                  ))
              .toSet() ??
          {},
      pushTimeSlots: (json['pushTimeSlots'] as List<dynamic>?)
              ?.map((e) => PushTimeSlot.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [const PushTimeSlot(hour: 8, minute: 0)],
      aiPushEnabled: json['aiPushEnabled'] as bool? ?? false,
      lastPushTime: json['lastPushTime'] != null
          ? DateTime.tryParse(json['lastPushTime'] as String)
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'enabled': enabled,
      'enabledContentTypes':
          enabledContentTypes.map((e) => e.name).toList(),
      'enabledPastNoteTypes':
          enabledPastNoteTypes.map((e) => e.name).toList(),
      'filterTagIds': filterTagIds,
      'filterWeatherTypes':
          filterWeatherTypes.map((e) => e.name).toList(),
      'pushTimeSlots': pushTimeSlots.map((e) => e.toJson()).toList(),
      'aiPushEnabled': aiPushEnabled,
      'lastPushTime': lastPushTime?.toIso8601String(),
    };
  }

  SmartPushSettings copyWith({
    bool? enabled,
    Set<PushContentType>? enabledContentTypes,
    Set<PastNoteType>? enabledPastNoteTypes,
    List<String>? filterTagIds,
    Set<WeatherFilterType>? filterWeatherTypes,
    List<PushTimeSlot>? pushTimeSlots,
    bool? aiPushEnabled,
    DateTime? lastPushTime,
  }) {
    return SmartPushSettings(
      enabled: enabled ?? this.enabled,
      enabledContentTypes: enabledContentTypes ?? this.enabledContentTypes,
      enabledPastNoteTypes: enabledPastNoteTypes ?? this.enabledPastNoteTypes,
      filterTagIds: filterTagIds ?? this.filterTagIds,
      filterWeatherTypes: filterWeatherTypes ?? this.filterWeatherTypes,
      pushTimeSlots: pushTimeSlots ?? this.pushTimeSlots,
      aiPushEnabled: aiPushEnabled ?? this.aiPushEnabled,
      lastPushTime: lastPushTime ?? this.lastPushTime,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SmartPushSettings &&
          runtimeType == other.runtimeType &&
          enabled == other.enabled &&
          enabledContentTypes == other.enabledContentTypes &&
          enabledPastNoteTypes == other.enabledPastNoteTypes &&
          filterTagIds == other.filterTagIds &&
          filterWeatherTypes == other.filterWeatherTypes &&
          pushTimeSlots == other.pushTimeSlots &&
          aiPushEnabled == other.aiPushEnabled;

  @override
  int get hashCode =>
      enabled.hashCode ^
      enabledContentTypes.hashCode ^
      enabledPastNoteTypes.hashCode ^
      filterTagIds.hashCode ^
      filterWeatherTypes.hashCode ^
      pushTimeSlots.hashCode ^
      aiPushEnabled.hashCode;

  @override
  String toString() {
    return 'SmartPushSettings(enabled: $enabled, contentTypes: $enabledContentTypes, '
        'pastNoteTypes: $enabledPastNoteTypes, aiPush: $aiPushEnabled)';
  }
}
