import 'package:flutter/material.dart';
import 'dart:convert';
import '../utils/http_utils.dart';
import '../utils/mmkv_ffi_fix.dart'; // 导入MMKV安全包装类

class WeatherService extends ChangeNotifier {
  String? _currentWeather;
  String? _temperature;
  String? _weatherDescription;
  bool _isLoading = false;
  String? _weatherIcon;
  double? _temperature_value;
  
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
  double? get temperatureValue => _temperature_value;
  
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
        // 尝试使用OpenMeteo API
        try {
          await _getOpenMeteoWeather(latitude, longitude);
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
              _temperature_value = cacheData['temperature_value'];
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
        'temperature_value': _temperature_value,
        'weather_icon': _weatherIcon,
        'timestamp': DateTime.now().toIso8601String(),
      };
      
      // 保存缓存和过期时间
      await _storage.setString(_cacheKey, json.encode(cacheData));
      await _storage.setString(
        _cacheExpiryKey, 
        DateTime.now().add(_cacheDuration).toIso8601String()
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
      final url = 'https://api.open-meteo.com/v1/forecast?latitude=$latitude&longitude=$longitude&current=temperature_2m,weather_code,wind_speed_10m&timezone=auto&language=zh_cn';
      
      final response = await HttpUtils.secureGet(
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
            _temperature_value = current['temperature_2m'] as double?; // Use 'as double?' for safe casting
            
            if (_temperature_value != null) {
              _temperature = '${_temperature_value?.toStringAsFixed(0)}°C';
            } else {
              _temperature = '- -'; // Default if null
            }
            
            if (weatherCode is int) { // Check type before using
              _weatherDescription = _getWeatherDescription(weatherCode);
              _weatherIcon = _getWeatherIconCode(weatherCode);
            } else {
              _weatherDescription = '未知'; // Default if code is invalid
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
    _weatherDescription = '获取失败';
    _temperature = '- -';
    _temperature_value = null;
    _currentWeather = '天气数据获取失败';
    _weatherIcon = 'error'; // 使用错误图标
    debugPrint('天气数据获取失败，显示错误状态');
    notifyListeners();
  }

  // 根据OpenMeteo的天气代码获取中文天气描述
  String _getWeatherDescription(int weatherCode) {
    switch (weatherCode) {
      case 0:
        return '晴';
      case 1:
      case 2:
        return '少云';
      case 3:
        return '多云';
      case 45:
      case 48:
        return '雾';
      case 51:
      case 53:
      case 55:
        return '毛毛雨';
      case 56:
      case 57:
        return '冻雨';
      case 61:
      case 63:
      case 65:
        return '雨';
      case 66:
      case 67:
        return '冻雨';
      case 71:
      case 73:
      case 75:
        return '雪';
      case 77:
        return '雪粒';
      case 80:
      case 81:
      case 82:
        return '阵雨';
      case 85:
      case 86:
        return '阵雪';
      case 95:
        return '雷雨';
      case 96:
      case 99:
        return '雷暴雨';
      default:
        return '未知';
    }
  }

  // 获取天气图标代码
  String _getWeatherIconCode(int weatherCode) {
    // OpenMeteo天气代码到图标映射
    if (weatherCode == 0) return 'clear_day';
    if (weatherCode >= 1 && weatherCode <= 3) return 'cloudy';
    if (weatherCode >= 45 && weatherCode <= 48) return 'fog';
    if (weatherCode >= 51 && weatherCode <= 67) return 'rainy';
    if (weatherCode >= 71 && weatherCode <= 77) return 'snowy';
    if (weatherCode >= 80 && weatherCode <= 82) return 'rainy';
    if (weatherCode >= 85 && weatherCode <= 86) return 'snowy';
    if (weatherCode >= 95) return 'thunderstorm';
    return 'cloudy';
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
    return '$_currentWeather $_temperature';
  }

  // 判断当前网络状态并返回最佳的天气获取策略
  Future<bool> shouldUseLocalWeather() async {
    try {
      // 尝试访问一个可靠的网站来检查网络连接
      final result = await HttpUtils.secureGet(
        'https://www.baidu.com',
        timeoutSeconds: 3 // 设置极短的超时时间
      );
      return result.statusCode != 200;
    } catch (e) {
      // 无法连接，表明很可能没有网络
      return true;
    }
  }
}