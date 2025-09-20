import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'dart:io';

/// Mock Path Provider Platform for testing
class MockPathProviderPlatform extends PathProviderPlatform {
  @override
  Future<String?> getApplicationDocumentsPath() async {
    return '/tmp/test_app_docs';
  }

  @override
  Future<String?> getApplicationSupportPath() async {
    return '/tmp/test_app_support';
  }

  @override
  Future<String?> getDownloadsPath() async {
    return '/tmp/test_downloads';
  }

  @override
  Future<String?> getTemporaryPath() async {
    return '/tmp/test_temp';
  }
}

/// Comprehensive test setup for Flutter plugins
class TestSetup {
  static MockPathProviderPlatform? _mockPathProvider;
  static bool _isInitialized = false;
  static bool _verboseLogging = false;

  /// Initialize all Flutter plugins for testing
  static Future<void> setupAll() async {
    if (_isInitialized) return;

    // Ensure Flutter test binding is initialized
    TestWidgetsFlutterBinding.ensureInitialized();

    // Setup SharedPreferences mock
    SharedPreferences.setMockInitialValues({});

    // Setup path_provider mock
    _mockPathProvider = MockPathProviderPlatform();
    PathProviderPlatform.instance = _mockPathProvider!;

    // Setup sqflite for testing
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      // Initialize FFI for desktop platforms
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    }

    // Create necessary mock directories
    await _createMockDirectories();

    _isInitialized = true;
  }

  /// Create mock directories for testing
  static Future<void> _createMockDirectories() async {
    try {
      await Directory('/tmp/test_app_docs').create(recursive: true);
      await Directory('/tmp/test_app_support').create(recursive: true);
      await Directory('/tmp/test_downloads').create(recursive: true);
      await Directory('/tmp/test_temp').create(recursive: true);
    } catch (e) {
      // Ignore directory creation errors in test environment
      if (_verboseLogging) {
        print('Warning: Could not create mock directories: $e');
      }
    }
  }

  /// Setup for unit tests (lighter version)
  static Future<void> setupUnitTest() async {
    if (_isInitialized) return;

    // Basic setup for unit tests
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});

    _isInitialized = true;
  }

  /// Setup for widget tests
  static Future<void> setupWidgetTest() async {
    if (_isInitialized) return;

    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});

    // Setup path_provider for widget tests
    _mockPathProvider = MockPathProviderPlatform();
    PathProviderPlatform.instance = _mockPathProvider!;

    _isInitialized = true;
  }

  /// Setup for integration tests
  static Future<void> setupIntegrationTest() async {
    await setupAll();
  }

  /// Clean up after tests
  static Future<void> teardown() async {
    _mockPathProvider = null;
    _isInitialized = false;
  }

  /// Get mock application documents directory
  static Directory getMockAppDocumentsDir() {
    return Directory('/tmp/test_app_docs');
  }

  /// Get mock temporary directory
  static Directory getMockTempDir() {
    return Directory('/tmp/test_temp');
  }

  /// Create a temporary directory for testing
  static Future<Directory> createTempTestDir(String prefix) async {
    final tempDir = await getTemporaryDirectory();
    final testDir = Directory('${tempDir.path}/$prefix');
    if (!await testDir.exists()) {
      await testDir.create(recursive: true);
    }
    return testDir;
  }

  /// Clean up temporary test directory
  static Future<void> cleanupTempTestDir(Directory dir) async {
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
  }
}
