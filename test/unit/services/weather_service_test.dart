/// Basic unit tests for WeatherService
library;

import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';

import 'package:thoughtecho/services/weather_service.dart';
import 'package:thoughtecho/services/network_service.dart';
import 'package:thoughtecho/services/weather_cache_manager.dart';
import 'package:thoughtecho/models/weather_data.dart';
import 'package:thoughtecho/utils/http_response.dart';

class MockNetworkService extends Mock implements NetworkService {
  @override
  Future<HttpResponse> get(String? url,
      {Map<String, String>? headers,
      Map<String, dynamic>? queryParameters,
      int? timeoutSeconds}) {
    return super.noSuchMethod(
      Invocation.method(
        #get,
        [url],
        {
          #headers: headers,
          #queryParameters: queryParameters,
          #timeoutSeconds: timeoutSeconds
        },
      ),
      returnValue: Future.value(HttpResponse('{}', 200, headers: {})),
    );
  }
}

class MockWeatherCacheManager extends Mock implements WeatherCacheManager {
  @override
  Future<void> initialize() {
    return super.noSuchMethod(
      Invocation.method(#initialize, []),
      returnValue: Future.value(),
    );
  }

  @override
  Future<WeatherData?> loadWeatherData(
      {double? latitude, double? longitude, Duration? maxAge}) {
    return super.noSuchMethod(
      Invocation.method(#loadWeatherData, [],
          {#latitude: latitude, #longitude: longitude, #maxAge: maxAge}),
      returnValue: Future.value(null),
    );
  }

  @override
  Future<void> saveWeatherData(WeatherData? weatherData) {
    return super.noSuchMethod(
      Invocation.method(#saveWeatherData, [weatherData]),
      returnValue: Future.value(),
    );
  }

  @override
  Future<WeatherData?> loadWeatherDataIgnoreExpiry(
      {double? latitude, double? longitude}) {
    return super.noSuchMethod(
      Invocation.method(#loadWeatherDataIgnoreExpiry, [],
          {#latitude: latitude, #longitude: longitude}),
      returnValue: Future.value(null),
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('WeatherService Tests', () {
    late WeatherService weatherService;
    late MockNetworkService mockNetworkService;
    late MockWeatherCacheManager mockCacheManager;

    setUp(() {
      mockNetworkService = MockNetworkService();
      mockCacheManager = MockWeatherCacheManager();

      NetworkService.instanceForTesting = mockNetworkService;

      weatherService = WeatherService()
        ..cacheManagerForTesting = mockCacheManager;
    });

    tearDown(() {
      NetworkService.instanceForTesting = null;
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

    test('refreshWeather should bypass cache and fetch from API directly',
        () async {
      // Arrange
      const latitude = 39.9042;
      const longitude = 116.4074;

      when(mockCacheManager.initialize()).thenAnswer((_) async => {});

      final mockApiResponse = {
        'current': {
          'temperature_2m': 20.5,
          'weather_code': 0, // Clear sky
          'wind_speed_10m': 5.0,
        }
      };

      when(mockNetworkService.get(
        any,
        timeoutSeconds: anyNamed('timeoutSeconds'),
      )).thenAnswer((_) async => HttpResponse(
            json.encode(mockApiResponse),
            200,
            headers: {},
          ));

      when(mockCacheManager.saveWeatherData(any)).thenAnswer((_) async => {});

      // Act
      await weatherService.refreshWeather(latitude, longitude);

      // Assert
      // Verify cache loading was bypassed by checking interactions with CacheManager
      verifyNever(mockCacheManager.loadWeatherData(
        latitude: anyNamed('latitude'),
        longitude: anyNamed('longitude'),
      ));

      // Verify network API was called directly by checking interactions with NetworkService
      verify(mockNetworkService.get(
        argThat(contains('latitude=$latitude')),
        timeoutSeconds: anyNamed('timeoutSeconds'),
      )).called(1);

      // Verify the new data was saved to cache
      verify(mockCacheManager.saveWeatherData(any)).called(1);

      // Verify state was updated
      expect(weatherService.state, equals(WeatherServiceState.success));
      expect(weatherService.hasData, isTrue);
      expect(weatherService.temperatureValue, equals(20.5));
    });

    test('getWeatherData with forceRefresh=true should bypass cache', () async {
      // Arrange
      const latitude = 31.2304;
      const longitude = 121.4737;

      when(mockCacheManager.initialize()).thenAnswer((_) async => {});

      final mockApiResponse = {
        'current': {
          'temperature_2m': 15.0,
          'weather_code': 3, // Overcast
          'wind_speed_10m': 3.0,
        }
      };

      when(mockNetworkService.get(
        any,
        timeoutSeconds: anyNamed('timeoutSeconds'),
      )).thenAnswer((_) async => HttpResponse(
            json.encode(mockApiResponse),
            200,
            headers: {},
          ));

      when(mockCacheManager.saveWeatherData(any)).thenAnswer((_) async => {});

      // Act
      await weatherService.getWeatherData(latitude, longitude,
          forceRefresh: true);

      // Assert
      // Cache reading bypassed
      verifyNever(mockCacheManager.loadWeatherData(
        latitude: anyNamed('latitude'),
        longitude: anyNamed('longitude'),
      ));

      // Network accessed
      verify(mockNetworkService.get(
        any,
        timeoutSeconds: anyNamed('timeoutSeconds'),
      )).called(1);

      // New data saved
      verify(mockCacheManager.saveWeatherData(any)).called(1);

      expect(weatherService.state, equals(WeatherServiceState.success));
      expect(weatherService.hasData, isTrue);
      expect(weatherService.temperatureValue, equals(15.0));
    });

    test(
        'refreshWeather should handle API failure and fallback to expired cache',
        () async {
      // Arrange
      const latitude = 39.9042;
      const longitude = 116.4074;

      when(mockCacheManager.initialize()).thenAnswer((_) async => {});

      // Simulate API failure
      when(mockNetworkService.get(
        any,
        timeoutSeconds: anyNamed('timeoutSeconds'),
      )).thenAnswer((_) async => HttpResponse('', 500, headers: {}));

      final expiredMockData = WeatherData(
        key: 'partly_cloudy',
        description: 'Partly Cloudy',
        temperature: 15.0,
        temperatureText: '15°C',
        iconCode: '02d',
        timestamp: DateTime.now().subtract(const Duration(days: 1)),
        latitude: latitude,
        longitude: longitude,
      );

      when(mockCacheManager.loadWeatherDataIgnoreExpiry(
        latitude: anyNamed('latitude'),
        longitude: anyNamed('longitude'),
      )).thenAnswer((_) async => expiredMockData);

      // Act
      await weatherService.refreshWeather(latitude, longitude);

      // Assert
      // Verify cache loading was bypassed initially
      verifyNever(mockCacheManager.loadWeatherData(
        latitude: anyNamed('latitude'),
        longitude: anyNamed('longitude'),
      ));

      // Verify network API was called
      verify(mockNetworkService.get(
        argThat(contains('latitude=$latitude')),
        timeoutSeconds: anyNamed('timeoutSeconds'),
      )).called(1);

      // Verify fallback to expired cache
      verify(mockCacheManager.loadWeatherDataIgnoreExpiry(
        latitude: latitude,
        longitude: longitude,
      )).called(1);

      // Verify state was updated to cached with expired data
      expect(weatherService.state, equals(WeatherServiceState.cached));
      expect(weatherService.hasData, isTrue);
      expect(weatherService.temperatureValue, equals(15.0));
      expect(weatherService.lastError, isNotNull);
    });

    test(
        'refreshWeather should enter error state on malformed API response (missing current)',
        () async {
      // Arrange
      const latitude = 39.9042;
      const longitude = 116.4074;

      when(mockCacheManager.initialize()).thenAnswer((_) async => {});

      // Simulate API success but malformed response
      when(mockNetworkService.get(
        any,
        timeoutSeconds: anyNamed('timeoutSeconds'),
      )).thenAnswer((_) async =>
          HttpResponse('{"other_key": "no_current_here"}', 200, headers: {}));

      // In case fallback is triggered, return null (no cache)
      when(mockCacheManager.loadWeatherDataIgnoreExpiry(
        latitude: anyNamed('latitude'),
        longitude: anyNamed('longitude'),
      )).thenAnswer((_) async => null);

      // Act
      await weatherService.refreshWeather(latitude, longitude);

      // Assert
      // Because we returned null from cache, state will be error.
      expect(weatherService.state, equals(WeatherServiceState.error));
      expect(weatherService.hasData, isFalse);
      expect(weatherService.lastError, contains('API响应格式错误: 缺少 current 数据'));
    });
  });
}
