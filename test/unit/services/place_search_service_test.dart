import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/services/network_service.dart';
import 'package:thoughtecho/services/place_search_service.dart';
import 'package:thoughtecho/utils/http_response.dart';

/// 只回放一段固定响应，并记下请求长什么样。
class _FakeNetworkService implements NetworkService {
  _FakeNetworkService(this.response);

  final HttpResponse response;

  int calls = 0;
  Uri? lastUri;
  Map<String, String>? lastHeaders;

  @override
  Future<HttpResponse> get(
    String url, {
    Map<String, String>? headers,
    int? timeoutSeconds,
  }) async {
    calls++;
    lastUri = Uri.parse(url);
    lastHeaders = headers;
    return response;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// 记下每次请求发出的时刻，用来验证限流。
class _RecordingNetworkService implements NetworkService {
  _RecordingNetworkService(this.response);

  final HttpResponse response;
  final List<DateTime> timestamps = [];

  @override
  Future<HttpResponse> get(
    String url, {
    Map<String, String>? headers,
    int? timeoutSeconds,
  }) async {
    timestamps.add(DateTime.now());
    return response;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

HttpResponse _jsonResponse(Object body, {int statusCode = 200}) =>
    HttpResponse(json.encode(body), statusCode, headers: const {});

void main() {
  // 参考点：北京天安门附近
  const refLat = 39.9042;
  const refLon = 116.4074;

  group('NominatimPlaceSearchService.searchNearby', () {
    test('空关键词不发请求，直接返回空列表', () async {
      final network = _FakeNetworkService(_jsonResponse(const []));
      final service = NominatimPlaceSearchService(networkService: network);

      expect(
        await service.searchNearby(refLat, refLon, query: '   '),
        isEmpty,
      );
      expect(network.calls, 0);
    });

    test('解析结果并按距离升序排列', () async {
      final network = _FakeNetworkService(
        _jsonResponse([
          {
            'name': '远处的咖啡馆',
            'lat': '39.9542',
            'lon': '116.4074',
            'type': 'cafe',
            'address': {'road': '远街', 'city': '北京市'},
          },
          {
            'name': '近处的咖啡馆',
            'lat': '39.9092',
            'lon': '116.4074',
            'type': 'cafe',
            'address': {'road': '近街', 'city': '北京市'},
          },
        ]),
      );
      final service = NominatimPlaceSearchService(networkService: network);

      final results = await service.searchNearby(refLat, refLon, query: '咖啡馆');

      expect(results.map((p) => p.name), ['近处的咖啡馆', '远处的咖啡馆']);
      expect(results.first.address, '近街 · 北京市');
      expect(
          results.first.distanceMeters, lessThan(results.last.distanceMeters!));
    });

    test('没有 name 时退到 address 里的类型化别名', () async {
      final network = _FakeNetworkService(
        _jsonResponse([
          {
            'lat': '39.9052',
            'lon': '116.4074',
            'display_name': '某商场, 东城区, 北京市',
            'address': {'shop': '某商场', 'city': '北京市'},
          },
        ]),
      );
      final service = NominatimPlaceSearchService(networkService: network);

      final results = await service.searchNearby(refLat, refLon, query: '商场');

      expect(results.single.name, '某商场');
    });

    test('坐标缺失的条目被丢掉，不会变成 0,0 的假地点', () async {
      final network = _FakeNetworkService(
        _jsonResponse([
          {'name': '没有坐标的地点'},
          {'name': '有坐标的地点', 'lat': '39.9052', 'lon': '116.4074'},
        ]),
      );
      final service = NominatimPlaceSearchService(networkService: network);

      final results = await service.searchNearby(refLat, refLon, query: '地点');

      expect(results.map((p) => p.name), ['有坐标的地点']);
    });

    test('非 200 响应降级为空列表，不抛给调用方', () async {
      final network = _FakeNetworkService(
        _jsonResponse(const [], statusCode: 429),
      );
      final service = NominatimPlaceSearchService(networkService: network);

      expect(await service.searchNearby(refLat, refLon, query: '咖啡馆'), isEmpty);
    });

    test('请求带上限定的 viewbox 和可识别的 User-Agent', () async {
      final network = _FakeNetworkService(_jsonResponse(const []));
      final service = NominatimPlaceSearchService(networkService: network);

      await service.searchNearby(refLat, refLon,
          query: '咖啡馆', localeCode: 'zh');

      final params = network.lastUri!.queryParameters;
      expect(params['q'], '咖啡馆');
      expect(params['format'], 'json');
      // bounded=1 + viewbox：不限定的话「咖啡馆」会搜出全球结果
      expect(params['bounded'], '1');
      expect(params['viewbox'], isNotNull);
      expect(network.lastHeaders!['User-Agent'], contains('ThoughtEcho'));
      expect(network.lastHeaders!['Accept-Language'], startsWith('zh-CN'));
    });
  });

  group('NominatimPlaceSearchService 限流', () {
    test('并发搜索被排成队，两次请求间隔不小于限流窗口', () async {
      final network = _RecordingNetworkService(_jsonResponse(const []));
      final service = NominatimPlaceSearchService(
        networkService: network,
        minRequestInterval: const Duration(milliseconds: 120),
      );

      // 防抖搜索还在飞、用户又按了回车，就是这个场景
      await Future.wait([
        service.searchNearby(refLat, refLon, query: '咖啡馆'),
        service.searchNearby(refLat, refLon, query: '公园'),
      ]);

      expect(network.timestamps, hasLength(2));
      final gap = network.timestamps[1].difference(network.timestamps[0]);
      expect(gap, greaterThanOrEqualTo(const Duration(milliseconds: 120)));
    });
  });

  group('NominatimPlaceSearchService.distanceBetween', () {
    test('同一个点距离为 0', () {
      expect(
        NominatimPlaceSearchService.distanceBetween(
            refLat, refLon, refLat, refLon),
        0,
      );
    });

    test('纬度差 0.01 度约等于 1.1 公里', () {
      final meters = NominatimPlaceSearchService.distanceBetween(
        refLat,
        refLon,
        refLat + 0.01,
        refLon,
      );

      expect(meters, closeTo(1113, 5));
    });
  });
}
