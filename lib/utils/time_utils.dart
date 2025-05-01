import 'package:flutter/material.dart';

/// 时间工具类，用于处理时间相关的功能
class TimeUtils {
  /// 获取当前时间段描述（晨曦、上午、午后、黄昏、夜晚、深夜）
  static String getCurrentDayPeriod() {
    final now = TimeOfDay.now();
    final hour = now.hour;
    
    if (hour >= 5 && hour < 8) {
      return '晨曦'; // 5:00-7:59 晨曦
    } else if (hour >= 8 && hour < 12) {
      return '上午'; // 8:00-11:59 上午
    } else if (hour >= 12 && hour < 17) {
      return '午后'; // 12:00-16:59 午后
    } else if (hour >= 17 && hour < 20) {
      return '黄昏'; // 17:00-19:59 黄昏
    } else if (hour >= 20 && hour < 23) {
      return '夜晚'; // 20:00-22:59 夜晚
    } else {
      return '深夜'; // 23:00-4:59 深夜
    }
  }

  /// 获取当前时间段的图标
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

  static String getDayPeriodLabel(String key) {
    return dayPeriodKeyToLabel[key] ?? key;
  }

  static IconData getDayPeriodIconByKey(String? key) {
    switch (key) {
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
    }
  }
} 