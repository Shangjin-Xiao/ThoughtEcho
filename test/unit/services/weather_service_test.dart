/// Basic unit tests for WeatherService
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
    });

    test('should validate coordinates', () {
      // Valid coordinates
      expect(() => weatherService.validateCoordinates(37.7749, -122.4194), returnsNormally);
      
      // Invalid coordinates
      expect(() => weatherService.validateCoordinates(100.0, -200.0), throwsA(isA<Exception>()));
    });
  });
}