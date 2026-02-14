import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/services/location_service.dart';

void main() {
  group('LocationService Display Logic', () {
    test(
        'Traditional Chinese city name (District/Ward) should not append City suffix',
        () {
      final service = LocationService();

      // Simulate setting language to Chinese
      service.currentLocaleCode = 'zh';

      // Simulate location update with Traditional Chinese characters
      // Country, Province, City, District
      // "臺東區" is Taito Ward in Traditional Chinese.
      service.parseLocationString('Japan,Tokyo,臺東區,Asakusa');

      // Check display location
      // Expected: "臺東區·Asakusa"
      // Current behavior (bug expected): "臺東區市·Asakusa"
      expect(service.getDisplayLocation(), '臺東區·Asakusa');
    });

    test('Traditional Chinese county name should not append City suffix', () {
      final service = LocationService();
      service.currentLocaleCode = 'zh';

      // Example: Hualien County (花蓮縣)
      service.parseLocationString('Taiwan,Hualien,花蓮縣,Hualien City');

      expect(service.getDisplayLocation(), '花蓮縣·Hualien City');
    });

    test(
        'Traditional Chinese Township (Xiang/Zhen) should not append City suffix',
        () {
      final service = LocationService();
      service.currentLocaleCode = 'zh';

      // Example: Township
      service.parseLocationString('Taiwan,Nantou,仁愛鄉,');

      expect(service.getDisplayLocation(), 'Nantou·仁愛鄉');
    });
  });
}
