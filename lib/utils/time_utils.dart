import 'package:flutter/material.dart';

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
}