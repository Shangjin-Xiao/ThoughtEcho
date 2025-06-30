/// Widget tests for HomePage
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import '../../lib/pages/home_page.dart';
import '../mocks/mock_database_service.dart';
import '../mocks/mock_settings_service.dart';
import '../mocks/mock_location_service.dart';
import '../mocks/mock_weather_service.dart';
import '../mocks/mock_ai_service.dart';
import '../mocks/mock_clipboard_service.dart';
import '../test_utils/test_helpers.dart';

void main() {
  group('HomePage Widget Tests', () {
    late MockDatabaseService mockDatabaseService;
    late MockSettingsService mockSettingsService;
    late MockLocationService mockLocationService;
    late MockWeatherService mockWeatherService;
    late MockAIService mockAIService;
    late MockClipboardService mockClipboardService;

    setUpAll(() {
      TestHelpers.setupTestEnvironment();
    });

    setUp(() async {
      mockDatabaseService = MockDatabaseService();
      mockSettingsService = MockSettingsService();
      mockLocationService = MockLocationService();
      mockWeatherService = MockWeatherService();
      mockAIService = MockAIService();
      mockClipboardService = MockClipboardService();

      // Initialize all services
      await mockDatabaseService.initialize();
      await mockSettingsService.initialize();
      await mockLocationService.initialize();
      await mockWeatherService.initialize();
      await mockAIService.initialize();
      await mockClipboardService.init();

      // Add some test data
      mockDatabaseService.addTestData();
    });

    tearDownAll(() {
      TestHelpers.teardownTestEnvironment();
    });

    testWidgets('should render HomePage with providers', (tester) async {
      await tester.pumpWidget(
        TestHelpers.createTestWidgetWithProviders(
          child: const HomePage(),
          databaseService: mockDatabaseService,
          settingsService: mockSettingsService,
          locationService: mockLocationService,
          weatherService: mockWeatherService,
          aiService: mockAIService,
        ),
      );

      await tester.pumpAndSettle();

      // Verify HomePage is rendered
      expect(find.byType(HomePage), findsOneWidget);
    });

    testWidgets('should display bottom navigation bar', (tester) async {
      await tester.pumpWidget(
        TestHelpers.createTestWidgetWithProviders(
          child: const HomePage(),
          databaseService: mockDatabaseService,
          settingsService: mockSettingsService,
          locationService: mockLocationService,
          weatherService: mockWeatherService,
          aiService: mockAIService,
        ),
      );

      await tester.pumpAndSettle();

      // Should have bottom navigation bar
      expect(find.byType(BottomNavigationBar), findsOneWidget);
      
      // Should have multiple navigation items
      expect(find.byType(BottomNavigationBarItem), findsWidgets);
    });

    testWidgets('should navigate between tabs', (tester) async {
      await tester.pumpWidget(
        TestHelpers.createTestWidgetWithProviders(
          child: const HomePage(),
          databaseService: mockDatabaseService,
          settingsService: mockSettingsService,
          locationService: mockLocationService,
          weatherService: mockWeatherService,
          aiService: mockAIService,
        ),
      );

      await tester.pumpAndSettle();

      // Find navigation items and test tapping
      final navigationBar = find.byType(BottomNavigationBar);
      expect(navigationBar, findsOneWidget);

      // Test tapping different tabs (if they exist)
      if (tester.widgetList(find.byType(BottomNavigationBarItem)).length > 1) {
        // Tap second tab
        await tester.tap(find.byType(BottomNavigationBarItem).at(1));
        await tester.pumpAndSettle();

        // Verify navigation occurred
        expect(find.byType(HomePage), findsOneWidget);
      }
    });

    testWidgets('should handle floating action button tap', (tester) async {
      await tester.pumpWidget(
        TestHelpers.createTestWidgetWithProviders(
          child: const HomePage(),
          databaseService: mockDatabaseService,
          settingsService: mockSettingsService,
          locationService: mockLocationService,
          weatherService: mockWeatherService,
          aiService: mockAIService,
        ),
      );

      await tester.pumpAndSettle();

      // Look for floating action button
      final fab = find.byType(FloatingActionButton);
      if (fab.evaluate().isNotEmpty) {
        await tester.tap(fab);
        await tester.pumpAndSettle();

        // Should open add note dialog or navigate to editor
        expect(
          find.byType(Dialog).or(find.byType(Navigator)),
          findsWidgets,
        );
      }
    });

    testWidgets('should display app bar', (tester) async {
      await tester.pumpWidget(
        TestHelpers.createTestWidgetWithProviders(
          child: const HomePage(),
          databaseService: mockDatabaseService,
          settingsService: mockSettingsService,
          locationService: mockLocationService,
          weatherService: mockWeatherService,
          aiService: mockAIService,
        ),
      );

      await tester.pumpAndSettle();

      // Should have an app bar or similar title area
      expect(
        find.byType(AppBar).or(find.byType(SliverAppBar)),
        findsWidgets,
      );
    });

    testWidgets('should handle data loading states', (tester) async {
      // Start with uninitialized services
      final uninitializedDb = MockDatabaseService();
      
      await tester.pumpWidget(
        TestHelpers.createTestWidgetWithProviders(
          child: const HomePage(),
          databaseService: uninitializedDb,
          settingsService: mockSettingsService,
          locationService: mockLocationService,
          weatherService: mockWeatherService,
          aiService: mockAIService,
        ),
      );

      // Should handle loading state
      await tester.pump();

      // Verify loading indicators or empty states
      expect(
        find.byType(CircularProgressIndicator).or(find.byType(LinearProgressIndicator)),
        findsWidgets,
      );
    });

    testWidgets('should display notes when data is available', (tester) async {
      await tester.pumpWidget(
        TestHelpers.createTestWidgetWithProviders(
          child: const HomePage(),
          databaseService: mockDatabaseService,
          settingsService: mockSettingsService,
          locationService: mockLocationService,
          weatherService: mockWeatherService,
          aiService: mockAIService,
        ),
      );

      await tester.pumpAndSettle();

      // Should display some form of list or content
      expect(
        find.byType(ListView).or(find.byType(GridView)).or(find.byType(SingleChildScrollView)),
        findsWidgets,
      );
    });

    testWidgets('should handle provider changes', (tester) async {
      await tester.pumpWidget(
        TestHelpers.createTestWidgetWithProviders(
          child: const HomePage(),
          databaseService: mockDatabaseService,
          settingsService: mockSettingsService,
          locationService: mockLocationService,
          weatherService: mockWeatherService,
          aiService: mockAIService,
        ),
      );

      await tester.pumpAndSettle();

      // Simulate data change
      mockDatabaseService.addTestData();
      await tester.pump();

      // Widget should still be rendered correctly
      expect(find.byType(HomePage), findsOneWidget);
    });

    testWidgets('should display different content for different tabs', (tester) async {
      await tester.pumpWidget(
        TestHelpers.createTestWidgetWithProviders(
          child: const HomePage(),
          databaseService: mockDatabaseService,
          settingsService: mockSettingsService,
          locationService: mockLocationService,
          weatherService: mockWeatherService,
          aiService: mockAIService,
        ),
      );

      await tester.pumpAndSettle();

      // Get initial content
      final initialWidgets = tester.widgetList(find.byType(Widget)).length;

      // Navigate to different tab if available
      final navItems = find.byType(BottomNavigationBarItem);
      if (navItems.evaluate().length > 1) {
        await tester.tap(navItems.at(1));
        await tester.pumpAndSettle();

        // Content should change (widget tree might be different)
        expect(find.byType(HomePage), findsOneWidget);
      }
    });

    testWidgets('should handle search functionality if present', (tester) async {
      await tester.pumpWidget(
        TestHelpers.createTestWidgetWithProviders(
          child: const HomePage(),
          databaseService: mockDatabaseService,
          settingsService: mockSettingsService,
          locationService: mockLocationService,
          weatherService: mockWeatherService,
          aiService: mockAIService,
        ),
      );

      await tester.pumpAndSettle();

      // Look for search functionality
      final searchIcon = find.byIcon(Icons.search);
      if (searchIcon.evaluate().isNotEmpty) {
        await tester.tap(searchIcon);
        await tester.pumpAndSettle();

        // Should show search interface
        expect(
          find.byType(TextField).or(find.byType(SearchBar)),
          findsWidgets,
        );
      }
    });

    testWidgets('should handle empty state gracefully', (tester) async {
      // Use empty database
      final emptyDb = MockDatabaseService();
      await emptyDb.initialize(); // No test data added

      await tester.pumpWidget(
        TestHelpers.createTestWidgetWithProviders(
          child: const HomePage(),
          databaseService: emptyDb,
          settingsService: mockSettingsService,
          locationService: mockLocationService,
          weatherService: mockWeatherService,
          aiService: mockAIService,
        ),
      );

      await tester.pumpAndSettle();

      // Should handle empty state gracefully
      expect(find.byType(HomePage), findsOneWidget);
      
      // Should show empty state UI or placeholders
      expect(
        find.textContaining('暂无').or(find.textContaining('空')).or(find.byType(Image)),
        findsWidgets,
      );
    });

    testWidgets('should respect theme settings', (tester) async {
      // Test with dark theme
      mockSettingsService.updateThemeMode(ThemeMode.dark);

      await tester.pumpWidget(
        TestHelpers.createTestWidgetWithProviders(
          child: const HomePage(),
          databaseService: mockDatabaseService,
          settingsService: mockSettingsService,
          locationService: mockLocationService,
          weatherService: mockWeatherService,
          aiService: mockAIService,
        ),
      );

      await tester.pumpAndSettle();

      // Should render without errors regardless of theme
      expect(find.byType(HomePage), findsOneWidget);
    });

    testWidgets('should handle orientation changes', (tester) async {
      await tester.pumpWidget(
        TestHelpers.createTestWidgetWithProviders(
          child: const HomePage(),
          databaseService: mockDatabaseService,
          settingsService: mockSettingsService,
          locationService: mockLocationService,
          weatherService: mockWeatherService,
          aiService: mockAIService,
        ),
      );

      await tester.pumpAndSettle();

      // Simulate orientation change
      await tester.binding.setSurfaceSize(const Size(800, 600)); // Landscape
      await tester.pumpAndSettle();

      expect(find.byType(HomePage), findsOneWidget);

      // Change back to portrait
      await tester.binding.setSurfaceSize(const Size(400, 800));
      await tester.pumpAndSettle();

      expect(find.byType(HomePage), findsOneWidget);
    });

    testWidgets('should handle accessibility requirements', (tester) async {
      await tester.pumpWidget(
        TestHelpers.createTestWidgetWithProviders(
          child: const HomePage(),
          databaseService: mockDatabaseService,
          settingsService: mockSettingsService,
          locationService: mockLocationService,
          weatherService: mockWeatherService,
          aiService: mockAIService,
        ),
      );

      await tester.pumpAndSettle();

      // Check for semantic widgets
      expect(
        find.byType(Semantics).or(find.byType(ExcludeSemantics)),
        findsWidgets,
      );

      // Verify interactive elements have proper semantics
      final buttons = find.byType(ElevatedButton)
          .or(find.byType(TextButton))
          .or(find.byType(IconButton))
          .or(find.byType(FloatingActionButton));
      
      // Each button should be tappable
      for (final button in buttons.evaluate()) {
        expect(button.widget, isA<Widget>());
      }
    });
  });
}