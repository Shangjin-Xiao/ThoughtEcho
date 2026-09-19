import 'dart:convert';
import 'dart:math' as math;

import '../utils/app_logger.dart';
import '../utils/i18n_language.dart';
import 'network_service.dart';

/// 地图选点页列出的一个地点。
///
/// 和 `Quote.poiName` 的关系：用户在列表里选中哪一条，[name] 就成为那条笔记的
/// `poiName`，[latitude]/[longitude] 成为它的坐标。
class PlaceInfo {
  const PlaceInfo({
    required this.name,
    required this.latitude,
    required this.longitude,
    this.address,
    this.distanceMeters,
    this.storageLocation,
  });

  /// 地点名，如"芝公园"。列表主行显示的就是它。
  final String name;

  final double latitude;
  final double longitude;

  /// 街道级地址，列表副行显示，用来区分同名地点。
  final String? address;

  /// 距离参考点的直线距离（米）。搜索结果按它排序；为 null 时排在最后。
  final double? distanceMeters;

  /// 搜索响应里 addressdetails 直接析出的入库四级串 `国家,省份,城市,区县`
  /// （格式与 `LocationService.buildStorageLocation` 一致）。
  ///
  /// 点选确认时优先用它，免去对该坐标的二次反查：既省一次在线请求等待，
  /// 又保证存下来的行政区和列表副行是同一份地址，不会出现"选的是这个
  /// 地点、存的却是另一条街"的错位。为 null 时调用方再走反查兜底。
  final String? storageLocation;
}

/// 地点搜索。
///
/// 单独抽出来是为了不把 POI 检索塞进 [LocationService]——后者管的是设备定位、
/// 坐标缓存和地址格式化。换成高德/腾讯这类国内 POI 源时只需另写一个实现。
abstract class PlaceSearchService {
  /// 在 [latitude]/[longitude] 附近按 [query] 搜索地点，按距离升序返回。
  ///
  /// [query] 为空时返回空列表——不做「自动列出附近地点」，那会把公共
  /// Nominatim 当 autocomplete 用，必被限流。
  ///
  /// [localeCode] 决定返回的地名用哪种语言。
  Future<List<PlaceInfo>> searchNearby(
    double latitude,
    double longitude, {
    required String query,
    String? localeCode,
    int limit = 20,
    int offset = 0,
  });

  /// 获取坐标周围的候选地点列表（无需用户输入关键词），支持分页与无限加载。
  /// 搜索半径严格限制在 5 公里内（±0.045°）。
  Future<List<PlaceInfo>> getNearbyPlaces(
    double latitude,
    double longitude, {
    String? categoryOrKeyword,
    String? localeCode,
    int limit = 20,
    int offset = 0,
  });
}

/// Nominatim（OpenStreetMap）实现：免费、无需 API Key，与项目已有的反向地理
/// 编码同源。
///
/// 使用条款要求单来源不超过 1 请求/秒并带上可识别的 User-Agent，
/// 见 https://operations.osmfoundation.org/policies/nominatim/。
/// 这里按 [_minRequestInterval] 串行节流；调用方（选点页）另有输入防抖。
class NominatimPlaceSearchService implements PlaceSearchService {
  NominatimPlaceSearchService({
    NetworkService? networkService,
    Duration? minRequestInterval,
  })  : _networkService = networkService,
        _minRequestInterval = minRequestInterval ?? _defaultMinRequestInterval;

  static const String _searchUrl = 'https://nominatim.openstreetmap.org/search';
  static const String _userAgent =
      'ThoughtEcho/3.4 (https://github.com/Shangjin-Xiao/ThoughtEcho)';
  static const Duration _defaultMinRequestInterval = Duration(
    milliseconds: 1100,
  );

  /// 搜索框限定在参考点周围这么多度的方框内，严格限制在 5 公里内（约 ±0.045°）。
  static const double _viewboxDelta = 0.045;

  final NetworkService? _networkService;

  /// 两次请求之间的最小间隔。测试里调小，免得每个用例真等一秒多。
  final Duration _minRequestInterval;

  DateTime _lastRequestAt = DateTime.fromMillisecondsSinceEpoch(0);

  /// 把限流排成一条队。
  ///
  /// 只判断「距上次请求过了多久」是不够的：两个并发调用会读到同一个
  /// [_lastRequestAt]、等同样长的时间，然后一起发出去——正好违反这个类
  /// 声称的 1 请求/秒。挂在同一条链上，后来者要等前一个把自己的间隔占满
  /// 才轮到它记时间戳。
  Future<void> _throttleQueue = Future<void>.value();

  NetworkService get _network => _networkService ?? NetworkService.instance;

  final Set<String> _seenPlaceIds = <String>{};
  int _categoryCursor = 0;

  @override
  Future<List<PlaceInfo>> searchNearby(
    double latitude,
    double longitude, {
    required String query,
    String? localeCode,
    int limit = 20,
    int offset = 0,
  }) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return const [];

    try {
      await _throttle();

      final queryParams = <String, String>{
        'q': trimmed,
        'format': 'json',
        'addressdetails': '1',
        'limit': '$limit',
        'viewbox': '${longitude - _viewboxDelta},'
            '${latitude + _viewboxDelta},'
            '${longitude + _viewboxDelta},'
            '${latitude - _viewboxDelta}',
        'bounded': '1',
      };
      if (offset > 0) {
        queryParams['offset'] = '$offset';
      }

      final uri = Uri.parse(_searchUrl).replace(
        queryParameters: queryParams,
      );

      final response = await _network.get(
        uri.toString(),
        headers: {
          'Accept-Language': I18nLanguage.buildAcceptLanguage(
            I18nLanguage.appLanguageOrSystem(localeCode),
          ),
          'User-Agent': _userAgent,
        },
        timeoutSeconds: 10,
      );

      if (response.statusCode != 200) {
        logWarning(
          'Nominatim 地点搜索返回 ${response.statusCode}',
          source: 'PlaceSearchService',
        );
        throw Exception('Nominatim 地点搜索失败 (HTTP ${response.statusCode})');
      }

      final decoded = json.decode(response.body);
      if (decoded is! List) return const [];

      final places = <PlaceInfo>[];
      for (final item in decoded) {
        if (item is! Map) continue;
        final place = _toPlace(item, latitude, longitude);
        if (place != null) {
          places.add(place);
        }
      }

      places.sort(
        (a, b) => (a.distanceMeters ?? double.infinity).compareTo(
          b.distanceMeters ?? double.infinity,
        ),
      );
      return places;
    } catch (e) {
      logWarning(
        '地点搜索失败: $e',
        source: 'PlaceSearchService',
      );
      rethrow;
    }
  }

  @override
  Future<List<PlaceInfo>> getNearbyPlaces(
    double latitude,
    double longitude, {
    String? categoryOrKeyword,
    String? localeCode,
    int limit = 20,
    int offset = 0,
  }) async {
    try {
      await _throttle();

      if (offset == 0) {
        _seenPlaceIds.clear();
        _categoryCursor = 0;
      } else {
        _categoryCursor++;
      }

      final queryParams = <String, String>{
        'format': 'json',
        'addressdetails': '1',
        'limit': '$limit',
        'viewbox': '${longitude - _viewboxDelta},'
            '${latitude + _viewboxDelta},'
            '${longitude + _viewboxDelta},'
            '${latitude - _viewboxDelta}',
        'bounded': '1',
      };
      final trimmed = categoryOrKeyword?.trim() ?? '';
      if (trimmed.isNotEmpty && offset > 0) {
        queryParams['offset'] = '$offset';
      }
      if (_seenPlaceIds.isNotEmpty) {
        // 限制最多传递 50 个 place_id 避免 URL 过长导致 HTTP 414
        queryParams['exclude_place_ids'] = _seenPlaceIds.take(50).join(',');
      }

      final categoriesToTry = trimmed.isNotEmpty
          ? [trimmed]
          : const [
              'attraction',
              'park',
              'museum',
              'monument',
            ];
      final baseIndex =
          trimmed.isNotEmpty ? 0 : (_categoryCursor % categoriesToTry.length);

      for (var attempt = 0; attempt < categoriesToTry.length; attempt++) {
        if (attempt > 0) {
          await _throttle();
        }
        final currentCatIndex = (baseIndex + attempt) % categoriesToTry.length;
        queryParams['q'] = categoriesToTry[currentCatIndex];

        final uri = Uri.parse(_searchUrl).replace(
          queryParameters: queryParams,
        );

        final response = await _network.get(
          uri.toString(),
          headers: {
            'Accept-Language': I18nLanguage.buildAcceptLanguage(
              I18nLanguage.appLanguageOrSystem(localeCode),
            ),
            'User-Agent': _userAgent,
          },
          timeoutSeconds: 10,
        );

        if (response.statusCode != 200) {
          logWarning(
            'Nominatim 附近候选地点搜索返回 ${response.statusCode}',
            source: 'PlaceSearchService',
          );
          throw Exception('Nominatim 附近候选地点搜索失败 (HTTP ${response.statusCode})');
        }

        final decoded = json.decode(response.body);
        if (decoded is! List) continue;

        final places = <PlaceInfo>[];
        for (final item in decoded) {
          if (item is! Map) continue;
          final placeId = item['place_id']?.toString();
          if (placeId != null && placeId.isNotEmpty) {
            if (_seenPlaceIds.contains(placeId)) {
              // 内存层过滤：若服务端未履行 exclude_place_ids 或返回重复项，主动跳过
              continue;
            }
            if (_seenPlaceIds.length >= 100) {
              _seenPlaceIds.remove(_seenPlaceIds.first);
            }
            _seenPlaceIds.add(placeId);
          }
          final place = _toPlace(item, latitude, longitude);
          if (place != null && (place.distanceMeters ?? 0) <= 5000) {
            places.add(place);
          }
        }

        if (places.isNotEmpty || trimmed.isNotEmpty) {
          places.sort(
            (a, b) => (a.distanceMeters ?? double.infinity).compareTo(
              b.distanceMeters ?? double.infinity,
            ),
          );
          return places;
        }
      }

      return const [];
    } catch (e) {
      logWarning(
        '附近候选地点搜索失败: $e',
        source: 'PlaceSearchService',
      );
      rethrow;
    }
  }

  /// 距上次请求不足 [_minRequestInterval] 时补足等待，满足 Nominatim 的限流。
  Future<void> _throttle() {
    final reserved = _throttleQueue.then((_) async {
      final elapsed = DateTime.now().difference(_lastRequestAt);
      if (elapsed < _minRequestInterval) {
        await Future<void>.delayed(_minRequestInterval - elapsed);
      }
      _lastRequestAt = DateTime.now();
    });
    // 队尾吞掉异常，否则一次失败会把后面所有请求一起带崩
    _throttleQueue = reserved.catchError((Object _) {});
    return reserved;
  }

  PlaceInfo? _toPlace(
    Map<dynamic, dynamic> item,
    double refLat,
    double refLon,
  ) {
    final lat = double.tryParse(item['lat']?.toString() ?? '');
    final lon = double.tryParse(item['lon']?.toString() ?? '');
    if (lat == null || lon == null) return null;

    final name = _extractName(item);
    if (name.isEmpty) return null;

    return PlaceInfo(
      name: name,
      latitude: lat,
      longitude: lon,
      address: _extractAddress(item),
      distanceMeters: distanceBetween(refLat, refLon, lat, lon),
      storageLocation: _storageLocationFromAddress(item['address']),
    );
  }

  /// 从搜索响应的 `addressdetails` 直接析出入库四级串。
  ///
  /// 字段映射与 `LocationService` 的在线反查保持一致（country / state 系 /
  /// city 系 / district 系），拼出来的 `国家,省份,城市,区县` 可直接入库。
  /// 省份和城市都缺失时返回 null（光有国家落不了地），调用方再走反查兜底；
  /// 区县允许空位。
  static String? _storageLocationFromAddress(dynamic address) {
    if (address is! Map) return null;

    String? s(dynamic v) {
      final cleaned = _cleanVariant(v);
      return cleaned.isNotEmpty ? cleaned : null;
    }

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
    if ((city == null || city == province) &&
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

    if ((province == null || province.isEmpty) &&
        (city == null || city.isEmpty)) {
      return null;
    }
    return '${country ?? ''},${province ?? ''},${city ?? ''},${district ?? ''}';
  }

  /// 去掉多语言/多变体混杂（如 "纽约;紐約" 取 "纽约"），口径与
  /// `LocationService.cleanGeocodingText` 一致。这里不直接复用那个方法：
  /// 它在 `LocationService` 上，这个纯搜索服务不引入那边的依赖。
  static String _cleanVariant(dynamic v) {
    if (v is! String) return '';
    final trimmed = v.trim();
    if (trimmed.isEmpty) return '';
    if (!trimmed.contains(';') && !trimmed.contains('/')) return trimmed;
    final head = trimmed
        .split(RegExp(r'\s*[;/]\s*'))
        .map((p) => p.trim())
        .where((p) => p.isNotEmpty)
        .toList();
    return head.isEmpty ? trimmed : head.first;
  }

  /// 地点名：优先 OSM 要素名，其次 address 里的类型化别名，最后取
  /// `display_name` 的第一段。
  static String _extractName(Map<dynamic, dynamic> item) {
    final direct = item['name'];
    if (direct is String && direct.trim().isNotEmpty) return direct.trim();

    final address = item['address'];
    if (address is Map) {
      const keys = [
        'amenity',
        'building',
        'shop',
        'tourism',
        'leisure',
        'historic',
        'office',
        'road',
      ];
      for (final key in keys) {
        final value = address[key];
        if (value is String && value.trim().isNotEmpty) return value.trim();
      }
    }

    final display = item['display_name']?.toString() ?? '';
    final head = display.split(',').first.trim();
    return head;
  }

  /// 副行地址：街道 + 区 + 市，用来区分「星巴克」这种重名地点。
  static String? _extractAddress(Map<dynamic, dynamic> item) {
    final address = item['address'];
    if (address is! Map) return null;

    final parts = <String>[];
    for (final key in ['road', 'suburb', 'city', 'town', 'state']) {
      final value = address[key];
      if (value is String && value.trim().isNotEmpty) {
        final trimmed = value.trim();
        if (parts.isEmpty || parts.last != trimmed) parts.add(trimmed);
      }
    }
    return parts.isEmpty ? null : parts.join(' · ');
  }

  /// 两点间的大圆距离（米），Haversine 公式。
  ///
  /// 不用 `Geolocator.distanceBetween`：那要求平台通道就绪，而这里只是给搜索
  /// 结果排序，测试里也跑不起平台通道。
  static double distanceBetween(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    const earthRadiusMeters = 6371000.0;
    double toRadians(double degrees) => degrees * math.pi / 180;

    final dLat = toRadians(lat2 - lat1);
    final dLon = toRadians(lon2 - lon1);
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(toRadians(lat1)) *
            math.cos(toRadians(lat2)) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
    return earthRadiusMeters * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  }
}
