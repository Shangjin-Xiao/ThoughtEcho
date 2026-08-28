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
  });

  /// 地点名，如"芝公园"。列表主行显示的就是它。
  final String name;

  final double latitude;
  final double longitude;

  /// 街道级地址，列表副行显示，用来区分同名地点。
  final String? address;

  /// 距离参考点的直线距离（米）。搜索结果按它排序；为 null 时排在最后。
  final double? distanceMeters;
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
  });
}

/// Nominatim（OpenStreetMap）实现：免费、无需 API Key，与项目已有的反向地理
/// 编码同源。
///
/// 使用条款要求单来源不超过 1 请求/秒并带上可识别的 User-Agent，
/// 见 https://operations.osmfoundation.org/policies/nominatim/。
/// 这里按 [_minRequestInterval] 串行节流；调用方（选点页）另有输入防抖。
class NominatimPlaceSearchService implements PlaceSearchService {
  NominatimPlaceSearchService({NetworkService? networkService})
      : _networkService = networkService;

  static const String _searchUrl = 'https://nominatim.openstreetmap.org/search';
  static const String _userAgent =
      'ThoughtEcho/3.4 (https://github.com/Shangjin-Xiao/ThoughtEcho)';
  static const Duration _minRequestInterval = Duration(milliseconds: 1100);

  /// 搜索框限定在参考点周围这么多度的方框内，约 ±11 公里。
  ///
  /// 不限定的话「星巴克」会搜出全球结果，前几条大概率不在用户所在的城市。
  static const double _viewboxDelta = 0.1;

  final NetworkService? _networkService;

  DateTime _lastRequestAt = DateTime.fromMillisecondsSinceEpoch(0);

  NetworkService get _network => _networkService ?? NetworkService.instance;

  @override
  Future<List<PlaceInfo>> searchNearby(
    double latitude,
    double longitude, {
    required String query,
    String? localeCode,
    int limit = 20,
  }) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return const [];

    try {
      await _throttle();

      final uri = Uri.parse(_searchUrl).replace(
        queryParameters: <String, String>{
          'q': trimmed,
          'format': 'json',
          'addressdetails': '1',
          'limit': '$limit',
          'viewbox': '${longitude - _viewboxDelta},'
              '${latitude + _viewboxDelta},'
              '${longitude + _viewboxDelta},'
              '${latitude - _viewboxDelta}',
          'bounded': '1',
        },
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
        logDebug(
          'Nominatim 地点搜索返回 ${response.statusCode}',
          source: 'PlaceSearchService',
        );
        return const [];
      }

      final decoded = json.decode(response.body);
      if (decoded is! List) return const [];

      final places = <PlaceInfo>[];
      for (final item in decoded) {
        if (item is! Map) continue;
        final place = _toPlace(item, latitude, longitude);
        if (place != null) places.add(place);
      }

      places.sort(
        (a, b) => (a.distanceMeters ?? double.infinity)
            .compareTo(b.distanceMeters ?? double.infinity),
      );
      return places;
    } catch (e, stack) {
      logError(
        '地点搜索失败',
        error: e,
        stackTrace: stack,
        source: 'PlaceSearchService',
      );
      return const [];
    }
  }

  /// 距上次请求不足 [_minRequestInterval] 时补足等待，满足 Nominatim 的限流。
  Future<void> _throttle() async {
    final elapsed = DateTime.now().difference(_lastRequestAt);
    if (elapsed < _minRequestInterval) {
      await Future<void>.delayed(_minRequestInterval - elapsed);
    }
    _lastRequestAt = DateTime.now();
  }

  PlaceInfo? _toPlace(
      Map<dynamic, dynamic> item, double refLat, double refLon) {
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
    );
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
