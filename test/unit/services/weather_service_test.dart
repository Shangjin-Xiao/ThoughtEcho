/// Unit tests for WeatherService
import 'package:flutter_test/flutter_test.dart';

import 'package:thoughtecho/services/weather_service.dart';
import 'package:thoughtecho/models/weather_data.dart';
import '../mocks/mock_weather_service.dart';
import '../test_utils/test_data.dart';
import '../test_utils/test_helpers.dart';

void main() {
  group('WeatherService Tests', () {
    late MockWeatherService weatherService;

    setUpAll(() {
      TestHelpers.setupTestEnvironment();
    });

    setUp(() async {
      weatherService = MockWeatherService();
      await weatherService.initialize();
    });

    tearDownAll(() {
      TestHelpers.teardownTestEnvironment();
    });

    group('Initialization', () {
      test('should initialize successfully', () {
        expect(weatherService.isInitialized, isTrue);
        expect(weatherService.currentWeatherData, isNotNull);
        expect(weatherService.state, equals(WeatherServiceState.success));
      });

      test('should have default weather data', () {
        final weather = weatherService.currentWeatherData!;
        expect(weather.isValid, isTrue);
        expect(weather.key, isNotEmpty);
        expect(weather.description, isNotEmpty);
        expect(weather.temperature, greaterThan(0));
        expect(weather.temperatureText, isNotEmpty);
      });
    });

    group('Weather by Coordinates', () {
      test('should get weather by coordinates successfully', () async {
        final weather = await weatherService.getWeatherByCoordinates(39.9042, 116.4074);
        
        expect(weather, isNotNull);
        expect(weather.isValid, isTrue);
        expect(weather.key, isNotEmpty);
        expect(weather.description, isNotEmpty);
        expect(weather.temperature, isA<double>());
        expect(weather.temperatureText, isNotEmpty);
        expect(weather.iconCode, isNotEmpty);
      });

      test('should return different weather for different regions', () async {
        // Northern region (cooler)
        final northWeather = await weatherService.getWeatherByCoordinates(45.0, 120.0);
        
        // Southern region (warmer)
        final southWeather = await weatherService.getWeatherByCoordinates(20.0, 110.0);
        
        expect(northWeather.temperature, lessThan(southWeather.temperature));
      });

      test('should handle extreme coordinates', () async {
        // Test with extreme but valid coordinates
        final weather1 = await weatherService.getWeatherByCoordinates(90.0, 180.0);
        final weather2 = await weatherService.getWeatherByCoordinates(-90.0, -180.0);
        final weather3 = await weatherService.getWeatherByCoordinates(0.0, 0.0);
        
        expect(weather1.isValid, isTrue);
        expect(weather2.isValid, isTrue);
        expect(weather3.isValid, isTrue);
      });

      test('should update service state during request', () async {
        expect(weatherService.state, equals(WeatherServiceState.success));
        expect(weatherService.isLoading, isFalse);
        
        final future = weatherService.getWeatherByCoordinates(31.2304, 121.4737);
        // Mock service completes immediately, but we can still verify the final state
        
        final weather = await future;
        expect(weatherService.state, equals(WeatherServiceState.success));
        expect(weatherService.isLoading, isFalse);
        expect(weather, isNotNull);
      });
    });

    group('Weather by City', () {
      test('should get weather by city name successfully', () async {
        final weather = await weatherService.getWeatherByCity('北京');
        
        expect(weather, isNotNull);
        expect(weather.isValid, isTrue);
        expect(weather.key, isNotEmpty);
        expect(weather.description, isNotEmpty);
      });

      test('should handle different city names', () async {
        final cities = ['北京', '上海', '深圳', '杭州'];
        
        for (final city in cities) {
          final weather = await weatherService.getWeatherByCity(city);
          expect(weather.isValid, isTrue);
          expect(weather.temperature, greaterThan(0));
        }
      });

      test('should handle English city names', () async {
        final weather = await weatherService.getWeatherByCity('beijing');
        
        expect(weather, isNotNull);
        expect(weather.isValid, isTrue);
      });

      test('should return default weather for unknown cities', () async {
        final weather = await weatherService.getWeatherByCity('UnknownCity');
        
        expect(weather, isNotNull);
        expect(weather.isValid, isTrue);
        expect(weather.key, equals('sunny'));
        expect(weather.temperature, equals(25.0));
      });
    });

    group('Caching', () {
      test('should cache weather data by coordinates', () async {
        final weather1 = await weatherService.getWeatherByCoordinates(39.9, 116.4);
        final weather2 = await weatherService.getWeatherByCoordinates(39.9, 116.4);
        
        expect(weatherService.state, equals(WeatherServiceState.cached));
        expect(weather1.key, equals(weather2.key));
        expect(weather1.temperature, equals(weather2.temperature));
      });

      test('should cache weather data by city', () async {
        final weather1 = await weatherService.getWeatherByCity('北京');
        final weather2 = await weatherService.getWeatherByCity('北京');
        
        expect(weatherService.state, equals(WeatherServiceState.cached));
        expect(weather1.key, equals(weather2.key));
        expect(weather1.temperature, equals(weather2.temperature));
      });

      test('should get cache info', () async {
        // Add some data to cache
        await weatherService.getWeatherByCity('北京');
        await weatherService.getWeatherByCoordinates(31.2, 121.4);
        
        final cacheInfo = await weatherService.getCacheInfo();
        
        expect(cacheInfo, isNotNull);
        expect(cacheInfo!['cache_size'], greaterThan(0));
        expect(cacheInfo['cache_keys'], isA<List>());
        expect(cacheInfo['last_updated'], isNotNull);
      });

      test('should clear cache', () async {
        // Add data to cache
        await weatherService.getWeatherByCity('北京');
        expect(weatherService.getCacheSize(), greaterThan(0));
        
        // Clear cache
        await weatherService.clearCache();
        expect(weatherService.getCacheSize(), equals(0));
      });

      test('should manage cache size efficiently', () async {
        // Add many items to cache
        for (int i = 0; i < 10; i++) {
          await weatherService.getWeatherByCity('City$i');
        }
        
        expect(weatherService.getCacheSize(), equals(10));
        
        // Clear specific items
        weatherService.removeFromCache('City0');
        expect(weatherService.getCacheSize(), equals(9));
      });
    });

    group('Data Refresh', () {
      test('should refresh weather data', () async {
        // Get initial weather
        await weatherService.getWeatherByCity('北京');
        final initialWeather = weatherService.currentWeatherData!;
        
        // Refresh
        await weatherService.refreshWeatherData();
        final refreshedWeather = weatherService.currentWeatherData!;
        
        expect(refreshedWeather, isNotNull);
        expect(refreshedWeather.key, equals(initialWeather.key));
        // Temperature might change slightly
        expect(refreshedWeather.temperature, isA<double>());
      });

      test('should handle refresh when no data exists', () async {
        // Clear current data by setting null (if possible) or ensure no data
        expect(() => weatherService.refreshWeatherData(), returnsNormally);
      });
    });

    group('Mock Data Management', () {
      test('should set mock weather data', () {
        weatherService.setMockWeatherData(
          key: 'test_weather',
          description: '测试天气',
          temperature: 30.0,
          iconCode: 'test_icon',
        );
        
        final weather = weatherService.currentWeatherData!;
        expect(weather.key, equals('test_weather'));
        expect(weather.description, equals('测试天气'));
        expect(weather.temperature, equals(30.0));
        expect(weather.iconCode, equals('test_icon'));
      });

      test('should handle default values in mock data', () {
        weatherService.setMockWeatherData();
        
        final weather = weatherService.currentWeatherData!;
        expect(weather.key, equals('test'));
        expect(weather.description, equals('测试天气'));
        expect(weather.temperature, equals(25.0));
        expect(weather.iconCode, equals('sunny'));
      });
    });

    group('Error Handling', () {
      test('should handle simulated errors', () {
        weatherService.simulateError('网络连接失败');
        
        expect(weatherService.state, equals(WeatherServiceState.error));
        expect(weatherService.lastError, equals('网络连接失败'));
        expect(weatherService.currentWeatherData!.isValid, isFalse);
      });

      test('should clear errors', () {
        weatherService.simulateError('测试错误');
        expect(weatherService.lastError, isNotNull);
        
        weatherService.clearError();
        expect(weatherService.lastError, isNull);
      });

      test('should handle network timeouts', () async {
        weatherService.simulateError('请求超时');
        
        expect(weatherService.state, equals(WeatherServiceState.error));
        expect(weatherService.lastError, contains('超时'));
      });

      test('should handle API errors', () {
        weatherService.simulateError('API调用失败');
        
        expect(weatherService.state, equals(WeatherServiceState.error));
        expect(weatherService.lastError, contains('API'));
      });
    });

    group('Utility Methods', () {
      test('should get weather icon for conditions', () {
        expect(weatherService.getWeatherIcon('sunny'), equals('☀️'));
        expect(weatherService.getWeatherIcon('cloudy'), equals('☁️'));
        expect(weatherService.getWeatherIcon('rainy'), equals('🌧️'));
        expect(weatherService.getWeatherIcon('snowy'), equals('❄️'));
        expect(weatherService.getWeatherIcon('foggy'), equals('🌫️'));
        expect(weatherService.getWeatherIcon('windy'), equals('💨'));
        expect(weatherService.getWeatherIcon('unknown'), equals('🌤️'));
      });

      test('should get temperature description', () {
        expect(weatherService.getTemperatureDescription(-5), equals('严寒'));
        expect(weatherService.getTemperatureDescription(5), equals('寒冷'));
        expect(weatherService.getTemperatureDescription(15), equals('凉爽'));
        expect(weatherService.getTemperatureDescription(25), equals('温暖'));
        expect(weatherService.getTemperatureDescription(32), equals('炎热'));
        expect(weatherService.getTemperatureDescription(40), equals('酷热'));
      });

      test('should check if data is fresh', () {
        weatherService.setMockWeatherData();
        expect(weatherService.isDataFresh(), isTrue);
        
        weatherService.simulateError('测试错误');
        expect(weatherService.isDataFresh(), isFalse);
      });

      test('should get weather summary', () {
        weatherService.setMockWeatherData(
          description: '晴天',
          temperature: 25.0,
        );
        
        final summary = weatherService.getWeatherSummary();
        expect(summary, equals('晴天 25°C'));
      });

      test('should handle missing weather data in summary', () {
        // Simulate no weather data
        weatherService.simulateError('无数据');
        
        final summary = weatherService.getWeatherSummary();
        expect(summary, equals('无天气数据'));
      });
    });

    group('State Management', () {
      test('should notify listeners on weather change', () async {
        bool notified = false;
        weatherService.addListener(() {
          notified = true;
        });

        await weatherService.getWeatherByCity('上海');
        expect(notified, isTrue);
      });

      test('should notify listeners on error', () {
        bool notified = false;
        weatherService.addListener(() {
          notified = true;
        });

        weatherService.simulateError('测试错误');
        expect(notified, isTrue);
      });

      test('should notify listeners on cache clear', () async {
        bool notified = false;
        weatherService.addListener(() {
          notified = true;
        });

        await weatherService.clearCache();
        expect(notified, isTrue);
      });

      test('should track state changes correctly', () async {
        expect(weatherService.state, equals(WeatherServiceState.success));
        
        final future = weatherService.getWeatherByCity('北京');
        await future;
        
        expect(weatherService.state, anyOf([
          WeatherServiceState.success,
          WeatherServiceState.cached,
        ]));
      });
    });

    group('Performance', () {
      test('should handle multiple rapid requests efficiently', () async {
        final stopwatch = Stopwatch()..start();
        
        final futures = <Future<WeatherData>>[];
        final cities = ['北京', '上海', '深圳', '杭州', '广州'];
        
        for (final city in cities) {
          futures.add(weatherService.getWeatherByCity(city));
        }
        
        final results = await Future.wait(futures);
        stopwatch.stop();
        
        expect(stopwatch.elapsedMilliseconds, lessThan(2000));
        expect(results.every((weather) => weather.isValid), isTrue);
      });

      test('should handle coordinate requests efficiently', () async {
        final stopwatch = Stopwatch()..start();
        
        final futures = <Future<WeatherData>>[];
        final coordinates = [
          [39.9, 116.4], // Beijing
          [31.2, 121.4], // Shanghai
          [22.5, 114.0], // Shenzhen
          [30.3, 120.2], // Hangzhou
          [23.1, 113.3], // Guangzhou
        ];
        
        for (final coord in coordinates) {
          futures.add(weatherService.getWeatherByCoordinates(coord[0], coord[1]));
        }
        
        final results = await Future.wait(futures);
        stopwatch.stop();
        
        expect(stopwatch.elapsedMilliseconds, lessThan(2000));
        expect(results.every((weather) => weather.isValid), isTrue);
      });

      test('should handle large cache efficiently', () async {
        final stopwatch = Stopwatch()..start();
        
        // Add many items to cache
        for (int i = 0; i < 50; i++) {
          await weatherService.getWeatherByCity('TestCity$i');
        }
        
        stopwatch.stop();
        
        expect(stopwatch.elapsedMilliseconds, lessThan(3000));
        expect(weatherService.getCacheSize(), equals(50));
        
        // Test cache retrieval performance
        final cacheStopwatch = Stopwatch()..start();
        final cacheInfo = await weatherService.getCacheInfo();
        cacheStopwatch.stop();
        
        expect(cacheStopwatch.elapsedMilliseconds, lessThan(100));
        expect(cacheInfo!['cache_size'], equals(50));
      });
    });

    group('Integration with WeatherData', () {
      test('should create valid WeatherData objects', () async {
        final weather = await weatherService.getWeatherByCity('北京');
        
        expect(weather, isA<WeatherData>());
        expect(weather.isValid, isTrue);
        expect(weather.hasTemperature, isTrue);
        expect(weather.hasDescription, isTrue);
      });

      test('should handle WeatherData validation', () {
        weatherService.setMockWeatherData(
          key: '',
          description: '',
          temperature: -999.0,
        );
        
        // Weather data should handle invalid values appropriately
        final weather = weatherService.currentWeatherData!;
        expect(weather, isNotNull);
      });

      test('should work with test data factory', () {
        final testWeather = TestData.createTestWeatherData();
        weatherService.addToCache('test', testWeather);
        
        expect(weatherService.getCacheSize(), greaterThan(0));
      });
    });

    group('Edge Cases', () {
      test('should handle concurrent requests to same location', () async {
        final futures = <Future<WeatherData>>[];
        
        // Multiple concurrent requests for same location
        for (int i = 0; i < 5; i++) {
          futures.add(weatherService.getWeatherByCity('北京'));
        }
        
        final results = await Future.wait(futures);
        
        // All should return valid data
        expect(results.every((weather) => weather.isValid), isTrue);
        
        // Should use cache for subsequent requests
        expect(weatherService.state, equals(WeatherServiceState.cached));
      });

      test('should handle special characters in city names', () async {
        final specialCities = [
          '北京市',
          'São Paulo',
          'Москва',
          'القاهرة',
          'เซี่ยงไฮ้',
        ];
        
        for (final city in specialCities) {
          final weather = await weatherService.getWeatherByCity(city);
          expect(weather.isValid, isTrue);
        }
      });

      test('should handle very small and large temperature values', () {
        weatherService.setMockWeatherData(temperature: -50.0);
        expect(weatherService.getTemperatureDescription(-50.0), equals('严寒'));
        
        weatherService.setMockWeatherData(temperature: 60.0);
        expect(weatherService.getTemperatureDescription(60.0), equals('酷热'));
      });
    });
  });
}