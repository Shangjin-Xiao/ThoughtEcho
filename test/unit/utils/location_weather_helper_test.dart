import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart' show Position;
import 'package:mockito/mockito.dart';
import 'package:thoughtecho/services/location_service.dart';
import 'package:thoughtecho/utils/location_weather_helper.dart';

class MockLocationService extends Mock implements LocationService {
  @override
  bool get hasLocationPermission {
    return super.noSuchMethod(
      Invocation.getter(#hasLocationPermission),
      returnValue: false,
    );
  }

  @override
  Future<bool> requestLocationPermission() {
    return super.noSuchMethod(
      Invocation.method(#requestLocationPermission, []),
      returnValue: Future.value(false),
    );
  }

  @override
  Future<Position?> getCurrentLocation({
    bool highAccuracy = false,
    bool skipPermissionRequest = false,
  }) {
    return super.noSuchMethod(
      Invocation.method(#getCurrentLocation, [], {
        #highAccuracy: highAccuracy,
        #skipPermissionRequest: skipPermissionRequest,
      }),
      returnValue: Future.value(null),
    );
  }

  @override
  String getFormattedLocation() {
    return super.noSuchMethod(
      Invocation.method(#getFormattedLocation, []),
      returnValue: '',
    );
  }
}

void main() {
  group('LocationSnapshot Tests', () {
    test('should create LocationSnapshot instance', () {
      final mockPosition = Position(
        longitude: 116.4074,
        latitude: 39.9042,
        timestamp: DateTime.now(),
        accuracy: 0.0,
        altitude: 0.0,
        altitudeAccuracy: 0.0,
        heading: 0.0,
        headingAccuracy: 0.0,
        speed: 0.0,
        speedAccuracy: 0.0,
      );

      final snapshot = LocationSnapshot(
        position: mockPosition,
        location: '北京市',
      );

      expect(snapshot.position, equals(mockPosition));
      expect(snapshot.location, equals('北京市'));
    });
  });

  group('LocationWeatherHelper Tests', () {
    late MockLocationService mockLocationService;

    setUp(() {
      mockLocationService = MockLocationService();
    });

    group('ensureLocationPermission', () {
      test('should return true if already has permission', () async {
        when(mockLocationService.hasLocationPermission).thenReturn(true);

        final result = await LocationWeatherHelper.ensureLocationPermission(
          mockLocationService,
        );

        expect(result, isTrue);
        verifyNever(mockLocationService.requestLocationPermission());
      });

      test('should request permission if not already granted', () async {
        when(mockLocationService.hasLocationPermission).thenReturn(false);
        when(mockLocationService.requestLocationPermission())
            .thenAnswer((_) async => true);

        final result = await LocationWeatherHelper.ensureLocationPermission(
          mockLocationService,
        );

        expect(result, isTrue);
        verify(mockLocationService.requestLocationPermission()).called(1);
      });

      test('should return false if request is denied', () async {
        when(mockLocationService.hasLocationPermission).thenReturn(false);
        when(mockLocationService.requestLocationPermission())
            .thenAnswer((_) async => false);

        final result = await LocationWeatherHelper.ensureLocationPermission(
          mockLocationService,
        );

        expect(result, isFalse);
        verify(mockLocationService.requestLocationPermission()).called(1);
      });
    });

    group('fetchLocation', () {
      test('should return null if position is null', () async {
        when(mockLocationService.getCurrentLocation())
            .thenAnswer((_) async => null);

        final result = await LocationWeatherHelper.fetchLocation(
          mockLocationService,
        );

        expect(result, isNull);
        verifyNever(mockLocationService.getFormattedLocation());
      });

      test('should return LocationSnapshot if position is available', () async {
        final mockPosition = Position(
          longitude: 121.4737,
          latitude: 31.2304,
          timestamp: DateTime.now(),
          accuracy: 0.0,
          altitude: 0.0,
          altitudeAccuracy: 0.0,
          heading: 0.0,
          headingAccuracy: 0.0,
          speed: 0.0,
          speedAccuracy: 0.0,
        );
        const mockFormattedLocation = '上海市';

        when(mockLocationService.getCurrentLocation())
            .thenAnswer((_) async => mockPosition);
        when(mockLocationService.getFormattedLocation())
            .thenReturn(mockFormattedLocation);

        final result = await LocationWeatherHelper.fetchLocation(
          mockLocationService,
        );

        expect(result, isNotNull);
        expect(result!.position, equals(mockPosition));
        expect(result.location, equals(mockFormattedLocation));
      });
    });
  });
}
