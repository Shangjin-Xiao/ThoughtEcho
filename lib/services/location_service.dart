import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'dart:convert';
import '../services/network_service.dart';
// import '../utils/dio_network_utils.dart'; // 导入dio网络工具
import 'local_geocoding_service.dart'; // 导入本地地理编码服务
import '../utils/app_logger.dart';
import '../utils/i18n_language.dart';

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
  static const String kAddressPending = '__address_pending__';
  static const String kAddressFailed = '__address_failed__';
  static const String _legacyPending = '位置待解析';
  static const String _legacyFailed = '地址解析失败';

  static bool isPendingMarker(String? s) =>
      s == kAddressPending || s == _legacyPending;

  static bool isFailedMarker(String? s) =>
      s == kAddressFailed || s == _legacyFailed;

  static bool isNonDisplayMarker(String? s) =>
      s == null || s.isEmpty || isPendingMarker(s) || isFailedMarker(s);

  Position? _currentPosition;
  String? _currentAddress;
  bool _hasLocationPermission = false;
  bool _isLocationServiceEnabled = false;
  bool _isLoading = false;
  int _geocodeToken = 0;
  Completer<void>? _initCompleter;

  // 城市搜索结果
  List<CityInfo> _searchResults = [];
  bool _isSearching = false;

  // 当前语言设置（用于 API 调用）
  String? _currentLocaleCode;

  Position? get currentPosition => _currentPosition;
  String? get currentAddress => _currentAddress;
  bool get hasLocationPermission => _hasLocationPermission;
  bool get isLocationServiceEnabled => _isLocationServiceEnabled;
  bool get isLoading => _isLoading;
  List<CityInfo> get searchResults => _searchResults;
  bool get isSearching => _isSearching;

  /// 获取当前语言代码（用于 API 调用）
  String? get currentLocaleCode => _currentLocaleCode;

  /// 设置当前语言代码并通知监听者（避免不必要重复刷新）
  set currentLocaleCode(String? code) {
    if (_currentLocaleCode == code) return;
    _currentLocaleCode = code;
    notifyListeners();
  }

  /// 获取 API 调用使用的语言参数
  String get _apiLanguageParam =>
      I18nLanguage.appLanguageOrSystem(_currentLocaleCode);

  // 地址组件
  String? _country;
  String? _province;
  String? _city;
  String? _district;

  String? get country => _country;
  String? get province => _province;
  String? get city => _city;
  String? get district => _district;

  /// 检查当前是否处于离线状态（有坐标但没有解析出地址）
  bool get isOfflineLocation =>
      _currentPosition != null && isNonDisplayMarker(_currentAddress);

  /// 检查是否有有效坐标
  bool get hasCoordinates => _currentPosition != null;

  // 初始化位置服务
  Future<void> init() async {
    if (_initCompleter != null) return _initCompleter!.future;
    _initCompleter = Completer<void>();
    var initFailedWithException = false;
    logDebug('开始初始化位置服务');
    try {
      // Windows平台使用geolocator_windows插件，支持系统定位服务
      // 需要在Windows设置中启用位置服务：设置 > 隐私 > 位置
      _isLocationServiceEnabled = await Geolocator.isLocationServiceEnabled();

      // 只在位置服务启用时检查权限
      if (_isLocationServiceEnabled) {
        logDebug('位置服务已启用');
        final permission = await Geolocator.checkPermission();
        _hasLocationPermission =
            (permission == LocationPermission.whileInUse ||
            permission == LocationPermission.always);
        logDebug('位置权限状态: $_hasLocationPermission');

        // 只在首次获取到权限时尝试获取位置
        if (_hasLocationPermission) {
          getCurrentLocation(highAccuracy: false)
              .then((position) {
                if (position != null) {
                  logDebug(
                    '初始化时获取位置: ${position.latitude}, ${position.longitude}',
                  );
                }
              })
              .catchError((e) {
                logDebug('初始化时获取位置失败: $e');
              });
        }
      } else {
        _hasLocationPermission = false;
        logDebug('位置服务未启用');
      }

      notifyListeners();
      _initCompleter!.complete();
    } catch (e) {
      initFailedWithException = true;
      logDebug('初始化位置服务错误: $e');
      _hasLocationPermission = false;
      notifyListeners();
      _initCompleter!.complete();
    } finally {
      // 首次异常失败后允许后续调用重新初始化；成功时保持现有行为
      if (initFailedWithException) {
        _initCompleter = null;
      }
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

      _hasLocationPermission =
          (permission == LocationPermission.whileInUse ||
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
      // iOS 必须使用 geolocator 请求权限，而不是 permission_handler
      LocationPermission permission = await Geolocator.checkPermission();

      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      _hasLocationPermission =
          (permission == LocationPermission.whileInUse ||
          permission == LocationPermission.always);
      notifyListeners();
      return _hasLocationPermission;
    } catch (e) {
      logDebug('请求位置权限失败: $e');
      return false;
    }
  }

  /// 刷新位置服务和权限的运行时状态（供网络恢复等场景调用）
  Future<void> refreshServiceStatus() async {
    try {
      final wasEnabled = _isLocationServiceEnabled;
      final hadPermission = _hasLocationPermission;

      _isLocationServiceEnabled = await Geolocator.isLocationServiceEnabled();

      final permission = await Geolocator.checkPermission();
      _hasLocationPermission =
          (permission == LocationPermission.whileInUse ||
          permission == LocationPermission.always);

      if (wasEnabled != _isLocationServiceEnabled ||
          hadPermission != _hasLocationPermission) {
        logDebug(
          '位置状态刷新: 服务=$_isLocationServiceEnabled (was $wasEnabled), '
          '权限=$_hasLocationPermission (was $hadPermission)',
        );
        notifyListeners();
      }
    } catch (e) {
      logDebug('刷新位置服务状态失败: $e');
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
      _hasLocationPermission =
          (permission == LocationPermission.whileInUse ||
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
      _currentPosition =
          await LocalGeocodingService.getCurrentPosition(
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
  // 优先级：缓存 → 系统SDK → Nominatim在线 → 系统SDK部分结果
  Future<void> getAddressFromLatLng() async {
    if (_currentPosition == null) {
      logDebug('没有位置信息，无法获取地址');
      return;
    }

    final token = ++_geocodeToken;

    try {
      logDebug('开始通过经纬度获取地址信息...');

      final lat = _currentPosition!.latitude;
      final lon = _currentPosition!.longitude;

      // Step 1: 系统SDK解析（含缓存）
      final systemResult =
          await LocalGeocodingService.getAddressFromCoordinates(
            lat,
            lon,
            localeCode: _apiLanguageParam,
          );

      if (token != _geocodeToken) return;

      // Step 2: 系统结果已达到首选展示格式（优先“省份·城市”）时，直接使用
      if (systemResult != null && _isPreferredDisplayReady(systemResult)) {
        _applyAddressResult(systemResult);
        logDebug(
          '系统地址解析成功(首选格式): $_currentAddress (国家:$_country, 省份:$_province, 城市:$_city, 区县:$_district)',
        );
        return;
      }

      if (systemResult != null) {
        logDebug('系统地址解析未达到首选格式，尝试在线补充: ${systemResult['formatted_address']}');
      } else {
        logDebug('系统地址解析失败，尝试在线解析');
      }

      // Step 3: 系统不完整时走在线补充（在线优先补齐，再逐步回退）
      Map<String, String?>? onlineResult;
      Map<String, String?>? mergedResult;
      try {
        onlineResult = await _reverseGeocodeWithNominatim(lat, lon);
        if (token != _geocodeToken) return;
        if (onlineResult != null) {
          mergedResult = _mergeAddressResult(
            preferred: onlineResult,
            fallback: systemResult,
          );

          if (_isPreferredDisplayReady(mergedResult)) {
            _applyAddressResult(mergedResult);
            logDebug(
              '在线补充后达到首选格式: $_currentAddress (国家:$_country, 省份:$_province, 城市:$_city, 区县:$_district)',
            );
            return;
          }
        }
      } catch (e) {
        logDebug('在线地址解析失败: $e');
      }

      if (token != _geocodeToken) return;

      // Step 4: 在线未达到首选时，优先使用系统可展示结果
      if (systemResult != null && _isAddressSufficient(systemResult)) {
        _applyAddressResult(systemResult);
        logDebug(
          '在线补充后仍不理想，回退系统结果: $_currentAddress (国家:$_country, 省份:$_province, 城市:$_city, 区县:$_district)',
        );
        return;
      }

      // Step 5: 系统也不足时，使用合并结果（尽可能保留信息）
      if (mergedResult != null && _isAddressSufficient(mergedResult)) {
        _applyAddressResult(mergedResult);
        logDebug(
          '使用在线+系统合并结果: $_currentAddress (国家:$_country, 省份:$_province, 城市:$_city, 区县:$_district)',
        );
        return;
      }

      // Step 6: 仍有在线部分结果时使用在线部分结果
      if (onlineResult != null && _isAddressSufficient(onlineResult)) {
        _applyAddressResult(onlineResult);
        logDebug(
          '使用在线部分结果: $_currentAddress (国家:$_country, 省份:$_province, 城市:$_city, 区县:$_district)',
        );
        return;
      }

      // Step 7: 仍有系统部分结果时回退系统
      if (systemResult != null) {
        _applyAddressResult(systemResult);
        logDebug(
          '最终回退系统部分结果: $_currentAddress (国家:$_country, 省份:$_province, 城市:$_city, 区县:$_district)',
        );
        return;
      }

      // Step 8: 全部失败
      _applyAddressResult(null);
    } catch (e) {
      logDebug('获取地址信息失败: $e');
      if (token == _geocodeToken) _applyAddressResult(null);
    }
  }

  /// 开发者模式：强制使用免费的在线反向地理编码（Nominatim）
  /// 返回 true 表示解析成功并更新了地址信息
  Future<bool> refreshAddressFromOnlineReverseGeocoding() async {
    if (_currentPosition == null) {
      logDebug('没有位置信息，无法使用在线反向地理编码');
      return false;
    }

    try {
      final result = await _reverseGeocodeWithNominatim(
        _currentPosition!.latitude,
        _currentPosition!.longitude,
      );
      if (result != null) {
        final merged = _mergeAddressResult(
          preferred: result,
          fallback: {
            'country': _country,
            'province': _province,
            'city': _city,
            'district': _district,
            'formatted_address': _currentAddress,
            'source': 'state',
          },
        );
        _applyAddressResult(merged);
        return true;
      }
      return false;
    } catch (e) {
      logDebug('开发者模式在线反向地理编码失败: $e');
      return false;
    }
  }

  /// 首选展示格式是否可用（例如“浙江省·杭州市”）
  bool _isPreferredDisplayReady(Map<String, String?> addr) {
    final city = addr['city']?.trim();
    final province = addr['province']?.trim();
    return city != null &&
        city.isNotEmpty &&
        province != null &&
        province.isNotEmpty;
  }

  /// 判断地址结果是否可用于降级展示（城市或省份至少其一可用）。
  bool _isAddressSufficient(Map<String, String?> addr) {
    final city = addr['city']?.trim();
    final province = addr['province']?.trim();
    return (city != null && city.isNotEmpty) ||
        (province != null && province.isNotEmpty);
  }

  /// 合并地址结果：优先使用 preferred，缺失字段回退到 fallback。
  Map<String, String?> _mergeAddressResult({
    required Map<String, String?> preferred,
    Map<String, String?>? fallback,
  }) {
    if (fallback == null) return preferred;

    String? pick(String key) {
      final preferredValue = preferred[key]?.trim();
      if (preferredValue != null && preferredValue.isNotEmpty) {
        return preferredValue;
      }
      final fallbackValue = fallback[key]?.trim();
      return (fallbackValue != null && fallbackValue.isNotEmpty)
          ? fallbackValue
          : null;
    }

    final country = pick('country');
    final province = pick('province');
    final city = pick('city');
    final district = pick('district');
    final street = pick('street');

    final formattedAddress = [
      country,
      province,
      city,
      district,
    ].whereType<String>().join(', ');

    return <String, String?>{
      'country': country,
      'province': province,
      'city': city,
      'district': district,
      'street': street,
      'formatted_address': formattedAddress.isNotEmpty
          ? formattedAddress
          : pick('formatted_address'),
      'source': preferred['source'] ?? fallback['source'],
    };
  }

  /// 将地址结果应用到内部状态，null 表示失败
  void _applyAddressResult(Map<String, String?>? result) {
    if (result != null) {
      _country = result['country'];
      _province = result['province'];
      _city = result['city'];
      _district = result['district'];
      _currentAddress = result['formatted_address'];
    } else {
      _country = null;
      _province = null;
      _city = null;
      _district = null;
      _currentAddress = kAddressFailed;
    }
    notifyListeners();
  }

  /// Nominatim 在线反向地理编码，返回地址 Map 或 null
  Future<Map<String, String?>?> _reverseGeocodeWithNominatim(
    double latitude,
    double longitude,
  ) async {
    final url =
        'https://nominatim.openstreetmap.org/reverse?format=json&lat=$latitude&lon=$longitude&zoom=18&addressdetails=1';

    final acceptLanguage = I18nLanguage.buildAcceptLanguage(_apiLanguageParam);

    final response = await NetworkService.instance.get(
      url,
      headers: {
        'Accept-Language': acceptLanguage,
        'User-Agent':
            'ThoughtEcho/3.4 (https://github.com/Shangjin-Xiao/ThoughtEcho)',
      },
      timeoutSeconds: 15,
    );

    if (response.statusCode != 200) {
      logDebug('Nominatim 返回非200状态码: ${response.statusCode}');
      return null;
    }

    try {
      final decoded = json.decode(response.body);
      if (decoded is! Map<String, dynamic>) return null;

      final address = decoded['address'];
      if (address is! Map) return null;

      String? s(dynamic v) =>
          (v is String && v.trim().isNotEmpty) ? v.trim() : null;

      final country = s(address['country']);
      final province = s(
        address['state'] ??
            address['province'] ??
            address['region'] ??
            address['state_district'] ??
            address['prefecture'],
      );

      final county = s(address['county']);
      String? city = s(
        address['city'] ??
            address['municipality'] ??
            address['town'] ??
            address['village'] ??
            county,
      );

      // 日本等地区可能出现 city=东京、county=新宿区；优先把更细粒度行政区用于 city 展示
      if ((city == null || (province != null && city == province)) &&
          county != null &&
          county != province) {
        city = county;
      }

      final district = s(
        address['city_district'] ??
            address['district'] ??
            address['suburb'] ??
            address['quarter'] ??
            address['neighbourhood'],
      );

      final parts = [
        country,
        province,
        city,
        district,
      ].whereType<String>().toList();
      final formattedAddress = parts.isNotEmpty ? parts.join(', ') : null;

      return <String, String?>{
        'country': country,
        'province': province,
        'city': city,
        'district': district,
        'formatted_address': formattedAddress,
        'source': 'nominatim',
      };
    } catch (e) {
      logDebug('Nominatim 响应解析失败: $e');
      return null;
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
      // 添加总体超时控制（使用 .timeout 替代 Future.any 避免未完成 Future 泄漏）
      final results = await _searchCityWithTimeout(
        query,
      ).timeout(const Duration(seconds: 12), onTimeout: () => <CityInfo>[]);

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
      final bool isChinese = _containsChinese(query);

      if (isChinese) {
        // 中文搜索：优先使用Nominatim API（对中文支持更好）
        logDebug('检测到中文输入，优先使用Nominatim API');

        final nominatimResults = await _searchCityWithNominatim(
          query,
        ).timeout(const Duration(seconds: 8), onTimeout: () => <CityInfo>[]);

        if (nominatimResults.isNotEmpty) {
          return nominatimResults;
        }

        // 如果Nominatim没有结果，回退到OpenMeteo
        logDebug('Nominatim无结果，尝试OpenMeteo');
        return await _searchCityWithOpenMeteo(
          query,
        ).timeout(const Duration(seconds: 8), onTimeout: () => <CityInfo>[]);
      } else {
        // 英文/拼音搜索：优先使用OpenMeteo API
        logDebug('检测到非中文输入，优先使用OpenMeteo API');

        final results = await _searchCityWithOpenMeteo(
          query,
        ).timeout(const Duration(seconds: 8), onTimeout: () => <CityInfo>[]);

        if (results.isNotEmpty) {
          return results;
        }

        // 如果OpenMeteo没有结果，尝试使用Nominatim API
        return await _searchCityWithNominatim(
          query,
        ).timeout(const Duration(seconds: 8), onTimeout: () => <CityInfo>[]);
      }
    } catch (e) {
      logDebug('城市搜索异常: $e');
      return <CityInfo>[];
    }
  }

  // 检测字符串是否主要包含中文字符
  bool _containsChinese(String text) {
    // Unicode范围：CJK统一汉字 + Extension A + 兼容汉字 + 部首
    // CJK Unified: 0x4E00-0x9FFF, Extension A: 0x3400-0x4DBF
    // CJK Compat Ideographs: 0xF900-0xFAFF, Radicals: 0x2E80-0x2FFF
    final chineseRegex = RegExp(
      r'[\u2e80-\u2fff\u3400-\u4dbf\u4e00-\u9fff\uf900-\ufaff]',
    );
    return chineseRegex.hasMatch(text);
  }

  // 使用OpenMeteo的地理编码API搜索城市
  Future<List<CityInfo>> _searchCityWithOpenMeteo(String query) async {
    try {
      // 对查询字符串进行URL编码
      final encodedQuery = Uri.encodeComponent(query.trim());

      // 根据输入语言和用户语言设置选择合适的语言参数
      // 如果输入包含中文，使用中文结果；否则根据用户语言设置
      final String languageParam = _containsChinese(query)
          ? 'zh'
          : _apiLanguageParam;

      // OpenMeteo地理编码API - 使用URL编码的查询参数
      final url =
          'https://geocoding-api.open-meteo.com/v1/search?name=$encodedQuery&count=15&language=$languageParam&format=json';

      logDebug('OpenMeteo搜索URL: $url');

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

  // 使用OpenStreetMap Nominatim API搜索城市
  Future<List<CityInfo>> _searchCityWithNominatim(String query) async {
    try {
      // 对查询字符串进行URL编码
      final encodedQuery = Uri.encodeComponent(query.trim());

      // 使用Nominatim API - 对中文搜索支持更好
      final url =
          'https://nominatim.openstreetmap.org/search?q=$encodedQuery&format=json&addressdetails=1&limit=15';

      logDebug('Nominatim搜索URL: $url');

      // 根据语言设置构建 Accept-Language 头
      final acceptLanguage = I18nLanguage.buildAcceptLanguage(
        _apiLanguageParam,
      );

      final response = await NetworkService.instance.get(
        url,
        headers: {
          'Accept-Language': acceptLanguage,
          'User-Agent':
              'ThoughtEcho/3.4 (https://github.com/Shangjin-Xiao/ThoughtEcho)',
        },
        timeoutSeconds: 15,
      );

      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);

        // 过滤并解析结果
        final results = <CityInfo>[];
        final seenLocations = <String>{};

        for (final item in data) {
          // 提取地址信息
          final address = item['address'] ?? {};
          final String type = item['type'] ?? '';
          final String classType = item['class'] ?? '';

          // 过滤掉非地点类型的结果（如道路、建筑等）
          // 只保留城市、城镇、村庄、行政区等地点类型
          final validTypes = {
            'city',
            'town',
            'village',
            'municipality',
            'hamlet',
            'suburb',
            'county',
            'state',
            'province',
            'country',
            'administrative',
            'locality',
            'place',
            'district',
          };
          final validClasses = {'place', 'boundary', 'administrative'};

          // 如果类型和class都不匹配，跳过此结果
          if (!validTypes.contains(type) && !validClasses.contains(classType)) {
            // 但如果address中有城市信息，仍然保留
            if (address['city'] == null &&
                address['town'] == null &&
                address['village'] == null &&
                address['municipality'] == null) {
              logDebug('跳过非地点类型结果: type=$type, class=$classType');
              continue;
            }
          }

          // 更灵活地处理地点名称
          String placeName = item['name'] ?? '';
          String cityName =
              address['city'] ??
              address['town'] ??
              address['village'] ??
              address['municipality'] ??
              placeName;
          String country = address['country'] ?? '';
          String state =
              address['state'] ??
              address['province'] ??
              address['county'] ??
              '';

          // 对于一些大城市，可能直接作为顶级地点返回
          if (address.isEmpty && placeName.isNotEmpty) {
            cityName = placeName;
          }

          // 跳过空的城市名
          if (cityName.isEmpty) continue;

          // 构建唯一标识符来去重
          final locationKey = '$country|$state|$cityName';
          if (seenLocations.contains(locationKey)) {
            continue;
          }
          seenLocations.add(locationKey);

          // 构建完整地址 - 国家, 省/州, 城市
          final String fullName = [
            country,
            state,
            cityName,
          ].where((part) => part.isNotEmpty).join(', ');

          logDebug('Nominatim结果: $placeName -> $cityName, $country, $state');

          results.add(
            CityInfo(
              name: cityName,
              fullName: fullName,
              lat: double.parse(item['lat'].toString()),
              lon: double.parse(item['lon'].toString()),
              country: country,
              province: state,
            ),
          );
        }

        return results;
      } else {
        logDebug('Nominatim搜索失败: ${response.statusCode}');
        return [];
      }
    } catch (e) {
      logDebug('Nominatim搜索发生错误: $e');
      return [];
    }
  }

  // 清空搜索结果
  void clearSearchResults() {
    _searchResults = [];
    _isSearching = false; // 确保搜索状态也重置
    notifyListeners();
  }

  // 使用选定的城市信息设置位置
  Future<void> setSelectedCity(CityInfo city) async {
    if (city.name.isEmpty) {
      throw Exception('City name is required');
    }

    // 保存旧状态用于回滚
    final oldCountry = _country;
    final oldProvince = _province;
    final oldCity = _city;
    final oldDistrict = _district;
    final oldAddress = _currentAddress;
    final oldPosition = _currentPosition;

    try {
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
      // 恢复旧状态而非清空
      _country = oldCountry;
      _province = oldProvince;
      _city = oldCity;
      _district = oldDistrict;
      _currentAddress = oldAddress;
      _currentPosition = oldPosition;
      notifyListeners();
      rethrow;
    }
  }

  // 获取格式化位置(国家,省份,城市,区县)
  String getFormattedLocation() {
    if (isNonDisplayMarker(_currentAddress)) return '';
    final parts = [
      _country ?? '',
      _province ?? '',
      _city ?? '',
      _district ?? '',
    ];
    if (parts.every((p) => p.trim().isEmpty)) return '';
    return parts.join(',');
  }

  /// 解析并格式化存储的位置字符串用于显示
  /// 输入格式: "国家,省份,城市,区县" (可能包含空字符串)
  /// 输出格式: "城市·区县" 或 "省份·区县" 或 "城市" 或 "省份" 或 "国家"
  static String formatLocationForDisplay(String? locationString) {
    if (locationString == null ||
        locationString.isEmpty ||
        isNonDisplayMarker(locationString)) {
      return '';
    }

    final parts = locationString.split(',');
    if (parts.length < 3) return locationString;

    final country = parts[0].trim();
    final province = parts[1].trim();
    final city = parts[2].trim();
    final district = parts.length > 3 ? parts[3].trim() : '';

    if (city.isNotEmpty) {
      if (district.isNotEmpty) {
        return '$city·$district';
      }
      if (province.isNotEmpty && province != city) {
        return '$province·$city';
      }
      return city;
    }

    // city 为空时（日本等地址结构），组合 province + district
    if (province.isNotEmpty) {
      if (district.isNotEmpty) {
        return '$province·$district';
      }
      if (country.isNotEmpty && country != province) {
        return '$country·$province';
      }
      return province;
    }

    if (country.isNotEmpty) {
      return country;
    }

    return '';
  }

  // 获取显示格式的位置，如"广州市·天河区"（中文）或 "Guangzhou · Tianhe"（英文）
  String getDisplayLocation() {
    final bool isChinese = _apiLanguageParam == 'zh';
    final separator = isChinese ? '·' : ' · ';
    final hasCity = _city != null && _city!.isNotEmpty;
    final hasDistrict = _district != null && _district!.isNotEmpty;
    final hasProvince = _province != null && _province!.isNotEmpty;

    if (hasCity) {
      String cityDisplay;
      if (isChinese) {
        cityDisplay = _formatChineseCityDisplay(_city!);
      } else {
        cityDisplay = _city!;
      }
      if (hasDistrict) {
        return '$cityDisplay$separator$_district';
      }
      if (hasProvince && _province != _city) {
        return '$_province$separator$cityDisplay';
      }
      return cityDisplay;
    }

    // city 为空时（日本等地址结构），组合 province + district
    if (hasProvince) {
      if (hasDistrict) {
        return '$_province$separator$_district';
      }
      final hasCountry = _country != null && _country!.isNotEmpty;
      if (hasCountry && _country != _province) {
        return '$_country$separator$_province';
      }
      return _province!;
    }

    return '';
  }

  /// 中文城市显示格式化：仅在明确是“城市名”时补全“市”后缀
  /// 避免把“新宿区”“Naka ward”这类行政区/英文名称错误显示成“新宿区市”“Naka ward市”
  bool _containsLatinOrDigit(String text) {
    return RegExp(r'[A-Za-z0-9]').hasMatch(text);
  }

  bool _isChineseAdminDivision(String text) {
    const adminSuffixes = {
      '市',
      '区',
      '區',
      '县',
      '縣',
      '镇',
      '鎮',
      '乡',
      '鄉',
      '村',
      '里',
      '盟',
      '旗',
      '郡',
      '町',
    };

    final trimmed = text.trim();
    return adminSuffixes.any(trimmed.endsWith);
  }

  String _formatChineseCityDisplay(String city) {
    final trimmed = city.trim();
    if (trimmed.isEmpty) return trimmed;

    if (_isChineseAdminDivision(trimmed)) {
      return trimmed;
    }

    // 自治州等行政单位不补“市”
    if (trimmed.endsWith('自治州')) {
      return trimmed;
    }

    // 对包含拉丁字符/数字的名称不强制补“市”
    if (_containsLatinOrDigit(trimmed)) {
      return trimmed;
    }

    return '$trimmed市';
  }

  /// 格式化坐标显示（用于离线状态或简单显示）
  /// [precision] 小数位数，默认2位（约1km精度）
  static String formatCoordinates(
    double? lat,
    double? lon, {
    int precision = 2,
  }) {
    if (lat == null || lon == null) return '';

    // 格式化纬度
    final latStr = lat.abs().toStringAsFixed(precision);
    final latDir = lat >= 0 ? 'N' : 'S';

    // 格式化经度
    final lonStr = lon.abs().toStringAsFixed(precision);
    final lonDir = lon >= 0 ? 'E' : 'W';

    return '$latStr°$latDir, $lonStr°$lonDir';
  }

  /// 获取位置显示文本（优先地址，离线时显示坐标）
  String getLocationDisplayText() {
    // 如果有城市或省份信息，返回友好格式
    final display = getDisplayLocation();
    if (display.isNotEmpty) {
      return display;
    }

    // 如果有格式化地址，返回地址
    if (_currentAddress != null && !isNonDisplayMarker(_currentAddress)) {
      return _currentAddress!;
    }

    // 离线时显示坐标
    if (_currentPosition != null) {
      return '📍 ${formatCoordinates(_currentPosition!.latitude, _currentPosition!.longitude)}';
    }

    return '';
  }

  /// 仅获取坐标位置（离线存储用）
  /// 返回 {latitude, longitude} 或 null
  Map<String, double>? getCoordinatesOnly() {
    if (_currentPosition == null) return null;
    return {
      'latitude': _currentPosition!.latitude,
      'longitude': _currentPosition!.longitude,
    };
  }

  /// 从经纬度设置位置（用于从数据库恢复离线坐标）
  void setCoordinates(double latitude, double longitude, {String? address}) {
    _currentPosition = Position(
      latitude: latitude,
      longitude: longitude,
      timestamp: DateTime.now(),
      accuracy: 0,
      altitude: 0,
      heading: 0,
      speed: 0,
      speedAccuracy: 0,
      altitudeAccuracy: 0,
      headingAccuracy: 0,
    );

    if (address != null && address.isNotEmpty && !isNonDisplayMarker(address)) {
      parseLocationString(address);
    } else {
      // 离线状态标记（保留 failed 标记以区分状态）
      _currentAddress = isFailedMarker(address)
          ? kAddressFailed
          : kAddressPending;
      _country = null;
      _province = null;
      _city = null;
      _district = null;
    }

    notifyListeners();
  }

  /// 尝试解析离线坐标的地址（联网后调用）
  Future<bool> resolveOfflineLocation() async {
    if (_currentPosition == null) return false;
    if (!isOfflineLocation) return true; // 已经有地址了

    try {
      logDebug('尝试解析离线位置...');
      await getAddressFromLatLng();
      return _currentAddress != null && !isNonDisplayMarker(_currentAddress);
    } catch (e) {
      logDebug('解析离线位置失败: $e');
      return false;
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
      String? normalizePart(String? value) {
        final trimmed = value?.trim();
        return (trimmed == null || trimmed.isEmpty) ? null : trimmed;
      }

      _country = normalizePart(parts[0]);
      _province = normalizePart(parts[1]);
      _city = normalizePart(parts[2]);
      _district = parts.length >= 4 ? normalizePart(parts[3]) : null;

      final addressParts = <String?>[
        _country,
        _province,
        _city,
        _district,
      ].whereType<String>().toList();

      _currentAddress = addressParts.isNotEmpty
          ? addressParts.join(', ')
          : null;
    }
  }
}
