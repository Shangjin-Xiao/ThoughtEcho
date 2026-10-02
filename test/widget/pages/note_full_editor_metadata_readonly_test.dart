import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:thoughtecho/gen_l10n/app_localizations.dart';
import 'package:thoughtecho/models/app_settings.dart';
import 'package:thoughtecho/models/quote_model.dart';
import 'package:thoughtecho/pages/note_full_editor_page.dart';
import 'package:thoughtecho/services/database_service.dart';
import 'package:thoughtecho/services/draft_service.dart';
import 'package:thoughtecho/services/feature_guide_service.dart';
import 'package:thoughtecho/services/location_service.dart';
import 'package:thoughtecho/services/mmkv_service.dart';
import 'package:thoughtecho/services/settings_service.dart';
import 'package:thoughtecho/services/unified_log_service.dart';
import 'package:thoughtecho/services/weather_service.dart';
import 'package:thoughtecho/utils/mmkv_ffi_fix.dart';

import '../../test_harness.dart';

class _TestSettingsService extends ChangeNotifier implements SettingsService {
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
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _TestLocationService extends ChangeNotifier implements LocationService {
  @override
  bool get hasLocationPermission => true;

  @override
  bool get isLocationServiceEnabled => true;

  @override
  String? get currentPoiName => null;

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _TestWeatherService extends ChangeNotifier implements WeatherService {
  @override
  bool get hasData => true;

  @override
  String get currentWeather => 'Sunny';

  @override
  String getFormattedWeather(AppLocalizations l10n) => 'Sunny 25°C';

  @override
  IconData getWeatherIconData() => Icons.wb_sunny;

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _TestDatabaseService extends ChangeNotifier implements DatabaseService {
  _TestDatabaseService({required this.fullQuote});

  final Quote fullQuote;

  @override
  Future<Quote?> getQuoteById(String id, {bool includeDeleted = false}) async {
    return fullQuote;
  }

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _TestFeatureGuideService extends FeatureGuideService {
  _TestFeatureGuideService() : super(SafeMMKV());

  @override
  bool hasShown(String guideId) => true;

  @override
  Future<void> markAsShown(String guideId) async {}

  @override
  Future<void> resetGuide(String guideId) async {}

  @override
  Future<void> resetAllGuides() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late DraftService draftService;
  late MMKVService mmkvService;

  setUpAll(() async {
    await TestHarness.initialize();
    await MMKVService().init();
  });

  setUp(() async {
    draftService = DraftService();
    mmkvService = MMKVService();
    await mmkvService.clear();
  });

  tearDown(() {
    UnifiedLogService.instance.dispose();
  });

  testWidgets(
      'NoteFullEditorPage allows removing location and weather in edit mode',
      (WidgetTester tester) async {
    final initialQuote = Quote(
      id: 'full-editor-test-123',
      content: 'Full editor test content',
      date: DateTime.now().toIso8601String(),
      location: 'Beijing, China',
      latitude: 39.9,
      longitude: 116.4,
      weather: 'Sunny',
      temperature: '25°C',
    );

    final mockSettings = _TestSettingsService();
    final mockLocation = _TestLocationService();
    final mockWeather = _TestWeatherService();
    final mockDatabase = _TestDatabaseService(fullQuote: initialQuote);
    final mockGuide = _TestFeatureGuideService();

    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<SettingsService>.value(value: mockSettings),
          ChangeNotifierProvider<LocationService>.value(value: mockLocation),
          ChangeNotifierProvider<WeatherService>.value(value: mockWeather),
          ChangeNotifierProvider<DatabaseService>.value(value: mockDatabase),
          ChangeNotifierProvider<FeatureGuideService>.value(value: mockGuide),
          Provider<DraftService>.value(value: draftService),
        ],
        child: MaterialApp(
          localizationsDelegates: const [
            ...AppLocalizations.localizationsDelegates,
            FlutterQuillLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('zh'),
          home: NoteFullEditorPage(
            initialContent: initialQuote.content,
            initialQuote: initialQuote,
            allTags: const [],
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    // Tap metadata icon on AppBar to open bottom sheet
    final metadataButton = find.byIcon(Icons.edit_note);
    expect(metadataButton, findsOneWidget);
    await tester.tap(metadataButton);
    await tester.pumpAndSettle();

    // Verify location and weather chips are initially selected
    final locationChip =
        find.byKey(const ValueKey('full_editor_location_chip'));
    final weatherChip = find.byKey(const ValueKey('full_editor_weather_chip'));

    expect(locationChip, findsOneWidget);
    expect(weatherChip, findsOneWidget);

    expect(tester.widget<FilterChip>(locationChip).selected, isTrue);
    expect(tester.widget<FilterChip>(weatherChip).selected, isTrue);

    // Tap location chip to show dialog
    await tester.ensureVisible(locationChip);
    await tester.tap(locationChip);
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.text('位置信息'), findsOneWidget);

    // Tap Cancel
    await tester.tap(find.descendant(
      of: find.byType(AlertDialog),
      matching: find.text('取消'),
    ));
    await tester.pumpAndSettle();
    expect(tester.widget<FilterChip>(locationChip).selected, isTrue);

    // Tap location chip again and remove it
    await tester.ensureVisible(locationChip);
    await tester.tap(locationChip);
    await tester.pumpAndSettle();
    await tester.tap(find.descendant(
      of: find.byType(AlertDialog),
      matching: find.text('移除'),
    ));
    await tester.pumpAndSettle();
    expect(tester.widget<FilterChip>(locationChip).selected, isFalse);

    // Tap weather chip to show dialog
    await tester.ensureVisible(weatherChip);
    await tester.tap(weatherChip);
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.text('天气信息'), findsOneWidget);

    // Tap Cancel
    await tester.tap(find.descendant(
      of: find.byType(AlertDialog),
      matching: find.text('取消'),
    ));
    await tester.pumpAndSettle();
    expect(tester.widget<FilterChip>(weatherChip).selected, isTrue);

    // Tap weather chip again and remove it
    await tester.ensureVisible(weatherChip);
    await tester.tap(weatherChip);
    await tester.pumpAndSettle();
    await tester.tap(find.descendant(
      of: find.byType(AlertDialog),
      matching: find.text('移除'),
    ));
    await tester.pumpAndSettle();
    expect(tester.widget<FilterChip>(weatherChip).selected, isFalse);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 600));
  });
}
