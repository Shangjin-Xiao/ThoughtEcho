import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:thoughtecho/services/mmkv_service.dart';
import 'package:thoughtecho/utils/mmkv_binary_reader.dart';
import 'package:thoughtecho/utils/mmkv_ffi_fix.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('mmkv_migration_test_');
    SharedPreferences.setMockInitialValues({});
    MMKVService().resetForTesting();
  });

  tearDown(() async {
    MMKVService().resetForTesting();
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

        await File(mmkvPath).writeAsBytes(
          encoder.toFileBytes(minTotalSize: 4096),
        );
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
      },
    );

    test(
      'Channel 3 heals app_installed_v2 and app_settings when populated thoughtecho.db exists on disk',
      () async {
        SharedPreferences.setMockInitialValues({});
        final fakeDbPath = '${tempDir.path}/thoughtecho.db';
        // Write > 8192 bytes to simulate a populated SQLite database
        await File(fakeDbPath).writeAsBytes(Uint8List(16384));

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
        expect(decoded['sentryDisclosureShown'], isTrue);
        expect(
          safeMmkv.lastMigrationSnapshot?.healedFromSqliteCount,
          equals(5),
        );
      },
    );

    test(
      'MMKVService async write methods await initialization when called before explicit init()',
      () async {
        SharedPreferences.setMockInitialValues({
          kKvEngineMigratedKey: true,
        });
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
      },
    );
  });
}
