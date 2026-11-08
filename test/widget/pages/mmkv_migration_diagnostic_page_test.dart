import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:thoughtecho/gen_l10n/app_localizations.dart';
import 'package:thoughtecho/pages/mmkv_migration_diagnostic_page.dart';
import 'package:thoughtecho/services/mmkv_service.dart';
import 'package:thoughtecho/utils/mmkv_binary_reader.dart';
import 'package:thoughtecho/utils/mmkv_ffi_fix.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('mmkv_diag_widget_test_');
    SharedPreferences.setMockInitialValues({
      'custom_data_directory_path': '/sp/only/path',
      'ai_settings': '{"apiKey":"sk-secret-12345"}',
    });
    MMKVService().resetForTesting();
  });

  tearDown(() {
    MMKVService().resetForTesting();
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  testWidgets(
    'MmkvMigrationDiagnosticPage displays overview, 100% consistency badge, and filters keys',
    (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final mmkvPath = '${tempDir.path}/mmkv.default';
      final encoder = MmkvBinaryEncoder()
        ..writeString('theme_style', 'paper')
        ..writeBool('app_installed_v2', true)
        ..writeInt('custom_color', 0xFF336699)
        ..writeString('ai_settings', '{"apiKey":"sk-secret-12345"}');

      File(mmkvPath).writeAsBytesSync(
        encoder.toFileBytes(minTotalSize: 4096),
      );
      File('$mmkvPath.crc').writeAsBytesSync(encoder.toCrcBytes());

      SafeMMKV().configureForTesting(
        candidateMmkvFiles: [mmkvPath],
        forceNativeMmkvSupport: false,
      );
      await MMKVService().init();

      await tester.pumpWidget(
        const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: Locale('zh'),
          home: MmkvMigrationDiagnosticPage(),
        ),
      );

      await tester.pumpAndSettle();

      // Overview & Summary cards render
      expect(
        find.byKey(const Key('mmkv_diagnostic_overview_card')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('mmkv_diagnostic_summary_card')),
        findsOneWidget,
      );
      expect(find.textContaining('100% 一致 ('), findsOneWidget);
      expect(find.textContaining('sk-secret-12345'), findsNothing);

      final report = await MMKVService().collectDiagnosticReport();
      final reportJson = json.encode(report.toRedactedJson());
      expect(reportJson, contains('ai_settings'));
      expect(reportJson, isNot(contains('sk-secret-12345')));

      // Filter by Bool
      final boolFilter = find.byKey(const Key('mmkv_filter_boolType'));
      await tester.ensureVisible(boolFilter);
      await tester.tap(boolFilter);
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('mmkv_key_tile_app_installed_v2')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('mmkv_key_tile_theme_style')),
        findsNothing,
      );

      // Filter by SP Only
      final spOnlyFilter = find.byKey(const Key('mmkv_filter_spOnly'));
      await tester.ensureVisible(spOnlyFilter);
      await tester.tap(spOnlyFilter);
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('mmkv_key_tile_custom_data_directory_path')),
        findsOneWidget,
      );
    },
  );
}
