import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:thoughtecho/services/mmkv_service.dart';
import 'package:thoughtecho/services/settings_service.dart';
import 'package:thoughtecho/utils/mmkv_binary_reader.dart';
import 'package:thoughtecho/utils/mmkv_ffi_fix.dart';
import 'package:thoughtecho/utils/platform_helper.dart';

import '../../test_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() async {
    await TestHarness.initialize();
    tempDir = await Directory.systemTemp.createTemp('mmkv_migration_test_');
    SharedPreferences.setMockInitialValues({});
    MMKVService().resetForTesting();
  });

  tearDown(() async {
    MMKVService().resetForTesting();
    await TestHarness.tearDown();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('SafeMMKV & MMKVService Phase 1 Migration', () {
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

      final safeMmkv = SafeMMKV()
        ..configureForTesting(
          candidateMmkvFiles: [mmkvPath],
          forceNativeMmkvSupport: false,
        );

      await safeMmkv.initialize();

      // Stale SP value ('light') must be overwritten by MMKV value ('dark')
      expect(safeMmkv.getString('theme_mode'), equals('dark'));
      expect(safeMmkv.getString('theme_style'), equals('paper'));
      expect(safeMmkv.getBool('app_installed_v2'), isTrue);
      expect(safeMmkv.getBool('agent_memory_enabled'), isFalse);
      expect(safeMmkv.getInt('custom_color'), equals(0xFF123456));
      expect(
        safeMmkv.getString('smart_push_today_daily_quote_pushed'),
        equals('2026-11-07'),
      );
      expect(
        safeMmkv.getString('draft_abc'),
        equals('{"plainText":"saved draft"}'),
      );

      // SP-only key must be preserved intact
      expect(
        safeMmkv.getString('custom_data_directory_path'),
        equals('/custom/notes/dir'),
      );

      // Migration watermarks must be set
      expect(safeMmkv.getBool(kKvEngineMigratedKey), isTrue);
      expect(safeMmkv.getBool(kLegacyMmkvMigrationCompleteKey), isTrue);

      // Diagnostic report must show 0 diffs
      final report = await safeMmkv.collectDiagnosticReport();
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
        final storage = SafeMMKV()
          ..configureForTesting(
            candidateMmkvFiles: [path],
            candidateDbPaths: const [],
            forceNativeMmkvSupport: false,
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
        final storage = SafeMMKV()
          ..configureForTesting(
            candidateMmkvFiles: [path],
            candidateDbPaths: const [],
            forceNativeMmkvSupport: false,
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
        final storage = SafeMMKV()
          ..configureForTesting(
            candidateMmkvFiles: [empty, corrupt, valid],
            candidateDbPaths: const [],
            forceNativeMmkvSupport: false,
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
        final service = MMKVService();
        SafeMMKV().configureForTesting(
          candidateMmkvFiles: const [],
          candidateDbPaths: const [],
          forceNativeMmkvSupport: false,
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
      final service = MMKVService();
      SafeMMKV().configureForTesting(
        candidateMmkvFiles: const [],
        candidateDbPaths: const [],
        forceNativeMmkvSupport: false,
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
        final storage = SafeMMKV()
          ..configureForTesting(
            candidateMmkvFiles: const [],
            candidateDbPaths: const [],
            forceNativeMmkvSupport: false,
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
          final storage = SafeMMKV()
            ..configureForTesting(
              candidateMmkvFiles: const [],
              candidateDbPaths: [path],
              forceNativeMmkvSupport: false,
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
        final storage = SafeMMKV()
          ..configureForTesting(
            candidateMmkvFiles: const [],
            candidateDbPaths: [path],
            forceNativeMmkvSupport: false,
          );
        await storage.initialize();
        expect(storage.getString('app_settings'), saved);
        expect(storage.lastMigrationSnapshot?.healedFromSqliteCount, 0);
      },
    );

    test('remove before init deletes the persisted value', () async {
      SharedPreferences.setMockInitialValues({'theme_style': 'paper'});
      SafeMMKV().configureForTesting(
        candidateMmkvFiles: const [],
        candidateDbPaths: const [],
        forceNativeMmkvSupport: false,
      );
      final service = MMKVService();
      expect(await service.remove('theme_style'), isTrue);
      expect(service.containsKey('theme_style'), isFalse);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.containsKey('theme_style'), isFalse);
    });

    test('synchronous reads before init return safe empty results', () {
      final service = MMKVService();
      expect(service.getString('missing'), isNull);
      expect(service.getBool('missing'), isNull);
      expect(service.getInt('missing'), isNull);
      expect(service.getDouble('missing'), isNull);
      expect(service.getStringList('missing'), isNull);
      expect(service.getJson('missing'), isNull);
      expect(service.containsKey('missing'), isFalse);
      expect(service.getAllKeys(), isEmpty);
    });

    test(
        'Channel 3 heals app_installed_v2 and app_settings when populated thoughtecho.db exists on disk',
        () async {
      // 1. An all-zero 16KB file without SQLite magic header must NOT trigger self-healing
      SharedPreferences.setMockInitialValues({});
      final corruptedDbPath = '${tempDir.path}/corrupted_thoughtecho.db';
      await File(corruptedDbPath).writeAsBytes(Uint8List(16384));

      final safeMmkvCorrupted = SafeMMKV()
        ..configureForTesting(
          candidateMmkvFiles: ['${tempDir.path}/nonexistent_mmkv.default'],
          candidateDbPaths: [corruptedDbPath],
          forceNativeMmkvSupport: false,
        );
      await safeMmkvCorrupted.initialize();
      expect(safeMmkvCorrupted.getBool('app_installed_v2'), isNull);

      // 2. A valid >8KB SQLite file with "SQLite format 3\0" header heals flags & preserves sentryDisclosureShown
      SharedPreferences.setMockInitialValues({
        'app_settings': json.encode({'sentryDisclosureShown': false}),
      });
      final fakeDbPath = '${tempDir.path}/thoughtecho.db';
      final validDbBytes = Uint8List(16384);
      final magic = ascii.encode('SQLite format 3\x00');
      validDbBytes.setRange(0, magic.length, magic);
      await File(fakeDbPath).writeAsBytes(validDbBytes);

      final safeMmkv = SafeMMKV()
        ..configureForTesting(
          candidateMmkvFiles: ['${tempDir.path}/nonexistent_mmkv.default'],
          candidateDbPaths: [fakeDbPath],
          forceNativeMmkvSupport: false,
        );

      await safeMmkv.initialize();

      expect(safeMmkv.getBool('app_installed_v2'), isTrue);
      expect(safeMmkv.getBool('initial_database_setup_complete'), isTrue);
      expect(safeMmkv.getBool('database_migration_complete'), isTrue);
      expect(safeMmkv.getBool('hasCompletedOnboarding'), isTrue);

      final appSettingsRaw = safeMmkv.getString('app_settings');
      expect(appSettingsRaw, isNotNull);
      final decoded = json.decode(appSettingsRaw!) as Map<String, dynamic>;
      expect(decoded['hasCompletedOnboarding'], isTrue);
      expect(decoded['sentryDisclosureShown'], isFalse);
      expect(safeMmkv.lastMigrationSnapshot?.healedFromSqliteCount, equals(5));
    });

    test(
        'MMKVService async write methods await initialization when called before explicit init()',
        () async {
      SharedPreferences.setMockInitialValues({kKvEngineMigratedKey: true});
      final service = MMKVService();
      service.resetForTesting();
      SafeMMKV().configureForTesting(
        candidateMmkvFiles: const [],
        forceNativeMmkvSupport: false,
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

      final safeMmkv = SafeMMKV()
        ..configureForTesting(
          candidateMmkvFiles: [primaryPath, secondaryPath],
          forceNativeMmkvSupport: false,
        );

      await safeMmkv.initialize();

      expect(safeMmkv.getString('theme_style'), equals('paper'));
      expect(safeMmkv.getString('secondary_only_key'), equals('rescued_value'));
      expect(safeMmkv.getBool('deleted_flag'), isNull);
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
      final mmkv = MMKVService();
      expect(mmkv.getString('theme_style'), equals('paper'));
      expect(mmkv.getString('theme_accent_material'), equals('emerald'));
      expect(mmkv.getString('theme_accent_paper'), equals('bamboo'));
      expect(mmkv.getString('theme_accent_plain'), equals('slate'));
      expect(mmkv.getInt('custom_color'), equals(0xFF112233));
      expect(mmkv.getBool('use_custom_color'), isTrue);
      expect(mmkv.getBool('use_dynamic_color'), isFalse);
      expect(
        mmkv.getString('smart_push_settings_v2'),
        contains('"enabled":true'),
      );
    });
  });
}
