import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/models/weather_data.dart';

void main() {
  group('WeatherCodeMapper.getKeyByDescription', () {
    test('returns correct key for known description', () {
      // Despite the method comment "通过中文描述反查天气key", the actual _keyToDescription
      // values are English keys mapped to themselves (e.g. 'clear': 'clear').
      expect(WeatherCodeMapper.getKeyByDescription('clear'), 'clear');
      expect(WeatherCodeMapper.getKeyByDescription('partly_cloudy'),
          'partly_cloudy');
      expect(WeatherCodeMapper.getKeyByDescription('thunderstorm_heavy'),
          'thunderstorm_heavy');
    });

    test('returns null for unknown description', () {
      expect(
          WeatherCodeMapper.getKeyByDescription('unknown_description'), isNull);
      expect(WeatherCodeMapper.getKeyByDescription(''), isNull);
    });
  });
}
