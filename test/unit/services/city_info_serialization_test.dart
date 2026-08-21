import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/services/location_service.dart';

void main() {
  group('CityInfo Serialization & Methods', () {
    test('toJson and fromJson work symmetrically', () {
      final original = CityInfo(
        name: '杭州',
        fullName: '中国, 浙江省, 杭州',
        lat: 30.2741,
        lon: 120.1551,
        country: '中国',
        province: '浙江省',
      );

      final json = original.toJson();
      final reconstructed = CityInfo.fromJson(json);

      expect(reconstructed.name, equals(original.name));
      expect(reconstructed.fullName, equals(original.fullName));
      expect(reconstructed.lat, equals(original.lat));
      expect(reconstructed.lon, equals(original.lon));
      expect(reconstructed.country, equals(original.country));
      expect(reconstructed.province, equals(original.province));
      expect(reconstructed, equals(original));
    });

    test('fromJson handles null / missing fields safely', () {
      final city = CityInfo.fromJson({});
      expect(city.name, isEmpty);
      expect(city.fullName, isEmpty);
      expect(city.lat, equals(0.0));
      expect(city.lon, equals(0.0));
      expect(city.country, isEmpty);
      expect(city.province, isEmpty);
    });

    test('copyWith updates specified fields', () {
      final original = CityInfo(
        name: 'Tokyo',
        fullName: 'Japan, Tokyo',
        lat: 35.6762,
        lon: 139.6503,
        country: 'Japan',
        province: 'Tokyo',
      );

      final updated = original.copyWith(name: 'Tokyo Central');
      expect(updated.name, equals('Tokyo Central'));
      expect(updated.country, equals('Japan'));
      expect(updated.lat, equals(35.6762));
    });

    test('equality and hashCode evaluate properly', () {
      final a = CityInfo(
        name: 'Paris',
        fullName: 'France, Île-de-France, Paris',
        lat: 48.8566,
        lon: 2.3522,
        country: 'France',
        province: 'Île-de-France',
      );
      final b = CityInfo(
        name: 'Paris',
        fullName: 'France, Île-de-France, Paris',
        lat: 48.8566,
        lon: 2.3522,
        country: 'France',
        province: 'Île-de-France',
      );
      final c = CityInfo(
        name: 'London',
        fullName: 'UK, London',
        lat: 51.5074,
        lon: -0.1278,
        country: 'UK',
        province: 'England',
      );

      expect(a == b, isTrue);
      expect(a.hashCode, equals(b.hashCode));
      expect(a == c, isFalse);
    });
  });
}
