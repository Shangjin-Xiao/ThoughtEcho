import 'dart:convert';
import '../utils/mmkv_ffi_fix.dart';
import '../models/weather_data.dart';
import 'package:thoughtecho/utils/app_logger.dart';

/// 天气缓存管理器
class WeatherCacheManager {
  static const String _cacheKey = 'weather_cache';
  static const String _cacheExpiryKey = 'weather_cache_expiry';
  static const Duration _defaultCacheDuration = Duration(hours: 3);

  SafeMMKV? _storage;
  bool _isInitialized = false;

  /// 初始化缓存管理器
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      _storage = SafeMMKV();
      await _storage!.initialize();
      _isInitialized = true;
      logDebug('天气缓存管理器初始化完成');
    } catch (e) {
      logError('天气缓存管理器初始化失败: $e', error: e);
      throw Exception('缓存管理器初始化失败');
    }
  }

  /// 检查缓存是否可用
  Future<bool> _ensureInitialized() async {
    if (!_isInitialized) {
      await initialize();
    }
    return _isInitialized;
  }

  /// 保存天气数据到缓存
  Future<void> saveWeatherData(WeatherData weatherData) async {
    try {
      if (!await _ensureInitialized()) return;

      final cacheData = weatherData.toJson();
      await _storage!.setString(_cacheKey, json.encode(cacheData));
      await _storage!.setString(
        _cacheExpiryKey,
        DateTime.now().add(_defaultCacheDuration).toIso8601String(),
      );

      logDebug('天气数据已保存到缓存: ${weatherData.description}');
    } catch (e) {
      logError('保存天气数据到缓存失败: $e', error: e);
    }
  }

  /// 从缓存加载天气数据
  Future<WeatherData?> loadWeatherData({
    double? latitude,
    double? longitude,
    Duration? maxAge,
  }) async {
    try {
      if (!await _ensureInitialized()) return null;

      // 检查缓存是否过期
      final cacheExpiryString = _storage!.getString(_cacheExpiryKey);
      if (cacheExpiryString != null) {
        final cacheExpiry = DateTime.parse(cacheExpiryString);
        if (DateTime.now().isAfter(cacheExpiry)) {
          logDebug('天气缓存已过期');
          return null;
        }
      } else {
        logDebug('天气缓存过期时间不存在');
        return null;
      }

      // 加载缓存数据
      final cacheJson = _storage!.getString(_cacheKey);
      if (cacheJson == null) {
        logDebug('天气缓存数据不存在');
        return null;
      }

      final weatherData = WeatherData.fromJson(json.decode(cacheJson));

      // 如果提供了位置信息，检查缓存的位置是否匹配
      if (latitude != null && longitude != null) {
        if (!weatherData.isLocationMatch(latitude, longitude)) {
          logDebug(
            '天气缓存位置不匹配，当前位置: ($latitude, $longitude)，缓存位置: (${weatherData.latitude}, ${weatherData.longitude})',
          );
          return null;
        }
      }

      // 如果提供了最大缓存时间，检查是否超时
      if (maxAge != null && weatherData.isExpired(maxAge)) {
        logDebug('天气缓存超过最大允许时间');
        return null;
      }

      logDebug('从缓存加载天气数据成功: ${weatherData.description}');
      return weatherData;
    } catch (e) {
      logError('从缓存加载天气数据失败: $e', error: e);
      return null;
    }
  }

  /// 清除天气缓存
  Future<void> clearCache() async {
    try {
      if (!await _ensureInitialized()) return;

      await _storage!.remove(_cacheKey);
      await _storage!.remove(_cacheExpiryKey);
      logDebug('天气缓存已清除');
    } catch (e) {
      logError('清除天气缓存失败: $e', error: e);
    }
  }

  /// 检查是否有有效的缓存
  Future<bool> hasValidCache({
    double? latitude,
    double? longitude,
    Duration? maxAge,
  }) async {
    final cachedData = await loadWeatherData(
      latitude: latitude,
      longitude: longitude,
      maxAge: maxAge,
    );
    return cachedData != null && cachedData.isValid;
  }

  /// 获取缓存信息（用于调试）
  Future<Map<String, dynamic>?> getCacheInfo() async {
    try {
      if (!await _ensureInitialized()) return null;

      final cacheJson = _storage!.getString(_cacheKey);
      final cacheExpiryString = _storage!.getString(_cacheExpiryKey);

      if (cacheJson == null || cacheExpiryString == null) {
        return null;
      }

      final cacheExpiry = DateTime.parse(cacheExpiryString);
      final isExpired = DateTime.now().isAfter(cacheExpiry);

      return {
        'hasCache': true,
        'isExpired': isExpired,
        'expiryTime': cacheExpiry.toIso8601String(),
        'remainingTime': isExpired
            ? 0
            : cacheExpiry.difference(DateTime.now()).inMinutes,
      };
    } catch (e) {
      logError('获取缓存信息失败: $e', error: e);
      return null;
    }
  }
}
