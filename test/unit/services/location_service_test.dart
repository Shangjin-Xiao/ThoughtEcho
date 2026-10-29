// ignore_for_file: depend_on_referenced_packages

import 'dart:async';
import 'package:dio/dio.dart' show CancelToken;

import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geolocator_platform_interface/geolocator_platform_interface.dart';
import 'package:thoughtecho/services/mmkv_service.dart';

import '../../test_harness.dart';
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
    CancelToken? cancelToken,
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

class _ConsentGeolocator extends GeolocatorPlatform
    with MockPlatformInterfaceMixin {
  int positionCalls = 0;
  final started = Completer<void>();
  Completer<Position>? pendingPosition;

  @override
  Future<bool> isLocationServiceEnabled() async => true;

  @override
  Future<LocationPermission> checkPermission() async =>
      LocationPermission.whileInUse;

  @override
  Future<Position> getCurrentPosition(
      {LocationSettings? locationSettings}) async {
    positionCalls++;
    if (!started.isCompleted) started.complete();
    return pendingPosition?.future ??
        Future.value(Position(
          latitude: 12.3,
          longitude: 45.6,
          timestamp: DateTime(2026),
          accuracy: 1,
          altitude: 0,
          altitudeAccuracy: 0,
          heading: 0,
          headingAccuracy: 0,
          speed: 0,
          speedAccuracy: 0,
        ));
  }
}

class _ConsentGeocoding extends GeocodingPlatform
    with MockPlatformInterfaceMixin {
  Completer<List<Placemark>>? pendingAddress;
  final started = Completer<void>();

  @override
  Future<void> setLocaleIdentifier(String localeIdentifier) async {}

  @override
  Future<List<Placemark>> placemarkFromCoordinates(
    double latitude,
    double longitude, {
    String? localeIdentifier,
  }) async {
    if (!started.isCompleted) started.complete();
    return pendingAddress?.future ?? Future.value(<Placemark>[]);
  }
}

class _ConsentNetwork implements NetworkService {
  final urls = <String>[];
  final started = Completer<void>();
  Completer<HttpResponse>? pendingResponse;
  CancelToken? cancellation;

  @override
  Future<HttpResponse> get(
    String url, {
    Map<String, String>? headers,
    int? timeoutSeconds,
    CancelToken? cancelToken,
  }) async {
    cancellation = cancelToken;
    urls.add(url);
    if (!started.isCompleted) started.complete();
    return pendingResponse?.future ??
        Future.value(HttpResponse(
          '{"address":{"country":"Example Country","state":"Example Region","city":"Example City"}}',
          200,
        ));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('Location consent', () {
    late GeolocatorPlatform originalLocation;
    GeocodingPlatform? originalGeocoding;
    late _ConsentGeolocator device;
    late _ConsentGeocoding geocoding;
    late _ConsentNetwork network;
    late LocationService service;

    setUp(() async {
      await TestHarness.initialize();
      await MMKVService().init();
      await MMKVService().setBool('location_service_enabled', false);
      originalLocation = GeolocatorPlatform.instance;
      try {
        originalGeocoding = GeocodingPlatform.instance;
      } catch (_) {
        originalGeocoding = null;
      }
      GeolocatorPlatform.instance = device = _ConsentGeolocator();
      GeocodingPlatform.instance = geocoding = _ConsentGeocoding();
      NetworkService.instanceForTesting = network = _ConsentNetwork();
      service = LocationService();
    });

    tearDown(() {
      service.dispose();
      GeolocatorPlatform.instance = originalLocation;
      if (originalGeocoding != null) {
        GeocodingPlatform.instance = originalGeocoding!;
      }
      NetworkService.instanceForTesting = null;
    });

    test('stored off choice blocks startup and refresh despite OS permission',
        () async {
      await service.init();
      await service.refreshServiceStatus();
      final position = await service.getCurrentLocation();
      expect(position, isNull);
      expect(device.positionCalls, 0);
      expect(network.urls, isEmpty);
    });

    test('missing preference does not inherit surviving OS permission',
        () async {
      await MMKVService().remove('location_service_enabled');
      await service.init();
      expect(await service.getCurrentLocation(), isNull);
      expect(device.positionCalls, 0);
      expect(network.urls, isEmpty);
    });

    test('explicit consent allows collection and coordinate geocoding',
        () async {
      await service.setLocationEnabled(true);
      final position = await service.getCurrentLocation();
      expect(position?.latitude, 12.3);
      expect(device.positionCalls, 1);
      expect(network.urls.single, contains('lat=12.3&lon=45.6'));
      expect(service.city, 'Example City');

      final restarted = LocationService();
      expect(restarted.locationEnabled, isTrue);
      restarted.dispose();
    });

    test('revocation discards an acquired position even after re-enabling',
        () async {
      await service.setLocationEnabled(true);
      device.pendingPosition = Completer<Position>();
      final fetch = service.getCurrentLocation();
      await device.started.future;

      final disable = service.setLocationEnabled(false);
      expect(service.locationEnabled, isFalse);
      expect(service.currentPosition, isNull);
      expect(service.isLoading, isFalse);
      await disable;
      await service.setLocationEnabled(true);
      device.pendingPosition!.complete(Position(
        latitude: 12.3,
        longitude: 45.6,
        timestamp: DateTime(2026),
        accuracy: 1,
        altitude: 0,
        altitudeAccuracy: 0,
        heading: 0,
        headingAccuracy: 0,
        speed: 0,
        speedAccuracy: 0,
      ));

      expect(await fetch, isNull);
      expect(service.currentPosition, isNull);
      expect(network.urls, isEmpty);
    });

    test('revocation during system geocoding prevents online fallback',
        () async {
      await service.setLocationEnabled(true);
      geocoding.pendingAddress = Completer<List<Placemark>>();
      final fetch = service.getCurrentLocation();
      await geocoding.started.future;

      await service.setLocationEnabled(false);
      await service.setLocationEnabled(true);
      geocoding.pendingAddress!.complete([]);
      expect(await fetch, isNull);
      expect(network.urls, isEmpty);
      expect(service.currentPosition, isNull);
      expect(service.currentAddress, isNull);
    });

    test('revocation drops online results and blocks cached coordinate reuse',
        () async {
      await service.setLocationEnabled(true);
      network.pendingResponse = Completer<HttpResponse>();
      service.setCoordinates(12.3, 45.6,
          address: 'Example Country, Example Region, Example City');
      service.currentLocaleCode = 'en';
      await network.started.future;

      await service.setLocationEnabled(false);
      expect(network.cancellation!.isCancelled, isTrue);
      network.pendingResponse!.complete(HttpResponse(
          '{"address":{"country":"Example Country","state":"Example Region","city":"Example City"}}',
          200));
      // Drain the locale refresh so its old-address fallback also runs.
      await Future<void>.delayed(Duration.zero);
      service.currentLocaleCode = 'zh';
      service.setCoordinates(12.3, 45.6);
      await service.getAddressFromLatLng();
      expect(await service.resolveOfflineLocation(), isFalse);
      expect(await service.refreshAddressFromOnlineReverseGeocoding(), isFalse);
      expect(await service.reverseGeocodePoint(12.3, 45.6), isNull);
      expect(service.currentPosition, isNull);
      expect(service.currentAddress, isNull);
      expect(service.city, isNull);
      expect(network.urls, hasLength(1));

      final restarted = LocationService();
      await restarted.init();
      expect(await restarted.getCurrentLocation(), isNull);
      expect(device.positionCalls, 0);
      restarted.dispose();
    });

    test('rapid enable then disable persists the last choice', () async {
      await Future.wait([
        service.setLocationEnabled(true),
        service.setLocationEnabled(false),
      ]);
      expect(service.locationEnabled, isFalse);
      final restarted = LocationService();
      expect(restarted.locationEnabled, isFalse);
      restarted.dispose();
    });
  });

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
