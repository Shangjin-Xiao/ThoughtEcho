import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:intl/intl.dart';
import '../utils/http_utils.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

  String? get currentWeather => _currentWeather;
  String? get temperature => _temperature;
  String? get weatherDescription => _weatherDescription;
  bool get isLoading => _isLoading;
  String? get weatherIcon => _weatherIcon;
  double? get temperatureValue => _temperature_value;

  // 获取天气信息
  Future<void> getWeatherData(double latitude, double longitude) async {
    try {
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
          // 如果API调用失败，尝试使用本地估算的天气数据
          _useLocalWeatherEstimation(latitude, longitude);
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

  // 使用本地估算的天气数据（基于经纬度和季节）
  void _useLocalWeatherEstimation(double latitude, double longitude) {
    debugPrint('使用本地天气估算');
    
    // 获取当前日期信息用于季节确定
    final now = DateTime.now();
    final month = now.month;
    
    // 判断大致季节（北半球视角）
    String season;
    if (month >= 3 && month <= 5) {
      season = '春季';
    } else if (month >= 6 && month <= 8) {
      season = '夏季';
    } else if (month >= 9 && month <= 11) {
      season = '秋季';
    } else {
      season = '冬季';
    }
    
    // 南北半球季节相反
    if (latitude < 0) {
      if (season == '夏季') {
        season = '冬季';
      } else if (season == '冬季') {
        season = '夏季';
      } else if (season == '春季') {
        season = '秋季';
      } else {
        season = '春季';
      }
    }
    
    // 根据纬度确定温度范围
    double baseTemp;
    if (latitude.abs() < 15) {
      // 热带
      baseTemp = 28;
    } else if (latitude.abs() < 30) {
      // 亚热带
      baseTemp = 22;
    } else if (latitude.abs() < 45) {
      // 温带
      baseTemp = 15;
    } else if (latitude.abs() < 60) {
      // 亚寒带
      baseTemp = 5;
    } else {
      // 寒带
      baseTemp = -10;
    }
    
    // 根据季节调整温度
    if (season == '夏季') {
      baseTemp += 10;
    } else if (season == '冬季') {
      baseTemp -= 10;
    } else {
      // 春秋季温度适中
      baseTemp += 2;
    }
    
    // 确定天气类型（简化模型）
    String weatherType;
    int weatherCode;
    
    // 随机天气变化因子
    final randomFactor = now.day % 4; // 0-3之间的数字，给天气添加一些随机性
    
    if (season == '夏季') {
      if (randomFactor == 0) {
        weatherType = '晴';
        weatherCode = 0;
      } else if (randomFactor == 1) {
        weatherType = '多云';
        weatherCode = 3;
      } else {
        weatherType = '阵雨';
        weatherCode = 80;
      }
    } else if (season == '冬季') {
      if (latitude.abs() > 40 && randomFactor > 1) {
        weatherType = '雪';
        weatherCode = 71;
      } else if (randomFactor == 0) {
        weatherType = '晴';
        weatherCode = 0;
      } else {
        weatherType = '多云';
        weatherCode = 3;
      }
    } else {
      // 春秋季
      if (randomFactor == 0) {
        weatherType = '晴';
        weatherCode = 0;
      } else if (randomFactor == 1) {
        weatherType = '多云';
        weatherCode = 3;
      } else if (randomFactor == 2) {
        weatherType = '小雨';
        weatherCode = 61;
      } else {
        weatherType = '阴';
        weatherCode = 3;
      }
    }
    
    // 设置天气数据
    _weatherDescription = weatherType;
    _currentWeather = weatherType;
    _temperature_value = baseTemp + (randomFactor - 1.5);
    _temperature = '${_temperature_value?.toStringAsFixed(0)}°C';
    _weatherIcon = _getWeatherIconCode(weatherCode);
    
    debugPrint('本地天气估算: $_weatherDescription, $_temperature');
  }

  // 从缓存加载天气数据
  Future<bool> _loadFromCache(double latitude, double longitude) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      // 检查缓存是否存在并且未过期
      final cacheExpiryString = prefs.getString(_cacheExpiryKey);
      if (cacheExpiryString != null) {
        final cacheExpiry = DateTime.parse(cacheExpiryString);
        if (DateTime.now().isBefore(cacheExpiry)) {
          // 缓存有效，可以使用
          final cacheJson = prefs.getString(_cacheKey);
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
      final prefs = await SharedPreferences.getInstance();
      
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
      await prefs.setString(_cacheKey, json.encode(cacheData));
      await prefs.setString(
        _cacheExpiryKey, 
        DateTime.now().add(_cacheDuration).toIso8601String()
      );
      
      debugPrint('天气数据已保存到缓存');
    } catch (e) {
      debugPrint('保存天气数据到缓存失败: $e');
    }
  }

  // 使用OpenMeteo API获取天气
  Future<void> _getOpenMeteoWeather(double latitude, double longitude) async {
    try {
      // OpenMeteo是完全免费的API，不需要API key
      final url = 'https://api.open-meteo.com/v1/forecast?latitude=$latitude&longitude=$longitude&current=temperature_2m,weather_code,wind_speed_10m&timezone=auto&language=zh_cn';
      
      final response = await HttpUtils.secureGet(
        url,
        timeoutSeconds: 10, // 降低超时时间，避免长时间等待
      );
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        
        // 解析天气代码和温度
        final current = data['current'];
        final weatherCode = current['weather_code'];
        _temperature_value = current['temperature_2m'];
        _temperature = '${_temperature_value?.toStringAsFixed(0)}°C';
        
        // 天气代码转换为中文描述
        _weatherDescription = _getWeatherDescription(weatherCode);
        _currentWeather = _weatherDescription;
        _weatherIcon = _getWeatherIconCode(weatherCode);
        
        debugPrint('天气数据获取成功：$_weatherDescription, $_temperature');
      } else {
        debugPrint('OpenMeteo请求失败: ${response.statusCode}，${response.body}');
        throw Exception('OpenMeteo请求失败: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('获取OpenMeteo天气失败: $e');
      throw e; // 重新抛出异常以便外部处理
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