import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:thoughtecho/pages/home_page.dart';
import 'package:thoughtecho/services/database_service.dart';
import 'package:thoughtecho/services/settings_service.dart';
import 'package:thoughtecho/controllers/search_controller.dart';
import 'package:thoughtecho/services/connectivity_service.dart';
import 'package:thoughtecho/services/ai_service.dart';
import 'package:thoughtecho/services/location_service.dart';
import 'package:thoughtecho/services/weather_service.dart';
import 'package:thoughtecho/services/excerpt_intent_service.dart';
import 'package:thoughtecho/models/quote_model.dart';
import 'package:thoughtecho/models/note_category.dart';
import 'package:thoughtecho/gen_l10n/app_localizations.dart';
import 'package:thoughtecho/widgets/daily_quote_view.dart';
import 'package:thoughtecho/pages/home/daily_prompt_panel.dart';
import 'package:thoughtecho/widgets/note_list_view.dart';
import 'package:thoughtecho/pages/ai_features_page.dart';
import 'package:thoughtecho/pages/settings_page.dart';

class MockDatabaseService extends ChangeNotifier implements DatabaseService {
  @override
  bool isInitialized = true;
  @override
  Future<void> initDatabase() async {}
  @override
  Future<List<NoteCategory>> getTags() async => [];
  @override
  Future<List<Quote>> searchQuotes(String query,
          {List<String>? tagIds,
          String sortBy = 'time',
          bool ascending = false}) async =>
      [];
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class MockSettingsService extends ChangeNotifier implements SettingsService {
  @override
  bool get showFavoriteButton => true;
  @override
  bool get todayThoughtsUseAI => false;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class MockSearchController extends ChangeNotifier
    implements NoteSearchController {
  @override
  String get searchQuery => '';
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class MockConnectivityService extends ChangeNotifier
    implements ConnectivityService {
  @override
  bool get isConnected => true;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class MockAIService extends ChangeNotifier implements AIService {
  @override
  bool hasValidApiKey() => false;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class MockLocationService extends ChangeNotifier implements LocationService {
  @override
  String? get city => 'Test City';
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class MockWeatherService extends ChangeNotifier implements WeatherService {
  @override
  String? get currentWeather => 'Sunny';
  @override
  String? get temperature => '20°C';
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class MockExcerptIntentService implements ExcerptIntentService {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('HomePage Widget Tests', () {
    late MockDatabaseService mockDatabaseService;
    late MockSettingsService mockSettingsService;
    late MockSearchController mockSearchController;
    late MockConnectivityService mockConnectivityService;
    late MockAIService mockAIService;
    late MockLocationService mockLocationService;
    late MockWeatherService mockWeatherService;
    late MockExcerptIntentService mockExcerptIntentService;

    setUp(() {
      mockDatabaseService = MockDatabaseService();
      mockSettingsService = MockSettingsService();
      mockSearchController = MockSearchController();
      mockConnectivityService = MockConnectivityService();
      mockAIService = MockAIService();
      mockLocationService = MockLocationService();
      mockWeatherService = MockWeatherService();
      mockExcerptIntentService = MockExcerptIntentService();
    });

    Widget createWidgetUnderTest() {
      return MultiProvider(
        providers: [
          ChangeNotifierProvider<DatabaseService>.value(
              value: mockDatabaseService),
          ChangeNotifierProvider<SettingsService>.value(
              value: mockSettingsService),
          ChangeNotifierProvider<NoteSearchController>.value(
              value: mockSearchController),
          ChangeNotifierProvider<ConnectivityService>.value(
              value: mockConnectivityService),
          ChangeNotifierProvider<AIService>.value(value: mockAIService),
          ChangeNotifierProvider<LocationService>.value(
              value: mockLocationService),
          ChangeNotifierProvider<WeatherService>.value(
              value: mockWeatherService),
          Provider<ExcerptIntentService>.value(value: mockExcerptIntentService),
        ],
        child: const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: HomePage(),
        ),
      );
    }

    testWidgets(
        'should render DailyQuoteView and HomeDailyPromptPanel on initial load',
        (WidgetTester tester) async {
      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pumpAndSettle();

      expect(find.byType(DailyQuoteView), findsOneWidget);
      expect(find.byType(HomeDailyPromptPanel), findsOneWidget);

      // Floating action button should be present
      expect(find.byType(FloatingActionButton), findsOneWidget);
    });

    testWidgets('should navigate to NoteListView when second tab is tapped',
        (WidgetTester tester) async {
      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pumpAndSettle();

      // Tap the second tab (Notes)
      await tester.tap(find.byIcon(Icons.book_outlined));
      await tester.pumpAndSettle();

      expect(find.byType(NoteListView), findsOneWidget);
    });

    testWidgets('should navigate to AIFeaturesPage when third tab is tapped',
        (WidgetTester tester) async {
      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pumpAndSettle();

      // Tap the third tab (Insights)
      await tester.tap(find.byIcon(Icons.auto_awesome_outlined));
      await tester.pumpAndSettle();

      expect(find.byType(AIFeaturesPage), findsOneWidget);
    });

    testWidgets('should navigate to SettingsPage when fourth tab is tapped',
        (WidgetTester tester) async {
      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pumpAndSettle();

      // Tap the fourth tab (Settings)
      await tester.tap(find.byIcon(Icons.settings_outlined));
      await tester.pumpAndSettle();

      expect(find.byType(SettingsPage), findsOneWidget);
    });

    testWidgets('short location chip keeps its natural visual width',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(800, 200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 400,
                child: HomeLocationWeatherDisplay(
                  key: HomeLocationWeatherDisplay.chipKey,
                  locationText: 'Beijing',
                  weatherText: 'Sunny 18°C',
                  weatherIcon: Icons.wb_sunny,
                ),
              ),
            ),
          ),
        ),
      );

      final chipSize = tester.getSize(
        find.descendant(
          of: find.byKey(HomeLocationWeatherDisplay.chipKey),
          matching: find.byType(FittedBox),
        ),
      );

      expect(chipSize.width, lessThan(360));
    });

    testWidgets('long English location chip uses remaining title space',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(320, 200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            appBar: AppBar(
              title: const Row(
                children: [
                  Text('ThoughtEcho'),
                  SizedBox(width: 8),
                  Expanded(
                    child: HomeLocationWeatherDisplay(
                      key: HomeLocationWeatherDisplay.chipKey,
                      locationText:
                          'Washington, District of Columbia, United States',
                      weatherText: 'Partly cloudy 18°C',
                      weatherIcon: Icons.cloud,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );

      final titleSize = tester.getSize(find.text('ThoughtEcho'));
      final chipSize = tester.getSize(
        find.descendant(
          of: find.byKey(HomeLocationWeatherDisplay.chipKey),
          matching: find.byType(FittedBox),
        ),
      );

      expect(titleSize.width, greaterThan(80));
      expect(chipSize.width, lessThanOrEqualTo(320 - titleSize.width - 8));
    });
  });
}
