import 'package:flutter/material.dart';

/// 天气数据模型
class WeatherData {
  final String key; // 天气关键字（如 'clear', 'cloudy' 等）
  final String description; // 天气描述（如 '晴', '多云' 等）
  final double? temperature; // 温度值
  final String? temperatureText; // 温度文本（如 '25°C'）
  final String iconCode; // 天气图标代码
  final DateTime timestamp; // 数据获取时间
  final double? latitude; // 位置纬度
  final double? longitude; // 位置经度

  const WeatherData({
    required this.key,
    required this.description,
    this.temperature,
    this.temperatureText,
    required this.iconCode,
    required this.timestamp,
    this.latitude,
    this.longitude,
  });

  /// 获取格式化的天气字符串
  String get formattedText {
    if (temperatureText != null) {
      return '$description $temperatureText';
    }
    return description;
  }

  /// 获取天气图标
  IconData get icon {
    switch (iconCode) {
      case 'clear_day':
        return Icons.wb_sunny;
      case 'clear_night':
        return Icons.nightlight_round;
      case 'cloudy':
        return Icons.cloud;
      case 'fog':
        return Icons.cloud;
      case 'rainy':
        return Icons.water_drop;
      case 'thunderstorm':
        return Icons.flash_on;
      case 'snowy':
        return Icons.ac_unit;
      case 'hail':
        return Icons.grain;
      case 'error':
        return Icons.error_outline;
      default:
        return Icons.cloud_queue;
    }
  }

  /// 检查数据是否有效
  bool get isValid => key != 'unknown' && key != 'error';

  /// 检查缓存是否过期（默认3小时）
  bool isExpired([Duration cacheDuration = const Duration(hours: 3)]) {
    return DateTime.now().difference(timestamp) > cacheDuration;
  }

  /// 检查位置是否匹配（允许0.05度误差，约5公里）
  bool isLocationMatch(double lat, double lon, [double tolerance = 0.05]) {
    if (latitude == null || longitude == null) return false;
    return (latitude! - lat).abs() < tolerance &&
        (longitude! - lon).abs() < tolerance;
  }

  /// 从JSON创建WeatherData
  factory WeatherData.fromJson(Map<String, dynamic> json) {
    return WeatherData(
      key: json['key'] ?? 'unknown',
      description: json['description'] ?? '未知',
      temperature: json['temperature']?.toDouble(),
      temperatureText: json['temperatureText'],
      iconCode: json['iconCode'] ?? 'cloudy',
      timestamp: DateTime.parse(json['timestamp']),
      latitude: json['latitude']?.toDouble(),
      longitude: json['longitude']?.toDouble(),
    );
  }

  /// 转换为JSON
  Map<String, dynamic> toJson() {
    return {
      'key': key,
      'description': description,
      'temperature': temperature,
      'temperatureText': temperatureText,
      'iconCode': iconCode,
      'timestamp': timestamp.toIso8601String(),
      'latitude': latitude,
      'longitude': longitude,
    };
  }

  /// 创建错误状态的天气数据
  factory WeatherData.error([String? message]) {
    return WeatherData(
      key: 'error',
      description: message ?? '天气数据获取失败',
      iconCode: 'error',
      timestamp: DateTime.now(),
    );
  }

  /// 创建未知状态的天气数据
  factory WeatherData.unknown() {
    return WeatherData(
      key: 'unknown',
      description: '未知天气',
      iconCode: 'cloudy',
      timestamp: DateTime.now(),
    );
  }

  @override
  String toString() {
    return 'WeatherData(key: $key, description: $description, temperature: $temperature)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is WeatherData &&
        other.key == key &&
        other.temperature == temperature &&
        other.latitude == latitude &&
        other.longitude == longitude;
  }

  @override
  int get hashCode {
    return Object.hash(key, temperature, latitude, longitude);
  }
}

/// 天气代码映射工具类
class WeatherCodeMapper {
  static const Map<String, String> _keyToDescription = {
    'clear': '晴',
    'partly_cloudy': '少云',
    'cloudy': '多云',
    'fog': '雾',
    'drizzle': '毛毛雨',
    'freezing_rain': '冻雨',
    'rain': '雨',
    'snow': '雪',
    'snow_grains': '雪粒',
    'rain_shower': '阵雨',
    'snow_shower': '阵雪',
    'thunderstorm': '雷雨',
    'thunderstorm_heavy': '雷暴雨',
    'unknown': '未知',
    'error': '获取失败',
  };

  static const Map<String, String> _keyToIconCode = {
    'clear': 'clear_day',
    'partly_cloudy': 'cloudy',
    'cloudy': 'cloudy',
    'fog': 'fog',
    'drizzle': 'rainy',
    'freezing_rain': 'rainy',
    'rain': 'rainy',
    'snow': 'snowy',
    'snow_grains': 'snowy',
    'rain_shower': 'rainy',
    'snow_shower': 'snowy',
    'thunderstorm': 'thunderstorm',
    'thunderstorm_heavy': 'thunderstorm',
    'unknown': 'cloudy',
    'error': 'error',
  };

  /// 通过中文描述反查天气key
  /// 返回null表示未找到匹配
  static String? getKeyByDescription(String description) {
    try {
      for (final entry in _keyToDescription.entries) {
        if (entry.value == description) return entry.key;
      }
    } catch (_) {}
    return null;
  }

  /// 根据OpenMeteo天气代码获取天气key
  static String getWeatherKey(int weatherCode) {
    if (weatherCode == 0) return 'clear';
    if (weatherCode == 1 || weatherCode == 2) return 'partly_cloudy';
    if (weatherCode == 3) return 'cloudy';
    if (weatherCode == 45 || weatherCode == 48) return 'fog';
    if (weatherCode >= 51 && weatherCode <= 55) return 'drizzle';
    if (weatherCode == 56 || weatherCode == 57) return 'freezing_rain';
    if (weatherCode >= 61 && weatherCode <= 67) return 'rain';
    if (weatherCode >= 71 && weatherCode <= 75) return 'snow';
    if (weatherCode == 77) return 'snow_grains';
    if (weatherCode >= 80 && weatherCode <= 82) return 'rain_shower';
    if (weatherCode == 85 || weatherCode == 86) return 'snow_shower';
    if (weatherCode == 95) return 'thunderstorm';
    if (weatherCode == 96 || weatherCode == 99) return 'thunderstorm_heavy';
    return 'unknown';
  }

  /// 根据key获取描述
  static String getDescription(String key) {
    return _keyToDescription[key] ?? '未知';
  }

  /// 根据key获取图标代码
  static String getIconCode(String key) {
    return _keyToIconCode[key] ?? 'cloudy';
  }

  /// 根据key获取图标
  static IconData getIcon(String key) {
    final iconCode = getIconCode(key);
    switch (iconCode) {
      case 'clear_day':
        return Icons.wb_sunny;
      case 'clear_night':
        return Icons.nightlight_round;
      case 'cloudy':
        return Icons.cloud;
      case 'fog':
        return Icons.cloud;
      case 'rainy':
        return Icons.water_drop;
      case 'thunderstorm':
        return Icons.flash_on;
      case 'snowy':
        return Icons.ac_unit;
      case 'hail':
        return Icons.grain;
      case 'error':
        return Icons.error_outline;
      default:
        return Icons.cloud_queue;
    }
  }
}
