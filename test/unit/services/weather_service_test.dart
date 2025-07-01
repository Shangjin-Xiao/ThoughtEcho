/// Basic unit tests for WeatherService
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/services/weather_service.dart';

void main() {
  group('WeatherService Tests', () {
    late WeatherService weatherService;

    setUp(() {
      weatherService = WeatherService();
    });

    test('should create WeatherService instance', () {
      expect(weatherService, isNotNull);
      expect(weatherService.state, equals(WeatherServiceState.idle));
    });

    test('should handle weather service states', () {
      expect(weatherService.state, equals(WeatherServiceState.idle));
      expect(weatherService.isLoading, isFalse);
      expect(weatherService.hasData, isFalse);
    });
  });
}
