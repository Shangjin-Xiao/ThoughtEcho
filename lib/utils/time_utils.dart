import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../gen_l10n/app_localizations.dart';

/// 时间工具类，用于处理时间相关的功能
class TimeUtils {
  /// 获取当前时间段描述（晨曦、上午、午后、黄昏、夜晚、深夜）
  /// 获取当前时间段的英文 Key
  static String getCurrentDayPeriodKey() {
    final now = TimeOfDay.now();
    final hour = now.hour;

    if (hour >= 5 && hour < 8) {
      return 'dawn'; // 5:00-7:59 晨曦
    } else if (hour >= 8 && hour < 12) {
      return 'morning'; // 8:00-11:59 上午
    } else if (hour >= 12 && hour < 17) {
      return 'afternoon'; // 12:00-16:59 午后
    } else if (hour >= 17 && hour < 20) {
      return 'dusk'; // 17:00-19:59 黄昏
    } else if (hour >= 20 && hour < 23) {
      return 'evening'; // 20:00-22:59 夜晚
    } else {
      return 'midnight'; // 23:00-4:59 深夜
    }
  }

  /// 根据时间段 Key 获取中文标签（旧方法，用于向后兼容）
  static String getDayPeriodLabel(String key) {
    return dayPeriodKeyToLabel[key] ?? key;
  }

  /// 根据时间段 Key 获取本地化标签（新方法，支持国际化）
  static String getLocalizedDayPeriodLabel(BuildContext context, String key) {
    final l10n = AppLocalizations.of(context);
    switch (key) {
      case 'dawn':
        return l10n.dayPeriodDawn;
      case 'morning':
        return l10n.dayPeriodMorning;
      case 'afternoon':
        return l10n.dayPeriodAfternoon;
      case 'dusk':
        return l10n.dayPeriodDusk;
      case 'evening':
        return l10n.dayPeriodEvening;
      case 'midnight':
        return l10n.dayPeriodMidnight;
      default:
        // 如果是旧的中文标签，尝试转换
        final reverseMap = dayPeriodKeyToLabel.map((k, v) => MapEntry(v, k));
        if (reverseMap.containsKey(key)) {
          return getLocalizedDayPeriodLabel(context, reverseMap[key]!);
        }
        return key;
    }
  }

  /// 根据时间段 Key 获取图标
  static IconData getDayPeriodIcon(String? dayPeriod) {
    switch (dayPeriod) {
      case '晨曦':
        return Icons.wb_twilight;
      case '上午':
        return Icons.wb_sunny_outlined;
      case '午后':
        return Icons.wb_sunny;
      case '黄昏':
        return Icons.nights_stay_outlined;
      case '夜晚':
        return Icons.nightlight_round;
      case '深夜':
        return Icons.bedtime;
      default:
        return Icons.access_time;
    }
  }

  /// key到label映射
  static const Map<String, String> dayPeriodKeyToLabel = {
    'dawn': '晨曦',
    'morning': '上午',
    'afternoon': '午后',
    'dusk': '黄昏',
    'evening': '夜晚',
    'midnight': '深夜',
  };

  static IconData getDayPeriodIconByKey(String? key) {
    // 直接使用 getDayPeriodIcon 方法，传入 key 对应的中文标签
    return getDayPeriodIcon(dayPeriodKeyToLabel[key]);
    /* switch (key) { // 旧逻辑保留注释，以备参考
      case 'dawn':
        return Icons.wb_twilight;
      case 'morning':
        return Icons.wb_sunny_outlined;
      case 'afternoon':
        return Icons.wb_sunny;
      case 'dusk':
        return Icons.nights_stay_outlined;
      case 'evening':
        return Icons.nightlight_round;
      case 'midnight':
        return Icons.bedtime;
      default:
        return Icons.access_time;
    } */
  }

  // 移除重复的 getDayPeriodIcon 定义，因为 getDayPeriodIconByKey 内部已调用它
  /* static IconData getDayPeriodIcon(String? dayPeriod) {
    switch (dayPeriod) {
      case '晨曦':
        return Icons.wb_twilight;
      case '上午':
        return Icons.wb_sunny_outlined;
      case '午后':
        return Icons.wb_sunny;
      case '黄昏':
        return Icons.nights_stay_outlined;
      case '夜晚':
        return Icons.nightlight_round;
      case '深夜':
        return Icons.bedtime;
      default:
        return Icons.access_time;
    }
  } */

  /// 相对时间格式（仅日期范围 + 时间），用于列表场景（本地化版本）
  /// - 今天：HH:mm
  /// - 昨天：昨天 HH:mm
  /// - 7天内：EEE HH:mm
  /// - 当年：MM-dd HH:mm
  /// - 往年：yyyy-MM-dd HH:mm
  static String formatRelativeDateTimeLocalized(
      BuildContext context, DateTime dateTime) {
    final l10n = AppLocalizations.of(context);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final weekAgo = now.subtract(const Duration(days: 7));
    final dateOnly = DateTime(dateTime.year, dateTime.month, dateTime.day);

    if (dateOnly == today) {
      return DateFormat('HH:mm').format(dateTime);
    } else if (dateOnly == yesterday) {
      return '${l10n.timeYesterday} ${DateFormat('HH:mm').format(dateTime)}';
    } else if (dateTime.isAfter(weekAgo)) {
      final locale = Localizations.localeOf(context).toString();
      return DateFormat('EEE HH:mm', locale).format(dateTime);
    } else if (dateTime.year == now.year) {
      return DateFormat('MM-dd HH:mm').format(dateTime);
    } else {
      return DateFormat('yyyy-MM-dd HH:mm').format(dateTime);
    }
  }

  /// 模糊时间格式（刚刚、几分钟前、几小时前、几天前），支持国际化
  static String formatElapsedRelativeTimeLocalized(
      BuildContext context, DateTime dateTime) {
    final l10n = AppLocalizations.of(context);
    final now = DateTime.now();
    final difference = now.difference(dateTime);

    if (difference.inDays > 0) {
      return l10n.timeDaysAgo(difference.inDays);
    } else if (difference.inHours > 0) {
      return l10n.timeHoursAgo(difference.inHours);
    } else if (difference.inMinutes > 0) {
      return l10n.timeMinutesAgo(difference.inMinutes);
    } else {
      return l10n.timeJustNow;
    }
  }

  /// 仅返回时间部分（HH:mm），用于需要和日期分离显示的场景
  static String formatQuoteTime(DateTime dateTime) =>
      DateFormat('HH:mm').format(dateTime);

  /// 兼容旧代码：调用 formatRelativeDateTime
  @Deprecated('请使用 formatRelativeDateTimeLocalized 或 formatQuoteTime 拆分后的方法')
  static String formatTime(DateTime dateTime) =>
      formatRelativeDateTime(dateTime);

  /// 相对时间格式（仅日期范围 + 时间），用于列表场景
  /// - 今天：HH:mm
  /// - 昨天：昨天 HH:mm
  /// - 7天内：EEE HH:mm
  /// - 当年：MM-dd HH:mm
  /// - 往年：yyyy-MM-dd HH:mm
  @Deprecated('请使用 formatRelativeDateTimeLocalized')
  static String formatRelativeDateTime(DateTime dateTime) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final weekAgo = now.subtract(const Duration(days: 7));
    final dateOnly = DateTime(dateTime.year, dateTime.month, dateTime.day);

    if (dateOnly == today) {
      return DateFormat('HH:mm').format(dateTime);
    } else if (dateOnly == yesterday) {
      return '昨天 ${DateFormat('HH:mm').format(dateTime)}';
    } else if (dateTime.isAfter(weekAgo)) {
      return DateFormat('EEE HH:mm', 'zh_CN').format(dateTime);
    } else if (dateTime.year == now.year) {
      return DateFormat('MM-dd HH:mm').format(dateTime);
    } else {
      return DateFormat('yyyy-MM-dd HH:mm').format(dateTime);
    }
  }

  /// 格式化日期（仅日期部分）
  /// 格式：2025年6月21日
  static String formatDate(DateTime dateTime) {
    return '${dateTime.year}年${dateTime.month}月${dateTime.day}日';
  }

  /// 格式化日期时间（完整日期和时间）
  /// 格式：2025年6月21日 14:30
  static String formatDateTime(DateTime dateTime) {
    return '${dateTime.year}年${dateTime.month}月${dateTime.day}日 ${dateTime.hour}:${dateTime.minute.toString().padLeft(2, '0')}';
  }

  /// 格式化笔记日期（日期 + 时间段）
  /// 格式：2025-06-21 上午
  static String formatQuoteDate(DateTime dateTime, {String? dayPeriod}) {
    final formattedDate =
        '${dateTime.year}-${dateTime.month.toString().padLeft(2, '0')}-${dateTime.day.toString().padLeft(2, '0')}';

    if (dayPeriod != null) {
      final dayPeriodLabel = getDayPeriodLabel(dayPeriod);
      return '$formattedDate $dayPeriodLabel';
    }

    // 如果没有提供 dayPeriod，根据时间推算
    final hour = dateTime.hour;
    String dayPeriodKey;
    if (hour >= 5 && hour < 8) {
      dayPeriodKey = 'dawn';
    } else if (hour >= 8 && hour < 12) {
      dayPeriodKey = 'morning';
    } else if (hour >= 12 && hour < 17) {
      dayPeriodKey = 'afternoon';
    } else if (hour >= 17 && hour < 20) {
      dayPeriodKey = 'dusk';
    } else if (hour >= 20 && hour < 23) {
      dayPeriodKey = 'evening';
    } else {
      dayPeriodKey = 'midnight';
    }

    final dayPeriodLabel = getDayPeriodLabel(dayPeriodKey);
    return '$formattedDate $dayPeriodLabel';
  }

  /// 格式化笔记日期（本地化版本，支持国际化）
  /// 可选参数 showExactTime：是否显示精确时间（时:分）
  /// 格式：2025-06-21 上午 或 2025-06-21 14:30 上午
  static String formatQuoteDateLocalized(
    BuildContext context,
    DateTime dateTime, {
    String? dayPeriod,
    bool showExactTime = false,
  }) {
    final formattedDate =
        '${dateTime.year}-${dateTime.month.toString().padLeft(2, '0')}-${dateTime.day.toString().padLeft(2, '0')}';

    String resolveDayPeriodKey() {
      final normalized = dayPeriod?.trim();

      // 优先使用传入值（兼容 key 与本地化标签）
      if (normalized != null && normalized.isNotEmpty) {
        if (dayPeriodKeyToLabel.containsKey(normalized)) {
          return normalized;
        }

        final reverseMap = dayPeriodKeyToLabel.map((k, v) => MapEntry(v, k));
        final mapped = reverseMap[normalized];
        if (mapped != null && mapped.isNotEmpty) {
          return mapped;
        }
      }

      // 兜底：根据时间推算时间段
      final hour = dateTime.hour;
      if (hour >= 5 && hour < 8) {
        return 'dawn';
      } else if (hour >= 8 && hour < 12) {
        return 'morning';
      } else if (hour >= 12 && hour < 17) {
        return 'afternoon';
      } else if (hour >= 17 && hour < 20) {
        return 'dusk';
      } else if (hour >= 20 && hour < 23) {
        return 'evening';
      } else {
        return 'midnight';
      }
    }

    final dayPeriodKey = resolveDayPeriodKey();
    final dayPeriodLabel = getLocalizedDayPeriodLabel(context, dayPeriodKey);

    if (showExactTime) {
      final timeStr = formatQuoteTime(dateTime);
      return '$formattedDate $timeStr';
    }

    return '$formattedDate $dayPeriodLabel';
  }

  /// 格式化文件名时间戳
  /// 格式：20250621_1430
  static String formatFileTimestamp(DateTime dateTime) {
    return '${dateTime.year}${dateTime.month.toString().padLeft(2, '0')}${dateTime.day.toString().padLeft(2, '0')}_${dateTime.hour.toString().padLeft(2, '0')}${dateTime.minute.toString().padLeft(2, '0')}';
  }

  /// 格式化日志时间戳（智能显示）
  /// - 今天：显示时分秒 (HH:mm:ss)
  /// - 一周内：显示星期和时分 (周一 14:30)
  /// - 更久：显示月日和时分 (6-21 14:30)
  static String formatLogTimestamp(DateTime timestamp) {
    final now = DateTime.now();
    final local = timestamp.toLocal();
    final difference = now.difference(local);

    // 今天的日志只显示时间
    if (local.year == now.year &&
        local.month == now.month &&
        local.day == now.day) {
      return '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}:${local.second.toString().padLeft(2, '0')}';
    }
    // 一周内的日志显示星期几和时间
    else if (difference.inDays < 7) {
      final weekdays = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];
      final weekday = weekdays[(local.weekday - 1) % 7];
      return '$weekday ${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
    }
    // 更久的日志显示日期和时间
    else {
      return '${local.month}-${local.day} ${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
    }
  }

  /// 从ISO格式字符串安全解析DateTime并格式化日期
  static String formatDateFromIso(String isoDate) {
    try {
      final date = DateTime.parse(isoDate);
      return formatDate(date);
    } catch (e) {
      return isoDate;
    }
  }

  /// 从ISO格式字符串安全解析DateTime并格式化日期时间
  static String formatDateTimeFromIso(String isoDate) {
    try {
      final date = DateTime.parse(isoDate);
      return formatDateTime(date);
    } catch (e) {
      return isoDate;
    }
  }
}
