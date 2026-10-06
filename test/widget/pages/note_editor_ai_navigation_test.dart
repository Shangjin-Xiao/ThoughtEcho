import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:thoughtecho/gen_l10n/app_localizations.dart';
import 'package:thoughtecho/models/quote_model.dart';
import 'package:thoughtecho/pages/note_full_editor_page.dart';
import 'package:thoughtecho/pages/thoughter_page.dart';
import 'package:thoughtecho/services/database_service.dart';
import 'package:thoughtecho/services/feature_guide_service.dart';
import 'package:thoughtecho/services/mmkv_service.dart';
import 'package:thoughtecho/services/settings_service.dart';
import 'package:thoughtecho/utils/mmkv_ffi_fix.dart';

import '../../test_harness.dart';

class _MockSettingsService extends ChangeNotifier implements SettingsService {
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

class _MockDatabaseService extends ChangeNotifier implements DatabaseService {
  int addQuoteCallCount = 0;
  int updateQuoteCallCount = 0;
  Quote? lastSavedQuote;

  @override
  Future<void> addQuote(Quote quote) async {
    addQuoteCallCount++;
    lastSavedQuote = quote;
  }

  @override
  Future<QuoteUpdateResult> updateQuote(Quote quote) async {
    updateQuoteCallCount++;
    lastSavedQuote = quote;
    return QuoteUpdateResult.updated;
  }

  @override
  Future<Quote?> getQuoteById(String id, {bool includeDeleted = false}) async {
    return null;
  }

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _MockFeatureGuideService extends FeatureGuideService {
  _MockFeatureGuideService() : super(SafeMMKV());

  @override
  bool hasShown(String guideId) => true;

  @override
  Future<void> markAsShown(String guideId) async {}

  @override
  Future<void> resetGuide(String guideId) async {}

  @override
  Future<void> resetAllGuides() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _MockDatabaseService databaseService;

  setUpAll(() async {
    await TestHarness.initialize();
    await MMKVService().init();
  });

  setUp(() async {
    databaseService = _MockDatabaseService();
    await MMKVService().clear();
  });

  Widget buildTestWidget({Quote? initialQuote, String initialContent = ''}) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<SettingsService>.value(
          value: _MockSettingsService(),
        ),
        ChangeNotifierProvider<DatabaseService>.value(
          value: databaseService,
        ),
        ChangeNotifierProvider<FeatureGuideService>(
          create: (_) => _MockFeatureGuideService(),
        ),
      ],
      child: MaterialApp(
        locale: const Locale('zh'),
        localizationsDelegates: const [
          ...AppLocalizations.localizationsDelegates,
          FlutterQuillLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: NoteFullEditorPage(
          initialContent: initialContent,
          initialQuote: initialQuote,
          skipDefaultMetadataAutofill: true,
        ),
      ),
    );
  }

  testWidgets(
    'AI Assistant with unsaved changes -> Save and Continue successfully saves and opens ThoughterPage',
    (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      // Enter note content
      final editor = find.byType(QuillEditor);
      expect(editor, findsOneWidget);
      final controller = tester.widget<QuillEditor>(editor).controller;
      controller.replaceText(
        0,
        0,
        'Test content for AI',
        const TextSelection.collapsed(offset: 19),
      );
      await tester.pumpAndSettle();

      // Tap AI assistant action button in AppBar
      final aiButton = find.byIcon(Icons.auto_awesome);
      expect(aiButton, findsOneWidget);
      await tester.tap(aiButton);
      await tester.pumpAndSettle();

      // Tap Polish Text option in AI menu sheet
      final l10n = await AppLocalizations.delegate.load(const Locale('zh'));
      final polishOption = find.text(l10n.polishText);
      expect(polishOption, findsOneWidget);
      await tester.tap(polishOption);
      await tester.pumpAndSettle();

      // Verify save confirmation dialog appears
      expect(find.text(l10n.saveRequired), findsOneWidget);

      // Tap "Save and continue"
      final saveAndContinueBtn = find.text(l10n.saveAndContinue);
      expect(saveAndContinueBtn, findsOneWidget);
      await tester.tap(saveAndContinueBtn);
      await tester.pumpAndSettle();

      // Verify note was saved
      expect(databaseService.addQuoteCallCount, equals(1));
      expect(databaseService.lastSavedQuote?.content,
          equals('Test content for AI'));

      // Verify ThoughterPage is now displayed
      expect(find.byType(ThoughterPage), findsOneWidget);
    },
  );

  testWidgets(
    'AI Assistant with unsaved changes -> Cancel does NOT save and stays on editor',
    (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      // Enter note content
      final editor = find.byType(QuillEditor);
      final controller = tester.widget<QuillEditor>(editor).controller;
      controller.replaceText(
        0,
        0,
        'Draft content to cancel',
        const TextSelection.collapsed(offset: 23),
      );
      await tester.pumpAndSettle();

      // Tap AI assistant button in AppBar
      await tester.tap(find.byIcon(Icons.auto_awesome));
      await tester.pumpAndSettle();

      // Tap AI option
      final l10n = await AppLocalizations.delegate.load(const Locale('zh'));
      await tester.tap(find.text(l10n.polishText));
      await tester.pumpAndSettle();

      // Tap Cancel
      await tester.tap(find.text(l10n.cancel));
      await tester.pumpAndSettle();

      // Verify not saved and still in NoteFullEditorPage
      expect(databaseService.addQuoteCallCount, equals(0));
      expect(find.byType(NoteFullEditorPage), findsOneWidget);
      expect(find.byType(ThoughterPage), findsNothing);
    },
  );

  testWidgets(
    'AppBar Save button saves note and pops editor',
    (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      // Enter note content
      final editor = find.byType(QuillEditor);
      final controller = tester.widget<QuillEditor>(editor).controller;
      controller.replaceText(
        0,
        0,
        'AppBar save content',
        const TextSelection.collapsed(offset: 19),
      );
      await tester.pumpAndSettle();

      // Tap Save button in AppBar
      await tester.tap(find.byIcon(Icons.save));
      await tester.pumpAndSettle();

      // Verify note was saved and editor was popped
      expect(databaseService.addQuoteCallCount, equals(1));
      expect(find.byType(NoteFullEditorPage), findsNothing);
    },
  );

  testWidgets(
    'Back intercept dialog save option saves note and exits editor',
    (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      // Enter note content
      final editor = find.byType(QuillEditor);
      final controller = tester.widget<QuillEditor>(editor).controller;
      controller.replaceText(
        0,
        0,
        'Back intercept save content',
        const TextSelection.collapsed(offset: 27),
      );
      await tester.pumpAndSettle();

      // Trigger back navigation (PopScope)
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      // Verify unsaved changes dialog is shown
      final l10n = await AppLocalizations.delegate.load(const Locale('zh'));
      expect(find.text(l10n.unsavedChangesTitle), findsOneWidget);

      // Tap Save button in dialog ("保存并退出")
      await tester.tap(find.text(l10n.saveAndExit));
      await tester.pumpAndSettle();

      // Verify note was saved and editor was popped
      expect(databaseService.addQuoteCallCount, equals(1));
      expect(find.byType(NoteFullEditorPage), findsNothing);
    },
  );
}
