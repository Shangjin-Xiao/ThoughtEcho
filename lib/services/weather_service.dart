import 'package:flutter/material.dart';
import 'dart:convert';
import '../services/network_service.dart';
import '../services/weather_cache_manager.dart';
import '../models/weather_data.dart';
import 'package:thoughtecho/utils/app_logger.dart';

/// 天气服务状态枚举
enum WeatherServiceState {
  idle, // 空闲状态
  loading, // 加载中
  success, // 成功获取
  error, // 获取失败
  cached, // 使用缓存数据
}

class WeatherService extends ChangeNotifier {
  WeatherData? _currentWeatherData;
  WeatherServiceState _state = WeatherServiceState.idle;
  String? _lastError;

  final WeatherCacheManager _cacheManager = WeatherCacheManager();
  bool _isInitialized = false;

  // Getters
  WeatherData? get currentWeatherData => _currentWeatherData;
  WeatherServiceState get state => _state;
  String? get lastError => _lastError;
  bool get isLoading => _state == WeatherServiceState.loading;
  bool get hasData =>
      _currentWeatherData != null && _currentWeatherData!.isValid;

  // 兼容性Getters（保持与旧版本的兼容性）
  String? get currentWeather => _currentWeatherData?.key;
  String? get temperature => _currentWeatherData?.temperatureText;
  String? get weatherDescription => _currentWeatherData?.description;
  String? get weatherIcon => _currentWeatherData?.iconCode;
  double? get temperatureValue => _currentWeatherData?.temperature;

  // 构造函数
  WeatherService() {
    _init();
  }

  // 初始化服务
  Future<void> _init() async {
    try {
      await _cacheManager.initialize();
      _isInitialized = true;
      logDebug('天气服务初始化完成');
    } catch (e) {
      logError('天气服务初始化失败: $e', error: e);
      _lastError = '服务初始化失败: $e';
    }
  }

  /// 确保服务已初始化
  Future<void> _ensureInitialized() async {
    if (!_isInitialized) {
      await _init();
    }
    if (!_isInitialized) {
      throw Exception('天气服务初始化失败');
    }
  }

  /// 获取天气数据的主要方法
  Future<void> getWeatherData(
    double latitude,
    double longitude, {
    bool forceRefresh = false,
    Duration? timeout,
  }) async {
    try {
      await _ensureInitialized();

      _setState(WeatherServiceState.loading);
      _lastError = null;

      // 如果不强制刷新，先尝试从缓存加载
      if (!forceRefresh) {
        final cachedData = await _cacheManager.loadWeatherData(
          latitude: latitude,
          longitude: longitude,
        );

        if (cachedData != null && cachedData.isValid) {
          _currentWeatherData = cachedData;
          _setState(WeatherServiceState.cached);
          logDebug('使用缓存的天气数据: ${cachedData.description}');
          return;
        }
      }

      // 从API获取新数据
      final weatherData = await _fetchWeatherFromAPI(
        latitude,
        longitude,
        timeout: timeout ?? const Duration(seconds: 15),
      );

      _currentWeatherData = weatherData;

      // 保存到缓存
      if (weatherData.isValid) {
        await _cacheManager.saveWeatherData(weatherData);
        _setState(WeatherServiceState.success);
      } else {
        _setState(WeatherServiceState.error);
      }
    } catch (e) {
      logError('获取天气数据失败: $e', error: e);
      _lastError = e.toString();
      _currentWeatherData = WeatherData.error('获取天气数据失败: $e');
      _setState(WeatherServiceState.error);
    }
  }

  /// 从API获取天气数据
  Future<WeatherData> _fetchWeatherFromAPI(
    double latitude,
    double longitude, {
    Duration timeout = const Duration(seconds: 10),
  }) async {
    try {
      final url = 'https://api.open-meteo.com/v1/forecast'
          '?latitude=$latitude'
          '&longitude=$longitude'
          '&current=temperature_2m,weather_code,wind_speed_10m'
          '&timezone=auto'
          '&language=zh_cn';

      final response = await NetworkService.instance
          .get(url, timeoutSeconds: timeout.inSeconds)
          .timeout(timeout);

      if (response.statusCode != 200) {
        throw Exception('API请求失败: ${response.statusCode}');
      }

      final data = json.decode(response.body);

      if (data == null || data['current'] is! Map<String, dynamic>) {
        throw Exception('API响应格式错误: 缺少 current 数据');
      }

      final current = data['current'] as Map<String, dynamic>;

      // 解析天气代码
      final weatherCode = current['weather_code'] as int?;
      if (weatherCode == null) {
        throw Exception('API响应格式错误: 缺少 weather_code');
      }

      // 解析温度
      final temperatureValue = current['temperature_2m'] as double?;
      String? temperatureText;
      if (temperatureValue != null) {
        temperatureText = '${temperatureValue.toStringAsFixed(0)}°C';
      }

      // 生成天气数据
      final weatherKey = WeatherCodeMapper.getWeatherKey(weatherCode);
      final description = WeatherCodeMapper.getDescription(weatherKey);
      final iconCode = WeatherCodeMapper.getIconCode(weatherKey);

      final weatherData = WeatherData(
        key: weatherKey,
        description: description,
        temperature: temperatureValue,
        temperatureText: temperatureText,
        iconCode: iconCode,
        timestamp: DateTime.now(),
        latitude: latitude,
        longitude: longitude,
      );

      logDebug(
        '从API获取天气数据成功: ${weatherData.description}, ${weatherData.temperatureText}',
      );
      return weatherData;
    } catch (e) {
      logError('API获取天气数据失败: $e', error: e);
      rethrow;
    }
  }

  /// 手动刷新天气数据
  Future<void> refreshWeather(double latitude, double longitude) async {
    await getWeatherData(latitude, longitude, forceRefresh: true);
  }

  /// 设置状态并通知监听器
  void _setState(WeatherServiceState newState) {
    if (_state != newState) {
      _state = newState;
      notifyListeners();
    }
  }

  /// 重置天气状态
  void resetWeatherState() {
    _currentWeatherData = null;
    _lastError = null;
    _setState(WeatherServiceState.idle);
    logDebug('天气状态已重置');
  }

  /// 检查是否有有效的天气数据
  bool get hasValidWeatherData => hasData;

  /// 获取格式化的天气字符串（兼容性方法）
  String getFormattedWeather() {
    return _currentWeatherData?.formattedText ?? '';
  }

  /// 获取天气图标（兼容性方法）
  IconData getWeatherIconData() {
    return _currentWeatherData?.icon ?? Icons.cloud_queue;
  }

  /// 根据天气key获取图标数据（静态方法，兼容性）
  static IconData getWeatherIconDataByKey(String key) {
    return WeatherCodeMapper.getIcon(key);
  }

  /// 获取天气描述（静态方法，兼容性）
  static String getWeatherDescription(String key) {
    return WeatherCodeMapper.getDescription(key);
  }

  /// 获取天气key（静态方法，兼容性）
  static String getWeatherKey(int weatherCode) {
    return WeatherCodeMapper.getWeatherKey(weatherCode);
  }

  /// 获取天气图标代码（静态方法，兼容性）
  static String getWeatherIconCode(String key) {
    return WeatherCodeMapper.getIconCode(key);
  }

  /// 修复：检查网络连通性，使用更可靠的检测方法
  Future<bool> shouldUseLocalWeather() async {
    try {
      // 使用天气API的健康检查端点，使用北京坐标避免海洋中心
      final result = await NetworkService.instance.get(
        'https://api.open-meteo.com/v1/forecast?latitude=39.9&longitude=116.4&current=temperature_2m',
        timeoutSeconds: 5,
      );
      return result.statusCode != 200;
    } catch (e) {
      logDebug('网络连通性检查失败: $e');
      return true; // 网络不可用，使用本地天气
    }
  }

  /// 获取缓存信息（用于调试）
  Future<Map<String, dynamic>?> getCacheInfo() async {
    try {
      await _ensureInitialized();
      return await _cacheManager.getCacheInfo();
    } catch (e) {
      logError('获取缓存信息失败: $e', error: e);
      return null;
    }
  }

  /// 清除缓存
  Future<void> clearCache() async {
    try {
      await _ensureInitialized();
      await _cacheManager.clearCache();
      logDebug('天气缓存已清除');
    } catch (e) {
      logError('清除天气缓存失败: $e', error: e);
    }
  }

  /// 设置模拟天气数据（兼容性方法）
  void setMockWeatherData() {
    _currentWeatherData = WeatherData.error('天气数据获取失败');
    _setState(WeatherServiceState.error);
    _lastError = '天气数据获取失败';
    logDebug('天气数据获取失败，显示错误状态');
  }

  // 静态常量映射（兼容性）
  static const weatherKeyToLabel = {
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
  };

  // 筛选用的简化天气分类映射
  static const filterCategoryToLabel = {
    'sunny': '晴',
    'rainy': '雨',
    'cloudy': '多云',
    'snowy': '雪',
  };

  // 简化分类到具体天气key的映射
  static const filterCategoryToKeys = {
    'sunny': ['clear'],
    'rainy': [
      'drizzle',
      'freezing_rain',
      'rain',
      'rain_shower',
      'thunderstorm',
      'thunderstorm_heavy',
    ],
    'cloudy': ['partly_cloudy', 'cloudy', 'fog'],
    'snowy': ['snow', 'snow_grains', 'snow_shower'],
  };

  /// 根据筛选分类获取对应的具体天气key列表
  static List<String> getWeatherKeysByFilterCategory(String filterCategory) {
    return filterCategoryToKeys[filterCategory] ?? [];
  }

  /// 根据具体天气key获取对应的筛选分类
  static String? getFilterCategoryByWeatherKey(String weatherKey) {
    for (final entry in filterCategoryToKeys.entries) {
      if (entry.value.contains(weatherKey)) {
        return entry.key;
      }
    }
    return null;
  }

  /// 获取筛选分类的图标
  static IconData getFilterCategoryIcon(String filterCategory) {
    switch (filterCategory) {
      case 'sunny':
        return Icons.wb_sunny;
      case 'rainy':
        return Icons.water_drop;
      case 'cloudy':
        return Icons.cloud;
      case 'snowy':
        return Icons.ac_unit;
      default:
        return Icons.cloud_queue;
    }
  }
}
