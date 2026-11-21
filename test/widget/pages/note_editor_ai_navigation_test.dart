import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:thoughtecho/gen_l10n/app_localizations.dart';
import 'package:thoughtecho/models/app_settings.dart';
import 'package:thoughtecho/models/chat_message.dart' as app_chat;
import 'package:thoughtecho/models/chat_session.dart';
import 'package:thoughtecho/models/local_ai_settings.dart';
import 'package:thoughtecho/models/multi_ai_settings.dart';
import 'package:thoughtecho/models/note_proposal_artifact.dart';
import 'package:thoughtecho/models/note_tag.dart';
import 'package:thoughtecho/models/quote_model.dart';
import 'package:thoughtecho/models/thoughter_entry.dart';
import 'package:thoughtecho/pages/note_full_editor_page.dart';
import 'package:thoughtecho/pages/thoughter_page.dart';
import 'package:thoughtecho/services/agent_service.dart';
import 'package:thoughtecho/services/agent_tool.dart';
import 'package:thoughtecho/services/agent_tools/ask_user_tool.dart';
import 'package:thoughtecho/services/agent_tools/propose_note_edit_tool.dart';
import 'package:thoughtecho/services/ai_service.dart';
import 'package:thoughtecho/services/app_preferences_service.dart';
import 'package:thoughtecho/services/chat_session_service.dart';
import 'package:thoughtecho/services/database_service.dart';
import 'package:thoughtecho/services/draft_service.dart';
import 'package:thoughtecho/services/feature_guide_service.dart';
import 'package:thoughtecho/services/location_service.dart';
import 'package:thoughtecho/services/settings_service.dart';
import 'package:thoughtecho/services/weather_service.dart';
import 'package:thoughtecho/widgets/add_note_dialog.dart';

import '../../test_harness.dart';

Future<void> _flushDraftIo(WidgetTester tester) async {
  await tester.pump();
  await tester.runAsync(() => DraftService().waitForIdleForTesting());
  await tester.pump();
  await tester.runAsync(() => DraftService().waitForIdleForTesting());
  await tester.pump();
}

Future<void> _settleAgentTurn(WidgetTester tester) async {
  for (var i = 0; i < 3; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump(const Duration(milliseconds: 100));
  }
}

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
  AppSettings get appSettings => AppSettings(developerMode: false);

  @override
  LocalAISettings get localAISettings => const LocalAISettings();

  @override
  MultiAISettings get multiAISettings => const MultiAISettings();

  @override
  bool get enableFirstOpenScrollPerfMonitor => false;

  @override
  bool get addNoteDialogDeferAutoMetadata => false;

  @override
  bool get addNoteDialogAutoFocus => false;

  @override
  bool get dontShowAgentExperimentalNotice => true;

  @override
  bool get agentMemoryNoticeShown => true;

  @override
  ThoughterPageMode get noteAiAssistantMode => ThoughterPageMode.agent;

  @override
  ThoughterPageMode get exploreAiAssistantMode => ThoughterPageMode.agent;

  @override
  bool get agentMemoryEnabled => false;

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

class _InMemoryChatSessionService extends ChatSessionService {
  final Map<String, ChatSession> _sessions = <String, ChatSession>{};
  final Map<String, List<app_chat.ChatMessage>> _messages =
      <String, List<app_chat.ChatMessage>>{};
  int _seq = 0;

  @override
  Future<void> init() async {}

  @override
  Future<ChatSession> createSession({
    required String sessionType,
    String? noteId,
    required String title,
  }) async {
    final now = DateTime.now();
    final session = ChatSession(
      id: 'session-${_seq++}',
      sessionType: sessionType,
      noteId: noteId,
      title: title,
      createdAt: now,
      lastActiveAt: now,
    );
    _sessions[session.id] = session;
    return session;
  }

  @override
  Future<ChatSession?> getLatestSessionForNote(String noteId) async => null;

  @override
  Future<void> addMessage(
    String sessionId,
    app_chat.ChatMessage message,
  ) async {
    _messages
        .putIfAbsent(sessionId, () => <app_chat.ChatMessage>[])
        .add(message);
  }

  @override
  Future<void> updateSessionTitle(String sessionId, String title) async {}

  @override
  Future<List<app_chat.ChatMessage>> getMessages(String sessionId) async =>
      List<app_chat.ChatMessage>.from(
        _messages[sessionId] ?? const <app_chat.ChatMessage>[],
      );

  @override
  Future<void> deleteSession(String sessionId) async {
    _sessions.remove(sessionId);
    _messages.remove(sessionId);
  }

  @override
  Future<bool?> sessionHasUserMessages(String sessionId) async =>
      _messages[sessionId]?.any((m) => m.isUser) ?? false;
}

class _TestAIService extends AIService {
  _TestAIService({required super.settingsService});
}

class _RecordingAgentService extends AgentService {
  _RecordingAgentService({required super.settingsService})
      : super(tools: const []);

  final StreamController<AgentEvent> _events =
      StreamController<AgentEvent>.broadcast(sync: true);
  int runCount = 0;
  String? lastUserMessage;
  AgentNoteContext? lastNoteContext;

  @override
  Stream<AgentEvent> get events => _events.stream;

  @override
  bool get isRunning => false;

  @override
  String get currentStatusKey => '';

  @override
  void setAskUserHandler(AskUserPromptHandler? handler) {}

  @override
  void requestStop() {}

  @override
  Future<AgentResponse> runAgent({
    required String userMessage,
    List<app_chat.ChatMessage>? history,
    AgentNoteContext? noteContext,
  }) async {
    runCount++;
    lastUserMessage = userMessage;
    lastNoteContext = noteContext;
    return AgentResponse(content: 'Itinerary summary response');
  }

  @override
  void dispose() {
    unawaited(_events.close());
    super.dispose();
  }
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
    if (seededQuote?.id == id) return seededQuote;
    if (lastSavedQuote?.id == id) return lastSavedQuote;
    return null;
  }

  Quote? seededQuote;

  @override
  Stream<List<NoteTag>> watchTags() =>
      Stream<List<NoteTag>>.value(const <NoteTag>[]);

  @override
  Future<List<NoteTag>> getTags() async => const <NoteTag>[];

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _MockFeatureGuideService extends FeatureGuideService {
  _MockFeatureGuideService() : super(AppPreferencesService());

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
    await AppPreferencesService().init();
  });

  setUp(() async {
    databaseService = _MockDatabaseService();
    await AppPreferencesService().clear();
    await DraftService().deleteAllDrafts();
  });

  tearDownAll(() async {
    await DraftService().resetForTesting();
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
      await _flushDraftIo(tester);
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
      await _flushDraftIo(tester);
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
      await _flushDraftIo(tester);
      await tester.pumpAndSettle();

      // Verify note was saved and editor was popped
      expect(databaseService.addQuoteCallCount, equals(1));
      expect(find.byType(NoteFullEditorPage), findsNothing);
    },
  );

  testWidgets(
    'new rich-text note saved via Ctrl+S passes editSource and deltaContent with matching revision to ThoughterPage',
    (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      final editor = find.byType(QuillEditor);
      final controller = tester.widget<QuillEditor>(editor).controller;
      controller.replaceText(
        0,
        0,
        'Rich bold note',
        const TextSelection.collapsed(offset: 14),
      );
      controller.formatText(0, 4, Attribute.bold);
      await tester.pump();

      // Save in-place via Ctrl+S
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await _flushDraftIo(tester);
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();

      expect(databaseService.addQuoteCallCount, equals(1));
      final savedQuote = databaseService.lastSavedQuote!;
      expect(savedQuote.id, isNotNull);
      expect(savedQuote.editSource, equals('fullscreen'));
      expect(savedQuote.deltaContent, isNotNull);

      // Open AI assistant without unsaved changes dialog (already clean)
      await tester.tap(find.byIcon(Icons.auto_awesome));
      await tester.pumpAndSettle();
      final l10n = await AppLocalizations.delegate.load(const Locale('zh'));
      await tester.tap(find.text(l10n.polishText));
      await tester.pumpAndSettle();

      final thoughterFinder = find.byType(ThoughterPage);
      expect(thoughterFinder, findsOneWidget);
      final thoughterQuote =
          tester.widget<ThoughterPage>(thoughterFinder).quote;
      expect(thoughterQuote, isNotNull);
      expect(thoughterQuote!.id, equals(savedQuote.id));
      expect(thoughterQuote.editSource, equals('fullscreen'));
      expect(thoughterQuote.deltaContent, equals(savedQuote.deltaContent));
      expect(
        ProposeNoteEditTool.kindForQuote(thoughterQuote),
        equals(ProposeNoteEditTool.kindForQuote(savedQuote)),
      );
      expect(
        ProposeNoteEditTool.revisionForQuote(thoughterQuote),
        equals(ProposeNoteEditTool.revisionForQuote(savedQuote)),
      );
    },
  );

  testWidgets(
    'saved fullscreen note falling back to plain text due to unreadable Delta still sends read-only AI questions without substitute revision',
    (tester) async {
      tester.view.physicalSize = const Size(900, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      TestWidgetsFlutterBinding
              .instance.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(() {
        TestWidgetsFlutterBinding.instance.platformDispatcher
            .clearAccessibilityFeaturesTestValue();
      });

      final settings = _MockSettingsService();
      final chatSessions = _InMemoryChatSessionService();
      final aiService = _TestAIService(settingsService: settings);
      final agentService = _RecordingAgentService(settingsService: settings);
      addTearDown(agentService.dispose);

      final corruptNote = Quote(
        id: 'corrupt-delta-note-1',
        content: 'Trip itinerary',
        date: '2026-06-06T12:00:00Z',
        editSource: 'fullscreen',
        deltaContent: '[{"insert":"Trip itinerary',
      );
      databaseService.seededQuote = corruptNote;

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<SettingsService>.value(value: settings),
            ChangeNotifierProvider<DatabaseService>.value(
              value: databaseService,
            ),
            ChangeNotifierProvider<FeatureGuideService>(
              create: (_) => _MockFeatureGuideService(),
            ),
            ChangeNotifierProvider<ChatSessionService>.value(
              value: chatSessions,
            ),
            ChangeNotifierProvider<AIService>.value(value: aiService),
            ChangeNotifierProvider<AgentService>.value(value: agentService),
            ChangeNotifierProvider<LocationService>.value(
              value: _TestLocationService(),
            ),
            ChangeNotifierProvider<WeatherService>.value(
              value: _TestWeatherService(),
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
              initialContent: corruptNote.content,
              initialQuote: corruptNote,
              skipDefaultMetadataAutofill: true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Editor displays plain-text fallback
      final controller =
          tester.widget<QuillEditor>(find.byType(QuillEditor)).controller;
      expect(controller.document.toPlainText().trim(), 'Trip itinerary');

      // Open AI assistant and trigger a read-only analysis prompt
      await tester.tap(find.byIcon(Icons.auto_awesome));
      await tester.pumpAndSettle();
      final l10n = await AppLocalizations.delegate.load(const Locale('zh'));
      await tester.tap(find.text(l10n.deepAnalysis));
      await tester.pumpAndSettle();
      await _settleAgentTurn(tester);
      await tester.pumpAndSettle();

      expect(find.byType(ThoughterPage), findsOneWidget);
      expect(agentService.runCount, equals(1));
      expect(agentService.lastNoteContext, isNotNull);
      expect(
        agentService.lastNoteContext!.noteId,
        equals('corrupt-delta-note-1'),
      );
      expect(agentService.lastNoteContext!.content, equals('Trip itinerary'));
      expect(
        agentService.lastNoteContext!.documentKind,
        equals(NoteDocumentKind.rich),
      );
      expect(agentService.lastNoteContext!.documentRevision, isNull);
      expect(find.textContaining('Itinerary summary response'), findsOneWidget);
    },
  );

  testWidgets(
    'AddNoteDialog is removed from underneath ThoughterPage after saving in full editor and opening AI assistant',
    (tester) async {
      tester.view.physicalSize = const Size(900, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      TestWidgetsFlutterBinding
              .instance.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(() {
        TestWidgetsFlutterBinding.instance.platformDispatcher
            .clearAccessibilityFeaturesTestValue();
      });

      final originalOnError = FlutterError.onError;
      FlutterError.onError = (details) {
        if (details.exceptionAsString().contains('A RenderFlex overflowed')) {
          return;
        }
        originalOnError?.call(details);
      };
      addTearDown(() => FlutterError.onError = originalOnError);

      final settings = _MockSettingsService();
      final chatSessions = _InMemoryChatSessionService();
      final aiService = _TestAIService(settingsService: settings);
      final agentService = _RecordingAgentService(settingsService: settings);
      addTearDown(agentService.dispose);

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<SettingsService>.value(value: settings),
            ChangeNotifierProvider<DatabaseService>.value(
              value: databaseService,
            ),
            ChangeNotifierProvider<FeatureGuideService>(
              create: (_) => _MockFeatureGuideService(),
            ),
            ChangeNotifierProvider<ChatSessionService>.value(
              value: chatSessions,
            ),
            ChangeNotifierProvider<AIService>.value(value: aiService),
            ChangeNotifierProvider<AgentService>.value(value: agentService),
            ChangeNotifierProvider<LocationService>.value(
              value: _TestLocationService(),
            ),
            ChangeNotifierProvider<WeatherService>.value(
              value: _TestWeatherService(),
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
                  onPressed: () => AddNoteDialog.show<void>(
                    context: context,
                    tags: const [],
                    prefilledContent: 'Compact note for AI',
                    onSave: databaseService.addQuote,
                  ),
                  child: const Text('Open Compact Note Sheet'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Open compact AddNoteDialog sheet and expand to NoteFullEditorPage
      await tester.tap(find.text('Open Compact Note Sheet'));
      await tester.pumpAndSettle();
      expect(find.byType(AddNoteDialog), findsOneWidget);

      await tester.tap(find.byIcon(Icons.fullscreen));
      await tester.pumpAndSettle();
      expect(find.byType(NoteFullEditorPage), findsOneWidget);

      // Save in place via Ctrl+S and navigate to ThoughterPage
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await _flushDraftIo(tester);
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();
      expect(databaseService.addQuoteCallCount, equals(1));

      await tester.tap(find.byIcon(Icons.auto_awesome));
      await tester.pumpAndSettle();
      final l10n = await AppLocalizations.delegate.load(const Locale('zh'));
      await tester.tap(find.text(l10n.askNote));
      await tester.pumpAndSettle();

      expect(find.byType(ThoughterPage), findsOneWidget);

      // Pop ThoughterPage and verify we return directly to the home page, NOT AddNoteDialog
      final thoughterContext = tester.element(find.byType(ThoughterPage));
      Navigator.of(thoughterContext).pop();
      await tester.pumpAndSettle();

      expect(find.byType(ThoughterPage), findsNothing);
      expect(find.byType(AddNoteDialog), findsNothing);
      expect(find.text('Open Compact Note Sheet'), findsOneWidget);
      expect(databaseService.addQuoteCallCount, equals(1));
    },
  );
}
