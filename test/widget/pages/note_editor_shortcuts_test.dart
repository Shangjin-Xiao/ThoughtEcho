import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:thoughtecho/gen_l10n/app_localizations.dart';
import 'package:thoughtecho/models/quote_model.dart';
import 'package:thoughtecho/pages/note_full_editor_page.dart';
import 'package:thoughtecho/services/database_service.dart';
import 'package:thoughtecho/services/draft_service.dart';
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

class _TestFeatureGuideService extends FeatureGuideService {
  _TestFeatureGuideService() : super(SafeMMKV());

  @override
  bool hasShown(String guideId) => true;

  @override
  Future<void> markAsShown(String guideId) async {}

  @override
  Future<void> resetGuide(String guideId) async {}

  @override
  Future<void> resetAllGuides() async {}
}

class _TestDatabaseService extends ChangeNotifier implements DatabaseService {
  final List<Quote> addedQuotes = [];
  final List<Quote> updatedQuotes = [];
  Completer<void>? saveCompleter;

  @override
  Future<void> addQuote(Quote quote) async {
    addedQuotes.add(quote);
    if (saveCompleter != null) {
      await saveCompleter!.future;
    }
  }

  @override
  Future<QuoteUpdateResult> updateQuote(Quote quote) async {
    updatedQuotes.add(quote);
    if (saveCompleter != null) {
      await saveCompleter!.future;
    }
    return QuoteUpdateResult.updated;
  }

  @override
  Future<Quote?> getQuoteById(String id, {bool includeDeleted = false}) async {
    for (final q in addedQuotes.reversed) {
      if (q.id == id) return q;
    }
    for (final q in updatedQuotes.reversed) {
      if (q.id == id) return q;
    }
    return null;
  }

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> _flushDraftIo(WidgetTester tester) async {
  await tester.pump();
  await tester.runAsync(() => DraftService().waitForIdleForTesting());
  await tester.pump();
  await tester.runAsync(() => DraftService().waitForIdleForTesting());
  await tester.pump();
}

Widget _buildTestApp({
  required _TestDatabaseService databaseService,
  Quote? initialQuote,
  String initialContent = '',
}) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<SettingsService>.value(
        value: _TestSettingsService(),
      ),
      ChangeNotifierProvider<FeatureGuideService>(
        create: (_) => _TestFeatureGuideService(),
      ),
      ChangeNotifierProvider<DatabaseService>.value(
        value: databaseService,
      ),
    ],
    child: MaterialApp(
      localizationsDelegates: const [
        ...AppLocalizations.localizationsDelegates,
        FlutterQuillLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => NoteFullEditorPage(
                      initialQuote: initialQuote,
                      initialContent: initialContent,
                      skipDefaultMetadataAutofill: true,
                    ),
                  ),
                );
              },
              child: const Text('Open Note Editor'),
            ),
          ),
        ),
      ),
    ),
  );
}

Future<void> _openEditor(WidgetTester tester) async {
  await tester.tap(find.text('Open Note Editor'));
  await tester.pumpAndSettle();
  expect(find.byType(NoteFullEditorPage), findsOneWidget);
}

Future<void> _saveViaShortcut(
  WidgetTester tester, {
  bool meta = false,
}) async {
  final modifier =
      meta ? LogicalKeyboardKey.metaLeft : LogicalKeyboardKey.controlLeft;
  await tester.sendKeyDownEvent(modifier);
  await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
  await tester.sendKeyUpEvent(modifier);
  await _flushDraftIo(tester);
  await tester.pump(const Duration(milliseconds: 350));
  await tester.pumpAndSettle();
}

Future<void> _pressEscape(WidgetTester tester) async {
  await tester.sendKeyEvent(LogicalKeyboardKey.escape);
  await _flushDraftIo(tester);
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _TestDatabaseService databaseService;

  setUpAll(() async {
    await TestHarness.initialize();
    await MMKVService().init();
  });

  setUp(() async {
    databaseService = _TestDatabaseService();
    await DraftService().deleteAllDrafts();
  });

  tearDownAll(() async {
    await DraftService().resetForTesting();
    await TestHarness.tearDown();
  });

  testWidgets(
    'Ctrl+S saves a new note without popping and updates subsequent saves to same note',
    (tester) async {
      final originalOnError = FlutterError.onError;
      FlutterError.onError = (details) {
        if (details.exceptionAsString().contains('A RenderFlex overflowed')) {
          return;
        }
        originalOnError?.call(details);
      };
      addTearDown(() => FlutterError.onError = originalOnError);

      await tester.pumpWidget(
        _buildTestApp(databaseService: databaseService),
      );
      await tester.pumpAndSettle();
      await _openEditor(tester);

      final editorFinder = find.byType(QuillEditor);
      expect(editorFinder, findsOneWidget);
      final controller = tester.widget<QuillEditor>(editorFinder).controller;

      // Type initial text
      controller.replaceText(
        0,
        0,
        'Initial shortcut text',
        const TextSelection.collapsed(offset: 21),
      );
      await tester.pump();

      // Press Ctrl+S
      await _saveViaShortcut(tester);

      // Verify that note was added and page is still open
      expect(databaseService.addedQuotes.length, 1);
      expect(databaseService.updatedQuotes.length, 0);
      expect(
          databaseService.addedQuotes.first.content, 'Initial shortcut text');
      expect(find.byType(NoteFullEditorPage), findsOneWidget);

      final savedId = databaseService.addedQuotes.first.id;
      expect(savedId, isNotNull);

      // Modify text again
      controller.replaceText(
        21,
        0,
        ' updated',
        const TextSelection.collapsed(offset: 29),
      );
      await tester.pump();

      // Press Ctrl+S a second time
      await _saveViaShortcut(tester);

      // Verify it was updated, not added as a duplicate note
      expect(databaseService.addedQuotes.length, 1);
      expect(databaseService.updatedQuotes.length, 1);
      expect(databaseService.updatedQuotes.first.id, savedId);
      expect(
        databaseService.updatedQuotes.first.content,
        'Initial shortcut text updated',
      );
      expect(find.byType(NoteFullEditorPage), findsOneWidget);
    },
  );

  testWidgets(
    'Cmd+S saves note without popping',
    (tester) async {
      final originalOnError = FlutterError.onError;
      FlutterError.onError = (details) {
        if (details.exceptionAsString().contains('A RenderFlex overflowed')) {
          return;
        }
        originalOnError?.call(details);
      };
      addTearDown(() => FlutterError.onError = originalOnError);

      await tester.pumpWidget(
        _buildTestApp(databaseService: databaseService),
      );
      await tester.pumpAndSettle();
      await _openEditor(tester);

      final editorFinder = find.byType(QuillEditor);
      final controller = tester.widget<QuillEditor>(editorFinder).controller;

      controller.replaceText(
        0,
        0,
        'Cmd+S saved text',
        const TextSelection.collapsed(offset: 16),
      );
      await tester.pump();

      // Press Cmd+S (metaLeft + keyS)
      await _saveViaShortcut(tester, meta: true);

      expect(databaseService.addedQuotes.length, 1);
      expect(databaseService.addedQuotes.first.content, 'Cmd+S saved text');
      expect(find.byType(NoteFullEditorPage), findsOneWidget);
    },
  );

  testWidgets(
    'Escape key opens unsaved changes dialog when dirty, and exits cleanly when clean or after save',
    (tester) async {
      final originalOnError = FlutterError.onError;
      FlutterError.onError = (details) {
        if (details.exceptionAsString().contains('A RenderFlex overflowed')) {
          return;
        }
        originalOnError?.call(details);
      };
      addTearDown(() => FlutterError.onError = originalOnError);

      await tester.pumpWidget(
        _buildTestApp(databaseService: databaseService),
      );
      await tester.pumpAndSettle();
      await _openEditor(tester);

      // 1. Initially clean - pressing Escape exits immediately without dialog
      await _pressEscape(tester);
      expect(find.byType(NoteFullEditorPage), findsNothing);
      expect(find.byType(AlertDialog), findsNothing);

      // Re-open editor
      await _openEditor(tester);
      final reloadedEditor = find.byType(QuillEditor);
      final reloadedController =
          tester.widget<QuillEditor>(reloadedEditor).controller;

      // 2. Dirty editor - pressing Escape opens unsaved changes dialog
      reloadedController.replaceText(
        0,
        0,
        'Unsaved changes',
        const TextSelection.collapsed(offset: 15),
      );
      await tester.pump();

      await _pressEscape(tester);
      expect(find.byType(AlertDialog), findsOneWidget);

      // Dismiss dialog by continuing editing
      final l10n =
          AppLocalizations.of(tester.element(find.byType(AlertDialog)));
      await tester.tap(find.text(l10n.continueEditing));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.byType(NoteFullEditorPage), findsOneWidget);

      // 3. Save via Ctrl+S - then pressing Escape exits cleanly without dialog
      await _saveViaShortcut(tester);
      expect(databaseService.addedQuotes.length, 1);

      await _pressEscape(tester);
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.byType(NoteFullEditorPage), findsNothing);
    },
  );

  testWidgets(
    'Rapid repeated Ctrl+S triggers are ignored while save is in progress',
    (tester) async {
      final originalOnError = FlutterError.onError;
      FlutterError.onError = (details) {
        if (details.exceptionAsString().contains('A RenderFlex overflowed')) {
          return;
        }
        originalOnError?.call(details);
      };
      addTearDown(() => FlutterError.onError = originalOnError);

      final saveCompleter = Completer<void>();
      databaseService.saveCompleter = saveCompleter;

      await tester.pumpWidget(
        _buildTestApp(databaseService: databaseService),
      );
      await tester.pumpAndSettle();
      await _openEditor(tester);

      final editorFinder = find.byType(QuillEditor);
      final controller = tester.widget<QuillEditor>(editorFinder).controller;

      controller.replaceText(
        0,
        0,
        'Concurrent save test',
        const TextSelection.collapsed(offset: 20),
      );
      await tester.pump();

      // First Ctrl+S starts save
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();

      expect(databaseService.addedQuotes.length, 1);

      // Second Ctrl+S while save is still in flight
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();

      // Still only 1 call
      expect(databaseService.addedQuotes.length, 1);

      // Complete first save
      saveCompleter.complete();
      await _flushDraftIo(tester);
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();

      expect(databaseService.addedQuotes.length, 1);
      expect(databaseService.updatedQuotes.length, 0);
    },
  );

  testWidgets(
    'Ctrl+S saves metadata changes and resets snapshot so Escape exits cleanly',
    (tester) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final originalOnError = FlutterError.onError;
      FlutterError.onError = (details) {
        if (details.exceptionAsString().contains('A RenderFlex overflowed')) {
          return;
        }
        originalOnError?.call(details);
      };
      addTearDown(() => FlutterError.onError = originalOnError);

      await tester.pumpWidget(
        _buildTestApp(databaseService: databaseService),
      );
      await tester.pumpAndSettle();
      await _openEditor(tester);

      // Open metadata bottom sheet
      await tester.tap(find.byIcon(Icons.edit_note));
      await tester.pumpAndSettle();

      // Enter author name
      final textFields = find.byType(TextField);
      expect(textFields, findsWidgets);
      await tester.enterText(textFields.first, 'Test Author');
      await tester.pumpAndSettle();

      // Close bottom sheet
      final doneButton = find.widgetWithIcon(TextButton, Icons.check);
      await tester.tap(doneButton);
      await tester.pumpAndSettle();

      // Press Escape with unsaved metadata changes -> dialog shows
      await _pressEscape(tester);
      expect(find.byType(AlertDialog), findsOneWidget);

      final l10n =
          AppLocalizations.of(tester.element(find.byType(AlertDialog)));
      await tester.tap(find.text(l10n.continueEditing));
      await tester.pumpAndSettle();

      // Save via Ctrl+S
      await _saveViaShortcut(tester);
      expect(databaseService.addedQuotes.length, 1);
      expect(databaseService.addedQuotes.first.sourceAuthor, 'Test Author');

      // Now pressing Escape should exit cleanly without confirmation dialog
      await _pressEscape(tester);
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.byType(NoteFullEditorPage), findsNothing);
    },
  );
}
