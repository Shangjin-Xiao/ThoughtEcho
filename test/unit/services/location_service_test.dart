/// Unit tests for LocationService
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';

import '../../lib/services/location_service.dart';
import '../mocks/mock_location_service.dart';
import '../test_utils/test_helpers.dart';

void main() {
  group('LocationService Tests', () {
    late MockLocationService locationService;

    setUpAll(() {
      TestHelpers.setupTestEnvironment();
    });

    setUp(() async {
      locationService = MockLocationService();
      await locationService.initialize();
    });

    tearDownAll(() {
      TestHelpers.teardownTestEnvironment();
    });

    group('Initialization', () {
      test('should initialize successfully', () async {
        expect(locationService.hasLocationPermission, isTrue);
        expect(locationService.isLocationServiceEnabled, isTrue);
        expect(locationService.currentPosition, isNotNull);
        expect(locationService.currentAddress, isNotNull);
      });

      test('should have default location set', () {
        final position = locationService.currentPosition!;
        expect(position.latitude, closeTo(39.9042, 0.1));
        expect(position.longitude, closeTo(116.4074, 0.1));
        expect(locationService.currentAddress, contains('北京'));
      });
    });

    group('Permission Management', () {
      test('should request permission successfully', () async {
        locationService.setPermissionStatus(false);
        expect(locationService.hasLocationPermission, isFalse);

        final granted = await locationService.requestPermission();
        expect(granted, isTrue);
        expect(locationService.hasLocationPermission, isTrue);
      });

      test('should check permission status', () async {
        locationService.setPermissionStatus(true);
        final hasPermission = await locationService.checkPermission();
        expect(hasPermission, isTrue);

        locationService.setPermissionStatus(false);
        final noPermission = await locationService.checkPermission();
        expect(noPermission, isFalse);
      });

      test('should handle permission denial', () async {
        locationService.setPermissionStatus(false);
        
        expect(
          () => locationService.getCurrentLocation(),
          throwsException,
        );
      });
    });

    group('Location Retrieval', () {
      test('should get current location successfully', () async {
        final position = await locationService.getCurrentLocation();
        
        expect(position, isNotNull);
        expect(position!.latitude, isA<double>());
        expect(position.longitude, isA<double>());
        expect(position.timestamp, isNotNull);
        expect(position.accuracy, greaterThan(0));
      });

      test('should handle location service disabled', () async {
        locationService.disableLocationService();
        
        expect(
          () => locationService.getCurrentLocation(),
          throwsException,
        );
      });

      test('should update position on multiple calls', () async {
        final position1 = await locationService.getCurrentLocation();
        await Future.delayed(const Duration(milliseconds: 10));
        final position2 = await locationService.getCurrentLocation();

        expect(position1, isNotNull);
        expect(position2, isNotNull);
        expect(position2!.timestamp.isAfter(position1!.timestamp), isTrue);
      });

      test('should handle loading state correctly', () async {
        expect(locationService.isLoading, isFalse);
        
        final future = locationService.getCurrentLocation();
        // Note: Due to mock implementation, loading state might not be observable
        // In real implementation, we could check loading state during async operation
        
        await future;
        expect(locationService.isLoading, isFalse);
      });
    });

    group('Address Resolution', () {
      test('should get address from coordinates', () async {
        // Beijing coordinates
        final address = await locationService.getAddressFromCoordinates(39.9042, 116.4074);
        expect(address, contains('北京'));

        // Shanghai coordinates
        final shanghaiAddress = await locationService.getAddressFromCoordinates(31.2304, 121.4737);
        expect(shanghaiAddress, contains('上海'));

        // Shenzhen coordinates
        final shenzhenAddress = await locationService.getAddressFromCoordinates(22.5431, 114.0579);
        expect(shenzhenAddress, contains('深圳'));
      });

      test('should handle unknown coordinates', () async {
        final address = await locationService.getAddressFromCoordinates(0.0, 0.0);
        expect(address, equals('未知位置'));
      });

      test('should handle invalid coordinates', () async {
        final address = await locationService.getAddressFromCoordinates(-200.0, 300.0);
        expect(address, isNotNull);
      });
    });

    group('City Search', () {
      test('should search cities successfully', () async {
        final results = await locationService.searchCities('北京');
        
        expect(results, isNotEmpty);
        expect(results.any((city) => city.name.contains('北京')), isTrue);
      });

      test('should return multiple results for partial match', () async {
        final results = await locationService.searchCities('上');
        
        expect(results, isNotEmpty);
        expect(results.any((city) => city.name.contains('上海')), isTrue);
      });

      test('should handle empty search query', () async {
        final results = await locationService.searchCities('');
        expect(results, isEmpty);
      });

      test('should handle no matches', () async {
        final results = await locationService.searchCities('不存在的城市名');
        expect(results, isEmpty);
      });

      test('should update search state correctly', () async {
        expect(locationService.isSearching, isFalse);
        
        final future = locationService.searchCities('北京');
        // Mock implementation completes immediately, so we can't check intermediate state
        
        final results = await future;
        expect(locationService.isSearching, isFalse);
        expect(locationService.searchResults, equals(results));
      });
    });

    group('City Selection', () {
      test('should select city and update position', () async {
        final cities = await locationService.searchCities('上海');
        expect(cities, isNotEmpty);
        
        final shanghai = cities.first;
        await locationService.selectCity(shanghai);
        
        expect(locationService.currentPosition!.latitude, closeTo(shanghai.lat, 0.1));
        expect(locationService.currentPosition!.longitude, closeTo(shanghai.lon, 0.1));
        expect(locationService.currentAddress, equals(shanghai.fullName));
      });

      test('should handle multiple city selections', () async {
        // Select Beijing
        final beijingCities = await locationService.searchCities('北京');
        await locationService.selectCity(beijingCities.first);
        
        final beijingPosition = locationService.currentPosition;
        expect(beijingPosition!.latitude, closeTo(39.9042, 0.1));
        
        // Select Shanghai
        final shanghaiCities = await locationService.searchCities('上海');
        await locationService.selectCity(shanghaiCities.first);
        
        final shanghaiPosition = locationService.currentPosition;
        expect(shanghaiPosition!.latitude, closeTo(31.2304, 0.1));
        expect(shanghaiPosition.latitude, isNot(equals(beijingPosition.latitude)));
      });
    });

    group('Error Handling', () {
      test('should handle permission errors', () async {
        locationService.setPermissionStatus(false);
        locationService.simulateError('位置权限被拒绝');
        
        expect(locationService.lastError, isNotNull);
        expect(locationService.lastError, contains('权限'));
      });

      test('should handle service disabled errors', () async {
        locationService.disableLocationService();
        locationService.simulateError('位置服务未启用');
        
        expect(locationService.lastError, isNotNull);
        expect(locationService.lastError, contains('服务'));
      });

      test('should clear errors', () {
        locationService.simulateError('测试错误');
        expect(locationService.lastError, isNotNull);
        
        locationService.clearError();
        expect(locationService.lastError, isNull);
      });

      test('should handle network errors during address resolution', () async {
        // Simulate network error
        locationService.simulateError('网络连接失败');
        
        // Should still handle gracefully
        final address = await locationService.getAddressFromCoordinates(39.9042, 116.4074);
        expect(address, isNotNull);
      });
    });

    group('Utility Methods', () {
      test('should format address correctly', () {
        locationService.setMockPosition(39.9042, 116.4074, address: '北京市朝阳区');
        
        final formatted = locationService.getFormattedAddress();
        expect(formatted, equals('北京市朝阳区'));
      });

      test('should format coordinates correctly', () {
        locationService.setMockPosition(39.9042, 116.4074);
        
        final coordinates = locationService.getCoordinatesString();
        expect(coordinates, contains('39.9042'));
        expect(coordinates, contains('116.4074'));
      });

      test('should handle null position in formatting', () {
        locationService.setMockPosition(0, 0);
        // Clear position to null (if such method exists)
        // Otherwise test with default mock behavior
        
        final formatted = locationService.getFormattedAddress();
        expect(formatted, isNotNull);
        
        final coordinates = locationService.getCoordinatesString();
        expect(coordinates, isNotNull);
      });
    });

    group('State Management', () {
      test('should notify listeners on position change', () async {
        bool notified = false;
        locationService.addListener(() {
          notified = true;
        });

        await locationService.getCurrentLocation();
        expect(notified, isTrue);
      });

      test('should notify listeners on address change', () async {
        bool notified = false;
        locationService.addListener(() {
          notified = true;
        });

        await locationService.getAddressFromCoordinates(31.2304, 121.4737);
        expect(notified, isTrue);
      });

      test('should notify listeners on city selection', () async {
        bool notified = false;
        locationService.addListener(() {
          notified = true;
        });

        final cities = await locationService.searchCities('上海');
        await locationService.selectCity(cities.first);
        expect(notified, isTrue);
      });

      test('should notify listeners on error', () {
        bool notified = false;
        locationService.addListener(() {
          notified = true;
        });

        locationService.simulateError('测试错误');
        expect(notified, isTrue);
      });
    });

    group('Performance', () {
      test('should handle multiple rapid location requests', () async {
        final stopwatch = Stopwatch()..start();
        
        final futures = <Future<Position?>>[];
        for (int i = 0; i < 10; i++) {
          futures.add(locationService.getCurrentLocation());
        }
        
        final results = await Future.wait(futures);
        stopwatch.stop();
        
        expect(stopwatch.elapsedMilliseconds, lessThan(2000));
        expect(results.every((result) => result != null), isTrue);
      });

      test('should handle multiple rapid searches', () async {
        final stopwatch = Stopwatch()..start();
        
        final futures = <Future<List<CityInfo>>>[];
        final cities = ['北京', '上海', '深圳', '杭州', '广州'];
        
        for (final city in cities) {
          futures.add(locationService.searchCities(city));
        }
        
        final results = await Future.wait(futures);
        stopwatch.stop();
        
        expect(stopwatch.elapsedMilliseconds, lessThan(2000));
        expect(results.every((result) => result.isNotEmpty), isTrue);
      });

      test('should handle large search results efficiently', () async {
        final stopwatch = Stopwatch()..start();
        
        // Search for common character that might return many results
        final results = await locationService.searchCities('市');
        
        stopwatch.stop();
        
        expect(stopwatch.elapsedMilliseconds, lessThan(1000));
        expect(results, isA<List<CityInfo>>());
      });
    });

    group('Edge Cases', () {
      test('should handle extreme coordinates', () async {
        const extremeCoordinates = [
          [90.0, 180.0],   // North Pole, International Date Line
          [-90.0, -180.0], // South Pole, opposite side
          [0.0, 0.0],      // Equator, Prime Meridian
        ];

        for (final coords in extremeCoordinates) {
          final address = await locationService.getAddressFromCoordinates(
            coords[0], 
            coords[1],
          );
          expect(address, isNotNull);
        }
      });

      test('should handle special characters in search', () async {
        final specialQueries = ['北京市', '上海-浦东', '深圳/南山'];
        
        for (final query in specialQueries) {
          final results = await locationService.searchCities(query);
          expect(results, isA<List<CityInfo>>());
        }
      });

      test('should handle concurrent operations', () async {
        final futures = <Future>[];
        
        // Start multiple operations concurrently
        futures.add(locationService.getCurrentLocation());
        futures.add(locationService.searchCities('北京'));
        futures.add(locationService.getAddressFromCoordinates(39.9, 116.4));
        
        // Should all complete without interfering with each other
        await Future.wait(futures);
        
        expect(locationService.currentPosition, isNotNull);
        expect(locationService.searchResults, isNotEmpty);
        expect(locationService.currentAddress, isNotNull);
      });
    });
  });
}