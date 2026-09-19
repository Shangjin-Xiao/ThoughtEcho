// ignore_for_file: depend_on_referenced_packages

import 'package:flutter_test/flutter_test.dart';
import 'package:geocoding_platform_interface/geocoding_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:thoughtecho/services/local_geocoding_service.dart';
import 'package:thoughtecho/services/location_service.dart';

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
}
