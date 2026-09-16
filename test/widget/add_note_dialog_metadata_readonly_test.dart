import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:thoughtecho/gen_l10n/app_localizations.dart';
import 'package:thoughtecho/models/app_settings.dart';
import 'package:thoughtecho/models/local_ai_settings.dart';
import 'package:thoughtecho/models/quote_model.dart';
import 'package:thoughtecho/services/database_service.dart';
import 'package:thoughtecho/services/location_service.dart';
import 'package:thoughtecho/services/settings_service.dart';
import 'package:thoughtecho/services/weather_service.dart';
import 'package:thoughtecho/services/unified_log_service.dart';
import 'package:thoughtecho/services/feature_guide_service.dart';
import 'package:thoughtecho/widgets/add_note_dialog.dart';

import '../test_harness.dart';

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
  AppSettings get appSettings => AppSettings(
        developerMode: false,
      );

  @override
  bool get enableFirstOpenScrollPerfMonitor => false;

  @override
  LocalAISettings get localAISettings => const LocalAISettings();

  @override
  bool get addNoteDialogDeferAutoMetadata => false;

  @override
  bool get addNoteDialogAutoFocus => true;

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _TestLocationService extends ChangeNotifier implements LocationService {
  @override
  bool get hasLocationPermission => true;

  @override
  bool get isLocationServiceEnabled => true;

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
  @override
  Future<Quote?> getQuoteById(String id, {bool includeDeleted = false}) async {
    return null; // Return null instead of throwing NoSuchMethodError to avoid triggering logDebug
  }

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _TestFeatureGuideService extends ChangeNotifier
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await TestHarness.initialize();
  });

  tearDown(() {
    // Clean up global logger periodic timer
    UnifiedLogService.instance.dispose();
  });

  testWidgets(
      'AddNoteDialog shows SnackBar and retains check state in edit mode',
      (WidgetTester tester) async {
    final initialQuote = Quote(
      id: 'test-id-123',
      content: 'Test initial note content',
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
    final mockDatabase = _TestDatabaseService();
    final mockGuide = _TestFeatureGuideService();

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<SettingsService>.value(value: mockSettings),
          ChangeNotifierProvider<LocationService>.value(value: mockLocation),
          ChangeNotifierProvider<WeatherService>.value(value: mockWeather),
          ChangeNotifierProvider<DatabaseService>.value(value: mockDatabase),
          ChangeNotifierProvider<FeatureGuideService>.value(value: mockGuide),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('zh'),
          home: Scaffold(
            body: AddNoteDialog(
              initialQuote: initialQuote,
              tags: const [],
              onSave: (_) {},
            ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 500));

    // Verify chips are rendered and checked initially
    final locationChip = find.byKey(const ValueKey('add_note_location_chip'));
    final weatherChip = find.byKey(const ValueKey('add_note_weather_chip'));

    expect(locationChip, findsOneWidget);
    expect(weatherChip, findsOneWidget);

    final FilterChip locationWidget = tester.widget(locationChip);
    final FilterChip weatherWidget = tester.widget(weatherChip);

    expect(locationWidget.selected, isTrue);
    expect(weatherWidget.selected, isTrue);

    // Tap the location chip to trigger the dialog
    await tester.tap(locationChip);
    await tester.pumpAndSettle();

    // Verify AlertDialog is shown
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.text('位置信息'), findsOneWidget);

    // Tap 'Cancel' to close the dialog
    await tester.tap(find.descendant(
      of: find.byType(AlertDialog),
      matching: find.text('取消'),
    ));
    await tester.pumpAndSettle();

    // Verify state remains selected
    var locationWidgetAfterTap = tester.widget<FilterChip>(locationChip);
    expect(locationWidgetAfterTap.selected, isTrue);

    // Tap again to show dialog and remove it
    await tester.tap(locationChip);
    await tester.pumpAndSettle();
    await tester.tap(find.descendant(
      of: find.byType(AlertDialog),
      matching: find.text('移除'),
    ));
    await tester.pumpAndSettle();

    // Verify state becomes unselected
    locationWidgetAfterTap = tester.widget<FilterChip>(locationChip);
    expect(locationWidgetAfterTap.selected, isFalse);

    // Dispose the widget tree and pump remaining animations to cleanly dispose all dialog components
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 600));
  });
}
