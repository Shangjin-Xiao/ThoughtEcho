import 'package:flutter/foundation.dart';
import '../services/location_service.dart';
import '../services/weather_service.dart';
import '../utils/app_logger.dart';

/// 天气搜索控制器
/// 管理设置界面中的城市搜索和天气更新逻辑
class WeatherSearchController extends ChangeNotifier {
  final LocationService _locationService;
  final WeatherService _weatherService;

  bool _isLoading = false;
  String? _errorMessage;
  String? _successMessage;

  WeatherSearchController(this._locationService, this._weatherService);

  /// 是否正在加载
  bool get isLoading => _isLoading;

  /// 错误信息
  String? get errorMessage => _errorMessage;

  /// 成功信息
  String? get successMessage => _successMessage;

  /// 清除状态信息
  void clearMessages() {
    _errorMessage = null;
    _successMessage = null;
    notifyListeners();
  }

  /// 选择城市并更新天气
  Future<bool> selectCityAndUpdateWeather(CityInfo cityInfo) async {
    _setLoading(true);
    _clearMessages();

    try {
      // 1. 设置选中的城市
      await _locationService.setSelectedCity(cityInfo);
      logDebug('城市设置成功: ${cityInfo.name}');

      // 2. 获取位置信息
      final position = _locationService.currentPosition;
      if (position == null) {
        throw Exception('无法获取选中城市的位置信息');
      }

      // 3. 获取天气数据
      await _weatherService
          .getWeatherData(position.latitude, position.longitude)
          .timeout(
            const Duration(seconds: 15),
            onTimeout: () {
              throw Exception('天气获取超时，请稍后重试');
            },
          );

      // 4. 检查天气数据是否获取成功
      if (_weatherService.currentWeather == '天气数据获取失败') {
        throw Exception('天气数据获取失败，请检查网络连接');
      }

      _successMessage = '已选择城市：${cityInfo.name}，天气已更新';
      logInfo('城市选择和天气更新成功: ${cityInfo.name}');
      return true;
    } catch (e) {
      _errorMessage = '处理城市选择时出错: ${e.toString()}';
      logError('城市选择失败', error: e);
      return false;
    } finally {
      _setLoading(false);
    }
  }

  /// 使用当前位置
  Future<bool> useCurrentLocation() async {
    _setLoading(true);
    _clearMessages();

    try {
      // 1. 获取当前位置
      final position = await _locationService.getCurrentLocation().timeout(
        const Duration(seconds: 20),
        onTimeout: () {
          throw Exception('位置获取超时，请检查位置权限设置');
        },
      );

      if (position == null) {
        throw Exception('无法获取当前位置，请确保已授予位置权限');
      }

      // 2. 获取天气数据
      await _weatherService
          .getWeatherData(position.latitude, position.longitude)
          .timeout(
            const Duration(seconds: 15),
            onTimeout: () {
              throw Exception('天气获取超时，请稍后重试');
            },
          );

      // 3. 检查天气数据是否获取成功
      if (_weatherService.currentWeather == '天气数据获取失败') {
        throw Exception('天气数据获取失败，请检查网络连接');
      }

      final cityName = _locationService.city ?? '当前位置';
      _successMessage = '已使用当前位置：$cityName，天气已更新';
      logInfo('当前位置获取和天气更新成功: $cityName');
      return true;
    } catch (e) {
      _errorMessage = '获取当前位置失败: ${e.toString()}';
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

  /// 清除消息
  void _clearMessages() {
    _errorMessage = null;
    _successMessage = null;
  }
}
