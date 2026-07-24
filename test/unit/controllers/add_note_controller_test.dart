import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:thoughtecho/controllers/add_note_controller.dart';
import 'package:thoughtecho/models/quote_model.dart';
import 'package:thoughtecho/services/location_service.dart';
import 'package:thoughtecho/services/weather_service.dart';
import 'package:thoughtecho/services/database_service.dart';

import 'add_note_controller_test.mocks.dart';

class FakeBuildContext extends Fake implements BuildContext {}

@GenerateMocks(
  [LocationService, DatabaseService],
)
@GenerateMocks(
  [],
  customMocks: [
    MockSpec<WeatherService>(
      onMissingStub: OnMissingStub.returnDefault,
    )
  ],
)
void main() {
  late MockLocationService mockLocationService;
  late MockWeatherService mockWeatherService;
  late MockDatabaseService mockDatabaseService;
  late AddNoteController controller;

  setUp(() {
    mockLocationService = MockLocationService();
    mockWeatherService = MockWeatherService();
    mockDatabaseService = MockDatabaseService();
    controller = AddNoteController(context: FakeBuildContext());
    controller.updateServices(
      locService: mockLocationService,
      weaService: mockWeatherService,
      dbService: mockDatabaseService,
    );
  });

  group('AddNoteController initial states', () {
    test('initial states are correct', () {
      expect(controller.includeLocation, isFalse);
      expect(controller.includeWeather, isFalse);
      expect(controller.isFetchingLocation, isFalse);
      expect(controller.isFetchingWeather, isFalse);
      expect(controller.isFetchingMetadata, isFalse);
      expect(controller.isLoadingHitokotoTags, isFalse);
    });

    test('initialQuote sets correct states', () {
      final quote = Quote(
        id: '1',
        content: 'test',
        date: DateTime.now().toIso8601String(),
        location: 'Test Location',
        latitude: 1.0,
        longitude: 2.0,
        weather: 'Sunny',
        temperature: '25°C',
      );

      final c = AddNoteController(
        context: FakeBuildContext(),
        initialQuote: quote,
      );

      expect(c.originalLocation, 'Test Location');
      expect(c.originalLatitude, 1.0);
      expect(c.originalLongitude, 2.0);
      expect(c.originalWeather, 'Sunny');
      expect(c.originalTemperature, '25°C');
      expect(c.includeLocation, isTrue);
      expect(c.includeWeather, isTrue);
    });
  });

  group('fetchLocationForNewNote', () {
    test('when permission denied', () async {
      when(mockLocationService.hasLocationPermission).thenReturn(false);
      when(mockLocationService.requestLocationPermission())
          .thenAnswer((_) async => false);

      bool deniedCalled = false;
      final c = AddNoteController(
        context: FakeBuildContext(),
        onLocationPermissionDenied: () => deniedCalled = true,
      )..updateServices(locService: mockLocationService);

      await c.fetchLocationForNewNote();

      expect(deniedCalled, isTrue);
      expect(c.includeLocation, isFalse);
      expect(c.isFetchingLocation, isFalse);
    });

    test('when permission granted and fetch succeeds', () async {
      when(mockLocationService.hasLocationPermission).thenReturn(true);

      final pos = Position(
        latitude: 10.0,
        longitude: 20.0,
        timestamp: DateTime.now(),
        accuracy: 0,
        altitude: 0,
        altitudeAccuracy: 0,
        heading: 0,
        headingAccuracy: 0,
        speed: 0,
        speedAccuracy: 0,
      );

      when(mockLocationService.getCurrentLocation())
          .thenAnswer((_) async => pos);
      when(mockLocationService.getFormattedLocation())
          .thenReturn('Mock Location');

      bool fetchedCalled = false;
      final c = AddNoteController(
        context: FakeBuildContext(),
        onLocationFetched: () => fetchedCalled = true,
      )..updateServices(locService: mockLocationService);

      await c.fetchLocationForNewNote();

      expect(fetchedCalled, isTrue);
      expect(c.newLatitude, 10.0);
      expect(c.newLongitude, 20.0);
      expect(c.newLocation, 'Mock Location');
      expect(c.isFetchingLocation, isFalse);
    });
  });

  group('fetchWeatherForNewNote', () {
    test('when missing coordinates', () async {
      when(mockLocationService.currentPosition).thenReturn(null);

      bool missingCoordsCalled = false;
      final c = AddNoteController(
        context: FakeBuildContext(),
        onWeatherMissingCoordinates: () => missingCoordsCalled = true,
      )..updateServices(
          locService: mockLocationService, weaService: mockWeatherService);

      await c.fetchWeatherForNewNote();

      expect(missingCoordsCalled, isTrue);
      expect(c.includeWeather, isFalse);
      expect(c.isFetchingWeather, isFalse);
    });

    test('when fetch succeeds', () async {
      final c = AddNoteController(
        context: FakeBuildContext(),
      )..updateServices(
          locService: mockLocationService, weaService: mockWeatherService);

      c.setNewLocationData('Loc', 30.0, 40.0);

      when(mockWeatherService.getWeatherData(30.0, 40.0))
          .thenAnswer((_) async {});
      when(mockWeatherService.hasData).thenReturn(true);

      await c.fetchWeatherForNewNote();

      verify(mockWeatherService.getWeatherData(30.0, 40.0)).called(1);
      expect(c.isFetchingWeather, isFalse);
    });
  });

  group('Hitokoto utility methods', () {
    test('shouldApplyHitokotoSubtypeTag', () {
      final c1 = AddNoteController(
        context: FakeBuildContext(),
        hitokotoData: {'provider': 'hitokoto'},
      );
      expect(c1.shouldApplyHitokotoSubtypeTag(), isTrue);

      final c2 = AddNoteController(
        context: FakeBuildContext(),
        hitokotoData: {'provider': 'hitokoto.cn'},
      );
      expect(c2.shouldApplyHitokotoSubtypeTag(), isFalse);

      final c3 = AddNoteController(
        context: FakeBuildContext(),
        hitokotoData: {},
      );
      expect(c3.shouldApplyHitokotoSubtypeTag(), isTrue);

      final c4 = AddNoteController(
        context: FakeBuildContext(),
        hitokotoData: null,
      );
      expect(c4.shouldApplyHitokotoSubtypeTag(), isTrue);
    });

    test('convertHitokotoTypeToTagName', () {
      expect(controller.convertHitokotoTypeToTagName('a'), '动画');
      expect(controller.convertHitokotoTypeToTagName('unknown'), '其他一言');
    });

    test('getIconForHitokotoType', () {
      expect(controller.getIconForHitokotoType('a'), '🎬');
      expect(controller.getIconForHitokotoType('unknown'), 'format_quote');
    });
  });

  group('AddNoteController metadata controls', () {
    test('setIncludeLocation updates state', () {
      controller.setIncludeLocation(true);
      expect(controller.includeLocation, isTrue);

      controller.setNewLocationData('Loc', 1.0, 2.0);
      controller.setIncludeLocation(false);
      expect(controller.includeLocation, isFalse);
      expect(controller.newLocation, isNull);
    });

    test('setIncludeWeather updates state', () {
      controller.setIncludeWeather(true);
      expect(controller.includeWeather, isTrue);
    });

    test('setOriginalLocationData updates state', () {
      controller.setOriginalLocationData('Old Loc', 3.0, 4.0);
      expect(controller.originalLocation, 'Old Loc');
      expect(controller.originalLatitude, 3.0);
      expect(controller.originalLongitude, 4.0);
    });
  });

  group('AddNoteController hydrateFromQuote', () {
    test('hydrates successfully', () {
      final quote = Quote(
        id: '1',
        content: 'content',
        date: DateTime.now().toIso8601String(),
        location: 'Hydrate Loc',
        latitude: 5.0,
        longitude: 6.0,
        weather: 'Rainy',
        temperature: '20°C',
      );

      controller.hydrateFromQuote(quote);

      expect(controller.originalLocation, 'Hydrate Loc');
      expect(controller.originalLatitude, 5.0);
      expect(controller.originalLongitude, 6.0);
      expect(controller.originalWeather, 'Rainy');
      expect(controller.originalTemperature, '20°C');
      expect(controller.includeLocation, isTrue);
      expect(controller.includeWeather, isTrue);
    });
  });

  group('AddNoteController location metadata', () {
    test('removeNewLocation clears pending coordinates before save', () {
      final controller = AddNoteController(context: FakeBuildContext())
        ..includeLocation = true
        ..setNewLocationData(null, 39.9042, 116.4074);

      controller.removeNewLocation();

      expect(controller.includeLocation, isFalse);
      expect(controller.newLocation, isNull);
      expect(controller.newLatitude, isNull);
      expect(controller.newLongitude, isNull);
    });

    test('removeOriginalLocation clears persisted coordinates before save', () {
      final controller = AddNoteController(
        context: FakeBuildContext(),
        initialQuote: Quote(
          id: 'note-1',
          content: 'content',
          date: DateTime(2026).toIso8601String(),
          location: LocationService.kAddressPending,
          latitude: 39.9042,
          longitude: 116.4074,
        ),
      );

      controller.removeOriginalLocation();

      expect(controller.includeLocation, isFalse);
      expect(controller.originalLocation, isNull);
      expect(controller.originalLatitude, isNull);
      expect(controller.originalLongitude, isNull);
    });
  });
}
