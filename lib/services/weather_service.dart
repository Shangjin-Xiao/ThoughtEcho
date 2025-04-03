import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:intl/intl.dart';
import '../utils/http_utils.dart'; // 确保使用安全HTTP工具类

class WeatherService extends ChangeNotifier {
  String? _currentWeather;
  String? _temperature;
  String? _weatherDescription;
  bool _isLoading = false;
  String? _weatherIcon;
  double? _temperature_value;

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
      
      // 使用开放的OpenMeteo API
      await _getOpenMeteoWeather(latitude, longitude);
      
      _isLoading = false;
      notifyListeners();
    } catch (e) {
      _isLoading = false;
      debugPrint('获取天气数据异常: $e');
      // 如果获取失败，设置模拟数据
      setMockWeatherData();
      notifyListeners();
    }
  }

  // 使用OpenMeteo API获取天气
  Future<void> _getOpenMeteoWeather(double latitude, double longitude) async {
    try {
      // OpenMeteo是完全免费的API，不需要API key
      final url = 'https://api.open-meteo.com/v1/forecast?latitude=$latitude&longitude=$longitude&current=temperature_2m,weather_code,wind_speed_10m&timezone=auto&language=zh_cn';
      
      final response = await HttpUtils.secureGet(url);
      
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

  // 设置模拟天气数据(当API不可用时)
  void setMockWeatherData() {
    _weatherDescription = '晴天';
    _temperature = '25°C';
    _temperature_value = 25.0;
    _currentWeather = '晴天';
    _weatherIcon = 'clear_day';
    debugPrint('使用模拟天气数据');
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
      default:
        return Icons.cloud_queue;
    }
  }

  // 获取格式化的天气字符串
  String getFormattedWeather() {
    if (_currentWeather == null || _temperature == null) return '';
    return '$_currentWeather $_temperature';
  }
} 