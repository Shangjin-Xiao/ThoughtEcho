import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:thoughtecho/gen_l10n/app_localizations.dart';
import 'package:thoughtecho/models/quote_model.dart';
import 'package:thoughtecho/pages/note_full_editor_page.dart';
import 'package:thoughtecho/services/database_service.dart';
import 'package:thoughtecho/services/feature_guide_service.dart';
import 'package:thoughtecho/services/mmkv_service.dart';
import 'package:thoughtecho/services/settings_service.dart';
import 'package:thoughtecho/utils/mmkv_ffi_fix.dart';

import '../../test_harness.dart';

class _TestSettingsService extends ChangeNotifier implements SettingsService {
  @override
  bool get autoAttachLocation => false;

  @override
  bool get autoAttachWeather => false;

  @override
  String? get defaultAuthor => null;

  @override
  String? get defaultSource => null;

  @override
  List<String> get defaultTagIds => const [];

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _TestDatabaseService extends ChangeNotifier implements DatabaseService {
  int addQuoteCallCount = 0;
  Completer<void>? saveCompleter;

  @override
  Future<void> addQuote(Quote quote) async {
    addQuoteCallCount += 1;
    if (saveCompleter != null) {
      await saveCompleter!.future;
    }
  }

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _TestFeatureGuideService extends FeatureGuideService {
  _TestFeatureGuideService() : super(SafeMMKV());

  @override
  bool hasShown(String guideId) => true;

  @override
  Future<void> markAsShown(String guideId) async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _TestDatabaseService databaseService;

  setUpAll(() async {
    await TestHarness.initialize();
    await MMKVService().init();
  });

  setUp(() {
    databaseService = _TestDatabaseService();
  });

  testWidgets(
      'save overlay displays progress and wraps editor body with RepaintBoundary',
      (tester) async {
    final saveCompleter = Completer<void>();
    databaseService.saveCompleter = saveCompleter;

    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<DatabaseService>.value(value: databaseService),
        ChangeNotifierProvider<SettingsService>.value(
          value: _TestSettingsService(),
        ),
        ChangeNotifierProvider<FeatureGuideService>(
          create: (_) => _TestFeatureGuideService(),
        ),
      ],
      child: MaterialApp(
        localizationsDelegates: const [
          ...AppLocalizations.localizationsDelegates,
          FlutterQuillLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: const NoteFullEditorPage(
          initialContent: 'Save overlay test body',
          skipDefaultMetadataAutofill: true,
        ),
      ),
    ));
    await tester.pumpAndSettle();

    // Verify RepaintBoundary elements exist for isolating editor body & overlay
    final repaintBoundaries = find.byType(RepaintBoundary);
    expect(repaintBoundaries, findsAtLeastNWidgets(2));

    // Tap save button to start saving
    final saveButton = find.byIcon(Icons.save);
    await tester.tap(saveButton);
    await tester.pump();

    // Save overlay should now be visible while database write is blocked
    expect(find.text('100%'), findsOneWidget);

    // Complete saving
    saveCompleter.complete();
    await tester.pumpAndSettle();

    // After completion, overlay should disappear
    expect(find.text('100%'), findsNothing);
  });
}
