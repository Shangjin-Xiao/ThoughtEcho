import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/services/location_service.dart';

void main() {
  group('LocationService.formatLocationForDisplay', () {
    test('formats full CSV correctly', () {
      const input = 'China,Beijing,Beijing,Chaoyang';
      expect(
        LocationService.formatLocationForDisplay(input),
        'Beijing·Chaoyang',
      );
    });

    test('formats CSV with missing district correctly', () {
      const input = 'China,Beijing,Beijing,';
      expect(LocationService.formatLocationForDisplay(input), 'Beijing');
    });

    test('formats CSV with missing district (no trailing comma) correctly', () {
      const input = 'China,Beijing,Beijing';
      expect(LocationService.formatLocationForDisplay(input), 'Beijing');
    });

    test(
      'formats CSV with missing district and different province correctly',
      () {
        const input = 'China,Zhejiang,Hangzhou,';
        expect(
          LocationService.formatLocationForDisplay(input),
          'Zhejiang·Hangzhou',
        );
      },
    );

    test('formats CSV with missing city but has district (Japan style)', () {
      const input = 'Japan,Tokyo,,Shinjuku';
      expect(LocationService.formatLocationForDisplay(input), 'Tokyo·Shinjuku');
    });

    test('formats Japan prefecture + ward correctly', () {
      const input = '日本,东京,新宿区,';
      expect(LocationService.formatLocationForDisplay(input), '东京·新宿区');
    });

    test('formats CSV with missing city and district correctly', () {
      const input = 'Japan,Chiba,,';
      expect(LocationService.formatLocationForDisplay(input), 'Japan·Chiba');
    });

    test('formats CSV with missing city, district, province correctly', () {
      const input = 'Japan,,,';
      expect(LocationService.formatLocationForDisplay(input), 'Japan');
    });

    test('returns empty string for empty CSV', () {
      const input = ',,,';
      expect(LocationService.formatLocationForDisplay(input), '');
    });

    test('returns original string for non-CSV', () {
      const input = 'Some Random String';
      expect(
        LocationService.formatLocationForDisplay(input),
        'Some Random String',
      );
    });

    test('returns empty string for null', () {
      expect(LocationService.formatLocationForDisplay(null), '');
    });

    test('returns empty string for empty string', () {
      expect(LocationService.formatLocationForDisplay(''), '');
    });

    test('returns empty string for pending marker', () {
      expect(
        LocationService.formatLocationForDisplay(
          LocationService.kAddressPending,
        ),
        '',
      );
    });

    test('returns empty string for failed marker', () {
      expect(
        LocationService.formatLocationForDisplay(
          LocationService.kAddressFailed,
        ),
        '',
      );
    });
  });

  group('LocationService.getDisplayLocation', () {
    test(
      'keeps English city and district unchanged when locale is English',
      () {
        final service = LocationService();
        service.currentLocaleCode = 'en';
        service.parseLocationString('Japan,Tokyo,Asakusa,Taito');

        expect(service.getDisplayLocation(), 'Asakusa · Taito');
      },
    );

    test('does not append Chinese 市 suffix in English locale', () {
      final service = LocationService();
      service.currentLocaleCode = 'en';
      service.parseLocationString('China,Guangdong,Dongguan,');

      expect(service.getDisplayLocation(), 'Guangdong · Dongguan');
    });

    test('Chinese locale still applies Chinese formatting rules', () {
      final service = LocationService();
      service.currentLocaleCode = 'zh';
      service.parseLocationString('中国,广东,东莞,南城区');

      expect(service.getDisplayLocation(), '东莞市·南城区');
    });
  });
}
