import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import '../../lib/services/database_service.dart';
import '../../lib/services/settings_service.dart';
import '../../lib/services/ai_service.dart';
import '../../lib/services/location_service.dart';
import '../../lib/services/weather_service.dart';
import '../../lib/models/quote_model.dart';
import '../../lib/models/note_category.dart';
import '../mocks/mock_database_service.dart';
import '../mocks/mock_settings_service.dart';
import '../mocks/mock_ai_service.dart';
import '../mocks/mock_location_service.dart';
import '../mocks/mock_weather_service.dart';

/// Test utilities for ThoughtEcho app testing
class TestUtils {
  /// Create a test app with all required providers and mock services
  static Widget createTestApp({
    required Widget home,
    MockDatabaseService? mockDatabase,
    MockSettingsService? mockSettings,
    MockAIService? mockAI,
    MockLocationService? mockLocation,
    MockWeatherService? mockWeather,
    ThemeData? theme,
    Locale? locale,
  }) {
    // Use provided mocks or create new ones
    mockDatabase ??= MockDatabaseService();
    mockSettings ??= MockSettingsService();
    mockAI ??= MockAIService();
    mockLocation ??= MockLocationService();
    mockWeather ??= MockWeatherService();

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
        theme: theme ?? ThemeData(
          primarySwatch: Colors.blue,
          useMaterial3: true,
        ),
        locale: locale,
        home: home,
      ),
    );
  }

  /// Create a minimal test widget wrapper
  static Widget createTestWidget(Widget child) {
    return MaterialApp(
      home: Scaffold(
        body: child,
      ),
    );
  }

  /// Wait for all animations and async operations to complete
  static Future<void> waitForAnimations(WidgetTester tester) async {
    await tester.pumpAndSettle();
    // Additional wait for any remaining async operations
    await Future.delayed(const Duration(milliseconds: 100));
    await tester.pump();
  }

  /// Verify that a widget is accessible (has semantic properties)
  static void verifyAccessibility(WidgetTester tester, Finder finder) {
    expect(finder, findsOneWidget);
    
    // Check if the widget has semantic information
    final Element element = tester.element(finder);
    final RenderObject? renderObject = element.renderObject;
    
    expect(renderObject, isNotNull);
    // Additional accessibility checks can be added here
  }

  /// Simulate user interaction with a delay
  static Future<void> tapWithDelay(
    WidgetTester tester, 
    Finder finder, {
    Duration delay = const Duration(milliseconds: 100),
  }) async {
    await tester.tap(finder);
    await Future.delayed(delay);
    await tester.pump();
  }

  /// Simulate device rotation
  static Future<void> rotateDevice(WidgetTester tester) async {
    final Size currentSize = tester.binding.window.physicalSize;
    await tester.binding.setSurfaceSize(Size(currentSize.height, currentSize.width));
    await tester.pumpAndSettle();
  }

  /// Create a test context with all services available
  static BuildContext createTestContext(WidgetTester tester) {
    final testWidget = createTestApp(
      home: Container(),
    );
    
    tester.pumpWidget(testWidget);
    return tester.element(find.byType(MaterialApp));
  }

  /// Assert that no exceptions were thrown
  static void expectNoExceptions(WidgetTester tester) {
    expect(tester.takeException(), isNull);
  }

  /// Find widget by key safely
  static Finder findByKey(String key) {
    return find.byKey(Key(key));
  }

  /// Find text containing specific substring
  static Finder findTextContaining(String substring) {
    return find.byWidgetPredicate(
      (Widget widget) => widget is Text && 
                         widget.data != null && 
                         widget.data!.contains(substring)
    );
  }

  /// Wait for a specific condition to be true
  static Future<void> waitForCondition(
    WidgetTester tester,
    bool Function() condition, {
    Duration timeout = const Duration(seconds: 5),
    Duration interval = const Duration(milliseconds: 100),
  }) async {
    final stopwatch = Stopwatch()..start();
    
    while (!condition() && stopwatch.elapsed < timeout) {
      await Future.delayed(interval);
      await tester.pump();
    }
    
    if (!condition()) {
      throw TimeoutException('Condition not met within timeout', timeout);
    }
  }

  /// Setup common test data
  static void setupTestData() {
    MockDatabaseService.resetTestData();
  }

  /// Create test quote with realistic data
  static Quote createTestQuote({
    String? id,
    String? content,
    String? categoryId,
    List<String>? tagIds,
    DateTime? date,
  }) {
    return Quote(
      id: id ?? 'test-quote-${DateTime.now().millisecondsSinceEpoch}',
      content: content ?? 'This is a test quote for testing purposes.',
      date: (date ?? DateTime.now()).toIso8601String(),
      categoryId: categoryId ?? 'test-category',
      tagIds: tagIds ?? ['test', 'quote'],
      location: 'Test Location',
      weather: 'Sunny',
      temperature: '22°C',
    );
  }

  /// Create test category with realistic data
  static NoteCategory createTestCategory({
    String? id,
    String? name,
    bool isDefault = false,
    String? iconName,
  }) {
    return NoteCategory(
      id: id ?? 'test-category-${DateTime.now().millisecondsSinceEpoch}',
      name: name ?? 'Test Category',
      isDefault: isDefault,
      iconName: iconName ?? 'bookmark',
    );
  }

  /// Verify that a Future completes successfully
  static Future<void> expectFutureCompletes<T>(
    Future<T> future, {
    Duration timeout = const Duration(seconds: 5),
  }) async {
    T result;
    try {
      result = await future.timeout(timeout);
    } catch (e) {
      fail('Future did not complete successfully: $e');
    }
    expect(result, isNotNull);
  }

  /// Verify that a Future throws a specific exception
  static Future<void> expectFutureThrows<T extends Exception>(
    Future future,
    Type exceptionType,
  ) async {
    bool threwExpectedException = false;
    try {
      await future;
    } catch (e) {
      if (e.runtimeType == exceptionType) {
        threwExpectedException = true;
      } else {
        fail('Expected $exceptionType but got ${e.runtimeType}: $e');
      }
    }
    
    if (!threwExpectedException) {
      fail('Expected $exceptionType to be thrown but no exception was thrown');
    }
  }

  /// Mock network delay for testing async operations
  static Future<void> mockNetworkDelay({
    Duration delay = const Duration(milliseconds: 500),
  }) async {
    await Future.delayed(delay);
  }

  /// Verify widget tree structure
  static void verifyWidgetTree(WidgetTester tester, List<Type> expectedTypes) {
    for (final type in expectedTypes) {
      expect(find.byType(type), findsAtLeastNWidgets(1));
    }
  }

  /// Get service from test context
  static T getService<T>(BuildContext context) {
    return Provider.of<T>(context, listen: false);
  }

  /// Simulate app lifecycle events
  static Future<void> simulateAppPause(WidgetTester tester) async {
    await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
      'flutter/lifecycle',
      const StandardMethodCodec().encodeMethodCall(
        const MethodCall('AppLifecycleState.paused'),
      ),
      (data) {},
    );
    await tester.pump();
  }

  static Future<void> simulateAppResume(WidgetTester tester) async {
    await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
      'flutter/lifecycle',
      const StandardMethodCodec().encodeMethodCall(
        const MethodCall('AppLifecycleState.resumed'),
      ),
      (data) {},
    );
    await tester.pump();
  }

  /// Validate JSON structures
  static void validateQuoteJson(Map<String, dynamic> json) {
    expect(json, containsPair('id', isA<String>()));
    expect(json, containsPair('content', isA<String>()));
    expect(json, containsPair('date', isA<String>()));
  }

  static void validateCategoryJson(Map<String, dynamic> json) {
    expect(json, containsPair('id', isA<String>()));
    expect(json, containsPair('name', isA<String>()));
    expect(json, containsPair('is_default', isA<int>()));
  }

  /// Clean up test environment
  static void cleanup() {
    MockDatabaseService.resetTestData();
  }
}

/// Extension methods for WidgetTester
extension WidgetTesterExtensions on WidgetTester {
  /// Tap and wait for animations
  Future<void> tapAndSettle(Finder finder) async {
    await tap(finder);
    await pumpAndSettle();
  }

  /// Enter text and wait for animations
  Future<void> enterTextAndSettle(Finder finder, String text) async {
    await enterText(finder, text);
    await pumpAndSettle();
  }

  /// Scroll until visible and then tap
  Future<void> scrollToAndTap(Finder finder, {Finder? scrollable}) async {
    if (scrollable != null) {
      await scrollUntilVisible(finder, 100.0, scrollable: scrollable);
    }
    await tap(finder);
    await pumpAndSettle();
  }
}

/// Custom matchers for testing
class TestMatchers {
  /// Matcher for checking if a Quote has specific content
  static Matcher hasQuoteContent(String content) {
    return predicate<Quote>((quote) => quote.content == content, 'has content "$content"');
  }

  /// Matcher for checking if a NoteCategory has specific name
  static Matcher hasCategoryName(String name) {
    return predicate<NoteCategory>((category) => category.name == name, 'has name "$name"');
  }

  /// Matcher for checking if a Future completes within timeout
  static Matcher completesWithin(Duration timeout) {
    return predicate<Future>(
      (future) async {
        try {
          await future.timeout(timeout);
          return true;
        } catch (e) {
          return false;
        }
      },
      'completes within $timeout',
    );
  }
}

/// Exception for timeout conditions in tests
class TimeoutException implements Exception {
  final String message;
  final Duration timeout;

  const TimeoutException(this.message, this.timeout);

  @override
  String toString() => 'TimeoutException: $message (timeout: $timeout)';
}