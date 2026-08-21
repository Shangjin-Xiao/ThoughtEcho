import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/constants/popular_cities.dart';
import 'package:thoughtecho/services/location_service.dart';

void main() {
  group('PopularCitiesData', () {
    test('contains domestic and international cities', () {
      expect(PopularCitiesData.domestic, isNotEmpty);
      expect(PopularCitiesData.international, isNotEmpty);
      expect(
        PopularCitiesData.all.length,
        equals(PopularCitiesData.domestic.length +
            PopularCitiesData.international.length),
      );
    });

    test('toCityInfo converts correctly', () {
      final beijing = PopularCitiesData.domestic.firstWhere(
        (c) => c.name == '北京',
      );
      final cityInfo = beijing.toCityInfo();

      expect(cityInfo, isA<CityInfo>());
      expect(cityInfo.name, equals('北京'));
      expect(cityInfo.country, equals('中国'));
      expect(cityInfo.province, equals('北京市'));
      expect(cityInfo.lat, equals(39.9042));
      expect(cityInfo.lon, equals(116.4074));
      expect(cityInfo.fullName, contains('北京'));
    });

    test('matches performs fuzzy keyword and pinyin matching', () {
      final beijing = PopularCitiesData.domestic.firstWhere(
        (c) => c.name == '北京',
      );
      expect(beijing.matches('北京'), isTrue);
      expect(beijing.matches('beijing'), isTrue);
      expect(beijing.matches('bj'), isTrue);
      expect(beijing.matches('PEKING'), isTrue);
      expect(beijing.matches('shanghai'), isFalse);
    });

    test('search returns matching cities instantly', () {
      final resultsZh = PopularCitiesData.search('上海');
      expect(resultsZh.any((c) => c.name == '上海'), isTrue);

      final resultsEn = PopularCitiesData.search('Tokyo');
      expect(resultsEn.any((c) => c.name == '东京'), isTrue);

      final resultsPinyin = PopularCitiesData.search('sz');
      expect(
          resultsPinyin.any((c) => c.name == '深圳' || c.name == '苏州'), isTrue);

      final emptyResults = PopularCitiesData.search('');
      expect(emptyResults, isEmpty);

      final unknownResults = PopularCitiesData.search('NonExistentCityXYZ123');
      expect(unknownResults, isEmpty);
    });
  });

  group('CityInfo equality', () {
    test('identifies matching city info objects', () {
      final cityA = CityInfo(
        name: '北京',
        fullName: '中国, 北京市, 北京',
        lat: 39.9042,
        lon: 116.4074,
        country: '中国',
        province: '北京市',
      );
      final cityB = CityInfo(
        name: '北京',
        fullName: '中国, 北京市, 北京',
        lat: 39.9042,
        lon: 116.4074,
        country: '中国',
        province: '北京市',
      );
      final cityC = CityInfo(
        name: '上海',
        fullName: '中国, 上海市, 上海',
        lat: 31.2304,
        lon: 121.4737,
        country: '中国',
        province: '上海市',
      );

      expect(cityA, equals(cityB));
      expect(cityA.hashCode, equals(cityB.hashCode));
      expect(cityA, isNot(equals(cityC)));
    });
  });
}
