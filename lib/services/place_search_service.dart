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
  static const _minRequestInterval = Duration(milliseconds: 1100);

  DateTime _lastRequestTime = DateTime.fromMillisecondsSinceEpoch(0);
  bool _isSearching = false;
  bool get isSearching => _isSearching;

  List<PoiInfo> _lastResults = [];
  List<PoiInfo> get lastResults => _lastResults;

  Future<void> _enforceRateLimit() async {
    final elapsed = DateTime.now().difference(_lastRequestTime);
    if (elapsed < _minRequestInterval) {
      await Future.delayed(_minRequestInterval - elapsed);
    }
    _lastRequestTime = DateTime.now();
  }

  @override
  Future<List<PoiInfo>> searchNearby(
    double lat,
    double lon, {
    String? query,
    int limit = 20,
  }) async {
    if (query == null || query.trim().isEmpty) {
      // 无搜索词时仅 reverse geocode 当前点
      final poi = await reverseSelectedPoint(lat, lon);
      _lastResults = poi != null ? [poi] : [];
      notifyListeners();
      return _lastResults;
    }

    _isSearching = true;
    notifyListeners();

    try {
      await _enforceRateLimit();

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
      final response = await http.get(uri, headers: {'User-Agent': _userAgent});

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
      return _lastResults = [];
    } finally {
      _isSearching = false;
      notifyListeners();
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
      final response = await http.get(uri, headers: {'User-Agent': _userAgent});

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
