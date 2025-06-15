// ignore_for_file: unused_element, non_constant_identifier_names
import 'package:flutter/material.dart';
import 'dart:convert';
import '../services/network_service.dart';
import '../utils/mmkv_ffi_fix.dart'; // 导入MMKV安全包装类

class WeatherService extends ChangeNotifier {
  String? _currentWeather;
  String? _temperature;
  String? _weatherDescription;
  bool _isLoading = false;
  String? _weatherIcon;
  double? _temperatureValue;

  // 缓存相关
  static const _cacheKey = 'weather_cache';
  static const _cacheExpiryKey = 'weather_cache_expiry';
  static const _cacheDuration = Duration(hours: 3); // 天气缓存3小时

  // MMKV存储实例
  late SafeMMKV _storage;
  bool _isInitialized = false;

  String? get currentWeather => _currentWeather;
  String? get temperature => _temperature;
  String? get weatherDescription => _weatherDescription;
  bool get isLoading => _isLoading;
  String? get weatherIcon => _weatherIcon;
  double? get temperatureValue => _temperatureValue;

  // 构造函数
  WeatherService() {
    _init();
  }

  // 初始化MMKV存储
  Future<void> _init() async {
    try {
      _storage = SafeMMKV();
      await _storage.initialize();
      _isInitialized = true;
      debugPrint('天气服务MMKV存储初始化完成');
    } catch (e) {
      debugPrint('天气服务MMKV存储初始化失败: $e');
    }
  }

  // 获取天气信息
  Future<void> getWeatherData(double latitude, double longitude) async {
    try {
      // 确保存储已初始化
      if (!_isInitialized) {
        await _init();
      }

      _isLoading = true;
      notifyListeners();

      // 首先尝试从缓存加载
      final bool hasCachedData = await _loadFromCache(latitude, longitude);

      // 如果缓存不可用或已过期，则从API获取
      if (!hasCachedData) {
        // 尝试使用OpenMeteo API，添加总体超时控制
        try {
          await _getOpenMeteoWeather(latitude, longitude).timeout(
            const Duration(seconds: 15), // 总体超时15秒
            onTimeout: () {
              debugPrint('天气数据获取超时');
              throw Exception('天气数据获取超时，请稍后重试');
            },
          );
          // 成功获取数据后保存到缓存
          await _saveToCache(latitude, longitude);
        } catch (e) {
          debugPrint('OpenMeteo API调用失败: $e');
          // API调用失败，直接抛出异常
          rethrow;
        }
      }

      _isLoading = false;
      notifyListeners();
    } catch (e) {
      _isLoading = false;
      debugPrint('获取天气数据异常: $e');
      // 所有方法都失败，设置模拟数据
      setMockWeatherData();
      notifyListeners();
    }
  }

  // 从缓存加载天气数据
  Future<bool> _loadFromCache(double latitude, double longitude) async {
    try {
      // 检查缓存是否存在并且未过期
      final cacheExpiryString = _storage.getString(_cacheExpiryKey);
      if (cacheExpiryString != null) {
        final cacheExpiry = DateTime.parse(cacheExpiryString);
        if (DateTime.now().isBefore(cacheExpiry)) {
          // 缓存有效，可以使用
          final cacheJson = _storage.getString(_cacheKey);
          if (cacheJson != null) {
            final cacheData = json.decode(cacheJson);

            // 检查缓存的位置是否与当前位置接近
            final cachedLat = cacheData['latitude'];
            final cachedLon = cacheData['longitude'];

            // 如果缓存的位置与当前位置相差不超过0.05度（约5公里），则使用缓存
            if ((cachedLat - latitude).abs() < 0.05 &&
                (cachedLon - longitude).abs() < 0.05) {
              _weatherDescription = cacheData['weather_description'];
              _currentWeather = _weatherDescription;
              _temperature = cacheData['temperature'];
              _temperatureValue = cacheData['temperature_value'];
              _weatherIcon = cacheData['weather_icon'];

              debugPrint('使用缓存的天气数据: $_weatherDescription, $_temperature');
              return true;
            }
          }
        }
      }

      return false; // 缓存不可用或已过期
    } catch (e) {
      debugPrint('从缓存加载天气数据失败: $e');
      return false;
    }
  }

  // 保存天气数据到缓存
  Future<void> _saveToCache(double latitude, double longitude) async {
    if (_weatherDescription == null || _temperature == null) {
      return; // 没有数据可缓存
    }

    try {
      // 创建缓存数据
      final cacheData = {
        'latitude': latitude,
        'longitude': longitude,
        'weather_description': _weatherDescription,
        'temperature': _temperature,
        'temperature_value': _temperatureValue,
        'weather_icon': _weatherIcon,
        'timestamp': DateTime.now().toIso8601String(),
      };

      // 保存缓存和过期时间
      await _storage.setString(_cacheKey, json.encode(cacheData));
      await _storage.setString(
        _cacheExpiryKey,
        DateTime.now().add(_cacheDuration).toIso8601String(),
      );

      debugPrint('天气数据已保存到MMKV缓存');
    } catch (e) {
      debugPrint('保存天气数据到MMKV缓存失败: $e');
    }
  }

  // 使用OpenMeteo API获取天气
  Future<void> _getOpenMeteoWeather(double latitude, double longitude) async {
    String? rawResponseBody; // Store raw response for debugging
    try {
      // OpenMeteo是完全免费的API，不需要API key
      final url =
          'https://api.open-meteo.com/v1/forecast?latitude=$latitude&longitude=$longitude&current=temperature_2m,weather_code,wind_speed_10m&timezone=auto&language=zh_cn';

      final response = await NetworkService.instance.get(
        url,
        timeoutSeconds: 10, // 降低超时时间，避免长时间等待
      );

      rawResponseBody = response.body; // Store raw response

      if (response.statusCode == 200) {
        // Add specific try-catch for JSON parsing and data access
        try {
          final data = json.decode(response.body);

          // Check if 'current' data exists and is a map
          if (data != null && data['current'] is Map<String, dynamic>) {
            final current = data['current'] as Map<String, dynamic>;

            // Safely access data with null checks or default values
            final weatherCode = current['weather_code'];
            _temperatureValue =
                current['temperature_2m']
                    as double?; // Use 'as double?' for safe casting
            if (_temperatureValue != null) {
              _temperature = '${_temperatureValue?.toStringAsFixed(0)}°C';
            } else {
              _temperature = '- -'; // Default if null
            }

            if (weatherCode is int) {
              // Check type before using
              _weatherDescription = WeatherService.getWeatherKey(weatherCode);
              _weatherIcon = WeatherService.getWeatherIconCode(
                _weatherDescription ?? 'unknown',
              );
            } else {
              _weatherDescription = 'unknown'; // Default if code is invalid
              _weatherIcon = 'cloudy'; // Default icon
            }
            _currentWeather = _weatherDescription;

            debugPrint('天气数据获取成功：$_weatherDescription, $_temperature');
          } else {
            debugPrint('OpenMeteo响应格式错误: 缺少 "current" 数据');
            throw Exception('OpenMeteo响应格式错误: 缺少 "current" 数据');
          }
        } catch (e) {
          // Catch JSON parsing or data access errors specifically
          debugPrint('解析OpenMeteo天气数据失败: $e. Raw response: $rawResponseBody');
          throw Exception('解析天气数据失败: $e'); // Rethrow specific error
        }
      } else {
        debugPrint('OpenMeteo请求失败: ${response.statusCode}，${response.body}');
        throw Exception('OpenMeteo请求失败: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('获取OpenMeteo天气失败: $e. Raw response: $rawResponseBody');
      rethrow; // 重新抛出异常以便外部处理
    }
  }

  // 设置天气数据获取失败的状态
  void setMockWeatherData() {
    _weatherDescription = 'unknown';
    _temperature = '- -';
    _temperatureValue = null;
    _currentWeather = '天气数据获取失败';
    _weatherIcon = 'error'; // 使用错误图标
    debugPrint('天气数据获取失败，显示错误状态');
    notifyListeners();
  }

  // 重置天气状态
  void resetWeatherState() {
    _currentWeather = null;
    _temperature = null;
    _weatherDescription = null;
    _weatherIcon = null;
    _temperatureValue = null;
    _isLoading = false;
    notifyListeners();
    debugPrint('天气状态已重置');
  }

  // 检查是否有有效的天气数据
  bool get hasValidWeatherData =>
      _currentWeather != null &&
      _currentWeather != 'unknown' &&
      _currentWeather != '天气数据获取失败';

  // 增加天气key到label的映射
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

  static String getWeatherDescription(String key) {
    return weatherKeyToLabel[key] ?? '未知';
  }

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

  static String getWeatherIconCode(String key) {
    switch (key) {
      case 'clear':
        return 'clear_day';
      case 'partly_cloudy':
        return 'cloudy';
      case 'cloudy':
        return 'cloudy';
      case 'fog':
        return 'fog';
      case 'drizzle':
        return 'rainy';
      case 'freezing_rain':
        return 'rainy';
      case 'rain':
        return 'rainy';
      case 'snow':
        return 'snowy';
      case 'snow_grains':
        return 'snowy';
      case 'rain_shower':
        return 'rainy';
      case 'snow_shower':
        return 'snowy';
      case 'thunderstorm':
        return 'thunderstorm';
      case 'thunderstorm_heavy':
        return 'thunderstorm';
      default:
        return 'cloudy';
    }
  }

  // 获取天气图标代码
  String _getWeatherIconCode(String weatherDescription) {
    return getWeatherIconCode(weatherDescription);
  }

  // 根据天气图标代码获取图标
  IconData getWeatherIconData() {
    if (_weatherIcon == null) return Icons.cloud_queue;

    switch (_weatherIcon) {
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

  // 获取格式化的天气字符串
  String getFormattedWeather() {
    if (_currentWeather == null || _temperature == null) return '';
    // 使用 getWeatherDescription 将英文 key 转换为中文标签
    return '${getWeatherDescription(_currentWeather!)} $_temperature';
  }

  // 判断当前网络状态并返回最佳的天气获取策略
  Future<bool> shouldUseLocalWeather() async {
    try {
      // 尝试访问一个可靠的网站来检查网络连接
      final result = await NetworkService.instance.get(
        'https://www.baidu.com',
        timeoutSeconds: 3, // 设置极短的超时时间
      );
      return result.statusCode != 200;
    } catch (e) {
      // 无法连接，表明很可能没有网络
      return true;
    }
  }

  static IconData getWeatherIconDataByKey(String key) {
    switch (getWeatherIconCode(key)) {
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
