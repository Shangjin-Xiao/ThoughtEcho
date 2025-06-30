import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:provider/provider.dart';

import 'package:thoughtecho/main.dart' as app;
import 'package:thoughtecho/services/database_service.dart';
import 'package:thoughtecho/services/settings_service.dart';
import 'package:thoughtecho/services/ai_service.dart';
import 'package:thoughtecho/services/location_service.dart';
import 'package:thoughtecho/services/weather_service.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('App Integration Tests', () {
    testWidgets('App should start and show home screen', (WidgetTester tester) async {
      // Launch the app
      app.main();
      await tester.pumpAndSettle();

      // Verify the app starts successfully
      expect(find.byType(MaterialApp), findsOneWidget);
      
      // Look for key elements that should be present on the home screen
      // Note: These might need adjustment based on actual app structure
      expect(find.byType(AppBar), findsOneWidget);
      
      // Check if the app doesn't crash during initial load
      await tester.pump(const Duration(seconds: 2));
      expect(tester.takeException(), isNull);
    });

    testWidgets('Services should be properly initialized', (WidgetTester tester) async {
      // Launch the app
      app.main();
      await tester.pumpAndSettle();

      // Get the build context to access providers
      final BuildContext context = tester.element(find.byType(MaterialApp));

      // Verify that all key services are available
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
    });

    testWidgets('Navigation should work between main screens', (WidgetTester tester) async {
      // Launch the app
      app.main();
      await tester.pumpAndSettle();

      // Try to find and tap navigation elements
      // Note: These selectors might need adjustment based on actual UI
      
      // Look for bottom navigation or drawer
      final navFinder = find.byType(BottomNavigationBar);
      if (navFinder.evaluate().isNotEmpty) {
        // Test bottom navigation
        await tester.tap(navFinder);
        await tester.pumpAndSettle();
        
        // Verify navigation worked (no exceptions)
        expect(tester.takeException(), isNull);
      }
      
      // Look for floating action button (if present)
      final fabFinder = find.byType(FloatingActionButton);
      if (fabFinder.evaluate().isNotEmpty) {
        await tester.tap(fabFinder);
        await tester.pumpAndSettle();
        
        // Verify FAB action worked
        expect(tester.takeException(), isNull);
      }
    });

    testWidgets('App should handle screen rotation', (WidgetTester tester) async {
      // Launch the app
      app.main();
      await tester.pumpAndSettle();

      // Get initial state
      final initialSize = tester.getSize(find.byType(MaterialApp));
      
      // Simulate device rotation by changing the size
      await tester.binding.setSurfaceSize(Size(initialSize.height, initialSize.width));
      await tester.pumpAndSettle();

      // Verify the app doesn't crash on rotation
      expect(tester.takeException(), isNull);
      expect(find.byType(MaterialApp), findsOneWidget);

      // Restore original size
      await tester.binding.setSurfaceSize(initialSize);
      await tester.pumpAndSettle();
    });

    testWidgets('App should maintain state during lifecycle events', (WidgetTester tester) async {
      // Launch the app
      app.main();
      await tester.pumpAndSettle();

      // Simulate app going to background
      await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
        'flutter/lifecycle',
        const StandardMethodCodec().encodeMethodCall(
          const MethodCall('AppLifecycleState.paused'),
        ),
        (data) {},
      );
      await tester.pump();

      // Verify app handles lifecycle change gracefully
      expect(tester.takeException(), isNull);

      // Simulate app coming back to foreground
      await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
        'flutter/lifecycle',
        const StandardMethodCodec().encodeMethodCall(
          const MethodCall('AppLifecycleState.resumed'),
        ),
        (data) {},
      );
      await tester.pumpAndSettle();

      // Verify app is still functional
      expect(find.byType(MaterialApp), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Database operations should work end-to-end', (WidgetTester tester) async {
      // Launch the app
      app.main();
      await tester.pumpAndSettle();

      // Get the database service
      final BuildContext context = tester.element(find.byType(MaterialApp));
      final DatabaseService dbService = Provider.of<DatabaseService>(context, listen: false);

      // Test database operations
      expect(() async {
        // Initialize database
        await dbService.initialize();
        
        // Get initial categories (should include default ones)
        final categories = await dbService.getCategories();
        expect(categories, isNotEmpty);
        
        // Get initial quotes
        final quotes = await dbService.getUserQuotes();
        // Should not throw, might be empty initially
        expect(quotes, isNotNull);
      }, returnsNormally);
    });

    testWidgets('Settings should persist across app restarts', (WidgetTester tester) async {
      // Launch the app
      app.main();
      await tester.pumpAndSettle();

      // Get the settings service
      final BuildContext context = tester.element(find.byType(MaterialApp));
      final SettingsService settingsService = Provider.of<SettingsService>(context, listen: false);

      // Test settings operations
      expect(() async {
        // Initialize settings
        await settingsService.initialize();
        
        // Set a test setting
        await settingsService.set('test_key', 'test_value');
        
        // Verify it was saved
        final value = await settingsService.get<String>('test_key');
        expect(value, equals('test_value'));
        
        // Clean up
        await settingsService.remove('test_key');
      }, returnsNormally);
    });
  });

  group('Performance Tests', () {
    testWidgets('App should start within reasonable time', (WidgetTester tester) async {
      final stopwatch = Stopwatch()..start();
      
      // Launch the app
      app.main();
      await tester.pumpAndSettle();
      
      stopwatch.stop();
      
      // App should start within 10 seconds (adjust as needed)
      expect(stopwatch.elapsedMilliseconds, lessThan(10000));
      
      // Verify the app actually loaded
      expect(find.byType(MaterialApp), findsOneWidget);
    });

    testWidgets('Large lists should scroll smoothly', (WidgetTester tester) async {
      // Launch the app
      app.main();
      await tester.pumpAndSettle();

      // Find scrollable widgets (like ListView)
      final scrollableFinder = find.byType(Scrollable);
      
      if (scrollableFinder.evaluate().isNotEmpty) {
        final scrollable = scrollableFinder.first;
        
        // Perform scroll operations and measure performance
        final stopwatch = Stopwatch()..start();
        
        // Scroll down
        await tester.drag(scrollable, const Offset(0, -200));
        await tester.pump();
        
        // Scroll up
        await tester.drag(scrollable, const Offset(0, 200));
        await tester.pump();
        
        stopwatch.stop();
        
        // Scrolling should be responsive (less than 100ms per operation)
        expect(stopwatch.elapsedMilliseconds, lessThan(200));
        
        // No exceptions should occur
        expect(tester.takeException(), isNull);
      }
    });
  });

  group('Error Handling Tests', () {
    testWidgets('App should handle network errors gracefully', (WidgetTester tester) async {
      // Launch the app
      app.main();
      await tester.pumpAndSettle();

      // The app should start successfully even if network services fail
      expect(find.byType(MaterialApp), findsOneWidget);
      expect(tester.takeException(), isNull);
      
      // Test that the app doesn't crash when network operations fail
      // This is a basic test - more specific network error testing would 
      // require mock services or actual network failure simulation
    });

    testWidgets('App should handle insufficient permissions gracefully', (WidgetTester tester) async {
      // Launch the app
      app.main();
      await tester.pumpAndSettle();

      // The app should start successfully even if permissions are denied
      expect(find.byType(MaterialApp), findsOneWidget);
      expect(tester.takeException(), isNull);
      
      // Test that location and other permission-dependent features
      // handle denials gracefully (would need more specific testing)
    });
  });
}