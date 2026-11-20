import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:thoughtecho/gen_l10n/app_localizations.dart';
import 'package:thoughtecho/models/app_settings.dart';
import 'package:thoughtecho/models/local_ai_settings.dart';
import 'package:thoughtecho/models/note_tag.dart';
import 'package:thoughtecho/models/quote_map_point.dart';
import 'package:thoughtecho/models/quote_model.dart';
import 'package:thoughtecho/pages/map_memory_page.dart';
import 'package:thoughtecho/pages/note_full_editor_page.dart';
import 'package:thoughtecho/services/app_preferences_service.dart';
import 'package:thoughtecho/services/database_service.dart';
import 'package:thoughtecho/services/draft_service.dart';
import 'package:thoughtecho/services/feature_guide_service.dart';
import 'package:thoughtecho/services/location_service.dart';
import 'package:thoughtecho/services/settings_service.dart';
import 'package:thoughtecho/services/weather_service.dart';
import 'package:thoughtecho/widgets/add_note_dialog.dart';

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
  AppSettings get appSettings => AppSettings(developerMode: false);

  @override
  bool get enableFirstOpenScrollPerfMonitor => false;

  @override
  LocalAISettings get localAISettings => const LocalAISettings();

  @override
  bool get addNoteDialogDeferAutoMetadata => false;

  @override
  bool get addNoteDialogAutoFocus => false;

  @override
  String get exportFormat => 'image';

  @override
  bool get showExactTime => false;

  @override
  bool get showNoteEditTime => false;

  @override
  bool get noteListDisableCardShadows => false;

  @override
  String get noteCardMediaStyle => 'grid';

  @override
  bool get prioritizeBoldContentInCollapse => false;

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _TestLocationService extends ChangeNotifier implements LocationService {
  @override
  Null get currentPosition => null;

  @override
  String? get currentAddress => null;

  @override
  bool get hasLocationPermission => false;

  @override
  bool get isLocationServiceEnabled => false;

  @override
  String? get currentPoiName => null;

  @override
  String? currentLocaleCode;

  @override
  String getFormattedLocation() => '';

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _TestWeatherService extends ChangeNotifier implements WeatherService {
  @override
  bool get hasData => false;

  @override
  String get currentWeather => '';

  @override
  String get temperature => '';

  @override
  String getFormattedWeather(AppLocalizations l10n) => '';

  @override
  IconData getWeatherIconData() => Icons.wb_sunny;

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _TestFeatureGuideService extends FeatureGuideService {
  _TestFeatureGuideService() : super(AppPreferencesService());

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
  final List<QuoteMapPoint> mapPoints = [];
  int getQuotesWithCoordinatesCallCount = 0;
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
    for (final q in updatedQuotes.reversed) {
      if (q.id == id) return q;
    }
    for (final q in addedQuotes.reversed) {
      if (q.id == id) return q;
    }
    return null;
  }

  @override
  Future<List<QuoteMapPoint>> getQuotesWithCoordinates({
    double? minLatitude,
    double? maxLatitude,
    double? minLongitude,
    double? maxLongitude,
    int? limit,
    int? offset,
  }) async {
    getQuotesWithCoordinatesCallCount += 1;
    return List<QuoteMapPoint>.from(mapPoints);
  }

  @override
  Future<List<NoteTag>> getTags() async => const [];

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
  ValueChanged<bool?>? onEditorResult,
}) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<SettingsService>.value(
        value: _TestSettingsService(),
      ),
      ChangeNotifierProvider<LocationService>.value(
        value: _TestLocationService(),
      ),
      ChangeNotifierProvider<WeatherService>.value(
        value: _TestWeatherService(),
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
              onPressed: () async {
                final result = await Navigator.of(context).push<bool>(
                  MaterialPageRoute<bool>(
                    builder: (_) => NoteFullEditorPage(
                      initialQuote: initialQuote,
                      initialContent: initialContent,
                      skipDefaultMetadataAutofill: true,
                    ),
                  ),
                );
                onEditorResult?.call(result);
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
    await AppPreferencesService().init();
  });

  setUp(() async {
    databaseService = _TestDatabaseService();
    await AppPreferencesService().clear();
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

  testWidgets(
    'Ctrl+S re-enables draft autosave and binds subsequent drafts to saved note ID',
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

      final controller =
          tester.widget<QuillEditor>(find.byType(QuillEditor)).controller;

      // Write first paragraph, wait for initial new_note_* draft, then press Ctrl+S
      controller.replaceText(
        0,
        0,
        'First paragraph',
        const TextSelection.collapsed(offset: 15),
      );
      await tester.pump();
      await tester.pump(const Duration(seconds: 3));
      await _flushDraftIo(tester);

      await _saveViaShortcut(tester);

      expect(databaseService.addedQuotes, hasLength(1));
      final savedId = databaseService.addedQuotes.first.id!;
      expect(savedId.startsWith('new_'), isFalse);

      // Immediately after save, draft storage is cleared
      final postSaveDraft =
          await tester.runAsync(() => DraftService().getLatestDraft());
      expect(postSaveDraft, isNull);

      // Continue editing and advance beyond the 2-second debounce
      controller.replaceText(
        15,
        0,
        '\nSecond paragraph',
        const TextSelection.collapsed(offset: 32),
      );
      await tester.pump();
      await tester.pump(const Duration(seconds: 3));
      await _flushDraftIo(tester);

      final updatedDraft =
          await tester.runAsync(() => DraftService().getLatestDraft());
      final allDraftIds =
          await tester.runAsync(() => DraftService().getAllDraftIds());

      expect(updatedDraft, isNotNull);
      expect(updatedDraft!['plainText'], 'First paragraph\nSecond paragraph');
      expect(updatedDraft['id'], savedId);
      expect(allDraftIds, [savedId]);
    },
  );

  testWidgets(
    'edits typed while Ctrl+S database write is in flight stay dirty and schedule draft autosave',
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

      final controller =
          tester.widget<QuillEditor>(find.byType(QuillEditor)).controller;

      controller.replaceText(
        0,
        0,
        'Committed prefix',
        const TextSelection.collapsed(offset: 16),
      );
      await tester.pump();

      // Trigger Ctrl+S while DB persistence blocks on saveCompleter
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();

      expect(databaseService.addedQuotes, hasLength(1));
      expect(databaseService.addedQuotes.first.content, 'Committed prefix');
      final savedId = databaseService.addedQuotes.first.id!;

      // User keeps typing while DB write is still in flight
      controller.replaceText(
        16,
        0,
        ' unsaved tail',
        const TextSelection.collapsed(offset: 29),
      );
      await tester.pump();

      // Finish DB write
      saveCompleter.complete();
      await _flushDraftIo(tester);
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();

      // Pressing Escape must warn about the unsaved tail instead of silently popping
      await _pressEscape(tester);
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.byType(NoteFullEditorPage), findsOneWidget);

      final l10n =
          AppLocalizations.of(tester.element(find.byType(AlertDialog)));
      await tester.tap(find.text(l10n.continueEditing));
      await tester.pumpAndSettle();

      // Advancing past debounce persists the in-flight edits as a draft for savedId
      await tester.pump(const Duration(seconds: 3));
      await _flushDraftIo(tester);

      final draft =
          await tester.runAsync(() => DraftService().getLatestDraft());
      expect(draft, isNotNull);
      expect(draft!['id'], savedId);
      expect(draft['plainText'], 'Committed prefix unsaved tail');
    },
  );

  testWidgets(
    'Escape after Ctrl+S returns true route result on clean exit and when discarding later edits',
    (tester) async {
      final originalOnError = FlutterError.onError;
      FlutterError.onError = (details) {
        if (details.exceptionAsString().contains('A RenderFlex overflowed')) {
          return;
        }
        originalOnError?.call(details);
      };
      addTearDown(() => FlutterError.onError = originalOnError);

      final routeResults = <bool?>[];
      await tester.pumpWidget(
        _buildTestApp(
          databaseService: databaseService,
          onEditorResult: routeResults.add,
        ),
      );
      await tester.pumpAndSettle();

      // 1. Exit without ever saving -> returns null
      await _openEditor(tester);
      await _pressEscape(tester);
      expect(routeResults, [null]);

      // 2. Save via Ctrl+S, then Escape cleanly -> returns true
      await _openEditor(tester);
      var controller =
          tester.widget<QuillEditor>(find.byType(QuillEditor)).controller;
      controller.replaceText(
        0,
        0,
        'Saved via shortcut',
        const TextSelection.collapsed(offset: 18),
      );
      await tester.pump();
      await _saveViaShortcut(tester);
      await _pressEscape(tester);
      expect(routeResults, [null, true]);

      // 3. Save via Ctrl+S, edit more, Escape and discard subsequent edits -> still returns true
      await _openEditor(tester);
      controller =
          tester.widget<QuillEditor>(find.byType(QuillEditor)).controller;
      controller.replaceText(
        0,
        0,
        'Saved base',
        const TextSelection.collapsed(offset: 10),
      );
      await tester.pump();
      await _saveViaShortcut(tester);

      controller.replaceText(
        10,
        0,
        ' discarded suffix',
        const TextSelection.collapsed(offset: 27),
      );
      await tester.pump();

      await _pressEscape(tester);
      expect(find.byType(AlertDialog), findsOneWidget);
      final l10n =
          AppLocalizations.of(tester.element(find.byType(AlertDialog)));
      await tester.tap(find.text(l10n.discardChanges));
      await _flushDraftIo(tester);
      await tester.pumpAndSettle();

      expect(find.byType(NoteFullEditorPage), findsNothing);
      expect(routeResults, [null, true, true]);
    },
  );

  testWidgets(
    'AddNoteDialog closes after switching to full editor, saving via Ctrl+S, and exiting via Escape',
    (tester) async {
      tester.view.physicalSize = const Size(900, 1200);
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
        MultiProvider(
          providers: [
            ChangeNotifierProvider<SettingsService>.value(
              value: _TestSettingsService(),
            ),
            ChangeNotifierProvider<LocationService>.value(
              value: _TestLocationService(),
            ),
            ChangeNotifierProvider<WeatherService>.value(
              value: _TestWeatherService(),
            ),
            ChangeNotifierProvider<FeatureGuideService>(
              create: (_) => _TestFeatureGuideService(),
            ),
            ChangeNotifierProvider<DatabaseService>.value(
              value: databaseService,
            ),
          ],
          child: MaterialApp(
            locale: const Locale('zh'),
            localizationsDelegates: const [
              ...AppLocalizations.localizationsDelegates,
              FlutterQuillLocalizations.delegate,
            ],
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: Builder(
                builder: (context) => ElevatedButton(
                  onPressed: () => showDialog<void>(
                    context: context,
                    builder: (_) => Dialog(
                      child: AddNoteDialog(
                        tags: const [],
                        prefilledContent: 'Compact dialog initial note',
                        onSave: databaseService.addQuote,
                      ),
                    ),
                  ),
                  child: const Text('Open Compact Dialog'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Open Compact Dialog'));
      await tester.pumpAndSettle();
      expect(find.byType(AddNoteDialog), findsOneWidget);

      // Expand to full editor
      await tester.tap(find.byIcon(Icons.fullscreen));
      await tester.pumpAndSettle();
      expect(find.byType(NoteFullEditorPage), findsOneWidget);

      // Save via Ctrl+S, then exit via Escape
      await _saveViaShortcut(tester);
      expect(databaseService.addedQuotes, hasLength(1));

      await _pressEscape(tester);
      // Allow AddNoteDialog's 300ms post-pop close delay to complete
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();

      expect(find.byType(NoteFullEditorPage), findsNothing);
      expect(find.byType(AddNoteDialog), findsNothing);
      expect(databaseService.addedQuotes, hasLength(1));
    },
  );

  testWidgets(
    'MapMemoryPage reloads map markers after editing note via Ctrl+S and exiting via Escape',
    (tester) async {
      tester.view.physicalSize = const Size(900, 1200);
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

      final mapQuote = Quote(
        id: 'map-note-1',
        content: 'Map note initial body',
        date: '2026-03-29T00:00:00.000Z',
        location: '示例省·示例市',
        latitude: 30.0,
        longitude: 120.0,
        editSource: 'fullscreen',
      );
      databaseService.addedQuotes.add(mapQuote);
      databaseService.mapPoints.add(
        const QuoteMapPoint(
          id: 'map-note-1',
          date: '2026-03-29T00:00:00.000Z',
          latitude: 30.0,
          longitude: 120.0,
        ),
      );

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<SettingsService>.value(
              value: _TestSettingsService(),
            ),
            ChangeNotifierProvider<LocationService>.value(
              value: _TestLocationService(),
            ),
            ChangeNotifierProvider<WeatherService>.value(
              value: _TestWeatherService(),
            ),
            ChangeNotifierProvider<FeatureGuideService>(
              create: (_) => _TestFeatureGuideService(),
            ),
            ChangeNotifierProvider<DatabaseService>.value(
              value: databaseService,
            ),
          ],
          child: const MaterialApp(
            locale: Locale('zh'),
            localizationsDelegates: [
              ...AppLocalizations.localizationsDelegates,
              FlutterQuillLocalizations.delegate,
            ],
            supportedLocales: AppLocalizations.supportedLocales,
            home: MapMemoryPage(),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      final countBeforeEdit = databaseService.getQuotesWithCoordinatesCallCount;
      expect(countBeforeEdit, greaterThanOrEqualTo(1));

      // Tap map marker to open note bottom sheet
      final markerFinder = find.byIcon(Icons.edit_note);
      expect(markerFinder, findsOneWidget);
      await tester.tap(markerFinder);
      await tester.pumpAndSettle();

      // Open action menu on QuoteItemWidget and tap edit
      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();
      final l10n = await AppLocalizations.delegate.load(const Locale('zh'));
      await tester.tap(find.text(l10n.editNoteMenu));
      await tester.pumpAndSettle();
      expect(find.byType(NoteFullEditorPage), findsOneWidget);

      // Edit content, press Ctrl+S, then press Escape
      final controller =
          tester.widget<QuillEditor>(find.byType(QuillEditor)).controller;
      controller.replaceText(
        21,
        0,
        ' updated',
        const TextSelection.collapsed(offset: 29),
      );
      await tester.pump();
      await _saveViaShortcut(tester);
      expect(databaseService.updatedQuotes, hasLength(1));

      await _pressEscape(tester);
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byType(NoteFullEditorPage), findsNothing);
      expect(
        databaseService.getQuotesWithCoordinatesCallCount,
        greaterThan(countBeforeEdit),
      );
    },
  );

  testWidgets(
    'turning off location or weather after Ctrl+S on a new note prompts on Escape and saves removal',
    (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final databaseService = _TestDatabaseService();
      final unsavedNewQuoteWithMetadata = Quote(
        content: 'Note with location and weather',
        date: '2026-03-29T00:00:00.000Z',
        location: '示例省·示例市',
        latitude: 30.0,
        longitude: 120.0,
        weather: 'clear',
        temperature: '22°C',
      );

      await tester.pumpWidget(
        _buildTestApp(
          databaseService: databaseService,
          initialQuote: unsavedNewQuoteWithMetadata,
          initialContent: 'Note with location and weather',
        ),
      );

      await _openEditor(tester);

      // Save new note in place via Ctrl+S (persists location & weather)
      await _saveViaShortcut(tester);
      expect(databaseService.addedQuotes, hasLength(1));
      expect(databaseService.addedQuotes.single.location, '示例省·示例市');
      expect(databaseService.addedQuotes.single.weather, 'clear');

      // Open metadata bottom sheet and uncheck both location and weather chips
      await tester.tap(find.byIcon(Icons.edit_note));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('full_editor_location_chip')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('full_editor_weather_chip')));
      await tester.pump();

      final l10n = await AppLocalizations.delegate.load(const Locale('en'));
      await tester.tap(find.text(l10n.done));
      await tester.pumpAndSettle();

      // Pressing Escape must detect unsaved metadata removal instead of exiting silently
      await _pressEscape(tester);
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.byType(NoteFullEditorPage), findsOneWidget);

      // Confirm save-and-exit in the unsaved-changes dialog and verify DB removes location & weather
      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text(l10n.saveAndExit),
        ),
      );
      await _flushDraftIo(tester);
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();

      expect(find.byType(NoteFullEditorPage), findsNothing);
      expect(databaseService.updatedQuotes, hasLength(1));
      expect(databaseService.updatedQuotes.single.location, isNull);
      expect(databaseService.updatedQuotes.single.latitude, isNull);
      expect(databaseService.updatedQuotes.single.longitude, isNull);
      expect(databaseService.updatedQuotes.single.weather, isNull);
      expect(databaseService.updatedQuotes.single.temperature, isNull);
    },
  );
}
