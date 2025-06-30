/// Mock WeatherService for testing
import 'package:flutter/foundation.dart';
import 'package:mockito/mockito.dart';
import 'dart:async';

import '../../lib/models/weather_data.dart';
import '../test_utils/test_data.dart';

enum WeatherServiceState {
  idle,
  loading,
  success,
  error,
  cached,
}

class MockWeatherService extends ChangeNotifier with Mock {
  WeatherData? _currentWeatherData;
  WeatherServiceState _state = WeatherServiceState.idle;
  String? _lastError;
  bool _isInitialized = false;
  Map<String, WeatherData> _cache = {};

  // Getters
  WeatherData? get currentWeatherData => _currentWeatherData;
  WeatherServiceState get state => _state;
  String? get lastError => _lastError;
  bool get isLoading => _state == WeatherServiceState.loading;
  bool get hasData => _currentWeatherData != null && _currentWeatherData!.isValid;
  bool get isInitialized => _isInitialized;

  // Compatibility getters
  String? get currentWeather => _currentWeatherData?.key;
  String? get temperature => _currentWeatherData?.temperatureText;
  String? get weatherDescription => _currentWeatherData?.description;
  String? get weatherIcon => _currentWeatherData?.iconCode;
  double? get temperatureValue => _currentWeatherData?.temperature;

  /// Initialize mock weather service
  Future<void> initialize() async {
    await Future.delayed(const Duration(milliseconds: 100));
    _isInitialized = true;
    
    // Set default weather data
    _currentWeatherData = TestData.createTestWeatherData();
    _state = WeatherServiceState.success;
    
    notifyListeners();
  }

  /// Get weather by coordinates
  Future<WeatherData> getWeatherByCoordinates(double latitude, double longitude) async {
    _setState(WeatherServiceState.loading);
    
    await Future.delayed(const Duration(milliseconds: 500));
    
    // Generate mock weather based on coordinates
    final cacheKey = '${latitude.toStringAsFixed(2)}_${longitude.toStringAsFixed(2)}';
    
    if (_cache.containsKey(cacheKey)) {
      _currentWeatherData = _cache[cacheKey]!;
      _setState(WeatherServiceState.cached);
      return _currentWeatherData!;
    }
    
    // Mock weather based on location
    WeatherData weatherData;
    if (latitude >= 35 && latitude <= 45) {
      // Northern regions - cooler weather
      weatherData = WeatherData(
        key: 'cloudy',
        description: '多云',
        temperature: 15.0,
        temperatureText: '15°C',
        iconCode: 'cloudy',
      );
    } else if (latitude >= 20 && latitude <= 35) {
      // Central regions - moderate weather
      weatherData = WeatherData(
        key: 'sunny',
        description: '晴天',
        temperature: 25.0,
        temperatureText: '25°C',
        iconCode: 'sunny',
      );
    } else {
      // Southern regions - warmer weather
      weatherData = WeatherData(
        key: 'hot',
        description: '炎热',
        temperature: 32.0,
        temperatureText: '32°C',
        iconCode: 'sunny',
      );
    }
    
    _currentWeatherData = weatherData;
    _cache[cacheKey] = weatherData;
    _setState(WeatherServiceState.success);
    
    return weatherData;
  }

  /// Get weather by city name
  Future<WeatherData> getWeatherByCity(String cityName) async {
    _setState(WeatherServiceState.loading);
    
    await Future.delayed(const Duration(milliseconds: 400));
    
    // Check cache first
    if (_cache.containsKey(cityName)) {
      _currentWeatherData = _cache[cityName]!;
      _setState(WeatherServiceState.cached);
      return _currentWeatherData!;
    }
    
    // Mock weather based on city name
    WeatherData weatherData;
    switch (cityName.toLowerCase()) {
      case '北京':
      case 'beijing':
        weatherData = WeatherData(
          key: 'cloudy',
          description: '多云',
          temperature: 18.0,
          temperatureText: '18°C',
          iconCode: 'cloudy',
        );
        break;
      case '上海':
      case 'shanghai':
        weatherData = WeatherData(
          key: 'rainy',
          description: '小雨',
          temperature: 22.0,
          temperatureText: '22°C',
          iconCode: 'rainy',
        );
        break;
      case '深圳':
      case 'shenzhen':
        weatherData = WeatherData(
          key: 'sunny',
          description: '晴天',
          temperature: 28.0,
          temperatureText: '28°C',
          iconCode: 'sunny',
        );
        break;
      case '杭州':
      case 'hangzhou':
        weatherData = WeatherData(
          key: 'foggy',
          description: '雾',
          temperature: 20.0,
          temperatureText: '20°C',
          iconCode: 'foggy',
        );
        break;
      default:
        weatherData = WeatherData(
          key: 'sunny',
          description: '晴天',
          temperature: 25.0,
          temperatureText: '25°C',
          iconCode: 'sunny',
        );
    }
    
    _currentWeatherData = weatherData;
    _cache[cityName] = weatherData;
    _setState(WeatherServiceState.success);
    
    return weatherData;
  }

  /// Refresh weather data
  Future<void> refreshWeatherData() async {
    if (_currentWeatherData == null) return;
    
    _setState(WeatherServiceState.loading);
    await Future.delayed(const Duration(milliseconds: 300));
    
    // Simulate slight temperature change
    final currentTemp = _currentWeatherData!.temperature;
    final newTemp = currentTemp + (-2 + (DateTime.now().millisecond % 5));
    
    _currentWeatherData = _currentWeatherData!.copyWith(
      temperature: newTemp,
      temperatureText: '${newTemp.toStringAsFixed(0)}°C',
    );
    
    _setState(WeatherServiceState.success);
  }

  /// Get cache info
  Future<Map<String, dynamic>?> getCacheInfo() async {
    await Future.delayed(const Duration(milliseconds: 50));
    
    return {
      'cache_size': _cache.length,
      'cache_keys': _cache.keys.toList(),
      'last_updated': DateTime.now().toIso8601String(),
    };
  }

  /// Clear cache
  Future<void> clearCache() async {
    await Future.delayed(const Duration(milliseconds: 100));
    _cache.clear();
    notifyListeners();
  }

  /// Set mock weather data for testing
  void setMockWeatherData({
    String? key,
    String? description,
    double? temperature,
    String? iconCode,
  }) {
    _currentWeatherData = WeatherData(
      key: key ?? 'test',
      description: description ?? '测试天气',
      temperature: temperature ?? 25.0,
      temperatureText: temperature != null ? '${temperature}°C' : '25°C',
      iconCode: iconCode ?? 'sunny',
    );
    _setState(WeatherServiceState.success);
  }

  /// Simulate error
  void simulateError(String error) {
    _lastError = error;
    _currentWeatherData = WeatherData.error(error);
    _setState(WeatherServiceState.error);
  }

  /// Clear error
  void clearError() {
    _lastError = null;
    notifyListeners();
  }

  /// Set state
  void _setState(WeatherServiceState newState) {
    _state = newState;
    notifyListeners();
  }

  /// Get weather icon for condition
  String getWeatherIcon(String condition) {
    switch (condition.toLowerCase()) {
      case 'sunny':
      case '晴':
        return '☀️';
      case 'cloudy':
      case '多云':
        return '☁️';
      case 'rainy':
      case '雨':
        return '🌧️';
      case 'snowy':
      case '雪':
        return '❄️';
      case 'foggy':
      case '雾':
        return '🌫️';
      case 'windy':
      case '风':
        return '💨';
      default:
        return '🌤️';
    }
  }

  /// Get temperature description
  String getTemperatureDescription(double temperature) {
    if (temperature < 0) return '严寒';
    if (temperature < 10) return '寒冷';
    if (temperature < 20) return '凉爽';
    if (temperature < 30) return '温暖';
    if (temperature < 35) return '炎热';
    return '酷热';
  }

  /// Check if weather data is fresh
  bool isDataFresh() {
    return _currentWeatherData != null && _state == WeatherServiceState.success;
  }

  /// Get weather summary
  String getWeatherSummary() {
    if (_currentWeatherData == null) return '无天气数据';
    
    return '${_currentWeatherData!.description} ${_currentWeatherData!.temperatureText}';
  }

  /// Add to cache
  void addToCache(String key, WeatherData data) {
    _cache[key] = data;
    notifyListeners();
  }

  /// Remove from cache
  void removeFromCache(String key) {
    _cache.remove(key);
    notifyListeners();
  }

  /// Get cache size
  int getCacheSize() {
    return _cache.length;
  }
}