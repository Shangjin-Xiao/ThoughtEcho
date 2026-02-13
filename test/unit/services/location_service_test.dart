/// Basic unit tests for LocationService
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/services/location_service.dart';

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
  });
}
