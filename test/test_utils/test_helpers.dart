/// Test helper utilities for ThoughtEcho test suite
/// Provides common testing utilities, matchers, and helper functions
library test_helpers;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'dart:io';
import 'dart:math';

import '../mocks/mock_database_service.dart';
import '../mocks/mock_settings_service.dart';
import '../mocks/mock_location_service.dart';
import '../mocks/mock_weather_service.dart';
import '../mocks/mock_ai_service.dart';

class TestHelpers {
  /// Initialize test database for testing
  static Future<Database> createTestDatabase({String? path}) async {
    if (Platform.isWindows || Platform.isLinux) {
      sqfliteFfiInit();
      return databaseFactoryFfi.openDatabase(
        path ?? inMemoryDatabasePath,
        options: OpenDatabaseOptions(
          version: 1,
          onCreate: _createTestTables,
        ),
      );
    } else {
      return openDatabase(
        path ?? inMemoryDatabasePath,
        version: 1,
        onCreate: _createTestTables,
      );
    }
  }

  /// Create test database tables
  static Future<void> _createTestTables(Database db, int version) async {
    // Create quotes table
    await db.execute('''
      CREATE TABLE quotes (
        id TEXT PRIMARY KEY,
        content TEXT NOT NULL,
        delta_content TEXT,
        date TEXT NOT NULL,
        category_id TEXT,
        tag_ids TEXT,
        source TEXT,
        source_author TEXT,
        source_work TEXT,
        location TEXT,
        weather TEXT,
        temperature TEXT,
        day_period TEXT,
        color_hex TEXT,
        edit_source TEXT,
        ai_analysis TEXT,
        sentiment TEXT,
        keywords TEXT,
        summary TEXT
      )
    ''');

    // Create categories table
    await db.execute('''
      CREATE TABLE categories (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        is_default BOOLEAN DEFAULT 0,
        icon_name TEXT
      )
    ''');

    // Create AI analyses table
    await db.execute('''
      CREATE TABLE ai_analyses (
        id TEXT PRIMARY KEY,
        quote_id TEXT NOT NULL,
        analysis_type TEXT NOT NULL,
        content TEXT NOT NULL,
        created_at TEXT NOT NULL,
        metadata TEXT,
        quote_count INTEGER
      )
    ''');
  }

  /// Create a test widget with providers
  static Widget createTestWidgetWithProviders({
    required Widget child,
    MockDatabaseService? databaseService,
    MockSettingsService? settingsService,
    MockLocationService? locationService,
    MockWeatherService? weatherService,
    MockAIService? aiService,
  }) {
    return MaterialApp(
      home: MultiProvider(
        providers: [
          ChangeNotifierProvider<MockDatabaseService>(
            create: (_) => databaseService ?? MockDatabaseService(),
          ),
          ChangeNotifierProvider<MockSettingsService>(
            create: (_) => settingsService ?? MockSettingsService(),
          ),
          ChangeNotifierProvider<MockLocationService>(
            create: (_) => locationService ?? MockLocationService(),
          ),
          ChangeNotifierProvider<MockWeatherService>(
            create: (_) => weatherService ?? MockWeatherService(),
          ),
          ChangeNotifierProvider<MockAIService>(
            create: (_) => aiService ?? MockAIService(),
          ),
        ],
        child: child,
      ),
    );
  }

  /// Wait for a condition to be true with timeout
  static Future<void> waitForCondition(
    bool Function() condition, {
    Duration timeout = const Duration(seconds: 5),
    Duration interval = const Duration(milliseconds: 100),
  }) async {
    final stopwatch = Stopwatch()..start();
    while (!condition() && stopwatch.elapsed < timeout) {
      await Future.delayed(interval);
    }
    if (!condition()) {
      throw TimeoutException(
        'Condition not met within ${timeout.inMilliseconds}ms',
        timeout,
      );
    }
  }

  /// Generate random string for testing
  static String generateRandomString(int length) {
    const chars = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    final random = Random();
    return String.fromCharCodes(
      Iterable.generate(length, (_) => chars.codeUnitAt(random.nextInt(chars.length))),
    );
  }

  /// Generate test Chinese content
  static String generateTestChineseContent() {
    final contents = [
      '今天是个好天气，心情很愉快。',
      '学习新技术让我感到充实和满足。',
      '和朋友聊天总是能带来快乐。',
      '读书是一种享受，知识让人成长。',
      '工作虽然忙碌，但充满挑战和机遇。',
      '生活需要平衡，劳逸结合很重要。',
      '梦想需要坚持，努力才能实现。',
      '感恩身边的人和事，珍惜当下。',
    ];
    final random = Random();
    return contents[random.nextInt(contents.length)];
  }

  /// Create test context for async operations
  static Future<T> runWithTestContext<T>(Future<T> Function() operation) async {
    return await operation();
  }

  /// Verify that a stream emits expected values
  static Future<void> expectStream<T>(
    Stream<T> stream,
    List<T> expectedValues, {
    Duration timeout = const Duration(seconds: 5),
  }) async {
    final actualValues = <T>[];
    final subscription = stream.listen(actualValues.add);
    
    try {
      await waitForCondition(
        () => actualValues.length >= expectedValues.length,
        timeout: timeout,
      );
      
      expect(actualValues, equals(expectedValues));
    } finally {
      await subscription.cancel();
    }
  }

  /// Custom matchers for testing
  static Matcher hasLength(int length) => predicate<List>(
    (list) => list.length == length,
    'has length $length',
  );

  static Matcher containsText(String text) => predicate<String>(
    (string) => string.contains(text),
    'contains text "$text"',
  );

  static Matcher isValidId() => predicate<String>(
    (id) => id.isNotEmpty && id.length >= 5,
    'is a valid ID',
  );

  static Matcher isValidDate() => predicate<String>(
    (dateStr) {
      try {
        DateTime.parse(dateStr);
        return true;
      } catch (e) {
        return false;
      }
    },
    'is a valid ISO date string',
  );

  /// Clean up test resources
  static Future<void> cleanupTestDatabase(Database? database) async {
    if (database != null) {
      await database.close();
    }
  }

  /// Setup and teardown helpers
  static void setupTestEnvironment() {
    // Initialize any global test configuration
  }

  static void teardownTestEnvironment() {
    // Clean up any global test resources
  }
}

/// Custom exception for test timeouts
class TimeoutException implements Exception {
  final String message;
  final Duration timeout;

  TimeoutException(this.message, this.timeout);

  @override
  String toString() => 'TimeoutException: $message';
}