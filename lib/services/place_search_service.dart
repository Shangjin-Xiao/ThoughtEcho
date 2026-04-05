import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../utils/app_logger.dart';

/// 地点信息（POI）
class PoiInfo {
  final String name;
  final String? address;
  final String? category;
  final double lat;
  final double lon;
  final double? distanceMeters;

  const PoiInfo({
    required this.name,
    this.address,
    this.category,
    required this.lat,
    required this.lon,
    this.distanceMeters,
  });
}

/// 地点搜索服务接口
abstract class PlaceSearchService {
  Future<List<PoiInfo>> searchNearby(
    double lat,
    double lon, {
    String? query,
    int limit,
  });

  Future<PoiInfo?> reverseSelectedPoint(double lat, double lon);
}

/// Nominatim 实现（免费，无需 API Key）
class NominatimPlaceSearchService extends ChangeNotifier
    implements PlaceSearchService {
  static const _baseUrl = 'https://nominatim.openstreetmap.org';
  static const _userAgent = 'ThoughtEcho/3.4.0 (thoughtecho@app)';
  static const _defaultMinRequestInterval = Duration(milliseconds: 1100);
  static const _defaultDebounceDuration = Duration(milliseconds: 350);
  static const _maxBackoffSteps = 3;

  final http.Client _httpClient;
  final bool _ownsHttpClient;
  final Future<void> Function(Duration duration) _delay;
  final DateTime Function() _now;
  final Duration _minRequestInterval;
  final Duration _debounceDuration;
  final int _max429Retries;

  NominatimPlaceSearchService({
    http.Client? httpClient,
    Future<void> Function(Duration duration)? delay,
    DateTime Function()? now,
    Duration minRequestInterval = _defaultMinRequestInterval,
    Duration debounceDuration = _defaultDebounceDuration,
    int max429Retries = _maxBackoffSteps,
  })  : _httpClient = httpClient ?? http.Client(),
        _ownsHttpClient = httpClient == null,
        _delay = delay ?? Future.delayed,
        _now = now ?? DateTime.now,
        _minRequestInterval = minRequestInterval,
        _debounceDuration = debounceDuration,
        _max429Retries = max429Retries;

  DateTime _lastRequestTime = DateTime.fromMillisecondsSinceEpoch(0);
  int _latestSearchToken = 0;
  bool _isSearching = false;
  bool get isSearching => _isSearching;

  List<PoiInfo> _lastResults = [];
  List<PoiInfo> get lastResults => _lastResults;

  Future<void> _enforceRateLimit() async {
    final elapsed = _now().difference(_lastRequestTime);
    if (elapsed < _minRequestInterval) {
      await _delay(_minRequestInterval - elapsed);
    }
    _lastRequestTime = _now();
  }

  Duration _backoffForRetry(int retryIndex) {
    final exponent = retryIndex <= 0 ? 0 : retryIndex - 1;
    final millis = 500 * (1 << exponent);
    return Duration(milliseconds: millis);
  }

  Future<http.Response?> _getWith429Backoff(
    Uri uri, {
    int? searchToken,
  }) async {
    var attempt = 0;

    while (true) {
      final response = await _httpClient.get(
        uri,
        headers: {'User-Agent': _userAgent},
      ).timeout(const Duration(seconds: 10));

      if (searchToken != null && searchToken != _latestSearchToken) {
        return null;
      }

      if (response.statusCode != 429) {
        return response;
      }

      if (attempt >= _max429Retries) {
        logDebug('Nominatim 请求 429，已达到最大重试次数: $_max429Retries');
        return response;
      }

      final retryCount = attempt + 1;
      final backoff = _backoffForRetry(retryCount);
      logDebug(
        'Nominatim 请求 429，准备第 $retryCount 次重试，退避 ${backoff.inMilliseconds}ms',
      );
      await _delay(backoff);

      if (searchToken != null && searchToken != _latestSearchToken) {
        return null;
      }

      attempt++;
    }
  }

  @override
  Future<List<PoiInfo>> searchNearby(
    double lat,
    double lon, {
    String? query,
    int limit = 20,
  }) async {
    final searchToken = ++_latestSearchToken;

    if (query == null || query.trim().isEmpty) {
      // 无搜索词时仅 reverse geocode 当前点
      final poi = await reverseSelectedPoint(lat, lon);
      if (searchToken != _latestSearchToken) return _lastResults;
      _lastResults = poi != null ? [poi] : [];
      notifyListeners();
      return _lastResults;
    }

    _isSearching = true;
    notifyListeners();

    try {
      if (_debounceDuration > Duration.zero) {
        await _delay(_debounceDuration);
      }
      if (searchToken != _latestSearchToken) return _lastResults;

      await _enforceRateLimit();
      if (searchToken != _latestSearchToken) return _lastResults;

      final viewboxDelta = 0.1;
      final params = {
        'q': query.trim(),
        'format': 'json',
        'addressdetails': '1',
        'limit': '$limit',
        'viewbox':
            '${lon - viewboxDelta},${lat + viewboxDelta},${lon + viewboxDelta},${lat - viewboxDelta}',
        'bounded': '1',
      };

      final uri =
          Uri.parse('$_baseUrl/search').replace(queryParameters: params);
      final response = await _getWith429Backoff(
        uri,
        searchToken: searchToken,
      );
      if (response == null || searchToken != _latestSearchToken) {
        return _lastResults;
      }

      if (response.statusCode != 200) {
        logDebug('Nominatim search 失败: ${response.statusCode}');
        return _lastResults = [];
      }

      final List<dynamic> data = json.decode(response.body);
      _lastResults = data.map((item) {
        final itemLat = double.tryParse(item['lat']?.toString() ?? '') ?? 0;
        final itemLon = double.tryParse(item['lon']?.toString() ?? '') ?? 0;
        return PoiInfo(
          name: _extractName(item),
          address: _extractAddress(item),
          category: item['type']?.toString(),
          lat: itemLat,
          lon: itemLon,
          distanceMeters: _haversine(lat, lon, itemLat, itemLon),
        );
      }).toList();

      _lastResults.sort((a, b) => (a.distanceMeters ?? double.infinity)
          .compareTo(b.distanceMeters ?? double.infinity));

      return _lastResults;
    } catch (e) {
      logDebug('PlaceSearchService.searchNearby 错误: $e');
      // 只有当前搜索仍是最新搜索时才清空缓存
      if (searchToken == _latestSearchToken) {
        _lastResults = [];
      }
      return [];
    } finally {
      if (searchToken == _latestSearchToken) {
        _isSearching = false;
        notifyListeners();
      }
    }
  }

  @override
  Future<PoiInfo?> reverseSelectedPoint(double lat, double lon) async {
    try {
      await _enforceRateLimit();

      final params = {
        'lat': '$lat',
        'lon': '$lon',
        'format': 'json',
        'addressdetails': '1',
        'zoom': '18',
      };

      final uri =
          Uri.parse('$_baseUrl/reverse').replace(queryParameters: params);
      final response = await _getWith429Backoff(uri);
      if (response == null) return null;

      if (response.statusCode != 200) {
        logDebug('Nominatim reverse 失败: ${response.statusCode}');
        return null;
      }

      final decoded = json.decode(response.body);
      if (decoded is! Map<String, dynamic> || decoded['error'] != null) {
        return null;
      }
      final data = decoded;

      return PoiInfo(
        name: _extractName(data),
        address: _extractAddress(data),
        category: data['type']?.toString(),
        lat: double.tryParse(data['lat']?.toString() ?? '') ?? lat,
        lon: double.tryParse(data['lon']?.toString() ?? '') ?? lon,
      );
    } catch (e) {
      logDebug('PlaceSearchService.reverseSelectedPoint 错误: $e');
      return null;
    }
  }

  @override
  void dispose() {
    if (_ownsHttpClient) {
      _httpClient.close();
    }
    super.dispose();
  }

  String _extractName(Map<String, dynamic> item) {
    // 优先用 name 字段
    if (item['name'] != null && (item['name'] as String).isNotEmpty) {
      return item['name'] as String;
    }
    // fallback 到 address 里的细粒度字段
    final addr = item['address'] as Map<String, dynamic>?;
    if (addr != null) {
      for (final key in [
        'amenity',
        'building',
        'shop',
        'tourism',
        'leisure',
        'road',
        'neighbourhood',
        'suburb',
      ]) {
        if (addr[key] != null && (addr[key] as String).isNotEmpty) {
          return addr[key] as String;
        }
      }
    }
    // 最终 fallback
    final display = item['display_name']?.toString() ?? '';
    final parts = display.split(',');
    return parts.isNotEmpty ? parts.first.trim() : display;
  }

  String? _extractAddress(Map<String, dynamic> item) {
    final addr = item['address'] as Map<String, dynamic>?;
    if (addr == null) return null;
    final parts = <String>[];
    for (final key in ['road', 'suburb', 'city', 'state']) {
      if (addr[key] != null && (addr[key] as String).isNotEmpty) {
        parts.add(addr[key] as String);
      }
    }
    return parts.isEmpty ? null : parts.join(', ');
  }

  static double _haversine(double lat1, double lon1, double lat2, double lon2) {
    const r = 6371000.0;
    final dLat = _toRad(lat2 - lat1);
    final dLon = _toRad(lon2 - lon1);
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_toRad(lat1)) *
            math.cos(_toRad(lat2)) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
    return r * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  }

  static double _toRad(double deg) => deg * math.pi / 180;
}
