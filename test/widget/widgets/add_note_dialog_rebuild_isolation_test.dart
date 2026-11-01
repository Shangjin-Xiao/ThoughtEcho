import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:provider/provider.dart';
import 'package:thoughtecho/controllers/add_note_controller.dart';
import 'package:thoughtecho/gen_l10n/app_localizations.dart';
import 'package:thoughtecho/models/app_settings.dart';
import 'package:thoughtecho/models/local_ai_settings.dart';
import 'package:thoughtecho/models/note_tag.dart';
import 'package:thoughtecho/models/quote_model.dart';
import 'package:thoughtecho/services/database_service.dart';
import 'package:thoughtecho/services/feature_guide_service.dart';
import 'package:thoughtecho/services/location_service.dart';
import 'package:thoughtecho/services/settings_service.dart';
import 'package:thoughtecho/services/weather_service.dart';
import 'package:thoughtecho/widgets/add_note_dialog.dart';

import '../../test_harness.dart';

class FakeBuildContext extends Fake implements BuildContext {}

Position _testPosition() => Position(
      longitude: 116.4074,
      latitude: 39.9042,
      timestamp: DateTime(2026, 1, 1),
      accuracy: 0.0,
      altitude: 0.0,
      altitudeAccuracy: 0.0,
      heading: 0.0,
      headingAccuracy: 0.0,
      speed: 0.0,
      speedAccuracy: 0.0,
    );

class _MockLocationService extends ChangeNotifier implements LocationService {
  Position? _position = _testPosition();
  String _formattedLocation = '北京市朝阳区';
  String? _poiName;

  @override
  bool get hasLocationPermission => true;

  @override
  bool get isLocationServiceEnabled => true;

  @override
  Position? get currentPosition => _position;

  @override
  String? get currentPoiName => _poiName;

  @override
  Future<Position?> getCurrentLocation({
    bool highAccuracy = false,
    bool skipPermissionRequest = false,
  }) async {
    _position = _testPosition();
    return _position;
  }

  @override
  String? currentLocaleCode;

  @override
  void setCoordinates(double lat, double lng, {String? address}) {
    _position = Position(
      latitude: lat,
      longitude: lng,
      timestamp: DateTime(2026, 1, 1),
      accuracy: 0.0,
      altitude: 0.0,
      altitudeAccuracy: 0.0,
      heading: 0.0,
      headingAccuracy: 0.0,
      speed: 0.0,
      speedAccuracy: 0.0,
    );
  }

  @override
  Future<void> getAddressFromLatLng() async {
    _formattedLocation = '北京市海淀区';
  }

  @override
  String getFormattedLocation() => _formattedLocation;

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _MockWeatherService extends ChangeNotifier implements WeatherService {
  final String _weather = '晴';
  final String _temperature = '22°C';
  final bool _hasData = true;

  @override
  bool get hasData => _hasData;

  @override
  String get currentWeather => _weather;

  @override
  String get temperature => _temperature;

  @override
  String getFormattedWeather(AppLocalizations l10n) =>
      '$_weather $_temperature';

  @override
  IconData getWeatherIconData() => Icons.wb_sunny;

  @override
  Future<void> getWeatherData(
    double latitude,
    double longitude, {
    bool forceRefresh = false,
    Duration? timeout,
  }) async {}

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _MockSettingsService extends ChangeNotifier implements SettingsService {
  @override
  bool get autoAttachLocation => false;

  @override
  bool get autoAttachWeather => false;

  @override
  String? get defaultAuthor => null;

  @override
  String? get defaultSource => null;

  @override
  List<String> get defaultTagIds => const [];

  @override
  AppSettings get appSettings => AppSettings(developerMode: false);

  @override
  bool get enableFirstOpenScrollPerfMonitor => false;

  @override
  LocalAISettings get localAISettings => const LocalAISettings();

  @override
  bool get addNoteDialogDeferAutoMetadata => false;

  @override
  bool get addNoteDialogAutoFocus => false;

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _MockDatabaseService extends ChangeNotifier implements DatabaseService {
  @override
  Future<Quote?> getQuoteById(String id, {bool includeDeleted = false}) async =>
      null;

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _MockFeatureGuideService extends ChangeNotifier
    implements FeatureGuideService {
  @override
  bool hasShown(String guideId) => true;

  @override
  bool hasShownAll(List<String> guideIds) => true;

  @override
  bool hasShownAny(List<String> guideIds) => true;

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Widget _wrapWithLocalizations({
  required Widget child,
  LocationService? locationService,
  WeatherService? weatherService,
}) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<LocationService>.value(
        value: locationService ?? _MockLocationService(),
      ),
      ChangeNotifierProvider<WeatherService>.value(
        value: weatherService ?? _MockWeatherService(),
      ),
      ChangeNotifierProvider<SettingsService>.value(
        value: _MockSettingsService(),
      ),
      ChangeNotifierProvider<DatabaseService>.value(
        value: _MockDatabaseService(),
      ),
      ChangeNotifierProvider<FeatureGuideService>.value(
        value: _MockFeatureGuideService(),
      ),
    ],
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('zh'),
      home: Scaffold(body: Center(child: child)),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await TestHarness.initialize();
  });

  group('LocationChipWidget direct tests', () {
    testWidgets('rebuilds only itself when controller metadata changes',
        (tester) async {
      final controller = AddNoteController(context: FakeBuildContext());
      int parentBuildCount = 0;

      await tester.pumpWidget(
        _wrapWithLocalizations(
          child: StatefulBuilder(
            builder: (context, setState) {
              parentBuildCount++;
              return LocationChipWidget(
                controller: controller,
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(parentBuildCount, equals(1));
      expect(
        tester
            .widget<FilterChip>(
                find.byKey(const ValueKey('add_note_location_chip')))
            .selected,
        isFalse,
      );

      // Mutate controller directly:
      controller.includeLocation = true;
      controller.setNewLocationData('北京市海淀区', 39.9, 116.4);
      await tester.pump();

      // Parent build count must remain 1 (no parent rebuild)
      expect(parentBuildCount, equals(1));
      expect(
        tester
            .widget<FilterChip>(
                find.byKey(const ValueKey('add_note_location_chip')))
            .selected,
        isTrue,
      );

      controller.dispose();
    });

    testWidgets('shows loading spinner when fetching location or updating',
        (tester) async {
      final controller = AddNoteController(context: FakeBuildContext());
      final isUpdatingLocationNotifier = ValueNotifier<bool>(false);

      await tester.pumpWidget(
        _wrapWithLocalizations(
          child: LocationChipWidget(
            controller: controller,
            isUpdatingLocation: isUpdatingLocationNotifier,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Initially no spinner
      expect(find.byType(CircularProgressIndicator), findsNothing);

      // Set fetching location on controller
      controller.isFetchingLocation = true;
      controller.notifyListeners();
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      controller.isFetchingLocation = false;
      controller.notifyListeners();
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsNothing);

      // Set isUpdatingLocationNotifier
      isUpdatingLocationNotifier.value = true;
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      isUpdatingLocationNotifier.dispose();
      controller.dispose();
    });

    testWidgets(
        'shows red dot indicator when only coordinates exist without address',
        (tester) async {
      final controller = AddNoteController(context: FakeBuildContext());

      await tester.pumpWidget(
        _wrapWithLocalizations(
          child: LocationChipWidget(
            controller: controller,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Initially no red dot Container with circle shape
      final redDotFinder = find.byWidgetPredicate((widget) {
        if (widget is Container && widget.decoration is BoxDecoration) {
          final box = widget.decoration as BoxDecoration;
          return box.shape == BoxShape.circle &&
              widget.constraints?.maxWidth == 8;
        }
        return false;
      });
      expect(redDotFinder, findsNothing);

      // Set coordinate only
      controller.includeLocation = true;
      controller.setNewLocationData(null, 39.9042, 116.4074);
      await tester.pump();

      expect(redDotFinder, findsOneWidget);

      // Provide address -> red dot disappears
      controller.setNewLocationData('北京市朝阳区', 39.9042, 116.4074);
      await tester.pump();

      expect(redDotFinder, findsNothing);

      controller.dispose();
    });

    testWidgets('long press triggers onOpenNearbyPicker in create mode',
        (tester) async {
      final controller = AddNoteController(context: FakeBuildContext());
      bool nearbyPickerTriggered = false;

      await tester.pumpWidget(
        _wrapWithLocalizations(
          child: LocationChipWidget(
            controller: controller,
            onOpenNearbyPicker: () async {
              nearbyPickerTriggered = true;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester
          .longPress(find.byKey(const ValueKey('add_note_location_chip')));
      await tester.pumpAndSettle();

      expect(nearbyPickerTriggered, isTrue);

      controller.dispose();
    });

    testWidgets('long press triggers onShowLocationDialog in edit mode',
        (tester) async {
      final controller = AddNoteController(context: FakeBuildContext());
      bool locationDialogTriggered = false;
      final quote = Quote(
        id: '1',
        content: 'test',
        date: DateTime(2026, 1, 1).toIso8601String(),
        location: '北京市',
        latitude: 39.9,
        longitude: 116.4,
      );

      await tester.pumpWidget(
        _wrapWithLocalizations(
          child: LocationChipWidget(
            controller: controller,
            initialQuote: quote,
            onShowLocationDialog: () async {
              locationDialogTriggered = true;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester
          .longPress(find.byKey(const ValueKey('add_note_location_chip')));
      await tester.pumpAndSettle();

      expect(locationDialogTriggered, isTrue);

      controller.dispose();
    });
  });

  group('WeatherChipWidget direct tests', () {
    testWidgets(
        'rebuilds only itself when weather changes without parent rebuild',
        (tester) async {
      final controller = AddNoteController(context: FakeBuildContext());
      final mockWeather = _MockWeatherService();
      int parentBuildCount = 0;

      await tester.pumpWidget(
        _wrapWithLocalizations(
          weatherService: mockWeather,
          child: StatefulBuilder(
            builder: (context, setState) {
              parentBuildCount++;
              return WeatherChipWidget(
                controller: controller,
                getWeatherService: () => mockWeather,
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(parentBuildCount, equals(1));
      expect(
        tester
            .widget<FilterChip>(
                find.byKey(const ValueKey('add_note_weather_chip')))
            .selected,
        isFalse,
      );

      // Toggle weather selection
      controller.includeWeather = true;
      controller.notifyListeners();
      await tester.pump();

      expect(parentBuildCount, equals(1));
      expect(
        tester
            .widget<FilterChip>(
                find.byKey(const ValueKey('add_note_weather_chip')))
            .selected,
        isTrue,
      );

      controller.dispose();
    });
  });

  group('AddNoteDialog full dialog rebuild isolation', () {
    testWidgets(
        'metadata change does not rebuild dialog body or recreate content field',
        (tester) async {
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<SettingsService>.value(
              value: _MockSettingsService(),
            ),
            ChangeNotifierProvider<LocationService>.value(
              value: _MockLocationService(),
            ),
            ChangeNotifierProvider<WeatherService>.value(
              value: _MockWeatherService(),
            ),
            ChangeNotifierProvider<DatabaseService>.value(
              value: _MockDatabaseService(),
            ),
            ChangeNotifierProvider<FeatureGuideService>.value(
              value: _MockFeatureGuideService(),
            ),
          ],
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: const Locale('zh'),
            home: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () => showDialog<void>(
                    context: context,
                    builder: (_) => Dialog(
                      child: AddNoteDialog(
                        tags: const [],
                        prefilledContent: 'Initial note content',
                        onSave: (quote) {},
                      ),
                    ),
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      const contentFieldKey = ValueKey('add_note_content_field');
      final contentFieldBefore =
          tester.widget<TextField>(find.byKey(contentFieldKey));

      // Click location chip
      final locationChip = find.byKey(const ValueKey('add_note_location_chip'));
      await tester.tap(locationChip);
      await tester.pump(const Duration(milliseconds: 250));

      final contentFieldAfter =
          tester.widget<TextField>(find.byKey(contentFieldKey));

      // The dialog body should be cached and preserved identical
      expect(
        identical(contentFieldBefore, contentFieldAfter),
        isTrue,
        reason:
            'Content field was recreated, indicating a full dialog rebuild occurred',
      );
    });

    testWidgets(
        'tag selection does not rebuild dialog body or recreate content field',
        (tester) async {
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<SettingsService>.value(
              value: _MockSettingsService(),
            ),
            ChangeNotifierProvider<LocationService>.value(
              value: _MockLocationService(),
            ),
            ChangeNotifierProvider<WeatherService>.value(
              value: _MockWeatherService(),
            ),
            ChangeNotifierProvider<DatabaseService>.value(
              value: _MockDatabaseService(),
            ),
            ChangeNotifierProvider<FeatureGuideService>.value(
              value: _MockFeatureGuideService(),
            ),
          ],
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: const Locale('zh'),
            home: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () => showDialog<void>(
                    context: context,
                    builder: (_) => Dialog(
                      child: AddNoteDialog(
                        tags: [
                          NoteTag(id: 'tag_1', name: 'Work', isDefault: false),
                        ],
                        prefilledContent: 'Initial note content',
                        onSave: (quote) {},
                      ),
                    ),
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      const contentFieldKey = ValueKey('add_note_content_field');
      final contentFieldBefore =
          tester.widget<TextField>(find.byKey(contentFieldKey));

      // Expand tags
      await tester.tap(find.byType(ExpansionTile));
      await tester.pumpAndSettle();

      // Select tag checkbox item
      final tagFinder = find.text('Work');
      expect(tagFinder, findsOneWidget);
      await tester.tap(tagFinder);
      await tester.pump();

      final contentFieldAfter =
          tester.widget<TextField>(find.byKey(contentFieldKey));

      expect(
        identical(contentFieldBefore, contentFieldAfter),
        isTrue,
        reason: 'Selecting tag caused full dialog rebuild',
      );
    });

    testWidgets(
        'weather selection does not rebuild dialog body or recreate content field',
        (tester) async {
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<SettingsService>.value(
              value: _MockSettingsService(),
            ),
            ChangeNotifierProvider<LocationService>.value(
              value: _MockLocationService(),
            ),
            ChangeNotifierProvider<WeatherService>.value(
              value: _MockWeatherService(),
            ),
            ChangeNotifierProvider<DatabaseService>.value(
              value: _MockDatabaseService(),
            ),
            ChangeNotifierProvider<FeatureGuideService>.value(
              value: _MockFeatureGuideService(),
            ),
          ],
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: const Locale('zh'),
            home: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () => showDialog<void>(
                    context: context,
                    builder: (_) => Dialog(
                      child: AddNoteDialog(
                        tags: const [],
                        prefilledContent: 'Initial note content',
                        onSave: (quote) {},
                      ),
                    ),
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      const contentFieldKey = ValueKey('add_note_content_field');
      final contentFieldBefore =
          tester.widget<TextField>(find.byKey(contentFieldKey));

      final weatherChip = find.byKey(const ValueKey('add_note_weather_chip'));
      await tester.tap(weatherChip);
      await tester.pump(const Duration(milliseconds: 100));

      final contentFieldAfter =
          tester.widget<TextField>(find.byKey(contentFieldKey));

      expect(
        identical(contentFieldBefore, contentFieldAfter),
        isTrue,
        reason: 'Selecting weather caused full dialog rebuild',
      );
    });

    testWidgets(
        'renders and captures screenshot of AddNoteDialog with location and weather chips',
        (tester) async {
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<SettingsService>.value(
              value: _MockSettingsService(),
            ),
            ChangeNotifierProvider<LocationService>.value(
              value: _MockLocationService(),
            ),
            ChangeNotifierProvider<WeatherService>.value(
              value: _MockWeatherService(),
            ),
            ChangeNotifierProvider<DatabaseService>.value(
              value: _MockDatabaseService(),
            ),
            ChangeNotifierProvider<FeatureGuideService>.value(
              value: _MockFeatureGuideService(),
            ),
          ],
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: const Locale('zh'),
            home: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () => showDialog<void>(
                    context: context,
                    builder: (_) => Dialog(
                      child: AddNoteDialog(
                        tags: const [],
                        prefilledContent: '快捷记事弹窗隔离重绘测试',
                        onSave: (quote) {},
                      ),
                    ),
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.byType(LocationChipWidget), findsOneWidget);
      expect(find.byType(WeatherChipWidget), findsOneWidget);

      final renderObject =
          find.byType(RepaintBoundary).first.evaluate().single.renderObject!;
      final layer = renderObject.debugLayer! as OffsetLayer;
      await tester.runAsync(() async {
        final image =
            await layer.toImage(renderObject.paintBounds, pixelRatio: 2.0);
        final png = await image.toByteData(format: ui.ImageByteFormat.png);
        image.dispose();
        if (png != null) {
          File('/tmp/location_weather_chips.png')
              .writeAsBytesSync(png.buffer.asUint8List());
        }
      });
    });
  });
}
