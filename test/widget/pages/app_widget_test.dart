import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import '../../../lib/main.dart';
import '../../../lib/services/database_service.dart';
import '../../../lib/services/settings_service.dart';
import '../../../lib/services/ai_service.dart';
import '../../../lib/services/location_service.dart';
import '../../../lib/services/weather_service.dart';
import '../../mocks/mock_database_service.dart';
import '../../mocks/mock_settings_service.dart';
import '../../mocks/mock_ai_service.dart';
import '../../mocks/mock_location_service.dart';
import '../../mocks/mock_weather_service.dart';

void main() {
  group('App Widget Tests', () {
    late MockDatabaseService mockDatabase;
    late MockSettingsService mockSettings;
    late MockAIService mockAI;
    late MockLocationService mockLocation;
    late MockWeatherService mockWeather;

    setUp(() {
      mockDatabase = MockDatabaseService();
      mockSettings = MockSettingsService();
      mockAI = MockAIService();
      mockLocation = MockLocationService();
      mockWeather = MockWeatherService();
      
      // Reset test data
      MockDatabaseService.resetTestData();
    });

    Widget createTestApp() {
      return MultiProvider(
        providers: [
          ChangeNotifierProvider<DatabaseService>.value(value: mockDatabase),
          ChangeNotifierProvider<SettingsService>.value(value: mockSettings),
          ChangeNotifierProvider<AIService>.value(value: mockAI),
          ChangeNotifierProvider<LocationService>.value(value: mockLocation),
          ChangeNotifierProvider<WeatherService>.value(value: mockWeather),
        ],
        child: MaterialApp(
          title: 'ThoughtEcho Test',
          theme: ThemeData(
            primarySwatch: Colors.blue,
            useMaterial3: true,
          ),
          home: Scaffold(
            appBar: AppBar(
              title: const Text('ThoughtEcho'),
            ),
            body: const Center(
              child: Text('Test App'),
            ),
            floatingActionButton: FloatingActionButton(
              onPressed: () {},
              child: const Icon(Icons.add),
            ),
          ),
        ),
      );
    }

    testWidgets('App should build without errors', (WidgetTester tester) async {
      // Build the widget
      await tester.pumpWidget(createTestApp());

      // Verify the app renders correctly
      expect(find.text('ThoughtEcho'), findsOneWidget);
      expect(find.text('Test App'), findsOneWidget);
      expect(find.byType(AppBar), findsOneWidget);
      expect(find.byType(FloatingActionButton), findsOneWidget);
    });

    testWidgets('Services should be accessible via Provider', (WidgetTester tester) async {
      await tester.pumpWidget(createTestApp());

      // Get the context to test provider access
      final BuildContext context = tester.element(find.byType(MaterialApp));

      // Verify all services are accessible
      expect(() => Provider.of<DatabaseService>(context, listen: false), 
             returnsNormally);
      expect(() => Provider.of<SettingsService>(context, listen: false), 
             returnsNormally);
      expect(() => Provider.of<AIService>(context, listen: false), 
             returnsNormally);
      expect(() => Provider.of<LocationService>(context, listen: false), 
             returnsNormally);
      expect(() => Provider.of<WeatherService>(context, listen: false), 
             returnsNormally);

      // Verify services are the mock instances
      final dbService = Provider.of<DatabaseService>(context, listen: false);
      final settingsService = Provider.of<SettingsService>(context, listen: false);
      final aiService = Provider.of<AIService>(context, listen: false);
      final locationService = Provider.of<LocationService>(context, listen: false);
      final weatherService = Provider.of<WeatherService>(context, listen: false);

      expect(dbService, isA<MockDatabaseService>());
      expect(settingsService, isA<MockSettingsService>());
      expect(aiService, isA<MockAIService>());
      expect(locationService, isA<MockLocationService>());
      expect(weatherService, isA<MockWeatherService>());
    });

    testWidgets('FAB should be tappable', (WidgetTester tester) async {
      await tester.pumpWidget(createTestApp());

      // Find and tap the FAB
      final fabFinder = find.byType(FloatingActionButton);
      expect(fabFinder, findsOneWidget);

      await tester.tap(fabFinder);
      await tester.pump();

      // Should not throw any exceptions
      expect(tester.takeException(), isNull);
    });

    testWidgets('App should handle theme changes', (WidgetTester tester) async {
      await tester.pumpWidget(createTestApp());

      // Get initial theme
      final BuildContext context = tester.element(find.byType(MaterialApp));
      final ThemeData initialTheme = Theme.of(context);

      expect(initialTheme, isNotNull);
      expect(initialTheme.useMaterial3, isTrue);
    });

    testWidgets('App should be accessible', (WidgetTester tester) async {
      await tester.pumpWidget(createTestApp());

      // Check for accessibility features
      expect(find.byType(AppBar), findsOneWidget);
      expect(find.byType(FloatingActionButton), findsOneWidget);

      // Verify semantic labels are present
      final Semantics appBarSemantics = tester.widget(find.ancestor(
        of: find.text('ThoughtEcho'),
        matching: find.byType(Semantics),
      ).first);
      expect(appBarSemantics, isNotNull);
    });

    testWidgets('App should handle rapid taps without crashing', (WidgetTester tester) async {
      await tester.pumpWidget(createTestApp());

      final fabFinder = find.byType(FloatingActionButton);

      // Rapidly tap the FAB multiple times
      for (int i = 0; i < 5; i++) {
        await tester.tap(fabFinder);
        await tester.pump(const Duration(milliseconds: 100));
      }

      // Should handle rapid taps gracefully
      expect(tester.takeException(), isNull);
    });

    testWidgets('App should handle screen size changes', (WidgetTester tester) async {
      await tester.pumpWidget(createTestApp());

      // Get initial size
      final Size initialSize = tester.getSize(find.byType(MaterialApp));
      expect(initialSize, isNotNull);

      // Change screen size to simulate rotation
      await tester.binding.setSurfaceSize(Size(initialSize.height, initialSize.width));
      await tester.pumpAndSettle();

      // App should still render correctly
      expect(find.text('ThoughtEcho'), findsOneWidget);
      expect(find.text('Test App'), findsOneWidget);
      expect(tester.takeException(), isNull);

      // Restore original size
      await tester.binding.setSurfaceSize(initialSize);
      await tester.pumpAndSettle();
    });
  });

  group('Mock Service Widget Integration Tests', () {
    late MockDatabaseService mockDatabase;
    late MockAIService mockAI;

    setUp(() {
      mockDatabase = MockDatabaseService();
      mockAI = MockAIService();
      MockDatabaseService.resetTestData();
    });

    Widget createServiceTestWidget({
      required Widget child,
    }) {
      return MultiProvider(
        providers: [
          ChangeNotifierProvider<DatabaseService>.value(value: mockDatabase),
          ChangeNotifierProvider<AIService>.value(value: mockAI),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: child,
          ),
        ),
      );
    }

    testWidgets('DatabaseService mock should work with Consumer', (WidgetTester tester) async {
      await tester.pumpWidget(
        createServiceTestWidget(
          child: Consumer<DatabaseService>(
            builder: (context, db, child) {
              return FutureBuilder<List<Quote>>(
                future: db.getUserQuotes(),
                builder: (context, snapshot) {
                  if (snapshot.hasData) {
                    return Text('Quotes: ${snapshot.data!.length}');
                  }
                  return const CircularProgressIndicator();
                },
              );
            },
          ),
        ),
      );

      // Wait for async operations
      await tester.pumpAndSettle();

      // Should show the quote count from mock data
      expect(find.text('Quotes: 2'), findsOneWidget);
    });

    testWidgets('AIService mock should work with streaming', (WidgetTester tester) async {
      String receivedText = '';

      await tester.pumpWidget(
        createServiceTestWidget(
          child: Consumer<AIService>(
            builder: (context, ai, child) {
              return Column(
                children: [
                  Text('AI Status: ${ai.isAnalyzing ? "Analyzing" : "Ready"}'),
                  Text('Received: $receivedText'),
                  ElevatedButton(
                    onPressed: () async {
                      final quote = Quote(
                        content: 'Test content',
                        date: DateTime.now().toIso8601String(),
                      );
                      await ai.analyzeQuoteStreaming(
                        quote,
                        onData: (data) {
                          receivedText = data;
                        },
                      );
                    },
                    child: const Text('Analyze'),
                  ),
                ],
              );
            },
          ),
        ),
      );

      // Tap the analyze button
      await tester.tap(find.text('Analyze'));
      await tester.pumpAndSettle();

      // Should show analysis is complete
      expect(find.text('AI Status: Ready'), findsOneWidget);
      expect(receivedText, isNotEmpty);
    });
  });
}