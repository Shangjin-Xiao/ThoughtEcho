import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/services/network_service.dart';
import 'package:thoughtecho/services/place_search_service.dart';
import 'package:thoughtecho/utils/http_response.dart';

/// 只回放一段固定响应，并记下请求长什么样。
class _FakeNetworkService implements NetworkService {
  _FakeNetworkService(
    this.response, {
    this.responses,
    this.shouldThrow = false,
  });

  final HttpResponse response;
  final List<HttpResponse>? responses;
  final bool shouldThrow;

  int calls = 0;
  Uri? lastUri;
  Map<String, String>? lastHeaders;

  @override
  Future<HttpResponse> get(
    String url, {
    Map<String, String>? headers,
    int? timeoutSeconds,
  }) async {
    final uri = Uri.parse(url);
    lastUri = uri;
    lastHeaders = headers;
    if (shouldThrow) {
      throw Exception('Network request failed');
    }
    if (responses != null && calls < responses!.length) {
      final res = responses![calls];
      calls++;
      return res;
    }
    calls++;
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
  final List<Uri> uris = [];

  @override
  Future<HttpResponse> get(
    String url, {
    Map<String, String>? headers,
    int? timeoutSeconds,
  }) async {
    timestamps.add(DateTime.now());
    uris.add(Uri.parse(url));
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

    test('非 200 响应时抛出异常，让调用方展示重试横幅', () async {
      final network = _FakeNetworkService(
        _jsonResponse(const [], statusCode: 429),
      );
      final service = NominatimPlaceSearchService(networkService: network);

      expect(
        () => service.searchNearby(refLat, refLon, query: '咖啡馆'),
        throwsException,
      );
    });

    test('网络异常时抛出异常，让调用方展示重试横幅', () async {
      final network = _FakeNetworkService(
        _jsonResponse(const [], statusCode: 500),
        shouldThrow: true,
      );
      final service = NominatimPlaceSearchService(networkService: network);

      expect(
        () => service.searchNearby(refLat, refLon, query: '咖啡馆'),
        throwsException,
      );
    });

    test('searchNearby 同样带上入库四级串', () async {
      final network = _FakeNetworkService(
        _jsonResponse([
          {
            'name': '朝阳公园',
            'lat': '39.9142',
            'lon': '116.4074',
            'address': {
              'country': '中国',
              'state': '北京市',
              'city': '北京市',
              'suburb': '朝阳区',
              'road': '农展馆南路',
            },
          },
        ]),
      );
      final service = NominatimPlaceSearchService(networkService: network);

      final results = await service.searchNearby(refLat, refLon, query: '公园');

      expect(results.single.storageLocation, '中国,北京市,北京市,朝阳区');
    });

    test('请求带上限定的 viewbox 和可识别的 User-Agent，且绑定 bounded=1 限制在附近', () async {
      final network = _FakeNetworkService(_jsonResponse(const []));
      final service = NominatimPlaceSearchService(networkService: network);

      await service.searchNearby(refLat, refLon,
          query: '咖啡馆', localeCode: 'zh');

      final params = network.lastUri!.queryParameters;
      expect(params['q'], '咖啡馆');
      expect(params['format'], 'json');
      expect(params['bounded'], '1');
      expect(params['viewbox'], isNotNull);
      expect(network.lastHeaders!['User-Agent'], contains('ThoughtEcho'));
      expect(network.lastHeaders!['Accept-Language'], startsWith('zh-CN'));
    });
  });

  group('NominatimPlaceSearchService 限流', () {
    test('限流窗口内并发来的两条被排成队，不会挤在一起发出去', () async {
      const interval = Duration(milliseconds: 200);
      final network = _RecordingNetworkService(_jsonResponse(const []));
      final service = NominatimPlaceSearchService(
        networkService: network,
        minRequestInterval: interval,
      );

      // 必须先发一次把窗口起点占上。冷启动时第一个调用不等待、且在让出
      // 事件循环之前就写好了时间戳，第二个自然会等——那种情况下即使没有
      // 串行化也看不出问题，测不到真正的竞态。
      await service.searchNearby(refLat, refLon, query: '先来一次');

      // 窗口还没过就并发来两条：不排队的话它们会读到同一个时间戳、算出同样
      // 的剩余等待，然后一起发出去。
      await Future.wait([
        service.searchNearby(refLat, refLon, query: '咖啡馆'),
        service.searchNearby(refLat, refLon, query: '公园'),
      ]);

      expect(network.timestamps, hasLength(3));
      final firstGap = network.timestamps[1].difference(network.timestamps[0]);
      final secondGap = network.timestamps[2].difference(network.timestamps[1]);

      // 下限取 150 而不是整个 200：`Future.delayed` 会提前一两毫秒触发，
      // 卡死在整个间隔上会让这条用例随机变红。而没串行时第二个间隔 ≈ 0，
      // 和 150 差得很远，照样能抓住。
      expect(firstGap, greaterThan(const Duration(milliseconds: 150)));
      expect(secondGap, greaterThan(const Duration(milliseconds: 150)));
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

  group('NominatimPlaceSearchService.getNearbyPlaces', () {
    test('严格限制在 5 公里半径内，过滤超出 5000 米的条目', () async {
      final network = _FakeNetworkService(
        _jsonResponse([
          {
            'name': '近处的书店',
            'lat': '39.9142',
            'lon': '116.4074',
            'type': 'shop',
            'address': {'shop': '近处的书店'},
          },
          {
            'name': '6公里外的景点',
            'lat': '39.9642',
            'lon': '116.4074',
            'type': 'tourism',
            'address': {'tourism': '远处的景点'},
          },
        ]),
      );
      final service = NominatimPlaceSearchService(networkService: network);

      final results = await service.getNearbyPlaces(refLat, refLon);

      expect(results.map((p) => p.name), ['近处的书店']);
      expect(network.lastUri!.queryParameters['viewbox'], isNotNull);
    });

    test('支持 offset 分页参数并传递给 API', () async {
      final network = _FakeNetworkService(_jsonResponse(const []));
      final service = NominatimPlaceSearchService(networkService: network);

      await service.getNearbyPlaces(refLat, refLon,
          categoryOrKeyword: '公园', offset: 20, limit: 20);

      final params = network.lastUri!.queryParameters;
      expect(params['offset'], '20');
      expect(params['limit'], '20');
    });

    test('传入 categoryOrKeyword 时将其设为 q 参数', () async {
      final network = _FakeNetworkService(_jsonResponse(const []));
      final service = NominatimPlaceSearchService(networkService: network);

      await service.getNearbyPlaces(refLat, refLon, categoryOrKeyword: '西湖区');

      final params = network.lastUri!.queryParameters;
      expect(params['q'], '西湖区');
    });

    test('未传入 categoryOrKeyword 时按页码轮替综合 POI 类别且不把全局 offset 强加给新类别', () async {
      final network = _FakeNetworkService(
        _jsonResponse(const []),
        responses: [
          _jsonResponse([
            {
              'place_id': 100,
              'name': '景点',
              'lat': '39.9052',
              'lon': '116.4074',
              'type': 'attraction',
              'address': {'tourism': '景点'},
            },
          ]),
          _jsonResponse([
            {
              'place_id': 200,
              'name': '公园',
              'lat': '39.9062',
              'lon': '116.4074',
              'type': 'park',
              'address': {'leisure': '公园'},
            },
          ]),
        ],
      );
      final service = NominatimPlaceSearchService(networkService: network);

      // 第一页 (offset=0) 默认请求 attraction
      final page1 =
          await service.getNearbyPlaces(refLat, refLon, offset: 0, limit: 20);
      expect(network.lastUri!.queryParameters['q'], 'attraction');
      expect(network.lastUri!.queryParameters.containsKey('amenity'), isFalse);
      expect(network.lastUri!.queryParameters.containsKey('offset'), isFalse);
      expect(page1.length, 1);
      expect(page1.first.name, '景点');

      // 第二页 (offset=20) 轮替到 park，依靠 exclude_place_ids 去重而不强加 offset=20
      final page2 =
          await service.getNearbyPlaces(refLat, refLon, offset: 20, limit: 20);
      expect(network.lastUri!.queryParameters['q'], 'park');
      expect(network.lastUri!.queryParameters.containsKey('offset'), isFalse);
      expect(
        network.lastUri!.queryParameters['exclude_place_ids'],
        contains('100'),
      );
      expect(page2.length, 1);
      expect(page2.first.name, '公园');
    });

    test('请求失败时抛出异常，让调用方展示重试横幅', () async {
      final network = _FakeNetworkService(
        _jsonResponse(const [], statusCode: 500),
      );
      final service = NominatimPlaceSearchService(networkService: network);

      expect(
        () => service.getNearbyPlaces(refLat, refLon),
        throwsException,
      );
    });

    test('分页时记录并传递 exclude_place_ids 避免重复返回第一页', () async {
      final network = _FakeNetworkService(
        _jsonResponse([
          {
            'place_id': 12345,
            'name': '近处的书店',
            'lat': '39.9142',
            'lon': '116.4074',
            'type': 'shop',
            'address': {'shop': '近处的书店'},
          },
        ]),
      );
      final service = NominatimPlaceSearchService(networkService: network);

      // 第一页抓取
      final page1 = await service.getNearbyPlaces(refLat, refLon, offset: 0);
      expect(page1.length, 1);
      expect(page1.first.name, '近处的书店');

      // 第二页抓取，应带上第一页的 place_id 且本地过滤重复项
      final page2 = await service.getNearbyPlaces(refLat, refLon, offset: 1);
      final params = network.lastUri!.queryParameters;
      expect(params['exclude_place_ids'], contains('12345'));
      expect(page2, isEmpty);
    });

    test('分类轮替重试时对后续尝试执行限流节流', () async {
      final network = _RecordingNetworkService(_jsonResponse(const []));
      final service = NominatimPlaceSearchService(
        networkService: network,
        minRequestInterval: const Duration(milliseconds: 50),
      );

      await service.getNearbyPlaces(refLat, refLon);

      // 验证按轮替顺序依次尝试四个分类
      expect(
        network.uris.map((u) => u.queryParameters['q']),
        ['attraction', 'park', 'museum', 'monument'],
      );
      // 检查后续请求之间满足限流间隔
      for (var i = 1; i < network.timestamps.length; i++) {
        final gap = network.timestamps[i].difference(network.timestamps[i - 1]);
        expect(gap, greaterThanOrEqualTo(const Duration(milliseconds: 35)));
      }
    });

    test('搜索结果自带入库四级串，点选可直接复用', () async {
      final network = _FakeNetworkService(
        _jsonResponse([
          {
            'name': '景山公园',
            'lat': '39.9242',
            'lon': '116.4014',
            'address': {
              'country': '中国',
              'state': '北京市',
              'city': '北京市',
              'city_district': '西城区',
              'road': '景山西街',
            },
          },
        ]),
      );
      final service = NominatimPlaceSearchService(networkService: network);

      final results = await service.getNearbyPlaces(refLat, refLon);

      expect(results.single.storageLocation, '中国,北京市,北京市,西城区');
    });

    test('响应里没有行政区字段时四级串为 null，调用方再走反查', () async {
      final network = _FakeNetworkService(
        _jsonResponse([
          {
            'name': '近处的书店',
            'lat': '39.9142',
            'lon': '116.4074',
            'address': {'road': '近街'},
          },
        ]),
      );
      final service = NominatimPlaceSearchService(networkService: network);

      final results = await service.getNearbyPlaces(refLat, refLon);

      expect(results.single.storageLocation, isNull);
    });
  });
}
