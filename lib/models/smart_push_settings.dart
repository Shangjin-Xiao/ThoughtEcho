/// 智能推送设置数据模型
/// 
/// 用于配置笔记智能推送功能，包括推送类型、时间、筛选条件等
/// 重构版本：简化用户体验，默认智能推送，高级选项可折叠

/// 推送模式
enum PushMode {
  smart,       // 智能推送（默认）- 自动选择最佳内容
  dailyQuote,  // 仅每日一言
  pastNotes,   // 仅过去的笔记
  both,        // 两者都推送
}

/// 过去笔记的推送类型
enum PastNoteType {
  yearAgoToday,      // 去年今日
  monthAgoToday,     // 往月今日（上个月的今天）
  weekAgoToday,      // 上周今日
  randomMemory,      // 随机回忆
  sameLocation,      // 相同地点（高级）
  sameWeather,       // 相同天气（高级）
}

/// 天气类型（用于高级筛选）
enum WeatherFilterType {
  clear,             // 晴
  cloudy,            // 多云
  rain,              // 雨
  snow,              // 雪
  fog,               // 雾
}

/// 推送频率
enum PushFrequency {
  daily,             // 每天
  weekdays,          // 工作日
  weekends,          // 周末
  custom,            // 自定义
}

/// 推送时间段
class PushTimeSlot {
  final int hour;      // 小时 (0-23)
  final int minute;    // 分钟 (0-59)
  final bool enabled;  // 是否启用
  final String? label; // 可选标签（如"早晨灵感"）

  const PushTimeSlot({
    required this.hour,
    required this.minute,
    this.enabled = true,
    this.label,
  });

  factory PushTimeSlot.fromJson(Map<String, dynamic> json) {
    return PushTimeSlot(
      hour: json['hour'] as int? ?? 8,
      minute: json['minute'] as int? ?? 0,
      enabled: json['enabled'] as bool? ?? true,
      label: json['label'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'hour': hour,
      'minute': minute,
      'enabled': enabled,
      'label': label,
    };
  }

  PushTimeSlot copyWith({
    int? hour,
    int? minute,
    bool? enabled,
    String? label,
  }) {
    return PushTimeSlot(
      hour: hour ?? this.hour,
      minute: minute ?? this.minute,
      enabled: enabled ?? this.enabled,
      label: label ?? this.label,
    );
  }

  String get formattedTime {
    final h = hour.toString().padLeft(2, '0');
    final m = minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  /// 获取友好的时间段描述
  String get periodDescription {
    if (hour >= 5 && hour < 9) return '清晨';
    if (hour >= 9 && hour < 12) return '上午';
    if (hour >= 12 && hour < 14) return '午间';
    if (hour >= 14 && hour < 18) return '下午';
    if (hour >= 18 && hour < 21) return '傍晚';
    if (hour >= 21 || hour < 5) return '夜间';
    return '';
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

  /// 推送模式
  final PushMode pushMode;

  /// 推送频率
  final PushFrequency frequency;

  /// 启用的过去笔记类型（智能模式自动选择，自定义模式手动选择）
  final Set<PastNoteType> enabledPastNoteTypes;

  /// 筛选的标签ID列表（高级选项）
  final List<String> filterTagIds;

  /// 筛选的天气类型（高级选项）
  final Set<WeatherFilterType> filterWeatherTypes;

  /// 推送时间段列表
  final List<PushTimeSlot> pushTimeSlots;

  /// 是否显示高级选项
  final bool showAdvancedOptions;

  /// 上次推送时间
  final DateTime? lastPushTime;

  /// 上次推送的笔记ID列表（防止重复推送）
  final List<String> recentlyPushedNoteIds;

  /// 推送历史记录上限
  static const int maxRecentPushedCount = 30;

  const SmartPushSettings({
    this.enabled = false,
    this.pushMode = PushMode.smart,
    this.frequency = PushFrequency.daily,
    this.enabledPastNoteTypes = const {
      PastNoteType.yearAgoToday,
      PastNoteType.monthAgoToday,
      PastNoteType.randomMemory,
    },
    this.filterTagIds = const [],
    this.filterWeatherTypes = const {},
    this.pushTimeSlots = const [
      PushTimeSlot(hour: 8, minute: 0, label: '早晨灵感'),
    ],
    this.showAdvancedOptions = false,
    this.lastPushTime,
    this.recentlyPushedNoteIds = const [],
  });

  factory SmartPushSettings.defaultSettings() => const SmartPushSettings();

  factory SmartPushSettings.fromJson(Map<String, dynamic> json) {
    // 兼容旧版本数据迁移
    PushMode mode = PushMode.smart;
    if (json.containsKey('pushMode')) {
      mode = PushMode.values.firstWhere(
        (m) => m.name == json['pushMode'],
        orElse: () => PushMode.smart,
      );
    } else if (json.containsKey('enabledContentTypes')) {
      // 旧版本迁移
      final oldTypes = json['enabledContentTypes'] as List<dynamic>?;
      if (oldTypes != null) {
        final hasDailyQuote = oldTypes.contains('dailyQuote');
        final hasPastNotes = oldTypes.contains('pastNotes');
        if (hasDailyQuote && hasPastNotes) {
          mode = PushMode.both;
        } else if (hasDailyQuote) {
          mode = PushMode.dailyQuote;
        } else if (hasPastNotes) {
          mode = PushMode.pastNotes;
        }
      }
    }

    return SmartPushSettings(
      enabled: json['enabled'] as bool? ?? false,
      pushMode: mode,
      frequency: json['frequency'] != null
          ? PushFrequency.values.firstWhere(
              (f) => f.name == json['frequency'],
              orElse: () => PushFrequency.daily,
            )
          : PushFrequency.daily,
      enabledPastNoteTypes: (json['enabledPastNoteTypes'] as List<dynamic>?)
              ?.map((e) => PastNoteType.values.firstWhere(
                    (type) => type.name == e,
                    orElse: () => PastNoteType.yearAgoToday,
                  ))
              .toSet() ??
          {PastNoteType.yearAgoToday, PastNoteType.randomMemory},
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
      showAdvancedOptions: json['showAdvancedOptions'] as bool? ?? false,
      lastPushTime: json['lastPushTime'] != null
          ? DateTime.tryParse(json['lastPushTime'] as String)
          : null,
      recentlyPushedNoteIds: (json['recentlyPushedNoteIds'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'enabled': enabled,
      'pushMode': pushMode.name,
      'frequency': frequency.name,
      'enabledPastNoteTypes': enabledPastNoteTypes.map((e) => e.name).toList(),
      'filterTagIds': filterTagIds,
      'filterWeatherTypes': filterWeatherTypes.map((e) => e.name).toList(),
      'pushTimeSlots': pushTimeSlots.map((e) => e.toJson()).toList(),
      'showAdvancedOptions': showAdvancedOptions,
      'lastPushTime': lastPushTime?.toIso8601String(),
      'recentlyPushedNoteIds': recentlyPushedNoteIds,
    };
  }

  SmartPushSettings copyWith({
    bool? enabled,
    PushMode? pushMode,
    PushFrequency? frequency,
    Set<PastNoteType>? enabledPastNoteTypes,
    List<String>? filterTagIds,
    Set<WeatherFilterType>? filterWeatherTypes,
    List<PushTimeSlot>? pushTimeSlots,
    bool? showAdvancedOptions,
    DateTime? lastPushTime,
    List<String>? recentlyPushedNoteIds,
  }) {
    return SmartPushSettings(
      enabled: enabled ?? this.enabled,
      pushMode: pushMode ?? this.pushMode,
      frequency: frequency ?? this.frequency,
      enabledPastNoteTypes: enabledPastNoteTypes ?? this.enabledPastNoteTypes,
      filterTagIds: filterTagIds ?? this.filterTagIds,
      filterWeatherTypes: filterWeatherTypes ?? this.filterWeatherTypes,
      pushTimeSlots: pushTimeSlots ?? this.pushTimeSlots,
      showAdvancedOptions: showAdvancedOptions ?? this.showAdvancedOptions,
      lastPushTime: lastPushTime ?? this.lastPushTime,
      recentlyPushedNoteIds: recentlyPushedNoteIds ?? this.recentlyPushedNoteIds,
    );
  }

  /// 添加已推送笔记ID到历史记录
  SmartPushSettings addPushedNoteId(String noteId) {
    final newList = List<String>.from(recentlyPushedNoteIds);
    if (!newList.contains(noteId)) {
      newList.add(noteId);
      // 保持列表不超过上限
      while (newList.length > maxRecentPushedCount) {
        newList.removeAt(0);
      }
    }
    return copyWith(
      recentlyPushedNoteIds: newList,
      lastPushTime: DateTime.now(),
    );
  }

  /// 检查今天是否应该推送（基于频率设置）
  bool shouldPushToday() {
    final now = DateTime.now();
    final weekday = now.weekday; // 1=Monday, 7=Sunday
    
    switch (frequency) {
      case PushFrequency.daily:
        return true;
      case PushFrequency.weekdays:
        return weekday >= 1 && weekday <= 5;
      case PushFrequency.weekends:
        return weekday == 6 || weekday == 7;
      case PushFrequency.custom:
        return true; // 自定义模式由时间槽控制
    }
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SmartPushSettings &&
          runtimeType == other.runtimeType &&
          enabled == other.enabled &&
          pushMode == other.pushMode &&
          frequency == other.frequency &&
          enabledPastNoteTypes == other.enabledPastNoteTypes &&
          filterTagIds == other.filterTagIds &&
          filterWeatherTypes == other.filterWeatherTypes &&
          pushTimeSlots == other.pushTimeSlots &&
          showAdvancedOptions == other.showAdvancedOptions;

  @override
  int get hashCode =>
      enabled.hashCode ^
      pushMode.hashCode ^
      frequency.hashCode ^
      enabledPastNoteTypes.hashCode ^
      filterTagIds.hashCode ^
      filterWeatherTypes.hashCode ^
      pushTimeSlots.hashCode ^
      showAdvancedOptions.hashCode;

  @override
  String toString() {
    return 'SmartPushSettings(enabled: $enabled, mode: $pushMode, frequency: $frequency)';
  }
}

// 保留旧枚举以兼容现有代码（可在后续版本移除）
@Deprecated('Use PushMode instead')
enum PushContentType {
  dailyQuote,
  pastNotes,
}
