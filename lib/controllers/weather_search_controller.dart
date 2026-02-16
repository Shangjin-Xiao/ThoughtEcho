import 'dart:async';

import 'package:flutter/foundation.dart';
import '../gen_l10n/app_localizations.dart';
import '../services/location_service.dart';
import '../services/weather_service.dart';
import '../utils/app_logger.dart';

/// 天气搜索操作结果类型
enum WeatherSearchResultType {
  citySelectedSuccess,
  currentLocationSuccess,
  weatherTimeout,
  weatherFetchFailed,
  locationTimeout,
  locationPermissionDenied,
  cityLocationNotFound,
  citySelectionError,
  locationFetchError,
}

/// 天气搜索操作结果
class WeatherSearchResult {
  final WeatherSearchResultType type;
  final bool isSuccess;
  final String? cityName;
  final String? errorDetail;

  const WeatherSearchResult({
    required this.type,
    required this.isSuccess,
    this.cityName,
    this.errorDetail,
  });

  /// 在 UI 层使用此方法获取国际化文本
  String getLocalizedMessage(AppLocalizations l10n) {
    switch (type) {
      case WeatherSearchResultType.citySelectedSuccess:
        return l10n.citySelectedWeatherUpdated(cityName ?? '');
      case WeatherSearchResultType.currentLocationSuccess:
        return l10n.currentLocationWeatherUpdated(
            cityName ?? l10n.currentLocationLabel);
      case WeatherSearchResultType.weatherTimeout:
        return l10n.weatherTimeoutRetry;
      case WeatherSearchResultType.weatherFetchFailed:
        return l10n.weatherFetchFailedCheckNetwork;
      case WeatherSearchResultType.locationTimeout:
        return l10n.locationTimeoutCheckPermission;
      case WeatherSearchResultType.locationPermissionDenied:
        return l10n.cannotGetCurrentLocation;
      case WeatherSearchResultType.cityLocationNotFound:
        return l10n.cannotGetSelectedCityLocation;
      case WeatherSearchResultType.citySelectionError:
        return l10n.citySelectionError(errorDetail ?? '');
      case WeatherSearchResultType.locationFetchError:
        return l10n.locationFetchError(errorDetail ?? '');
    }
  }
}

/// 天气搜索控制器
/// 管理设置界面中的城市搜索和天气更新逻辑
class WeatherSearchController extends ChangeNotifier {
  final LocationService _locationService;
  final WeatherService _weatherService;

  bool _isLoading = false;
  WeatherSearchResult? _lastResult;

  WeatherSearchController(this._locationService, this._weatherService);

  /// 是否正在加载
  bool get isLoading => _isLoading;

  /// 最近一次操作结果
  WeatherSearchResult? get lastResult => _lastResult;

  /// 兼容性 getter（供现有 UI 代码过渡使用）
  /// @deprecated 使用 lastResult 代替
  String? get errorMessage => _lastResult != null && !_lastResult!.isSuccess
      ? _lastResult!.errorDetail
      : null;
  String? get successMessage => null; // 已移至 lastResult

  /// 清除状态信息
  void clearMessages() {
    _lastResult = null;
    notifyListeners();
  }

  /// 选择城市并更新天气
  Future<bool> selectCityAndUpdateWeather(CityInfo cityInfo) async {
    _setLoading(true);
    _lastResult = null;

    try {
      // 1. 设置选中的城市
      await _locationService.setSelectedCity(cityInfo);
      logDebug('城市设置成功: ${cityInfo.name}');

      // 2. 获取位置信息
      final position = _locationService.currentPosition;
      if (position == null) {
        _lastResult = const WeatherSearchResult(
          type: WeatherSearchResultType.cityLocationNotFound,
          isSuccess: false,
        );
        return false;
      }

      // 3. 获取天气数据
      await _weatherService
          .getWeatherData(position.latitude, position.longitude)
          .timeout(
        const Duration(seconds: 15),
        onTimeout: () {
          throw TimeoutException('Weather fetch timeout');
        },
      );

      // 4. 检查天气数据是否获取成功
      if (!_weatherService.hasValidWeatherData) {
        _lastResult = const WeatherSearchResult(
          type: WeatherSearchResultType.weatherFetchFailed,
          isSuccess: false,
        );
        return false;
      }

      _lastResult = WeatherSearchResult(
        type: WeatherSearchResultType.citySelectedSuccess,
        isSuccess: true,
        cityName: cityInfo.name,
      );
      logInfo('城市选择和天气更新成功: ${cityInfo.name}');
      return true;
    } on TimeoutException {
      _lastResult = const WeatherSearchResult(
        type: WeatherSearchResultType.weatherTimeout,
        isSuccess: false,
      );
      return false;
    } catch (e) {
      _lastResult = WeatherSearchResult(
        type: WeatherSearchResultType.citySelectionError,
        isSuccess: false,
        errorDetail: e.toString(),
      );
      logError('城市选择失败', error: e);
      return false;
    } finally {
      _setLoading(false);
    }
  }

  /// 使用当前位置
  Future<bool> useCurrentLocation() async {
    _setLoading(true);
    _lastResult = null;

    try {
      // 1. 获取当前位置
      final position = await _locationService.getCurrentLocation().timeout(
        const Duration(seconds: 20),
        onTimeout: () {
          throw TimeoutException('Location fetch timeout');
        },
      );

      if (position == null) {
        _lastResult = const WeatherSearchResult(
          type: WeatherSearchResultType.locationPermissionDenied,
          isSuccess: false,
        );
        return false;
      }

      // 2. 获取天气数据
      await _weatherService
          .getWeatherData(position.latitude, position.longitude)
          .timeout(
        const Duration(seconds: 15),
        onTimeout: () {
          throw TimeoutException('Weather fetch timeout');
        },
      );

      // 3. 检查天气数据是否获取成功
      if (!_weatherService.hasValidWeatherData) {
        _lastResult = const WeatherSearchResult(
          type: WeatherSearchResultType.weatherFetchFailed,
          isSuccess: false,
        );
        return false;
      }

      final cityName = _locationService.city;
      _lastResult = WeatherSearchResult(
        type: WeatherSearchResultType.currentLocationSuccess,
        isSuccess: true,
        cityName: cityName,
      );
      logInfo('当前位置获取和天气更新成功: $cityName');
      return true;
    } on TimeoutException catch (e) {
      final isLocationTimeout = e.message?.contains('Location') ?? false;
      _lastResult = WeatherSearchResult(
        type: isLocationTimeout
            ? WeatherSearchResultType.locationTimeout
            : WeatherSearchResultType.weatherTimeout,
        isSuccess: false,
      );
      return false;
    } catch (e) {
      _lastResult = WeatherSearchResult(
        type: WeatherSearchResultType.locationFetchError,
        isSuccess: false,
        errorDetail: e.toString(),
      );
      logError('当前位置获取失败', error: e);
      return false;
    } finally {
      _setLoading(false);
    }
  }

  /// 设置加载状态
  void _setLoading(bool loading) {
    _isLoading = loading;
    notifyListeners();
  }
}
