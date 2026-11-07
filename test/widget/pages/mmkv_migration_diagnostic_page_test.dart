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

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('mmkv_diag_widget_test_');
    SharedPreferences.setMockInitialValues({
      'custom_data_directory_path': '/sp/only/path',
    });
    MMKVService().resetForTesting();
  });

  tearDown(() async {
    MMKVService().resetForTesting();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  testWidgets(
    'MmkvMigrationDiagnosticPage displays overview, 100% consistency badge, and filters keys',
    (tester) async {
      final mmkvPath = '${tempDir.path}/mmkv.default';
      final encoder = MmkvBinaryEncoder()
        ..writeString('theme_style', 'paper')
        ..writeBool('app_installed_v2', true)
        ..writeInt('custom_color', 0xFF336699);

      await File(mmkvPath).writeAsBytes(
        encoder.toFileBytes(minTotalSize: 4096),
      );
      await File('$mmkvPath.crc').writeAsBytes(encoder.toCrcBytes());

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
      expect(find.textContaining('100% 一致'), findsOneWidget);

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
