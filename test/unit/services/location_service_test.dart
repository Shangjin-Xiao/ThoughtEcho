// ignore_for_file: depend_on_referenced_packages

import 'package:flutter_test/flutter_test.dart';
import 'package:geocoding_platform_interface/geocoding_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:thoughtecho/services/local_geocoding_service.dart';
import 'package:thoughtecho/services/location_service.dart';
import 'package:thoughtecho/services/network_service.dart';
import 'package:thoughtecho/utils/http_response.dart';

class _FakeNetworkService implements NetworkService {
  final Map<String, Duration> delays;
  final Map<String, String> responses;

  _FakeNetworkService({
    required this.delays,
    required this.responses,
  });

  @override
  Future<HttpResponse> get(
    String url, {
    Map<String, String>? headers,
    int? timeoutSeconds,
  }) async {
    for (final entry in delays.entries) {
      if (url.contains(entry.key)) {
        await Future.delayed(entry.value);
        final body = responses[entry.key] ?? '[]';
        return HttpResponse(body, 200);
      }
    }
    return HttpResponse('[]', 200);
  }

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _SlowMockGeocodingPlatform extends GeocodingPlatform
    with MockPlatformInterfaceMixin {
  final Duration delay;
  _SlowMockGeocodingPlatform(this.delay);

  @override
  Future<void> setLocaleIdentifier(String localeIdentifier) async {
    if (delay > Duration.zero) await Future.delayed(delay);
  }

  @override
  Future<List<Placemark>> placemarkFromCoordinates(
    double latitude,
    double longitude, {
    String? localeIdentifier,
  }) async {
    if (delay > Duration.zero) await Future.delayed(delay);
    return [
      Placemark(
        name: '故宫博物院',
        locality: '北京市',
        subLocality: '东城区',
      ),
    ];
  }
}

void main() {
  group('LocationService Tests', () {
    late LocationService locationService;

    setUp(() {
      locationService = LocationService();
    });

    test('should create LocationService instance', () {
      expect(locationService, isNotNull);
    });

    test('should have basic functionality', () {
      expect(() => locationService.toString(), returnsNormally);
    });

    test('zh display should not append 市 for ward-style city names', () {
      locationService.currentLocaleCode = 'zh';
      locationService.parseLocationString('日本,东京,新宿区,');

      expect(locationService.getDisplayLocation(), '东京·新宿区');
    });

    test('zh display should keep latin ward names without 市 suffix', () {
      locationService.currentLocaleCode = 'zh';
      locationService.parseLocationString('Japan,Kanagawa,Naka ward,');

      expect(locationService.getDisplayLocation(), 'Kanagawa·Naka ward');
    });

    test('zh display should prefer province and city style output', () {
      locationService.currentLocaleCode = 'zh';
      locationService.parseLocationString('中国,浙江省,杭州,');

      expect(locationService.getDisplayLocation(), '浙江省·杭州市');
    });

    test('LocalGeocodingService 超时时安全中断并返回 null，不挂起队列', () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      GeocodingPlatform? original;
      try {
        original = GeocodingPlatform.instance;
      } catch (_) {
        original = null;
      }

      try {
        // 设置慢速平台实例（200ms），强行触发 20ms 超时
        GeocodingPlatform.instance =
            _SlowMockGeocodingPlatform(const Duration(milliseconds: 200));

        final result = await LocalGeocodingService.getAddressFromCoordinates(
          39.9042,
          116.4074,
          bypassCache: true,
          timeout: const Duration(milliseconds: 20),
        );

        // 验证超时安全返回 null，不抛异常
        expect(result, isNull);

        // 验证队列未被挂起：后续正常任务可继续执行
        GeocodingPlatform.instance = _SlowMockGeocodingPlatform(Duration.zero);
        final normalResult =
            await LocalGeocodingService.getAddressFromCoordinates(
          39.9042,
          116.4074,
          bypassCache: true,
          timeout: const Duration(seconds: 1),
        );
        expect(normalResult, isNotNull);
        expect(normalResult!['city'], '北京市');
      } finally {
        if (original != null) {
          GeocodingPlatform.instance = original;
        }
      }
    });
  });

  group('LocationService Search Concurrency Tests', () {
    late LocationService locationService;

    setUp(() {
      locationService = LocationService();
      NetworkService.instanceForTesting = _FakeNetworkService(
        delays: {
          'slow_city': const Duration(milliseconds: 100),
          'fast_city': const Duration(milliseconds: 10),
        },
        responses: {
          'slow_city': '''
[
  {
    "name": "Slow City",
    "lat": 1.0,
    "lon": 1.0,
    "address": {
      "country": "CountryA",
      "city": "Slow City"
    }
  }
]
''',
          'fast_city': '''
[
  {
    "name": "Fast City",
    "lat": 2.0,
    "lon": 2.0,
    "address": {
      "country": "CountryB",
      "city": "Fast City"
    }
  }
]
''',
        },
      );
    });

    tearDown(() {
      NetworkService.instanceForTesting = null;
    });

    test('searchCity 乱序返回时，高延迟旧请求结果不应覆盖最新结果', () async {
      int notifyCount = 0;
      locationService.addListener(() => notifyCount++);

      final futureSlow = locationService.searchCity('slow_city');
      expect(locationService.isSearching, isTrue);

      await Future.delayed(const Duration(milliseconds: 5));

      final futureFast = locationService.searchCity('fast_city');
      expect(locationService.isSearching, isTrue);

      await futureFast;

      expect(locationService.searchResults.length, 1);
      expect(locationService.searchResults.first.name, 'Fast City');
      expect(locationService.isSearching, isFalse);
      final countAfterFast = notifyCount;

      await futureSlow;

      // 过期旧请求返回后，结果不应被覆盖，状态与通知次数应保持不变
      expect(locationService.searchResults.length, 1);
      expect(locationService.searchResults.first.name, 'Fast City');
      expect(locationService.isSearching, isFalse);
      expect(notifyCount, countAfterFast);
    });

    test('clearSearchResults 中途打断时，未完成的后台请求结果被丢弃', () async {
      int notifyCount = 0;
      locationService.addListener(() => notifyCount++);

      final futureSlow = locationService.searchCity('slow_city');
      expect(locationService.isSearching, isTrue);

      await Future.delayed(const Duration(milliseconds: 5));

      locationService.clearSearchResults();
      expect(locationService.searchResults, isEmpty);
      expect(locationService.isSearching, isFalse);
      final countAfterClear = notifyCount;

      await futureSlow;

      expect(locationService.searchResults, isEmpty);
      expect(locationService.isSearching, isFalse);
      expect(notifyCount, countAfterClear);
    });

    test('searchCity 传入空字符串打断时，未完成的后台请求结果被丢弃', () async {
      int notifyCount = 0;
      locationService.addListener(() => notifyCount++);

      final futureSlow = locationService.searchCity('slow_city');
      expect(locationService.isSearching, isTrue);

      await Future.delayed(const Duration(milliseconds: 5));

      final emptyFuture = locationService.searchCity('   ');
      await emptyFuture;

      expect(locationService.searchResults, isEmpty);
      expect(locationService.isSearching, isFalse);
      final countAfterEmpty = notifyCount;

      await futureSlow;

      expect(locationService.searchResults, isEmpty);
      expect(locationService.isSearching, isFalse);
      expect(notifyCount, countAfterEmpty);
    });
  });
}
