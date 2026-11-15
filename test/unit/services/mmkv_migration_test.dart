import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:thoughtecho/services/app_preferences_service.dart';
import 'package:thoughtecho/services/settings_service.dart';
import 'package:thoughtecho/utils/mmkv_binary_reader.dart';
import 'package:thoughtecho/utils/platform_helper.dart';

import '../../test_harness.dart';

class _CountingStorageAdapter implements StorageAdapter {
  _CountingStorageAdapter({this.initGate});

  final Future<void>? initGate;
  final Map<String, Object?> _data = {};
  int initializeCount = 0;

  @override
  Future<void> initialize() async {
    initializeCount++;
    if (initGate != null) {
      await initGate;
    }
  }

  Future<void> reload() async {}

  @override
  Future<bool> setString(String key, String value) async {
    _data[key] = value;
    return true;
  }

  @override
  String? getString(String key) {
    final value = _data[key];
    return value is String ? value : null;
  }

  @override
  Future<bool> setInt(String key, int value) async {
    _data[key] = value;
    return true;
  }

  @override
  int? getInt(String key) {
    final value = _data[key];
    return value is int ? value : null;
  }

  @override
  Future<bool> setDouble(String key, double value) async {
    _data[key] = value;
    return true;
  }

  @override
  double? getDouble(String key) {
    final value = _data[key];
    return value is double ? value : null;
  }

  @override
  Future<bool> setBool(String key, bool value) async {
    _data[key] = value;
    return true;
  }

  @override
  bool? getBool(String key) {
    final value = _data[key];
    return value is bool ? value : null;
  }

  @override
  Future<bool> setStringList(String key, List<String> value) async {
    _data[key] = List<String>.from(value);
    return true;
  }

  @override
  List<String>? getStringList(String key) {
    final value = _data[key];
    return value is List<String> ? List<String>.from(value) : null;
  }

  @override
  bool containsKey(String key) => _data.containsKey(key);

  @override
  Future<bool> remove(String key) async {
    _data.remove(key);
    return true;
  }

  @override
  Future<bool> clear() async {
    _data.clear();
    return true;
  }

  @override
  Set<String> getKeys() => _data.keys.toSet();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() async {
    await TestHarness.initialize();
    tempDir = await Directory.systemTemp.createTemp('mmkv_migration_test_');
    SharedPreferences.setMockInitialValues({});
    AppPreferencesService().resetForTesting();
  });

  tearDown(() async {
    AppPreferencesService().resetForTesting();
    await TestHarness.tearDown();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('AppPreferencesService Migration', () {
    test(
        'migrates binary mmkv.default entries to SharedPreferences, overwrites stale SP values, and preserves SP-only keys',
        () async {
      // Seed SharedPreferences with a stale value for theme_mode and an SP-only key
      SharedPreferences.setMockInitialValues({
        'theme_mode': 'light',
        'custom_data_directory_path': '/custom/notes/dir',
      });

      final mmkvPath = '${tempDir.path}/mmkv.default';
      final encoder = MmkvBinaryEncoder()
        ..writeString('theme_mode', 'dark')
        ..writeString('theme_style', 'paper')
        ..writeBool('app_installed_v2', true)
        ..writeBool('agent_memory_enabled', false)
        ..writeInt('custom_color', 0xFF123456)
        ..writeString('smart_push_today_daily_quote_pushed', '2026-11-07')
        ..writeString('draft_abc', '{"plainText":"saved draft"}');

      await File(mmkvPath)
          .writeAsBytes(encoder.toFileBytes(minTotalSize: 4096));
      await File('$mmkvPath.crc').writeAsBytes(encoder.toCrcBytes());

      final appPrefs = AppPreferencesService()
        ..configureForTesting(
          candidateMmkvFiles: [mmkvPath],
        );

      await appPrefs.initialize();

      // Stale SP value ('light') must be overwritten by MMKV value ('dark')
      expect(appPrefs.getString('theme_mode'), equals('dark'));
      expect(appPrefs.getString('theme_style'), equals('paper'));
      expect(appPrefs.getBool('app_installed_v2'), isTrue);
      expect(appPrefs.getBool('agent_memory_enabled'), isFalse);
      expect(appPrefs.getInt('custom_color'), equals(0xFF123456));
      expect(
        appPrefs.getString('smart_push_today_daily_quote_pushed'),
        equals('2026-11-07'),
      );
      expect(
        appPrefs.getString('draft_abc'),
        equals('{"plainText":"saved draft"}'),
      );

      // SP-only key must be preserved intact
      expect(
        appPrefs.getString('custom_data_directory_path'),
        equals('/custom/notes/dir'),
      );

      // Migration watermarks must be set
      expect(appPrefs.getBool(kKvEngineMigratedKey), isTrue);
      expect(appPrefs.getBool(kLegacyMmkvMigrationCompleteKey), isTrue);

      // Diagnostic report must show 0 diffs
      final report = await appPrefs.collectDiagnosticReport();
      expect(report.kvEngineMigrated, isTrue);
      expect(report.primaryBinaryResult.crcMatched, isTrue);
      expect(report.diffCount, equals(0));
    });

    test(
      'completed migration preserves newer preferences on restart and rescan',
      () async {
        final path = '${tempDir.path}/mmkv.default';
        final encoder = MmkvBinaryEncoder()
          ..writeString('theme_style', 'material')
          ..writeString('theme_mode', 'dark')
          ..writeTombstone('draft_retained');
        await File(path).writeAsBytes(encoder.toFileBytes());
        await File('$path.crc').writeAsBytes(encoder.toCrcBytes());
        SharedPreferences.setMockInitialValues({
          kKvEngineMigratedKey: true,
          'theme_style': 'paper',
          'draft_retained': 'new draft',
        });
        final storage = AppPreferencesService()
          ..configureForTesting(
            candidateMmkvFiles: [path],
            candidateDbPaths: const [],
          );
        await storage.initialize();
        expect(storage.getString('theme_style'), 'paper');
        expect(storage.getString('theme_mode'), isNull);

        final snapshot = await storage.runMigration(force: true);
        expect(snapshot.wasAlreadyMigrated, isTrue);
        expect(snapshot.migratedFromBinaryCount, 1);
        expect(storage.getString('theme_style'), 'paper');
        expect(storage.getString('theme_mode'), 'dark');
        expect(storage.getString('draft_retained'), 'new draft');
      },
    );

    test(
      'first migration applies tombstones to stale SharedPreferences',
      () async {
        SharedPreferences.setMockInitialValues({
          'draft_removed': 'stale draft',
        });
        final path = '${tempDir.path}/mmkv.default';
        final encoder = MmkvBinaryEncoder()..writeTombstone('draft_removed');
        await File(path).writeAsBytes(encoder.toFileBytes());
        await File('$path.crc').writeAsBytes(encoder.toCrcBytes());
        final storage = AppPreferencesService()
          ..configureForTesting(
            candidateMmkvFiles: [path],
            candidateDbPaths: const [],
          );
        await storage.initialize();
        expect(storage.containsKey('draft_removed'), isFalse);
        final prefs = await SharedPreferences.getInstance();
        expect(prefs.containsKey('draft_removed'), isFalse);
      },
    );

    test(
      'empty and corrupt candidates cannot hide a valid recovery file',
      () async {
        final empty = '${tempDir.path}/empty';
        final corrupt = '${tempDir.path}/corrupt';
        final valid = '${tempDir.path}/valid';
        await File(empty).writeAsBytes(Uint8List(4096));
        final bad = MmkvBinaryEncoder()..writeString('theme_style', 'plain');
        await File(corrupt).writeAsBytes(bad.toFileBytes());
        await File('$corrupt.crc').writeAsBytes(
          bad.toCrcBytes(
            overrideCrcDigest: 0xdeadbeef,
            lastCrcDigest: 0xdeadbeef,
          ),
        );
        final good = MmkvBinaryEncoder()..writeString('theme_style', 'paper');
        await File(valid).writeAsBytes(good.toFileBytes());
        await File('$valid.crc').writeAsBytes(good.toCrcBytes());
        final storage = AppPreferencesService()
          ..configureForTesting(
            candidateMmkvFiles: [empty, corrupt, valid],
            candidateDbPaths: const [],
          );
        await storage.initialize();
        expect(storage.getString('theme_style'), 'paper');
        expect(storage.lastMigrationSnapshot?.primaryMmkvFilePath, valid);
      },
    );

    test(
      'clear before init persists watermarks and prevents legacy resurrection',
      () async {
        SharedPreferences.setMockInitialValues({'theme_style': 'paper'});
        final service = AppPreferencesService()
          ..configureForTesting(
            candidateMmkvFiles: const [],
            candidateDbPaths: const [],
          );
        expect(await service.clear(), isTrue);
        final prefs = await SharedPreferences.getInstance();
        final nonLogKeys =
            prefs.getKeys().where((k) => !k.startsWith('log_level')).toSet();
        expect(nonLogKeys, {
          kKvEngineMigratedKey,
          kLegacyMmkvMigrationCompleteKey,
        });
        expect(prefs.containsKey('theme_style'), isFalse);
        expect(prefs.getBool(kKvEngineMigratedKey), isTrue);
        expect(prefs.getBool(kLegacyMmkvMigrationCompleteKey), isTrue);
        expect(service.getString('theme_style'), isNull);
      },
    );

    test('concurrent first writes persist every value', () async {
      final service = AppPreferencesService()
        ..configureForTesting(
          candidateMmkvFiles: const [],
          candidateDbPaths: const [],
        );
      expect(
        await Future.wait([
          service.setString('theme_style', 'paper'),
          service.setBool('use_dynamic_color', false),
          service.setInt('custom_color', 42),
        ]),
        everyElement(isTrue),
      );
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('theme_style'), 'paper');
      expect(prefs.getBool('use_dynamic_color'), isFalse);
      expect(prefs.getInt('custom_color'), 42);
    });

    test(
      'diagnostic JSON redacts nested credentials and preserves safe fields',
      () async {
        final payload = {
          'providers': [
            {'name': 'Synthetic provider', 'apiKey': 'synthetic-credential'},
          ],
          'enabled': true,
        };
        SharedPreferences.setMockInitialValues({
          kKvEngineMigratedKey: true,
          'multi_ai_settings': json.encode(payload),
          'webdav_password': 'synthetic-password',
          'draft_example': 'synthetic private draft',
          'theme_style': 'paper',
        });
        final storage = AppPreferencesService()
          ..configureForTesting(
            candidateMmkvFiles: const [],
            candidateDbPaths: const [],
          );
        await storage.initialize();
        final report = await storage.collectDiagnosticReport();
        final serialized = json.encode(report.toRedactedJson());
        expect(serialized, isNot(contains('synthetic-credential')));
        expect(serialized, isNot(contains('synthetic-password')));
        expect(serialized, isNot(contains('synthetic private draft')));
        final entry = report.comparisons.singleWhere(
          (entry) => entry.key == 'multi_ai_settings',
        );
        final redacted = json.decode(
          entry.toRedactedJson()['sharedPrefsValue'] as String,
        ) as Map;
        expect(redacted['enabled'], isTrue);
        expect(
          (redacted['providers'] as List).single['name'],
          'Synthetic provider',
        );
        expect(storage.getString('multi_ai_settings'), json.encode(payload));
      },
    );

    for (final size in [4096, 8192, 8193]) {
      test(
        'SQLite recovery respects the populated-file boundary at $size bytes',
        () async {
          final path = '${tempDir.path}/thoughtecho.db';
          final bytes = Uint8List(size);
          final magic = ascii.encode('SQLite format 3\x00');
          bytes.setRange(0, magic.length, magic);
          await File(path).writeAsBytes(bytes);
          final storage = AppPreferencesService()
            ..configureForTesting(
              candidateMmkvFiles: const [],
              candidateDbPaths: [path],
            );
          await storage.initialize();
          expect(
            storage.getBool('app_installed_v2'),
            size > 8192 ? isTrue : isNull,
          );
          expect(
            storage.lastMigrationSnapshot?.healedFromSqliteCount,
            size > 8192 ? 5 : 0,
          );
        },
      );
    }

    test(
      'SQLite recovery leaves existing installations and settings unchanged',
      () async {
        const saved =
            '{"hasCompletedOnboarding":false,"sentryDisclosureShown":false}';
        SharedPreferences.setMockInitialValues({
          'app_installed_v2': true,
          'app_settings': saved,
        });
        final path = '${tempDir.path}/thoughtecho.db';
        final bytes = Uint8List(16384);
        final magic = ascii.encode('SQLite format 3\x00');
        bytes.setRange(0, magic.length, magic);
        await File(path).writeAsBytes(bytes);
        final storage = AppPreferencesService()
          ..configureForTesting(
            candidateMmkvFiles: const [],
            candidateDbPaths: [path],
          );
        await storage.initialize();
        expect(storage.getString('app_settings'), saved);
        expect(storage.lastMigrationSnapshot?.healedFromSqliteCount, 0);
      },
    );

    test('remove before init deletes the persisted value', () async {
      SharedPreferences.setMockInitialValues({'theme_style': 'paper'});
      final service = AppPreferencesService()
        ..configureForTesting(
          candidateMmkvFiles: const [],
          candidateDbPaths: const [],
        );
      expect(await service.remove('theme_style'), isTrue);
      expect(service.containsKey('theme_style'), isFalse);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.containsKey('theme_style'), isFalse);
    });

    test('synchronous reads before init return safe empty results', () {
      final service = AppPreferencesService();
      expect(service.isInitialized, isFalse);
      expect(service.getString('missing'), isNull);
      expect(service.getBool('missing'), isNull);
      expect(service.getInt('missing'), isNull);
      expect(service.getDouble('missing'), isNull);
      expect(service.getStringList('missing'), isNull);
      expect(service.getJson('missing'), isNull);
      expect(service.containsKey('missing'), isFalse);
      expect(service.getAllKeys(), isEmpty);
      expect(() => service.getAllKeysStrict(), throwsStateError);
    });

    test(
        'Channel 3 heals app_installed_v2 and app_settings when populated thoughtecho.db exists on disk',
        () async {
      // 1. An all-zero 16KB file without SQLite magic header must NOT trigger self-healing
      SharedPreferences.setMockInitialValues({});
      final corruptedDbPath = '${tempDir.path}/corrupted_thoughtecho.db';
      await File(corruptedDbPath).writeAsBytes(Uint8List(16384));

      final appPrefsCorrupted = AppPreferencesService()
        ..configureForTesting(
          candidateMmkvFiles: ['${tempDir.path}/nonexistent_mmkv.default'],
          candidateDbPaths: [corruptedDbPath],
        );
      await appPrefsCorrupted.initialize();
      expect(appPrefsCorrupted.getBool('app_installed_v2'), isNull);

      // 2. A valid >8KB SQLite file with "SQLite format 3\0" header heals flags & preserves sentryDisclosureShown
      SharedPreferences.setMockInitialValues({
        'app_settings': json.encode({'sentryDisclosureShown': false}),
      });
      final fakeDbPath = '${tempDir.path}/thoughtecho.db';
      final validDbBytes = Uint8List(16384);
      final magic = ascii.encode('SQLite format 3\x00');
      validDbBytes.setRange(0, magic.length, magic);
      await File(fakeDbPath).writeAsBytes(validDbBytes);

      final appPrefs = AppPreferencesService()
        ..configureForTesting(
          candidateMmkvFiles: ['${tempDir.path}/nonexistent_mmkv.default'],
          candidateDbPaths: [fakeDbPath],
        );

      await appPrefs.initialize();

      expect(appPrefs.getBool('app_installed_v2'), isTrue);
      expect(appPrefs.getBool('initial_database_setup_complete'), isTrue);
      expect(appPrefs.getBool('database_migration_complete'), isTrue);
      expect(appPrefs.getBool('hasCompletedOnboarding'), isTrue);

      final appSettingsRaw = appPrefs.getString('app_settings');
      expect(appSettingsRaw, isNotNull);
      final decoded = json.decode(appSettingsRaw!) as Map<String, dynamic>;
      expect(decoded['hasCompletedOnboarding'], isTrue);
      expect(decoded['sentryDisclosureShown'], isFalse);
      expect(appPrefs.lastMigrationSnapshot?.healedFromSqliteCount, equals(5));
    });

    test(
        'AppPreferencesService async write methods await initialization when called before explicit init()',
        () async {
      SharedPreferences.setMockInitialValues({kKvEngineMigratedKey: true});
      final service = AppPreferencesService();
      service.resetForTesting();
      service.configureForTesting(
        candidateMmkvFiles: const [],
      );

      // Call setBool, setInt, setDouble, setStringList, setJson without calling service.init() first
      expect(await service.setBool('flag_a', true), isTrue);
      expect(await service.setInt('count_b', 42), isTrue);
      expect(await service.setDouble('ratio_c', 3.14), isTrue);
      expect(await service.setStringList('list_d', ['x', 'y']), isTrue);
      expect(await service.setJson('json_e', {'ok': 1}), isTrue);

      expect(service.getBool('flag_a'), isTrue);
      expect(service.getInt('count_b'), equals(42));
      expect(service.getDouble('ratio_c'), closeTo(3.14, 1e-9));
      expect(service.getStringList('list_d'), equals(['x', 'y']));
      expect(service.getJson('json_e'), equals({'ok': 1}));

      final arch = await PlatformHelper.getCpuArchitecture();
      final expectedArch =
          PlatformHelper.pointerBits == 64 ? '64-bit' : '32-bit';
      expect(arch, equals(expectedArch));
    });

    test(
        'merges entries across candidate MMKV files and respects tombstones from primary candidate',
        () async {
      final primaryPath = '${tempDir.path}/primary_mmkv.default';
      final secondaryPath = '${tempDir.path}/secondary_mmkv.default';

      final primaryEncoder = MmkvBinaryEncoder()
        ..writeString('theme_style', 'paper')
        ..writeBool('app_installed_v2', true)
        ..writeTombstone('deleted_flag');
      File(primaryPath)
          .writeAsBytesSync(primaryEncoder.toFileBytes(minTotalSize: 4096));
      File('$primaryPath.crc').writeAsBytesSync(primaryEncoder.toCrcBytes());

      final secondaryEncoder = MmkvBinaryEncoder()
        ..writeString('theme_style', 'plain')
        ..writeBool('deleted_flag', true)
        ..writeString('secondary_only_key', 'rescued_value');
      File(secondaryPath)
          .writeAsBytesSync(secondaryEncoder.toFileBytes(minTotalSize: 4096));
      File('$secondaryPath.crc')
          .writeAsBytesSync(secondaryEncoder.toCrcBytes());

      final appPrefs = AppPreferencesService()
        ..configureForTesting(
          candidateMmkvFiles: [primaryPath, secondaryPath],
        );

      await appPrefs.initialize();

      expect(appPrefs.getString('theme_style'), equals('paper'));
      expect(appPrefs.getString('secondary_only_key'), equals('rescued_value'));
      expect(appPrefs.getBool('deleted_flag'), isNull);
    });

    test(
        'SettingsService.restoreAllSettingsFromBackup restores theme and push settings and notifies listeners',
        () async {
      final prefs = await SharedPreferences.getInstance();
      final settingsService = SettingsService(prefs);
      var notified = false;
      settingsService.addListener(() {
        notified = true;
      });

      final backupData = {
        'theme_style': 'paper',
        'theme_accent_material': 'emerald',
        'theme_accent_paper': 'bamboo',
        'theme_accent_plain': 'slate',
        'custom_color': 0xFF112233,
        'use_custom_color': true,
        'use_dynamic_color': false,
        'smart_push_settings_v2': {'enabled': true, 'intervalHours': 6},
      };

      await settingsService.restoreAllSettingsFromBackup(backupData);

      expect(notified, isTrue);
      final appPrefs = AppPreferencesService();
      expect(appPrefs.getString('theme_style'), equals('paper'));
      expect(appPrefs.getString('theme_accent_material'), equals('emerald'));
      expect(appPrefs.getString('theme_accent_paper'), equals('bamboo'));
      expect(appPrefs.getString('theme_accent_plain'), equals('slate'));
      expect(appPrefs.getInt('custom_color'), equals(0xFF112233));
      expect(appPrefs.getBool('use_custom_color'), isTrue);
      expect(appPrefs.getBool('use_dynamic_color'), isFalse);
      expect(
        appPrefs.getString('smart_push_settings_v2'),
        contains('"enabled":true'),
      );
    });

    test('AppPreferencesService resolves to the same singleton', () {
      expect(
          identical(AppPreferencesService(), AppPreferencesService()), isTrue);
    });

    test(
        'force migration does not resurrect retired SQLite keys and diagnostics treats binary-only retired keys as consistent',
        () async {
      final path = '${tempDir.path}/mmkv.default';
      final encoder = MmkvBinaryEncoder()
        ..writeString('theme_style', 'paper')
        ..writeString('draft_legacy_1', '{"plainText":"old draft"}')
        ..writeString(
          'periodic_insights_history',
          '[{"insight":"old","periodType":"week","periodLabel":"W1","createdAt":"2026-07-01T00:00:00.000","isAiGenerated":true}]',
        );
      await File(path).writeAsBytes(encoder.toFileBytes(minTotalSize: 4096));
      await File('$path.crc').writeAsBytes(encoder.toCrcBytes());

      SharedPreferences.setMockInitialValues({
        kKvEngineMigratedKey: true,
        kDraftsSqliteMigratedKey: true,
        kPeriodicInsightsSqliteMigratedKey: true,
        'theme_style': 'paper',
      });

      final storage = AppPreferencesService()
        ..configureForTesting(
          candidateMmkvFiles: [path],
          candidateDbPaths: const [],
        );
      await storage.initialize();

      // Already retired keys must stay absent after init & forced migration
      final snapshot = await storage.runMigration(force: true);
      expect(snapshot.migratedFromBinaryCount, equals(0));
      expect(storage.containsKey('draft_legacy_1'), isFalse);
      expect(storage.containsKey('periodic_insights_history'), isFalse);

      // Diagnostic report must treat retired binary-only keys as consistent
      final report = await storage.collectDiagnosticReport();
      expect(report.diffCount, equals(0));
      final retiredDraftEntry = report.comparisons.singleWhere(
        (entry) => entry.key == 'draft_legacy_1',
      );
      expect(retiredDraftEntry.allConsistent, isTrue);
      final retiredInsightEntry = report.comparisons.singleWhere(
        (entry) => entry.key == 'periodic_insights_history',
      );
      expect(retiredInsightEntry.allConsistent, isTrue);

      // Clearing storage preserves SQLite takeover watermarks and prevents resurrection
      expect(await storage.clear(), isTrue);
      expect(storage.getBool(kDraftsSqliteMigratedKey), isTrue);
      expect(storage.getBool(kPeriodicInsightsSqliteMigratedKey), isTrue);
      final afterClearSnapshot = await storage.runMigration(force: true);
      // 仅非退役键 theme_style 被迁移，已由 SQLite 接管的草稿/洞察键不得复活
      expect(afterClearSnapshot.migratedFromBinaryCount, equals(1));
      expect(storage.getString('theme_style'), equals('paper'));
      expect(storage.containsKey('draft_legacy_1'), isFalse);
      expect(storage.containsKey('periodic_insights_history'), isFalse);
    });

    test(
        'cold-upgrade skipping intermediate versions migrates legacy mmkv.default, archives files to .migrated.bak, and keeps diagnostics readable',
        () async {
      final mmkvPath = '${tempDir.path}/mmkv.default';
      final encoder = MmkvBinaryEncoder()
        ..writeBool('app_installed_v2', true)
        ..writeString('theme_style', 'paper')
        ..writeString('theme_mode', 'dark')
        ..writeInt('custom_color', 0xFF2B5B84)
        ..writeDouble('font_scale', 1.25)
        ..writeString('favorite_tags', json.encode(['随想', '读书']))
        ..writeString(
          'app_settings',
          json.encode({'hasCompletedOnboarding': true}),
        );

      await File(mmkvPath)
          .writeAsBytes(encoder.toFileBytes(minTotalSize: 4096));
      await File('$mmkvPath.crc').writeAsBytes(encoder.toCrcBytes());

      final service = AppPreferencesService()
        ..configureForTesting(
          candidateMmkvFiles: [mmkvPath],
          candidateDbPaths: const [],
        );

      await service.init();

      expect(service.isInitialized, isTrue);
      expect(service.getBool('app_installed_v2'), isTrue);
      expect(service.getString('theme_style'), equals('paper'));
      expect(service.getString('theme_mode'), equals('dark'));
      expect(service.getInt('custom_color'), equals(0xFF2B5B84));
      expect(service.getDouble('font_scale'), closeTo(1.25, 1e-9));
      expect(service.getStringList('favorite_tags'), equals(['随想', '读书']));
      expect(
        service.getJson('app_settings'),
        equals({'hasCompletedOnboarding': true}),
      );
      expect(service.lastMigrationSnapshot?.wasAlreadyMigrated, isFalse);
      expect(
        service.lastMigrationSnapshot?.migratedFromBinaryCount,
        greaterThanOrEqualTo(7),
      );

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('theme_style'), equals('paper'));
      expect(prefs.getBool(kKvEngineMigratedKey), isTrue);
      expect(prefs.getBool(kLegacyMmkvMigrationCompleteKey), isTrue);

      // Original mmkv.default and .crc are archived to .migrated.bak and .migrated.bak.crc
      expect(File(mmkvPath).existsSync(), isFalse);
      expect(File('$mmkvPath.crc').existsSync(), isFalse);
      expect(File('$mmkvPath.migrated.bak').existsSync(), isTrue);
      expect(File('$mmkvPath.migrated.bak.crc').existsSync(), isTrue);

      final report = await service.collectDiagnosticReport();
      expect(report.kvEngineMigrated, isTrue);
      expect(report.primaryBinaryResult.fileExists, isTrue);
      expect(report.primaryBinaryResult.crcMatched, isTrue);
      expect(report.diffCount, equals(0));
      expect(report.consistentCount, greaterThan(0));

      // Simulated subsequent cold restart reads SharedPreferences cleanly without re-migrating
      service.resetForTesting();
      service.configureForTesting(
        candidateMmkvFiles: [mmkvPath],
        candidateDbPaths: const [],
      );
      await service.init();
      expect(service.getString('theme_style'), equals('paper'));
      expect(service.lastMigrationSnapshot?.wasAlreadyMigrated, isTrue);
    });

    test(
        'migrates provider_api_keys and wipes mmkv.default, .crc, and .migrated.bak from disk',
        () async {
      final mmkvPath = '${tempDir.path}/mmkv.default';
      final secretPayload = json.encode({'openai': 'synthetic-provider-key'});
      final encoder = MmkvBinaryEncoder()
        ..writeString('provider_api_keys', secretPayload)
        ..writeString('theme_style', 'paper');

      await File(mmkvPath)
          .writeAsBytes(encoder.toFileBytes(minTotalSize: 4096));
      await File('$mmkvPath.crc').writeAsBytes(encoder.toCrcBytes());
      await File('$mmkvPath.migrated.bak').writeAsBytes(Uint8List(64));
      await File('$mmkvPath.migrated.bak.crc').writeAsBytes(Uint8List(32));

      final service = AppPreferencesService()
        ..configureForTesting(
          candidateMmkvFiles: [mmkvPath],
          candidateDbPaths: const [],
        );

      await service.init();

      expect(service.getString('provider_api_keys'), equals(secretPayload));
      expect(service.getString('theme_style'), equals('paper'));

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('provider_api_keys'), equals(secretPayload));

      expect(File(mmkvPath).existsSync(), isFalse);
      expect(File('$mmkvPath.crc').existsSync(), isFalse);
      expect(File('$mmkvPath.migrated.bak').existsSync(), isFalse);
      expect(File('$mmkvPath.migrated.bak.crc').existsSync(), isFalse);
    });

    test(
        'migrates ai_settings and multi_ai_settings with non-empty apiKey and wipes MMKV artifacts from disk',
        () async {
      final cases = <String, String>{
        'ai_settings': json.encode({
          'apiKey': 'synthetic-ai-secret',
          'model': 'synthetic-model',
        }),
        'multi_ai_settings': json.encode({
          'currentProviderId': 'provider_1',
          'providers': [
            {
              'id': 'provider_1',
              'name': 'Synthetic Provider',
              'apiKey': 'synthetic-multi-secret',
            },
          ],
        }),
      };

      for (final entry in cases.entries) {
        final caseDir = await tempDir.createTemp('wipe_${entry.key}_');
        final mmkvPath = '${caseDir.path}/mmkv.default';
        final encoder = MmkvBinaryEncoder()
          ..writeString(entry.key, entry.value)
          ..writeString('theme_style', 'plain');

        await File(mmkvPath)
            .writeAsBytes(encoder.toFileBytes(minTotalSize: 4096));
        await File('$mmkvPath.crc').writeAsBytes(encoder.toCrcBytes());

        SharedPreferences.setMockInitialValues({});
        final service = AppPreferencesService()
          ..resetForTesting()
          ..configureForTesting(
            candidateMmkvFiles: [mmkvPath],
            candidateDbPaths: const [],
          );

        await service.init();

        expect(service.getString(entry.key), equals(entry.value));
        expect(service.getString('theme_style'), equals('plain'));
        expect(File(mmkvPath).existsSync(), isFalse);
        expect(File('$mmkvPath.crc').existsSync(), isFalse);
        expect(File('$mmkvPath.migrated.bak').existsSync(), isFalse);
        expect(File('$mmkvPath.migrated.bak.crc').existsSync(), isFalse);
      }
    });

    test('reload refreshes values updated externally in SharedPreferences',
        () async {
      SharedPreferences.setMockInitialValues({
        kKvEngineMigratedKey: true,
        'external_string': 'initial',
      });

      final service = AppPreferencesService()
        ..configureForTesting(
          candidateMmkvFiles: const [],
          candidateDbPaths: const [],
        );
      await service.init();
      expect(service.getString('external_string'), equals('initial'));

      // Simulate an external isolate writing to the underlying SharedPreferences store
      SharedPreferences.resetStatic();
      final externalPrefs = await SharedPreferences.getInstance();
      await externalPrefs.setString('external_string', 'updated_from_outside');
      await externalPrefs.setInt('external_counter', 99);

      // Cached adapter retains stale snapshot until reload() is called
      expect(service.getString('external_string'), equals('initial'));
      expect(service.getInt('external_counter'), isNull);

      await service.reload();

      expect(
        service.getString('external_string'),
        equals('updated_from_outside'),
      );
      expect(service.getInt('external_counter'), equals(99));
    });

    test(
        'concurrent init() calls complete safely without re-running initialization',
        () async {
      final gate = Completer<void>();
      final adapter = _CountingStorageAdapter(initGate: gate.future);
      final service = AppPreferencesService()
        ..configureForTesting(
          primaryAdapter: adapter,
          candidateMmkvFiles: const [],
          candidateDbPaths: const [],
        );

      final pending = Future.wait([
        AppPreferencesService().init(),
        AppPreferencesService().init(),
        AppPreferencesService().init(),
      ]);

      await Future<void>.delayed(Duration.zero);
      expect(adapter.initializeCount, equals(1));

      gate.complete();
      await pending;

      expect(service.isInitialized, isTrue);
      expect(adapter.initializeCount, equals(1));

      await AppPreferencesService().init();
      expect(adapter.initializeCount, equals(1));
    });

    test(
        'concurrent init() calls with legacy mmkv.default complete migration once',
        () async {
      final mmkvPath = '${tempDir.path}/mmkv.default';
      final encoder = MmkvBinaryEncoder()
        ..writeString('theme_style', 'paper')
        ..writeBool('app_installed_v2', true);
      await File(mmkvPath)
          .writeAsBytes(encoder.toFileBytes(minTotalSize: 4096));
      await File('$mmkvPath.crc').writeAsBytes(encoder.toCrcBytes());

      final service = AppPreferencesService()
        ..configureForTesting(
          candidateMmkvFiles: [mmkvPath],
          candidateDbPaths: const [],
        );

      await Future.wait([
        AppPreferencesService().init(),
        AppPreferencesService().init(),
        AppPreferencesService().init(),
      ]);

      expect(service.isInitialized, isTrue);
      expect(service.getString('theme_style'), equals('paper'));
      expect(service.getBool('app_installed_v2'), isTrue);
      expect(File('$mmkvPath.migrated.bak').existsSync(), isTrue);
    });

    test(
        'set*/get* roundtrips, remove, containsKey, and key enumeration work end-to-end',
        () async {
      SharedPreferences.setMockInitialValues({kKvEngineMigratedKey: true});
      final service = AppPreferencesService()
        ..configureForTesting(
          candidateMmkvFiles: const [],
          candidateDbPaths: const [],
        );
      await service.init();

      expect(await service.setString('rt_str', 'hello'), isTrue);
      expect(await service.setBool('rt_bool', true), isTrue);
      expect(await service.setInt('rt_int', 2026), isTrue);
      expect(await service.setDouble('rt_double', 2.71828), isTrue);
      expect(
        await service.setStringList('rt_list', ['alpha', 'beta']),
        isTrue,
      );
      expect(
        await service.setJson('rt_json', {
          'nested': {'count': 3},
          'items': ['a', 'b'],
        }),
        isTrue,
      );

      expect(service.getString('rt_str'), equals('hello'));
      expect(service.getBool('rt_bool'), isTrue);
      expect(service.getInt('rt_int'), equals(2026));
      expect(service.getDouble('rt_double'), closeTo(2.71828, 1e-9));
      expect(service.getStringList('rt_list'), equals(['alpha', 'beta']));
      expect(
        service.getJson('rt_json'),
        equals({
          'nested': {'count': 3},
          'items': ['a', 'b'],
        }),
      );

      for (final key in [
        'rt_str',
        'rt_bool',
        'rt_int',
        'rt_double',
        'rt_list',
        'rt_json',
      ]) {
        expect(service.containsKey(key), isTrue, reason: key);
      }

      final expectedKeys = [
        'rt_str',
        'rt_bool',
        'rt_int',
        'rt_double',
        'rt_list',
        'rt_json',
      ];
      expect(service.getAllKeys(), containsAll(expectedKeys));
      expect(service.getKeys(), containsAll(expectedKeys));
      expect(service.getAllKeysStrict(), containsAll(expectedKeys));

      expect(await service.remove('rt_str'), isTrue);
      expect(service.containsKey('rt_str'), isFalse);
      expect(service.getString('rt_str'), isNull);
      expect(service.getAllKeys(), isNot(contains('rt_str')));
    });
  });
}
