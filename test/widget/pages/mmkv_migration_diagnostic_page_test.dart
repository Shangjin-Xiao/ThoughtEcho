import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:thoughtecho/gen_l10n/app_localizations.dart';
import 'package:thoughtecho/pages/mmkv_migration_diagnostic_page.dart';
import 'package:thoughtecho/services/app_preferences_service.dart';
import 'package:thoughtecho/utils/mmkv_binary_reader.dart';

import '../../test_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() async {
    await TestHarness.initialize();
    tempDir = await TestHarness.createTempDirectory('mmkv_diag_widget_test');
    SharedPreferences.setMockInitialValues({
      'custom_data_directory_path': '/sp/only/path',
      'ai_settings': '{"apiKey":"sk-secret-12345"}',
    });
    AppPreferencesService().resetForTesting();
  });

  tearDown(() async {
    AppPreferencesService().resetForTesting();
    await TestHarness.deleteTempDirectory(tempDir);
  });

  Future<void> waitForLoading(WidgetTester tester) async {
    for (var i = 0; i < 50; i++) {
      await tester.pump(const Duration(milliseconds: 50));
      if (find.byType(CircularProgressIndicator).evaluate().isEmpty) {
        break;
      }
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
    }
    await tester.pumpAndSettle();
  }

  testWidgets(
    'MmkvMigrationDiagnosticPage displays overview, 100% consistency badge, and filters keys',
    (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      String? copiedClipboardText;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (
        MethodCall methodCall,
      ) async {
        if (methodCall.method == 'Clipboard.setData') {
          copiedClipboardText = (methodCall.arguments
              as Map<Object?, Object?>)['text'] as String?;
          return null;
        }
        if (methodCall.method == 'Clipboard.getData') {
          if (copiedClipboardText == null) return null;
          return <String, dynamic>{'text': copiedClipboardText};
        }
        return null;
      });
      addTearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, null);
      });

      final mmkvPath = '${tempDir.path}/mmkv.default';
      final encoder = MmkvBinaryEncoder()
        ..writeString('theme_style', 'paper')
        ..writeBool('app_installed_v2', true)
        ..writeInt('custom_color', 0xFF336699);

      File(mmkvPath).writeAsBytesSync(encoder.toFileBytes(minTotalSize: 4096));
      File('$mmkvPath.crc').writeAsBytesSync(encoder.toCrcBytes());

      AppPreferencesService().configureForTesting(
        candidateMmkvFiles: [mmkvPath],
      );
      await tester.runAsync(() async {
        await AppPreferencesService().init();
      });

      await tester.pumpWidget(
        const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: Locale('zh'),
          home: MmkvMigrationDiagnosticPage(),
        ),
      );
      await waitForLoading(tester);

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

      late final MmkvDiagnosticReport report;
      await tester.runAsync(() async {
        report = await AppPreferencesService().collectDiagnosticReport();
      });
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
      expect(find.byKey(const Key('mmkv_key_tile_theme_style')), findsNothing);

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

  testWidgets(
    'MmkvMigrationDiagnosticPage re-runs migration and shows localized feedback',
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
        ..writeBool('app_installed_v2', true);
      File(mmkvPath).writeAsBytesSync(encoder.toFileBytes(minTotalSize: 4096));
      File('$mmkvPath.crc').writeAsBytesSync(encoder.toCrcBytes());

      AppPreferencesService().configureForTesting(
        candidateMmkvFiles: [mmkvPath],
      );
      await tester.runAsync(() async {
        await AppPreferencesService().init();
      });

      await tester.pumpWidget(
        const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: Locale('fr'),
          home: MmkvMigrationDiagnosticPage(),
        ),
      );
      await waitForLoading(tester);

      final rerunButton = find.byKey(
        const Key('mmkv_diagnostic_rerun_migration_button'),
      );
      expect(rerunButton, findsOneWidget);
      await tester.ensureVisible(rerunButton);
      await tester.tap(rerunButton);
      await waitForLoading(tester);

      expect(
        find.byKey(const Key('mmkv_diagnostic_summary_card')),
        findsOneWidget,
      );
      expect(
        find.text('Migration relancée et rapport actualisé'),
        findsOneWidget,
      );
      expect(find.text('Résumé de cohérence du stockage'), findsOneWidget);
    },
  );

  testWidgets(
    'MmkvMigrationDiagnosticPage copies redacted diagnostic JSON to clipboard',
    (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      String? copiedClipboardText;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (
        MethodCall methodCall,
      ) async {
        if (methodCall.method == 'Clipboard.setData') {
          copiedClipboardText = (methodCall.arguments
              as Map<Object?, Object?>)['text'] as String?;
          return null;
        }
        return null;
      });
      addTearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, null);
      });

      final mmkvPath = '${tempDir.path}/mmkv.default';
      final encoder = MmkvBinaryEncoder()..writeString('theme_style', 'paper');
      File(mmkvPath).writeAsBytesSync(encoder.toFileBytes(minTotalSize: 4096));
      File('$mmkvPath.crc').writeAsBytesSync(encoder.toCrcBytes());

      AppPreferencesService().configureForTesting(
        candidateMmkvFiles: [mmkvPath],
      );
      await tester.runAsync(() async {
        await AppPreferencesService().init();
      });

      await tester.pumpWidget(
        const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: Locale('zh'),
          home: MmkvMigrationDiagnosticPage(),
        ),
      );
      await waitForLoading(tester);

      final copyJsonButton = find.byKey(
        const Key('mmkv_diagnostic_copy_json_action_button'),
      );
      expect(copyJsonButton, findsOneWidget);
      await tester.ensureVisible(copyJsonButton);
      await tester.tap(copyJsonButton);
      await tester.pumpAndSettle();

      expect(copiedClipboardText, isNotNull);
      expect(() => json.decode(copiedClipboardText!), returnsNormally);
      expect(copiedClipboardText, contains('ai_settings'));
      expect(copiedClipboardText, isNot(contains('sk-secret-12345')));
      expect(find.byType(SnackBar), findsOneWidget);
    },
  );
}
