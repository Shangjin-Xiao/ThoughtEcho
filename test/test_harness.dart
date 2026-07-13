import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// A path-provider fake that keeps every plugin path inside one test root.
final class TestPathProviderPlatform extends PathProviderPlatform {
  /// Creates a fake rooted at [root].
  TestPathProviderPlatform(this.root);

  /// The directory that owns every returned path.
  final Directory root;

  String get _applicationCachePath => p.join(root.path, 'cache');
  String get _applicationDocumentsPath => p.join(root.path, 'documents');
  String get _applicationSupportPath => p.join(root.path, 'support');
  String get _downloadsPath => p.join(root.path, 'downloads');
  String get _externalStoragePath => p.join(root.path, 'external');
  String get _libraryPath => p.join(root.path, 'library');
  String get _temporaryPath => p.join(root.path, 'temporary');

  @override
  Future<String?> getApplicationCachePath() async => _applicationCachePath;

  @override
  Future<String?> getApplicationDocumentsPath() async =>
      _applicationDocumentsPath;

  @override
  Future<String?> getApplicationSupportPath() async => _applicationSupportPath;

  @override
  Future<String?> getDownloadsPath() async => _downloadsPath;

  @override
  Future<List<String>?> getExternalCachePaths() async => [
        _externalStoragePath,
      ];

  @override
  Future<String?> getExternalStoragePath() async => _externalStoragePath;

  @override
  Future<List<String>?> getExternalStoragePaths({
    StorageDirectory? type,
  }) async =>
      [_externalStoragePath];

  @override
  Future<String?> getLibraryPath() async => _libraryPath;

  @override
  Future<String?> getTemporaryPath() async => _temporaryPath;
}

/// Installs deterministic plugin fakes for a test isolate.
///
/// Tests that need Flutter plugins should call [initialize] in `setUp` or
/// `setUpAll` and [tearDown] in the corresponding cleanup hook. The harness
/// owns one temporary root per isolate, so concurrent test files never share
/// plugin paths or SQLite files.
final class TestHarness {
  static bool _desktopDatabaseConfigured = false;
  static PathProviderPlatform? _originalPathProvider;
  static TestPathProviderPlatform? _pathProvider;
  static Directory? _root;

  /// Installs the shared-preferences, path-provider, and desktop SQLite fakes.
  static Future<void> initialize() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});

    if (_pathProvider != null) {
      return;
    }

    final root = await Directory.systemTemp.createTemp('thoughtecho_test_');
    for (final child in [
      'cache',
      'documents',
      'support',
      'downloads',
      'external',
      'library',
      'temporary',
    ]) {
      await Directory(p.join(root.path, child)).create();
    }

    _root = root;
    _originalPathProvider = PathProviderPlatform.instance;
    _pathProvider = TestPathProviderPlatform(root);
    PathProviderPlatform.instance = _pathProvider!;

    if (!_desktopDatabaseConfigured &&
        (Platform.isLinux || Platform.isMacOS || Platform.isWindows)) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
      _desktopDatabaseConfigured = true;
    }

    // Some existing suites install the harness in setUpAll. Register cleanup
    // here so their test-owned paths are still released at the enclosing test
    // scope, while explicit calls to tearDown remain safe and idempotent.
    addTearDown(TestHarness.tearDown);
  }

  /// Removes the isolated files and restores the path-provider implementation.
  static Future<void> tearDown() async {
    final originalPathProvider = _originalPathProvider;
    if (originalPathProvider != null) {
      PathProviderPlatform.instance = originalPathProvider;
    }

    final root = _root;
    _originalPathProvider = null;
    _pathProvider = null;
    _root = null;

    if (root != null && await root.exists()) {
      await root.delete(recursive: true);
    }
  }

  /// Creates a directory below this isolate's temporary root.
  static Future<Directory> createTempDirectory(String prefix) async {
    await initialize();
    final root = _root!;
    final directory = Directory(p.join(root.path, 'temporary', prefix));
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
    return directory;
  }

  /// Deletes a directory created for an individual test.
  static Future<void> deleteTempDirectory(Directory directory) async {
    if (await directory.exists()) {
      await directory.delete(recursive: true);
    }
  }

  /// Returns the fake application-documents directory after initialization.
  static Directory get applicationDocumentsDirectory {
    final pathProvider = _pathProvider;
    if (pathProvider == null) {
      throw StateError(
          'Call TestHarness.initialize() before reading test paths.');
    }
    return Directory(p.join(pathProvider.root.path, 'documents'));
  }
}
