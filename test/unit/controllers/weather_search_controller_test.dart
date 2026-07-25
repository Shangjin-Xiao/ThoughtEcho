import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';

import 'package:thoughtecho/controllers/weather_search_controller.dart';
import 'package:thoughtecho/services/location_service.dart';
import 'package:thoughtecho/services/weather_service.dart';
import 'package:geolocator/geolocator.dart';
import 'package:thoughtecho/gen_l10n/app_localizations.dart';

// Since Mockito 5.4.1, trying to generate mocks for methods that return final classes (like IconData in flutter)
// will result in invalid_use_of_type_outside_library error in flutter analyze.
// However WeatherSearchController does not use getWeatherIconData, so we can just mock manually or use a custom Mock
class MockLocationService extends Mock implements LocationService {
  @override
  bool get hasLocationPermission => super.noSuchMethod(
        Invocation.getter(#hasLocationPermission),
        returnValue: false,
      ) as bool;

  @override
  String get city => super.noSuchMethod(
        Invocation.getter(#city),
        returnValue: '',
      ) as String;

  @override
  Position? get currentPosition => super.noSuchMethod(
        Invocation.getter(#currentPosition),
      ) as Position?;

  @override
  Future<void> setSelectedCity(CityInfo? cityInfo) => super.noSuchMethod(
        Invocation.method(#setSelectedCity, [cityInfo]),
        returnValue: Future<void>.value(),
      ) as Future<void>;

  @override
  Future<Position?> getCurrentLocation({
    bool highAccuracy = false,
    bool skipPermissionRequest = false,
  }) =>
      super.noSuchMethod(
        Invocation.method(
          #getCurrentLocation,
          [],
          {
            #highAccuracy: highAccuracy,
            #skipPermissionRequest: skipPermissionRequest,
          },
        ),
        returnValue: Future<Position?>.value(),
      ) as Future<Position?>;
}

class MockWeatherService extends Mock implements WeatherService {
  @override
  bool get hasValidWeatherData => super.noSuchMethod(
        Invocation.getter(#hasValidWeatherData),
        returnValue: false,
      ) as bool;

  @override
  Future<void> getWeatherData(double? lat, double? lon,
          {bool forceRefresh = false, Duration? timeout}) =>
      super.noSuchMethod(
        Invocation.method(
          #getWeatherData,
          [lat, lon],
          {#forceRefresh: forceRefresh, #timeout: timeout},
        ),
        returnValue: Future<void>.value(),
      ) as Future<void>;
}

class FakeAppLocalizations implements AppLocalizations {
  @override
  String citySelectedWeatherUpdated(String cityName) =>
      'citySelectedWeatherUpdated:$cityName';
  @override
  String citySelectionError(String error) => 'citySelectionError:$error';
  @override
  String currentLocationWeatherUpdated(String cityName) =>
      'currentLocationWeatherUpdated:$cityName';
  @override
  String locationFetchError(String error) => 'locationFetchError:$error';
  @override
  String get weatherTimeoutRetry => 'weatherTimeoutRetry';
  @override
  String get weatherFetchFailedCheckNetwork => 'weatherFetchFailedCheckNetwork';
  @override
  String get locationTimeoutCheckPermission => 'locationTimeoutCheckPermission';
  @override
  String get cannotGetCurrentLocation => 'cannotGetCurrentLocation';
  @override
  String get cannotGetSelectedCityLocation => 'cannotGetSelectedCityLocation';
  @override
  String get currentLocationLabel => 'currentLocationLabel';

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late WeatherSearchController controller;
  late MockLocationService mockLocationService;
  late MockWeatherService mockWeatherService;
  late FakeAppLocalizations l10n;

  setUp(() {
    mockLocationService = MockLocationService();
    mockWeatherService = MockWeatherService();
    controller =
        WeatherSearchController(mockLocationService, mockWeatherService);
    l10n = FakeAppLocalizations();
  });

  group('WeatherSearchController', () {
    test('initial state is correct', () {
      expect(controller.isLoading, isFalse);
      expect(controller.lastResult, isNull);
    });

    test('clearMessages resets lastResult', () async {
      when(mockLocationService.currentPosition).thenReturn(null);
      when(mockLocationService.setSelectedCity(any)).thenAnswer((_) async {});

      final cityInfo = CityInfo(
          name: 'TestCity',
          fullName: 'TestCity, TestCountry',
          lat: 0.0,
          lon: 0.0,
          country: 'TestCountry',
          province: 'TestProvince');

      await controller.selectCityAndUpdateWeather(cityInfo);

      expect(controller.lastResult, isNotNull);

      controller.clearMessages();

      expect(controller.lastResult, isNull);
    });

    group('selectCityAndUpdateWeather', () {
      final cityInfo = CityInfo(
          name: 'TestCity',
          fullName: 'TestCity, TestCountry',
          lat: 0.0,
          lon: 0.0,
          country: 'TestCountry',
          province: 'TestProvince');

      test('returns false when position is null', () async {
        when(mockLocationService.setSelectedCity(any)).thenAnswer((_) async {});
        when(mockLocationService.currentPosition).thenReturn(null);

        final result = await controller.selectCityAndUpdateWeather(cityInfo);

        expect(result, isFalse);
        expect(controller.lastResult?.type,
            WeatherSearchResultType.cityLocationNotFound);
        expect(controller.lastResult?.isSuccess, isFalse);
        expect(controller.lastResult?.getLocalizedMessage(l10n),
            'cannotGetSelectedCityLocation');
      });

      test('returns false on weather fetch timeout', () async {
        final position = Position(
          longitude: 0.0,
          latitude: 0.0,
          timestamp: DateTime.now(),
          accuracy: 0.0,
          altitude: 0.0,
          altitudeAccuracy: 0.0,
          heading: 0.0,
          headingAccuracy: 0.0,
          speed: 0.0,
          speedAccuracy: 0.0,
        );

        when(mockLocationService.setSelectedCity(any)).thenAnswer((_) async {});
        when(mockLocationService.currentPosition).thenReturn(position);
        when(mockWeatherService.getWeatherData(any, any))
            .thenThrow(TimeoutException('Weather fetch timeout'));

        final result = await controller.selectCityAndUpdateWeather(cityInfo);

        expect(result, isFalse);
        expect(controller.lastResult?.type,
            WeatherSearchResultType.weatherTimeout);
        expect(controller.lastResult?.isSuccess, isFalse);
        expect(controller.lastResult?.getLocalizedMessage(l10n),
            'weatherTimeoutRetry');
      });

      test('returns false when weather fetch fails', () async {
        final position = Position(
          longitude: 0.0,
          latitude: 0.0,
          timestamp: DateTime.now(),
          accuracy: 0.0,
          altitude: 0.0,
          altitudeAccuracy: 0.0,
          heading: 0.0,
          headingAccuracy: 0.0,
          speed: 0.0,
          speedAccuracy: 0.0,
        );

        when(mockLocationService.setSelectedCity(any)).thenAnswer((_) async {});
        when(mockLocationService.currentPosition).thenReturn(position);
        when(mockWeatherService.getWeatherData(any, any))
            .thenAnswer((_) async {});
        when(mockWeatherService.hasValidWeatherData).thenReturn(false);

        final result = await controller.selectCityAndUpdateWeather(cityInfo);

        expect(result, isFalse);
        expect(controller.lastResult?.type,
            WeatherSearchResultType.weatherFetchFailed);
        expect(controller.lastResult?.isSuccess, isFalse);
        expect(controller.lastResult?.getLocalizedMessage(l10n),
            'weatherFetchFailedCheckNetwork');
      });

      test('returns true on success', () async {
        final position = Position(
          longitude: 0.0,
          latitude: 0.0,
          timestamp: DateTime.now(),
          accuracy: 0.0,
          altitude: 0.0,
          altitudeAccuracy: 0.0,
          heading: 0.0,
          headingAccuracy: 0.0,
          speed: 0.0,
          speedAccuracy: 0.0,
        );

        when(mockLocationService.setSelectedCity(any)).thenAnswer((_) async {});
        when(mockLocationService.currentPosition).thenReturn(position);
        when(mockWeatherService.getWeatherData(any, any))
            .thenAnswer((_) async {});
        when(mockWeatherService.hasValidWeatherData).thenReturn(true);

        final result = await controller.selectCityAndUpdateWeather(cityInfo);

        expect(result, isTrue);
        expect(controller.lastResult?.type,
            WeatherSearchResultType.citySelectedSuccess);
        expect(controller.lastResult?.isSuccess, isTrue);
        expect(controller.lastResult?.cityName, 'TestCity');
        expect(controller.lastResult?.getLocalizedMessage(l10n),
            'citySelectedWeatherUpdated:TestCity');
      });

      test('returns false on generic exception', () async {
        when(mockLocationService.setSelectedCity(any))
            .thenThrow(Exception('Test error'));

        final result = await controller.selectCityAndUpdateWeather(cityInfo);

        expect(result, isFalse);
        expect(controller.lastResult?.type,
            WeatherSearchResultType.citySelectionError);
        expect(controller.lastResult?.isSuccess, isFalse);
        expect(controller.lastResult?.errorDetail, contains('Test error'));
        expect(controller.lastResult?.getLocalizedMessage(l10n),
            contains('citySelectionError:Exception: Test error'));
      });
    });

    group('useCurrentLocation', () {
      test('returns false when position is null', () async {
        when(mockLocationService.getCurrentLocation())
            .thenAnswer((_) async => null);

        final result = await controller.useCurrentLocation();

        expect(result, isFalse);
        expect(controller.lastResult?.type,
            WeatherSearchResultType.locationPermissionDenied);
        expect(controller.lastResult?.isSuccess, isFalse);
        expect(controller.lastResult?.getLocalizedMessage(l10n),
            'cannotGetCurrentLocation');
      });

      test('returns false on location fetch timeout', () async {
        when(mockLocationService.getCurrentLocation())
            .thenThrow(TimeoutException('Location fetch timeout'));

        final result = await controller.useCurrentLocation();

        expect(result, isFalse);
        expect(controller.lastResult?.type,
            WeatherSearchResultType.locationTimeout);
        expect(controller.lastResult?.isSuccess, isFalse);
        expect(controller.lastResult?.getLocalizedMessage(l10n),
            'locationTimeoutCheckPermission');
      });

      test('returns false on weather fetch timeout', () async {
        final position = Position(
          longitude: 0.0,
          latitude: 0.0,
          timestamp: DateTime.now(),
          accuracy: 0.0,
          altitude: 0.0,
          altitudeAccuracy: 0.0,
          heading: 0.0,
          headingAccuracy: 0.0,
          speed: 0.0,
          speedAccuracy: 0.0,
        );

        when(mockLocationService.getCurrentLocation())
            .thenAnswer((_) async => position);
        when(mockWeatherService.getWeatherData(any, any))
            .thenThrow(TimeoutException('Weather fetch timeout'));

        final result = await controller.useCurrentLocation();

        expect(result, isFalse);
        expect(controller.lastResult?.type,
            WeatherSearchResultType.weatherTimeout);
        expect(controller.lastResult?.isSuccess, isFalse);
        expect(controller.lastResult?.getLocalizedMessage(l10n),
            'weatherTimeoutRetry');
      });

      test('returns false when weather fetch fails', () async {
        final position = Position(
          longitude: 0.0,
          latitude: 0.0,
          timestamp: DateTime.now(),
          accuracy: 0.0,
          altitude: 0.0,
          altitudeAccuracy: 0.0,
          heading: 0.0,
          headingAccuracy: 0.0,
          speed: 0.0,
          speedAccuracy: 0.0,
        );

        when(mockLocationService.getCurrentLocation())
            .thenAnswer((_) async => position);
        when(mockWeatherService.getWeatherData(any, any))
            .thenAnswer((_) async {});
        when(mockWeatherService.hasValidWeatherData).thenReturn(false);

        final result = await controller.useCurrentLocation();

        expect(result, isFalse);
        expect(controller.lastResult?.type,
            WeatherSearchResultType.weatherFetchFailed);
        expect(controller.lastResult?.isSuccess, isFalse);
        expect(controller.lastResult?.getLocalizedMessage(l10n),
            'weatherFetchFailedCheckNetwork');
      });

      test('returns true on success', () async {
        final position = Position(
          longitude: 0.0,
          latitude: 0.0,
          timestamp: DateTime.now(),
          accuracy: 0.0,
          altitude: 0.0,
          altitudeAccuracy: 0.0,
          heading: 0.0,
          headingAccuracy: 0.0,
          speed: 0.0,
          speedAccuracy: 0.0,
        );

        when(mockLocationService.getCurrentLocation())
            .thenAnswer((_) async => position);
        when(mockWeatherService.getWeatherData(any, any))
            .thenAnswer((_) async {});
        when(mockWeatherService.hasValidWeatherData).thenReturn(true);
        when(mockLocationService.city).thenReturn('CurrentCity');

        final result = await controller.useCurrentLocation();

        expect(result, isTrue);
        expect(controller.lastResult?.type,
            WeatherSearchResultType.currentLocationSuccess);
        expect(controller.lastResult?.isSuccess, isTrue);
        expect(controller.lastResult?.cityName, 'CurrentCity');
        expect(controller.lastResult?.getLocalizedMessage(l10n),
            'currentLocationWeatherUpdated:CurrentCity');
      });

      test(
          'currentLocationSuccess localized message handles null city correctly',
          () {
        final result = WeatherSearchResult(
          type: WeatherSearchResultType.currentLocationSuccess,
          isSuccess: true,
          cityName: null,
        );
        expect(result.getLocalizedMessage(l10n),
            'currentLocationWeatherUpdated:currentLocationLabel');
      });

      test('returns false on generic exception', () async {
        when(mockLocationService.getCurrentLocation())
            .thenThrow(Exception('Test location error'));

        final result = await controller.useCurrentLocation();

        expect(result, isFalse);
        expect(controller.lastResult?.type,
            WeatherSearchResultType.locationFetchError);
        expect(controller.lastResult?.isSuccess, isFalse);
        expect(controller.lastResult?.errorDetail,
            contains('Test location error'));
        expect(controller.lastResult?.getLocalizedMessage(l10n),
            contains('locationFetchError:Exception: Test location error'));
      });
    });
  });
}
