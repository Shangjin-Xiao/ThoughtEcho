import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:convert';
import '../services/network_service.dart';
// import '../utils/dio_network_utils.dart'; // 导入dio网络工具
import 'local_geocoding_service.dart'; // 导入本地地理编码服务
import '../utils/app_logger.dart';

class CityInfo {
  final String name; // 城市名称
  final String fullName; // 完整名称包括国家和省份
  final double lat; // 纬度
  final double lon; // 经度
  final String country; // 国家
  final String province; // 省/州

  CityInfo({
    required this.name,
    required this.fullName,
    required this.lat,
    required this.lon,
    required this.country,
    required this.province,
  });

  @override
  String toString() => fullName;
}

class LocationService extends ChangeNotifier {
  Position? _currentPosition;
  String? _currentAddress;
  bool _hasLocationPermission = false;
  bool _isLocationServiceEnabled = false;
  bool _isLoading = false;

  // 城市搜索结果
  List<CityInfo> _searchResults = [];
  bool _isSearching = false;

  Position? get currentPosition => _currentPosition;
  String? get currentAddress => _currentAddress;
  bool get hasLocationPermission => _hasLocationPermission;
  bool get isLocationServiceEnabled => _isLocationServiceEnabled;
  bool get isLoading => _isLoading;
  List<CityInfo> get searchResults => _searchResults;
  bool get isSearching => _isSearching;

  // 地址组件
  String? _country;
  String? _province;
  String? _city;
  String? _district;

  String? get country => _country;
  String? get province => _province;
  String? get city => _city;
  String? get district => _district;

  // 初始化位置服务
  Future<void> init() async {
    logDebug('开始初始化位置服务');
    try {
      _isLocationServiceEnabled = await Geolocator.isLocationServiceEnabled();

      // 只在位置服务启用时检查权限
      if (_isLocationServiceEnabled) {
        logDebug('位置服务已启用');
        final permission = await Geolocator.checkPermission();
        _hasLocationPermission = (permission == LocationPermission.whileInUse ||
            permission == LocationPermission.always);
        logDebug('位置权限状态: $_hasLocationPermission');

        // 只在首次获取到权限时尝试获取位置
        if (_hasLocationPermission) {
          getCurrentLocation(highAccuracy: false).then((position) {
            if (position != null) {
              logDebug('初始化时获取位置: ${position.latitude}, ${position.longitude}');
            }
          });
        }
      } else {
        _hasLocationPermission = false;
        logDebug('位置服务未启用');
      }

      notifyListeners();
    } catch (e) {
      logDebug('初始化位置服务错误: $e');
      _hasLocationPermission = false;
      notifyListeners();
    }
  }

  // 检查位置权限
  Future<bool> checkLocationPermission() async {
    try {
      // 检查位置服务是否启用
      _isLocationServiceEnabled = await Geolocator.isLocationServiceEnabled();

      if (!_isLocationServiceEnabled) {
        return false;
      }

      // 检查位置权限状态
      LocationPermission permission = await Geolocator.checkPermission();

      // 只检查权限，不自动请求
      if (permission == LocationPermission.denied) {
        // permission = await Geolocator.requestPermission(); // 移除自动请求
        // if (permission == LocationPermission.denied) {
        _hasLocationPermission = false;
        notifyListeners();
        return false; // 直接返回 false，表示权限不足
        // }
      }

      if (permission == LocationPermission.deniedForever) {
        _hasLocationPermission = false;
        notifyListeners();
        return false;
      }

      _hasLocationPermission = (permission == LocationPermission.whileInUse ||
          permission == LocationPermission.always);

      notifyListeners();
      return _hasLocationPermission;
    } catch (e) {
      logDebug('检查位置权限失败: $e');
      _hasLocationPermission = false;
      notifyListeners();
      return false;
    }
  }

  // 请求位置权限
  Future<bool> requestLocationPermission() async {
    try {
      var status = await Permission.location.request();
      _hasLocationPermission = status.isGranted;
      notifyListeners();
      return _hasLocationPermission;
    } catch (e) {
      logDebug('请求位置权限失败: $e');
      return false;
    }
  }

  // 获取当前位置
  Future<Position?> getCurrentLocation({
    bool highAccuracy = false,
    bool skipPermissionRequest = false, // 添加跳过权限请求的参数
  }) async {
    // 检查位置服务是否启用
    if (!_isLocationServiceEnabled) {
      _isLocationServiceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!_isLocationServiceEnabled) {
        logDebug('位置服务未启用');
        return null;
      }
    }

    // 如果没有权限且需要请求权限
    if (!_hasLocationPermission && !skipPermissionRequest) {
      // 检查权限，但不自动请求
      final permission = await Geolocator.checkPermission();
      _hasLocationPermission = (permission == LocationPermission.whileInUse ||
          permission == LocationPermission.always);

      if (!_hasLocationPermission) {
        logDebug('位置权限不足，无法获取位置');
        return null; // 直接返回 null，表示无法获取位置
      }
    } else if (!_hasLocationPermission && skipPermissionRequest) {
      // 如果没有权限但选择跳过权限请求
      logDebug('跳过权限请求，由于权限不足无法获取位置');
      return null;
    }

    try {
      _isLoading = true;
      notifyListeners();

      logDebug('开始获取位置，使用${highAccuracy ? "高" : "低"}精度模式...');

      // 使用LocalGeocodingService获取位置，并添加超时控制
      _currentPosition = await LocalGeocodingService.getCurrentPosition(
        highAccuracy: highAccuracy,
      ).timeout(
        const Duration(seconds: 15), // 15秒超时
        onTimeout: () {
          logDebug('位置获取超时');
          throw Exception('位置获取超时，请重试');
        },
      );

      if (_currentPosition != null) {
        logDebug(
          '位置获取成功: ${_currentPosition?.latitude}, ${_currentPosition?.longitude}',
        );
        // 使用本地解析方法获取地址，也添加超时控制
        try {
          await getAddressFromLatLng().timeout(
            const Duration(seconds: 10), // 地址解析10秒超时
            onTimeout: () {
              logDebug('地址解析超时，但位置信息仍然可用');
              // 不抛出异常，允许继续使用位置信息
            },
          );
        } catch (e) {
          logDebug('地址解析失败: $e，但位置信息仍然可用');
        }
      } else {
        logDebug('无法获取当前位置');
      }

      _isLoading = false;
      notifyListeners();
      return _currentPosition;
    } catch (e) {
      _isLoading = false;
      logDebug('获取位置失败: $e');
      notifyListeners();
      return null; // 失败时返回null而不是之前的位置
    }
  }

  // 根据经纬度获取地址信息
  Future<void> getAddressFromLatLng() async {
    if (_currentPosition == null) {
      logDebug('没有位置信息，无法获取地址');
      return;
    }

    try {
      logDebug('开始通过经纬度获取地址信息...');

      // 使用系统SDK获取地址信息
      final addressInfo = await LocalGeocodingService.getAddressFromCoordinates(
        _currentPosition!.latitude,
        _currentPosition!.longitude,
      );

      // 如果本地解析成功
      if (addressInfo != null) {
        _country = addressInfo['country'];
        _province = addressInfo['province'];
        _city = addressInfo['city'];
        _district = addressInfo['district'];
        _currentAddress = addressInfo['formatted_address'];

        logDebug(
          '本地地址解析成功: $_currentAddress (国家:$_country, 省份:$_province, 城市:$_city, 区县:$_district)',
        );
        notifyListeners();
        return;
      }

      // 如果本地解析失败，总是尝试使用在线服务 (Nominatim)
      try {
        await _getAddressFromLatLngOnline();
      } catch (e) {
        logDebug('在线地址解析失败: $e');
        _country = null;
        _province = null;
        _city = null;
        _district = null;
        _currentAddress = '地址解析失败';
        notifyListeners();
      }
    } catch (e) {
      logDebug('获取地址信息失败: $e');
      _country = null;
      _province = null;
      _city = null;
      _district = null;
      _currentAddress = '地址解析失败';
      notifyListeners();
    }
  }

  // 使用在线服务获取地址（备用方法）
  Future<void> _getAddressFromLatLngOnline() async {
    try {
      final url =
          'https://nominatim.openstreetmap.org/reverse?format=json&lat=${_currentPosition!.latitude}&lon=${_currentPosition!.longitude}&zoom=18&addressdetails=1';

      final response = await NetworkService.instance.get(
        url,
        headers: {
          'Accept-Language': 'zh-CN,zh;q=0.9',
          'User-Agent': 'ThoughtEcho App',
        },
        timeoutSeconds: 15,
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);

        // 解析国家、省、市、区信息
        if (data.containsKey('address')) {
          final address = data['address'];
          _country = address['country'];
          _province = address['state'] ?? address['province'];
          _city = address['city'] ??
              address['county'] ??
              address['town'] ??
              address['village'];
          _district = address['district'] ?? address['suburb'];

          // 组合完整地址显示
          _currentAddress = '$_country, $_province, $_city';
          if (_district != null && _district!.isNotEmpty) {
            _currentAddress = '$_currentAddress, $_district';
          }

          logDebug('在线地址解析成功: $_currentAddress');
        }
      }
    } catch (e) {
      throw Exception('在线地址解析调用失败: $e');
    }
  }

  // 搜索城市
  Future<List<CityInfo>> searchCity(String query) async {
    if (query.trim().isEmpty) {
      _searchResults = [];
      notifyListeners();
      return _searchResults;
    }

    _isSearching = true;
    notifyListeners();

    try {
      // 添加总体超时控制
      final results = await Future.any([
        _searchCityWithTimeout(query),
        Future.delayed(
          const Duration(seconds: 12),
          () => <CityInfo>[],
        ), // 12秒超时返回空列表
      ]);

      _searchResults = results;
      return _searchResults;
    } catch (e) {
      logDebug('城市搜索失败: $e');
      _searchResults = [];
      return _searchResults;
    } finally {
      _isSearching = false;
      notifyListeners();
    }
  }

  // 带超时的城市搜索
  Future<List<CityInfo>> _searchCityWithTimeout(String query) async {
    try {
      // 首先尝试使用OpenMeteo API
      final results = await _searchCityWithOpenMeteo(
        query,
      ).timeout(const Duration(seconds: 8), onTimeout: () => <CityInfo>[]);

      if (results.isNotEmpty) {
        return results;
      }

      // 如果OpenMeteo没有结果，尝试使用OpenStreetMap API
      return await _searchCityOnline(
        query,
      ).timeout(const Duration(seconds: 8), onTimeout: () => <CityInfo>[]);
    } catch (e) {
      logDebug('城市搜索异常: $e');
      return <CityInfo>[];
    }
  }

  // 使用OpenMeteo的地理编码API搜索城市
  Future<List<CityInfo>> _searchCityWithOpenMeteo(String query) async {
    try {
      // OpenMeteo地理编码API
      final url =
          'https://geocoding-api.open-meteo.com/v1/search?name=$query&count=10&language=zh&format=json';

      final response = await NetworkService.instance.get(
        url,
        timeoutSeconds: 10,
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);

        // 检查是否有结果
        if (data.containsKey('results') &&
            data['results'] is List &&
            data['results'].isNotEmpty) {
          final List<dynamic> results = data['results'];

          return results.map((item) {
            // 提取地点信息
            final String name = item['name'] ?? '';
            final String country = item['country'] ?? '';
            final String admin1 = item['admin1'] ?? ''; // 省/州级行政区

            // 构建完整地址
            final String fullName = [
              country,
              admin1,
              name,
            ].where((part) => part.isNotEmpty).join(', ');

            return CityInfo(
              name: name,
              fullName: fullName,
              lat: item['latitude'] ?? 0.0,
              lon: item['longitude'] ?? 0.0,
              country: country,
              province: admin1,
            );
          }).toList();
        }
      }

      // 如果没有结果或请求失败，返回空列表
      return [];
    } catch (e) {
      logDebug('OpenMeteo地理编码API调用失败: $e');
      return [];
    }
  }

  // 在线搜索城市
  Future<List<CityInfo>> _searchCityOnline(String query) async {
    _isSearching = true;
    notifyListeners();

    try {
      // 首先尝试使用OpenMeteo的地理编码API搜索城市
      final results = await _searchCityWithOpenMeteo(query);

      // 如果OpenMeteo返回了结果，直接使用
      if (results.isNotEmpty) {
        _searchResults = results;
        return _searchResults;
      }

      // 如果OpenMeteo没有返回结果，回退到OpenStreetMap的Nominatim API
      logDebug('OpenMeteo没有返回结果，尝试使用OpenStreetMap API');
      final url =
          'https://nominatim.openstreetmap.org/search?q=$query&format=json&addressdetails=1&limit=10';

      final response = await NetworkService.instance.get(
        url,
        headers: {
          'Accept-Language': 'zh-CN,zh;q=0.9',
          'User-Agent': 'ThoughtEcho App',
        },
        timeoutSeconds: 15,
      );

      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        _searchResults = data.map((item) {
          // 提取地址信息
          final address = item['address'] ?? {};

          // 更灵活地处理地点名称，支持城市、地区、国家等各种类型的地点
          String placeName = item['name'] ?? '';
          String cityName = address['city'] ??
              address['town'] ??
              address['village'] ??
              address['municipality'] ??
              placeName;
          String country = address['country'] ?? '';
          String state = address['state'] ??
              address['province'] ??
              address['county'] ??
              '';

          // 对于一些大城市，可能直接作为顶级地点返回，没有详细的address信息
          if (address.isEmpty && placeName.isNotEmpty) {
            cityName = placeName;
          }

          // 构建完整地址 - 国家, 省/州, 城市
          final String fullName = [
            country,
            state,
            cityName,
          ].where((part) => part.isNotEmpty).join(', ');

          logDebug(
            '搜索结果: $placeName, $cityName, $country, $state, 完整: $fullName',
          );

          return CityInfo(
            name: cityName,
            fullName: fullName,
            lat: double.parse(item['lat']),
            lon: double.parse(item['lon']),
            country: country,
            province: state,
          );
        }).toList();
      } else {
        _searchResults = [];
        logDebug('搜索城市失败: ${response.statusCode}, ${response.body}');
      }
    } catch (e) {
      _searchResults = [];
      logDebug('搜索城市发生错误: $e');
      // 重新抛出异常以便外部处理
      rethrow;
    } finally {
      _isSearching = false;
      notifyListeners();
    }

    return _searchResults;
  }

  // 清空搜索结果
  void clearSearchResults() {
    _searchResults = [];
    _isSearching = false; // 确保搜索状态也重置
    notifyListeners();
  }

  // 使用选定的城市信息设置位置
  Future<void> setSelectedCity(CityInfo city) async {
    try {
      if (city.name.isEmpty || city.country.isEmpty || city.province.isEmpty) {
        throw Exception('城市信息不完整');
      }

      // 手动设置位置组件
      _country = city.country;
      _province = city.province;
      _city = city.name;
      _district = null;

      // 更新地址字符串
      List<String> addressParts = [
        city.country,
        city.province,
        city.name,
      ].where((part) => part.isNotEmpty).toList();
      _currentAddress = addressParts.join(', ');

      // 验证经纬度的有效性
      if (city.lat < -90 ||
          city.lat > 90 ||
          city.lon < -180 ||
          city.lon > 180) {
        throw Exception('无效的经纬度');
      }

      // 创建一个模拟的Position对象来保持API一致性
      _currentPosition = Position(
        latitude: city.lat,
        longitude: city.lon,
        timestamp: DateTime.now(),
        accuracy: 0,
        altitude: 0,
        heading: 0,
        speed: 0,
        speedAccuracy: 0,
        altitudeAccuracy: 0,
        headingAccuracy: 0,
      );

      notifyListeners();
      logDebug('成功设置城市: $_currentAddress');
    } catch (e) {
      logDebug('设置城市失败: $e');
      // 重置所有状态
      _country = null;
      _province = null;
      _city = null;
      _district = null;
      _currentAddress = null;
      _currentPosition = null;
      notifyListeners();
      // 重新抛出异常以便UI层处理
      rethrow;
    }
  }

  // 获取格式化位置(国家,省份,城市,区县)
  String getFormattedLocation() {
    if (_currentAddress == null) return '';
    return '$_country,$_province,$_city${_district != null ? ',$_district' : ''}';
  }

  // 获取显示格式的位置，如"广州市·天河区"
  String getDisplayLocation() {
    if (_city == null) return '';

    // 如果城市名已经包含"市"，不再添加
    String cityDisplay = _city!.endsWith('市') ? _city! : '$_city市';

    // 如果有区县信息，添加中文中间点和区县名称
    if (_district != null && _district!.isNotEmpty) {
      return '$cityDisplay·$_district';
    } else {
      return cityDisplay;
    }
  }

  // 从格式化的位置字符串解析地址组件
  void parseLocationString(String? locationString) {
    if (locationString == null || locationString.isEmpty) {
      _country = null;
      _province = null;
      _city = null;
      _district = null;
      _currentAddress = null;
      return;
    }

    final parts = locationString.split(',');
    if (parts.length >= 3) {
      _country = parts[0];
      _province = parts[1];
      _city = parts[2];
      _district = parts.length >= 4 ? parts[3] : null;

      // 构建显示地址
      _currentAddress = '$_country, $_province, $_city';
      if (_district != null && _district!.isNotEmpty) {
        _currentAddress = '$_currentAddress, $_district';
      }
    }
  }
}
