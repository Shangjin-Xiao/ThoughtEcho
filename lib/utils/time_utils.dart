import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

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

  /// 根据时间段 Key 获取中文标签
  static String getDayPeriodLabel(String key) {
    return dayPeriodKeyToLabel[key] ?? key;
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

  // TODO: 优化：_formatTime 函数同时处理日期和时间格式化，职责可能过于混淆。考虑拆分为更具体的函数，例如 formatQuoteDate 和 formatQuoteTime。
  static String _formatTime(DateTime dateTime) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = DateTime(now.year, now.month, now.day - 1);
    final aWeekAgo = now.subtract(const Duration(days: 7));

    final date = DateTime(dateTime.year, dateTime.month, dateTime.day);

    if (date.isAtSameMomentAs(today)) {
      return DateFormat('HH:mm').format(dateTime); // 今天，显示时间
    } else if (date.isAtSameMomentAs(yesterday)) {
      return '昨天 ${DateFormat('HH:mm').format(dateTime)}'; // 昨天
    } else if (dateTime.isAfter(aWeekAgo)) {
      return DateFormat('EEEE HH:mm', 'zh_CN').format(dateTime); // 一周内，显示星期和时间
    } else if (dateTime.year == now.year) {
      return DateFormat('MM-dd HH:mm').format(dateTime); // 今年，显示月日和时间
    } else {
      return DateFormat('yyyy-MM-dd HH:mm').format(dateTime); // 往年，显示年月日和时间
    }
  }
}