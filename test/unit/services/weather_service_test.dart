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
      // Verify cache loading was bypassed
      verifyNever(mockCacheManager.loadWeatherData(
        latitude: anyNamed('latitude'),
        longitude: anyNamed('longitude'),
      ));

      // Verify network API was called
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
  });
}
