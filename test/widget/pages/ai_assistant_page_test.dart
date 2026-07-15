import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:thoughtecho/gen_l10n/app_localizations.dart';
import 'package:thoughtecho/models/ai_assistant_entry.dart';
import 'package:thoughtecho/models/ai_provider_settings.dart';
import 'package:thoughtecho/models/chat_message.dart' as app_chat;
import 'package:thoughtecho/models/chat_session.dart';
import 'package:thoughtecho/models/multi_ai_settings.dart';
import 'package:thoughtecho/models/quote_model.dart';
import 'package:thoughtecho/pages/ai_assistant_page.dart';
import 'package:thoughtecho/services/agent_service.dart';
import 'package:thoughtecho/services/agent_tool.dart';
import 'package:thoughtecho/services/ai_service.dart';
import 'package:thoughtecho/services/chat_session_service.dart';
import 'package:thoughtecho/services/location_service.dart';
import 'package:thoughtecho/services/settings_service.dart';
import 'package:thoughtecho/services/weather_service.dart';
import 'package:thoughtecho/widgets/ai/tool_progress_panel.dart';

import '../../test_harness.dart';

Quote _buildQuote() => Quote(
      id: 'note-1',
      content: '今天的笔记内容',
      date: DateTime(2026, 4, 5).toIso8601String(),
    );

class _InMemoryChatSessionService extends ChatSessionService {
  final Map<String, ChatSession> _sessions = <String, ChatSession>{};
  final Map<String, List<app_chat.ChatMessage>> _messages =
      <String, List<app_chat.ChatMessage>>{};
  int _sessionSeq = 0;

  @override
  Future<void> init() async {}

  void seedSession(
    ChatSession session,
    List<app_chat.ChatMessage> messages,
  ) {
    _sessions[session.id] = session;
    _messages[session.id] = List<app_chat.ChatMessage>.from(messages);
  }

  @override
  Future<ChatSession> createSession({
    required String sessionType,
    String? noteId,
    required String title,
  }) async {
    final now = DateTime.now();
    final session = ChatSession(
      id: 'session-${_sessionSeq++}',
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
  Future<ChatSession?> getLatestSessionForNote(String noteId) async {
    final candidates = _sessions.values
        .where((session) => session.noteId == noteId)
        .toList(growable: false);
    if (candidates.isEmpty) {
      return null;
    }
    candidates.sort((a, b) => b.lastActiveAt.compareTo(a.lastActiveAt));
    return candidates.first;
  }

  @override
  Future<void> addMessage(
      String sessionId, app_chat.ChatMessage message) async {
    _messages
        .putIfAbsent(sessionId, () => <app_chat.ChatMessage>[])
        .add(message);
  }

  @override
  Future<void> updateSessionTitle(String sessionId, String title) async {
    final session = _sessions[sessionId];
    if (session == null) return;
    _sessions[sessionId] = session.copyWith(title: title);
  }

  @override
  Future<List<app_chat.ChatMessage>> getMessages(String sessionId) async {
    return List<app_chat.ChatMessage>.from(
      _messages[sessionId] ?? const <app_chat.ChatMessage>[],
    );
  }
}

class _FakeAIService extends AIService {
  _FakeAIService({required super.settingsService});

  int askQuestionCalls = 0;
  int summarizeCalls = 0;
  int generalConversationCalls = 0;

  @override
  Stream<String> streamPolishText(String content) => Stream.value('已润色内容');

  @override
  Stream<String> streamContinueText(String content) => Stream.value('续写内容');

  @override
  Stream<String> streamSummarizeNote(Quote quote, {List<String>? tagNames}) {
    summarizeCalls++;
    return Stream.value('深度分析结果');
  }

  @override
  Stream<String> streamAnalyzeSource(String content) => Stream.value(
      '{"author":"作者A","work":"作品B","confidence":"高","explanation":"来源分析结果"}');

  @override
  Stream<String> streamGenerateInsights(
    List<Quote> quotes, {
    String analysisType = 'comprehensive',
    String analysisStyle = 'professional',
    String? customPrompt,
  }) =>
      Stream.value('智能洞察结果');

  @override
  Stream<String> streamAskQuestion(
    Quote quote,
    String question, {
    bool? enableThinking,
    List<app_chat.ChatMessage>? history,
    Function(String)? onThinking,
  }) {
    askQuestionCalls++;
    return Stream.value('笔记问答结果');
  }

  @override
  Stream<String> streamGeneralConversation(
    String question, {
    bool? enableThinking,
    List<app_chat.ChatMessage>? history,
    String? systemContext,
    Function(String)? onThinking,
  }) {
    generalConversationCalls++;
    return Stream.value('普通对话结果');
  }
}

class _FakeAgentService extends AgentService {
  _FakeAgentService({
    required super.settingsService,
    this.simulateToolProgress = false,
    this.emitSmartResultCard = false,
    this.responseContent = 'Agent 响应',
    this.responseChunks = const <String>[],
    this.responseChunkDelay = const Duration(milliseconds: 12),
    this.preToolText,
    this.toolProgressDelay = const Duration(milliseconds: 12),
    this.postToolDelay = Duration.zero,
    this.toolName = 'search_notes',
    Map<String, Object?>? toolArguments,
    this.toolResult = '搜索结果',
    this.error,
  })  : effectiveToolArguments = Map<String, Object?>.unmodifiable(
          toolArguments ?? const <String, Object?>{},
        ),
        super(tools: const []);

  final Map<String, Object?> effectiveToolArguments;

  int runCount = 0;
  final bool simulateToolProgress;
  final bool emitSmartResultCard;
  final String responseContent;
  final List<String> responseChunks;
  final Duration responseChunkDelay;
  final String? preToolText;
  final Duration toolProgressDelay;
  final Duration postToolDelay;
  final String toolName;
  final String toolResult;
  final Object? error;
  bool _mockIsRunning = false;
  String _mockStatusKey = '';
  bool stopRequested = false;
  final Set<Timer> _pendingTimers = <Timer>{};
  final StreamController<AgentEvent> _eventController =
      StreamController<AgentEvent>.broadcast(sync: true);

  @override
  Stream<AgentEvent> get events => _eventController.stream;

  @override
  bool get isRunning => _mockIsRunning;

  @override
  String get currentStatusKey => _mockStatusKey;

  void _setMockState({
    required bool isRunning,
    required String statusKey,
  }) {
    _mockIsRunning = isRunning;
    _mockStatusKey = statusKey;
    notifyListeners();
  }

  @override
  void requestStop() {
    stopRequested = true;
    _cancelPendingTimers();
    _setMockState(isRunning: false, statusKey: '');
  }

  Future<void> _delay(Duration duration) {
    final completer = Completer<void>();
    late final Timer timer;
    timer = Timer(duration, () {
      _pendingTimers.remove(timer);
      completer.complete();
    });
    _pendingTimers.add(timer);
    return completer.future;
  }

  void _cancelPendingTimers() {
    for (final timer in _pendingTimers) {
      timer.cancel();
    }
    _pendingTimers.clear();
  }

  @override
  Future<AgentResponse> runAgent({
    required String userMessage,
    List<app_chat.ChatMessage>? history,
    String? noteContext,
  }) async {
    runCount++;
    _setMockState(isRunning: true, statusKey: 'agentThinking');

    if (error != null) {
      _setMockState(isRunning: false, statusKey: '');
      throw error!;
    }

    if (simulateToolProgress) {
      _emitEvent(AgentThinkingEvent());
      if (preToolText != null) {
        _emitEvent(AgentTextDeltaEvent(preToolText!));
      }
      final toolCallId = 'tool-call-1';
      _emitEvent(
        AgentToolCallStartEvent(
          toolCallId: toolCallId,
          toolName: toolName,
          arguments: effectiveToolArguments.isEmpty
              ? <String, Object?>{'query': userMessage}
              : effectiveToolArguments,
        ),
      );
      await _delay(toolProgressDelay);
      if (stopRequested) {
        _setMockState(isRunning: false, statusKey: '');
        return AgentResponse(content: '');
      }
      _emitEvent(
        AgentToolCallResultEvent(
          toolCallId: toolCallId,
          toolName: toolName,
          result: toolResult,
          isError: false,
        ),
      );
      await _delay(postToolDelay);
    }

    final toolCalls = emitSmartResultCard
        ? <ToolCall>[
            ToolCall(
              id: 'tool-call-2',
              name: 'propose_edit',
              arguments: <String, Object?>{
                'title': '润色结果',
                'content': '这是可应用的新内容',
                'action': 'replace',
                'include_location': true,
                'include_weather': true,
              },
            ),
          ]
        : const <ToolCall>[];

    for (final chunk in responseChunks) {
      _emitEvent(AgentTextDeltaEvent(chunk));
      await _delay(responseChunkDelay);
    }
    await _delay(const Duration(milliseconds: 12));
    if (stopRequested) {
      _setMockState(isRunning: false, statusKey: '');
      return AgentResponse(content: '');
    }
    _emitEvent(
      AgentResponseEvent(
        content: responseContent.replaceAll(
          '''
```smart_result
{"type":"smart_result","title":"润色结果","content":"这是可应用的新内容"}
```
''',
          '',
        ),
        toolCalls: toolCalls,
      ),
    );
    _setMockState(isRunning: false, statusKey: '');
    return AgentResponse(content: responseContent, toolCalls: toolCalls);
  }

  void _emitEvent(AgentEvent event) {
    _eventController.add(event);
  }

  @override
  void dispose() {
    _cancelPendingTimers();
    _eventController.close();
    super.dispose();
  }
}

class _ControllableAgentService extends AgentService {
  _ControllableAgentService({
    required super.settingsService,
    required this.responses,
  }) : super(tools: const <AgentTool>[]);

  final List<Completer<AgentResponse>> responses;
  final StreamController<AgentEvent> _eventController =
      StreamController<AgentEvent>.broadcast();
  int runCount = 0;
  bool _mockIsRunning = false;

  @override
  Stream<AgentEvent> get events => _eventController.stream;

  @override
  bool get isRunning => _mockIsRunning;

  @override
  void requestStop() {
    _mockIsRunning = false;
    notifyListeners();
  }

  @override
  Future<AgentResponse> runAgent({
    required String userMessage,
    List<app_chat.ChatMessage>? history,
    String? noteContext,
  }) {
    _mockIsRunning = true;
    notifyListeners();
    return responses[runCount++].future.whenComplete(() {
      _mockIsRunning = false;
      notifyListeners();
    });
  }

  @override
  void dispose() {
    unawaited(_eventController.close());
    super.dispose();
  }
}

Future<Widget> _buildHarness({
  required SettingsService settingsService,
  required ChatSessionService chatSessionService,
  _FakeAIService? aiService,
  AgentService? agentService,
  required Widget child,
}) async {
  final effectiveAgentService =
      agentService ?? _FakeAgentService(settingsService: settingsService);
  final effectiveAiService =
      aiService ?? _FakeAIService(settingsService: settingsService);

  return MultiProvider(
    providers: [
      ChangeNotifierProvider<SettingsService>.value(value: settingsService),
      ChangeNotifierProvider<ChatSessionService>.value(
          value: chatSessionService),
      ChangeNotifierProvider<AgentService>.value(value: effectiveAgentService),
      ChangeNotifierProvider<AIService>.value(value: effectiveAiService),
      ChangeNotifierProvider<LocationService>(
        create: (_) => LocationService(),
      ),
      ChangeNotifierProvider<WeatherService>(
        create: (_) => WeatherService(),
      ),
    ],
    child: MaterialApp(
      locale: const Locale('zh'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: child,
    ),
  );
}

Future<void> _submitInput(WidgetTester tester, String text) async {
  await tester.enterText(find.byType(TextField).last, text);
  await tester.pump();
  final sendButtonFinder = find.byKey(
    const ValueKey('ai_assistant_send_button'),
  );
  final effectiveSendFinder = sendButtonFinder.evaluate().isNotEmpty
      ? sendButtonFinder
      : find.widgetWithIcon(IconButton, Icons.arrow_upward).last;
  final sendButton = tester.widget<IconButton>(effectiveSendFinder);
  sendButton.onPressed?.call();
  await tester.pump();
  await tester.pumpAndSettle();
}

AppLocalizations _l10n(WidgetTester tester) {
  return AppLocalizations.of(tester.element(find.byType(AIAssistantPage)));
}

void main() {
  group('AIAssistantPage', () {
    late SettingsService settingsService;
    late _InMemoryChatSessionService chatSessionService;

    setUp(() async {
      await TestHarness.initialize();
      settingsService = await SettingsService.create();
      chatSessionService = _InMemoryChatSessionService();
    });

    tearDown(() async {
      await TestHarness.tearDown();
    });

    testWidgets('explore entry defaults to agent without mode toggle',
        (tester) async {
      await tester.pumpWidget(
        await _buildHarness(
          settingsService: settingsService,
          chatSessionService: chatSessionService,
          child: const AIAssistantPage(
            key: ValueKey('explore_default_page'),
            entrySource: AIAssistantEntrySource.explore,
          ),
        ),
      );
      await tester.pumpAndSettle();

      final l10n = _l10n(tester);
      expect(find.text(l10n.aiModeChat), findsNothing);
      expect(find.text(l10n.aiModeAgent), findsNothing);
      expect(find.widgetWithText(ActionChip, '/润色'), findsNothing);
    });

    testWidgets('does not offer attachments that Agent cannot consume',
        (tester) async {
      await tester.pumpWidget(
        await _buildHarness(
          settingsService: settingsService,
          chatSessionService: chatSessionService,
          child: const AIAssistantPage(
            entrySource: AIAssistantEntrySource.explore,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.widgetWithIcon(IconButton, Icons.add), findsNothing);
    });

    testWidgets('hides the unsupported thinking toggle in Agent mode',
        (tester) async {
      const provider = AIProviderSettings(
        id: 'openai',
        name: 'OpenAI',
        apiUrl: 'https://api.openai.com/v1/chat/completions',
        model: 'o3-mini',
      );
      await settingsService.saveMultiAISettings(
        const MultiAISettings(
          providers: [provider],
          currentProviderId: 'openai',
        ),
      );
      await settingsService.setExploreAiAssistantMode(
        AIAssistantPageMode.agent,
      );

      await tester.pumpWidget(
        await _buildHarness(
          settingsService: settingsService,
          chatSessionService: chatSessionService,
          child: const AIAssistantPage(
            entrySource: AIAssistantEntrySource.explore,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '触发重建');
      await tester.pump();

      expect(find.byIcon(Icons.psychology), findsNothing);
      expect(find.byIcon(Icons.psychology_outlined), findsNothing);
    });

    testWidgets('note entry keeps note context and defaults to agent',
        (tester) async {
      await tester.pumpWidget(
        await _buildHarness(
          settingsService: settingsService,
          chatSessionService: chatSessionService,
          child: AIAssistantPage(
            key: const ValueKey('note_default_page'),
            entrySource: AIAssistantEntrySource.note,
            quote: _buildQuote(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final l10n = _l10n(tester);
      expect(find.text(l10n.aiModeChat), findsNothing);
      expect(find.text(l10n.aiModeAgent), findsNothing);
      expect(find.textContaining(l10n.currentNoteContext), findsOneWidget);
    });

    testWidgets(
        'explore entry renders guide summary welcome as first system message',
        (tester) async {
      const insight = '这本月你用心记录了3天，4篇文字承载着日常感悟。'
          '午后书写、雨相伴，「随记」是你的思绪主线。';
      await tester.pumpWidget(
        await _buildHarness(
          settingsService: settingsService,
          chatSessionService: chatSessionService,
          child: const AIAssistantPage(
            entrySource: AIAssistantEntrySource.explore,
            exploreGuideSummary: insight,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.textContaining('这本月你用心记录了3天'),
        findsOneWidget,
      );
      expect(find.textContaining('「随记」是你的思绪主线'), findsOneWidget);
    });

    testWidgets('remembered mode is isolated between explore and note entry',
        (tester) async {
      await settingsService.setExploreAiAssistantMode(
        AIAssistantPageMode.agent,
      );
      await settingsService.setNoteAiAssistantMode(
        AIAssistantPageMode.noteChat,
      );

      await tester.pumpWidget(
        await _buildHarness(
          settingsService: settingsService,
          chatSessionService: chatSessionService,
          child: const AIAssistantPage(
            key: ValueKey('explore_memory_page'),
            entrySource: AIAssistantEntrySource.explore,
          ),
        ),
      );
      await tester.pumpAndSettle();

      final l10n = _l10n(tester);
      expect(find.text(l10n.aiModeAgent), findsNothing);
      expect(find.text(l10n.aiModeChat), findsNothing);

      await tester.pumpWidget(
        await _buildHarness(
          settingsService: settingsService,
          chatSessionService: chatSessionService,
          child: AIAssistantPage(
            key: const ValueKey('note_memory_page'),
            entrySource: AIAssistantEntrySource.note,
            quote: _buildQuote(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final noteL10n = _l10n(tester);
      expect(find.text(noteL10n.aiModeChat), findsNothing);
      expect(find.text(noteL10n.aiModeAgent), findsNothing);
    });

    testWidgets('dragging messages keeps the focused input keyboard active',
        (tester) async {
      final now = DateTime.now();
      final session = ChatSession(
        id: 'scroll-session',
        sessionType: 'general',
        title: '滚动测试',
        createdAt: now,
        lastActiveAt: now,
      );
      chatSessionService.seedSession(
        session,
        List<app_chat.ChatMessage>.generate(
          30,
          (index) => app_chat.ChatMessage(
            id: 'history-$index',
            role: 'assistant',
            isUser: false,
            content: '历史消息 $index：一段足以占据单行高度的内容',
            timestamp: now,
          ),
        ),
      );
      await tester.pumpWidget(
        await _buildHarness(
          settingsService: settingsService,
          chatSessionService: chatSessionService,
          child: AIAssistantPage(
            entrySource: AIAssistantEntrySource.explore,
            session: session,
          ),
        ),
      );
      await tester.pumpAndSettle();

      final inputFinder = find.byType(TextField).last;
      await tester.tap(inputFinder);
      await tester.pump();
      final inputFocusNode = tester.widget<TextField>(inputFinder).focusNode!;
      expect(inputFocusNode.hasFocus, isTrue);

      final listContext = tester.element(find.byType(ListView));
      final listController =
          tester.widget<ListView>(find.byType(ListView)).controller!;
      ScrollUpdateNotification(
        metrics: listController.position,
        context: listContext,
        scrollDelta: -1,
        dragDetails: DragUpdateDetails(globalPosition: Offset.zero),
      ).dispatch(listContext);
      await tester.pump();

      expect(inputFocusNode.hasFocus, isTrue);
    });

    testWidgets(
        'scroll-to-bottom reaches the latest extent while input focused',
        (tester) async {
      final agentService = _FakeAgentService(
        settingsService: settingsService,
        responseContent: '回答完成',
        responseChunks: <String>[
          List<String>.filled(80, '第一批流式内容').join('\n'),
          List<String>.filled(30, '随后到达的新内容').join('\n'),
        ],
        responseChunkDelay: const Duration(milliseconds: 1000),
      );
      await settingsService
          .setExploreAiAssistantMode(AIAssistantPageMode.agent);
      await tester.pumpWidget(
        await _buildHarness(
          settingsService: settingsService,
          chatSessionService: chatSessionService,
          agentService: agentService,
          child: const AIAssistantPage(
            entrySource: AIAssistantEntrySource.explore,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).last, '生成较长回答');
      await tester.pump();
      final inputFocusNode =
          tester.widget<TextField>(find.byType(TextField).last).focusNode!;
      final sendButton = find.byKey(
        const ValueKey('ai_assistant_send_button'),
      );
      final effectiveSendButton = sendButton.evaluate().isNotEmpty
          ? sendButton
          : find.widgetWithIcon(IconButton, Icons.arrow_upward).last;
      tester.widget<IconButton>(effectiveSendButton).onPressed?.call();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      final listContext = tester.element(find.byType(ListView));
      final listController =
          tester.widget<ListView>(find.byType(ListView)).controller!;
      ScrollUpdateNotification(
        metrics: listController.position,
        context: listContext,
        scrollDelta: -1,
        dragDetails: DragUpdateDetails(globalPosition: Offset.zero),
      ).dispatch(listContext);
      await tester.pump();
      final bottomButton = find.byKey(
        const ValueKey('ai_assistant_scroll_to_bottom'),
      );
      expect(bottomButton, findsOneWidget);
      expect(inputFocusNode.hasFocus, isTrue);

      tester.widget<IconButton>(bottomButton).onPressed?.call();
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      expect(
        listController.position.pixels,
        moreOrLessEquals(
          listController.position.maxScrollExtent,
          epsilon: 1,
        ),
      );
      expect(inputFocusNode.hasFocus, isTrue);
      await tester.pump(const Duration(seconds: 2));
    });

    testWidgets('agent mode routes deep analysis with extra prompt to workflow',
        (tester) async {
      final aiService = _FakeAIService(settingsService: settingsService);
      final agentService = _FakeAgentService(settingsService: settingsService);
      await settingsService.setNoteAiAssistantMode(AIAssistantPageMode.agent);

      await tester.pumpWidget(
        await _buildHarness(
          settingsService: settingsService,
          chatSessionService: chatSessionService,
          aiService: aiService,
          agentService: agentService,
          child: AIAssistantPage(
            entrySource: AIAssistantEntrySource.note,
            quote: _buildQuote(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await _submitInput(tester, '/深度分析 帮我拆解重点');
      await tester.pumpAndSettle();

      expect(aiService.summarizeCalls, 1);
      expect(aiService.askQuestionCalls, 0);
      expect(aiService.generalConversationCalls, 0);
      expect(agentService.runCount, 0);
    });

    testWidgets('explore agent mode deep analysis shows bound note notice',
        (tester) async {
      final aiService = _FakeAIService(settingsService: settingsService);
      final agentService = _FakeAgentService(settingsService: settingsService);
      await settingsService
          .setExploreAiAssistantMode(AIAssistantPageMode.agent);

      await tester.pumpWidget(
        await _buildHarness(
          settingsService: settingsService,
          chatSessionService: chatSessionService,
          aiService: aiService,
          agentService: agentService,
          child: const AIAssistantPage(
            entrySource: AIAssistantEntrySource.explore,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await _submitInput(tester, '/深度分析 帮我拆解重点');

      expect(aiService.summarizeCalls, 0);
      expect(aiService.askQuestionCalls, 0);
      expect(aiService.generalConversationCalls, 0);
      expect(agentService.runCount, 0);
      expect(find.textContaining('此功能需要绑定笔记才能使用'), findsAtLeastNWidgets(1));
    });

    testWidgets(
        'agent tool progress remains briefly after completion without placeholder',
        (tester) async {
      final agentService = _FakeAgentService(
        settingsService: settingsService,
        simulateToolProgress: true,
      );
      await settingsService
          .setExploreAiAssistantMode(AIAssistantPageMode.agent);

      await tester.pumpWidget(
        await _buildHarness(
          settingsService: settingsService,
          chatSessionService: chatSessionService,
          agentService: agentService,
          child: const AIAssistantPage(
            entrySource: AIAssistantEntrySource.explore,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), '帮我做一次分析');
      await tester.pump();
      final sendButtonFinder =
          find.byKey(const ValueKey('ai_assistant_send_button'));
      final effectiveSendFinder = sendButtonFinder.evaluate().isNotEmpty
          ? sendButtonFinder
          : find.widgetWithIcon(IconButton, Icons.arrow_upward).last;
      tester.widget<IconButton>(effectiveSendFinder).onPressed?.call();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 80));

      expect(find.text('...'), findsNothing);

      await tester.pump(const Duration(milliseconds: 500));
      final l10n = _l10n(tester);
      final completedHeaderFinder =
          find.textContaining(l10n.executedNOperations(1));
      expect(completedHeaderFinder, findsOneWidget);
      final completedPanelFinder = find.ancestor(
        of: completedHeaderFinder,
        matching: find.byType(ToolProgressPanel),
      );
      expect(completedPanelFinder, findsWidgets);
    });

    testWidgets(
        'tool spinner stops at result and panel is folded before final answer',
        (tester) async {
      final agentService = _FakeAgentService(
        settingsService: settingsService,
        simulateToolProgress: true,
        toolProgressDelay: const Duration(milliseconds: 20),
        postToolDelay: const Duration(milliseconds: 300),
        responseChunks: const <String>['正式回答开始'],
        responseChunkDelay: const Duration(milliseconds: 300),
      );
      await settingsService
          .setExploreAiAssistantMode(AIAssistantPageMode.agent);

      await tester.pumpWidget(
        await _buildHarness(
          settingsService: settingsService,
          chatSessionService: chatSessionService,
          agentService: agentService,
          child: const AIAssistantPage(
            entrySource: AIAssistantEntrySource.explore,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), '查询后回答');
      await tester.pump();
      final sendButtonFinder =
          find.byKey(const ValueKey('ai_assistant_send_button'));
      final effectiveSendFinder = sendButtonFinder.evaluate().isNotEmpty
          ? sendButtonFinder
          : find.widgetWithIcon(IconButton, Icons.arrow_upward).last;
      tester.widget<IconButton>(effectiveSendFinder).onPressed?.call();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 80));

      final panel = find.byType(ToolProgressPanel);
      expect(panel, findsOneWidget);
      expect(
        find.descendant(
          of: panel,
          matching: find.byType(CircularProgressIndicator),
        ),
        findsNothing,
      );
      expect(find.text('搜索结果'), findsNothing);

      await tester.pump(const Duration(milliseconds: 300));
      expect(find.textContaining('正式回答开始'), findsOneWidget);
      expect(find.text('搜索结果'), findsNothing);
      await tester.pump(const Duration(milliseconds: 400));
    });

    testWidgets('agent response renders chunks before generation completes',
        (tester) async {
      final agentService = _FakeAgentService(
        settingsService: settingsService,
        responseContent: '第一段第二段',
        responseChunks: const <String>['第一段', '第二段'],
        responseChunkDelay: const Duration(milliseconds: 200),
      );
      await settingsService
          .setExploreAiAssistantMode(AIAssistantPageMode.agent);

      await tester.pumpWidget(
        await _buildHarness(
          settingsService: settingsService,
          chatSessionService: chatSessionService,
          agentService: agentService,
          child: const AIAssistantPage(
            entrySource: AIAssistantEntrySource.explore,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), '请流式回答');
      await tester.pump();
      final sendButtonFinder =
          find.byKey(const ValueKey('ai_assistant_send_button'));
      final effectiveSendFinder = sendButtonFinder.evaluate().isNotEmpty
          ? sendButtonFinder
          : find.widgetWithIcon(IconButton, Icons.arrow_upward).last;
      tester.widget<IconButton>(effectiveSendFinder).onPressed?.call();

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 80));

      expect(find.textContaining('第一段'), findsOneWidget);
      expect(find.textContaining('第一段第二段'), findsNothing);

      await tester.pump(const Duration(milliseconds: 400));
      expect(find.textContaining('第一段第二段'), findsOneWidget);
    });

    testWidgets('agent keeps pre-tool narration as a normal message',
        (tester) async {
      final agentService = _FakeAgentService(
        settingsService: settingsService,
        simulateToolProgress: true,
        preToolText: '让我先看看最近的记录。',
        toolProgressDelay: const Duration(milliseconds: 160),
      );
      await settingsService
          .setExploreAiAssistantMode(AIAssistantPageMode.agent);

      await tester.pumpWidget(
        await _buildHarness(
          settingsService: settingsService,
          chatSessionService: chatSessionService,
          agentService: agentService,
          child: const AIAssistantPage(
            entrySource: AIAssistantEntrySource.explore,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), '帮我看看我最近都写了什么内容');
      await tester.pump();
      final sendButtonFinder =
          find.byKey(const ValueKey('ai_assistant_send_button'));
      final effectiveSendFinder = sendButtonFinder.evaluate().isNotEmpty
          ? sendButtonFinder
          : find.widgetWithIcon(IconButton, Icons.arrow_upward).last;
      tester.widget<IconButton>(effectiveSendFinder).onPressed?.call();

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 40));

      final l10n = _l10n(tester);
      expect(
          find.text(l10n.agentReviewingRecentNotes), findsAtLeastNWidgets(1));
      await tester.pump(const Duration(milliseconds: 220));
      final completedHeader = find.textContaining(l10n.executedNOperations(1));
      expect(completedHeader, findsOneWidget);
      final narration = find.textContaining('让我先看看最近的记录。');
      expect(narration, findsOneWidget);
      expect(
        find.ancestor(of: narration, matching: find.byType(ToolProgressPanel)),
        findsNothing,
      );
    });

    testWidgets('agent tool panel shows human summary instead of raw payload',
        (tester) async {
      final agentService = _FakeAgentService(
        settingsService: settingsService,
        simulateToolProgress: true,
        toolProgressDelay: const Duration(milliseconds: 160),
        toolName: 'search_notes',
        toolArguments: const <String, Object?>{'query': '露营'},
        toolResult:
            '{"notes":[{"id":"n1","content_preview":"周末去露营"}],"pagination":{"offset":0,"limit":10,"next_offset":1,"has_more":true,"total_count":2},"summary":"找到 1 条匹配笔记（总计 2 条，可分页查看）"}',
      );
      await settingsService
          .setExploreAiAssistantMode(AIAssistantPageMode.agent);

      await tester.pumpWidget(
        await _buildHarness(
          settingsService: settingsService,
          chatSessionService: chatSessionService,
          agentService: agentService,
          child: const AIAssistantPage(
            entrySource: AIAssistantEntrySource.explore,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), '帮我找露营记录');
      await tester.pump();
      final sendButtonFinder =
          find.byKey(const ValueKey('ai_assistant_send_button'));
      final effectiveSendFinder = sendButtonFinder.evaluate().isNotEmpty
          ? sendButtonFinder
          : find.widgetWithIcon(IconButton, Icons.arrow_upward).last;
      tester.widget<IconButton>(effectiveSendFinder).onPressed?.call();

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 40));

      final l10n = _l10n(tester);
      await tester.pump(const Duration(milliseconds: 220));
      expect(
        find.textContaining(l10n.agentSearchingNotesForQuery('露营')),
        findsAtLeastNWidgets(1),
      );
      final completedHeaderFinder =
          find.textContaining(l10n.executedNOperations(1));
      expect(completedHeaderFinder, findsOneWidget);
      await tester.tap(completedHeaderFinder);
      await tester.pumpAndSettle();

      expect(
          find.text(l10n.agentFoundMatchingNotesWithMore(2)), findsOneWidget);
      expect(find.textContaining('"notes":['), findsNothing);
      expect(find.textContaining('content_preview'), findsNothing);
    });

    testWidgets('agent stop button interrupts pending tool run',
        (tester) async {
      final agentService = _FakeAgentService(
        settingsService: settingsService,
        simulateToolProgress: true,
        toolProgressDelay: const Duration(milliseconds: 300),
        responseContent: '这段回复不应该出现',
      );
      await settingsService
          .setExploreAiAssistantMode(AIAssistantPageMode.agent);

      await tester.pumpWidget(
        await _buildHarness(
          settingsService: settingsService,
          chatSessionService: chatSessionService,
          agentService: agentService,
          child: const AIAssistantPage(
            entrySource: AIAssistantEntrySource.explore,
          ),
        ),
      );
      await tester.pumpAndSettle();
      final l10n = _l10n(tester);

      await tester.enterText(find.byType(TextField), '帮我看看最近写了什么');
      await tester.pump();
      final sendButtonFinder =
          find.byKey(const ValueKey('ai_assistant_send_button'));
      final effectiveSendFinder = sendButtonFinder.evaluate().isNotEmpty
          ? sendButtonFinder
          : find.widgetWithIcon(IconButton, Icons.arrow_upward).last;
      tester.widget<IconButton>(effectiveSendFinder).onPressed?.call();

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 40));
      await tester.tap(find.byIcon(Icons.stop).last);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 420));

      expect(agentService.stopRequested, isTrue);
      expect(find.text(l10n.agentErrorCancelled), findsOneWidget);
      expect(find.text('这段回复不应该出现'), findsNothing);
      expect(find.byIcon(Icons.arrow_upward), findsAtLeastNWidgets(1));
    });

    testWidgets('a stopped run cannot clear a newer Agent run', (tester) async {
      final firstResponse = Completer<AgentResponse>();
      final secondResponse = Completer<AgentResponse>();
      final agentService = _ControllableAgentService(
        settingsService: settingsService,
        responses: [firstResponse, secondResponse],
      );
      await settingsService.setExploreAiAssistantMode(
        AIAssistantPageMode.agent,
      );

      await tester.pumpWidget(
        await _buildHarness(
          settingsService: settingsService,
          chatSessionService: chatSessionService,
          agentService: agentService,
          child: const AIAssistantPage(
            entrySource: AIAssistantEntrySource.explore,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'first request');
      await tester.pump();
      tester
          .widget<IconButton>(
            find.widgetWithIcon(IconButton, Icons.arrow_upward).last,
          )
          .onPressed
          ?.call();
      await tester.pump(const Duration(milliseconds: 40));
      await tester.tap(find.byIcon(Icons.stop).last);
      await tester.pump();

      await tester.enterText(find.byType(TextField), 'second request');
      await tester.pump();
      tester
          .widget<IconButton>(
            find.widgetWithIcon(IconButton, Icons.arrow_upward).last,
          )
          .onPressed
          ?.call();
      await tester.pump();
      expect(agentService.runCount, 2);

      firstResponse.complete(AgentResponse(content: 'stale response'));
      await tester.pump();
      expect(find.byIcon(Icons.stop), findsAtLeastNWidgets(1));
    });

    testWidgets('disposing an Agent page stops its pending run',
        (tester) async {
      final agentService = _FakeAgentService(
        settingsService: settingsService,
        simulateToolProgress: true,
        toolProgressDelay: const Duration(milliseconds: 300),
      );
      await settingsService.setExploreAiAssistantMode(
        AIAssistantPageMode.agent,
      );

      await tester.pumpWidget(
        await _buildHarness(
          settingsService: settingsService,
          chatSessionService: chatSessionService,
          agentService: agentService,
          child: const AIAssistantPage(
            entrySource: AIAssistantEntrySource.explore,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), '帮我看看最近写了什么');
      await tester.pump();
      tester
          .widget<IconButton>(
            find.widgetWithIcon(IconButton, Icons.arrow_upward).last,
          )
          .onPressed
          ?.call();
      await tester.pump(const Duration(milliseconds: 40));

      await tester.pumpWidget(const SizedBox.shrink());

      expect(agentService.stopRequested, isTrue);
      await tester.pump(const Duration(milliseconds: 320));
    });

    testWidgets('Agent failure never displays raw exception details',
        (tester) async {
      const secretUrl = 'https://token:secret@example.test/path';
      final agentService = _FakeAgentService(
        settingsService: settingsService,
        error: StateError(secretUrl),
      );
      await settingsService.setExploreAiAssistantMode(
        AIAssistantPageMode.agent,
      );

      await tester.pumpWidget(
        await _buildHarness(
          settingsService: settingsService,
          chatSessionService: chatSessionService,
          agentService: agentService,
          child: const AIAssistantPage(
            entrySource: AIAssistantEntrySource.explore,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await _submitInput(tester, '开始请求');

      expect(find.byType(SnackBar), findsOneWidget);
      expect(find.textContaining(secretUrl), findsNothing);
    });

    testWidgets('Agent missing API key gives actionable localized guidance',
        (tester) async {
      final agentService = _FakeAgentService(
        settingsService: settingsService,
        error: const AgentRequestException(
          AgentFailureType.missingApiKey,
          providerName: 'OpenAI',
        ),
      );
      await settingsService.setExploreAiAssistantMode(
        AIAssistantPageMode.agent,
      );

      await tester.pumpWidget(
        await _buildHarness(
          settingsService: settingsService,
          chatSessionService: chatSessionService,
          agentService: agentService,
          child: const AIAssistantPage(
            entrySource: AIAssistantEntrySource.explore,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await _submitInput(tester, '开始请求');

      expect(find.text('请先为 OpenAI 配置 API 密钥，然后重试。'), findsOneWidget);
    });

    testWidgets('Agent timeout gives localized retry guidance', (tester) async {
      final agentService = _FakeAgentService(
        settingsService: settingsService,
        error: const AgentRequestException(AgentFailureType.timeout),
      );
      await settingsService.setExploreAiAssistantMode(
        AIAssistantPageMode.agent,
      );

      await tester.pumpWidget(
        await _buildHarness(
          settingsService: settingsService,
          chatSessionService: chatSessionService,
          agentService: agentService,
          child: const AIAssistantPage(
            entrySource: AIAssistantEntrySource.explore,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await _submitInput(tester, '开始请求');

      expect(find.text('请求超时，请检查网络后重试。'), findsOneWidget);
    });

    testWidgets('agent structured smart result renders apply card',
        (tester) async {
      final agentService = _FakeAgentService(
        settingsService: settingsService,
        responseContent: '''
这是润色建议说明。
''',
        emitSmartResultCard: true,
      );
      await settingsService.setNoteAiAssistantMode(AIAssistantPageMode.agent);

      await tester.pumpWidget(
        await _buildHarness(
          settingsService: settingsService,
          chatSessionService: chatSessionService,
          agentService: agentService,
          child: AIAssistantPage(
            entrySource: AIAssistantEntrySource.note,
            quote: _buildQuote(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await _submitInput(tester, '请润色这段文字');
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 220));
      });
      await tester.pump();
      await tester.pumpAndSettle();

      expect(agentService.runCount, 1);
      expect(find.text('这是可应用的新内容', findRichText: true), findsOneWidget);
      expect(
        find.byKey(const ValueKey('ai_workflow_result_smart_result')),
        findsOneWidget,
      );
    });

    testWidgets('does not render a suggestion card from text-only smart result',
        (tester) async {
      final agentService = _FakeAgentService(
        settingsService: settingsService,
        responseContent: '''
```smart_result
{"title":"未验证建议","content":"不应可应用"}
```
''',
      );
      await settingsService.setNoteAiAssistantMode(AIAssistantPageMode.agent);

      await tester.pumpWidget(
        await _buildHarness(
          settingsService: settingsService,
          chatSessionService: chatSessionService,
          agentService: agentService,
          child: AIAssistantPage(
            entrySource: AIAssistantEntrySource.note,
            quote: _buildQuote(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await _submitInput(tester, '请润色这段文字');
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 220));
      });
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('ai_workflow_result_smart_result')),
        findsNothing,
      );
    });

    testWidgets('new smart result card remains visible at the latest extent',
        (tester) async {
      final now = DateTime.now();
      final session = ChatSession(
        id: 'smart-result-scroll-session',
        sessionType: 'agent',
        noteId: 'note-1',
        title: '建议卡片滚动测试',
        createdAt: now,
        lastActiveAt: now,
      );
      chatSessionService.seedSession(
        session,
        List<app_chat.ChatMessage>.generate(
          24,
          (index) => app_chat.ChatMessage(
            id: 'smart-history-$index',
            role: 'assistant',
            isUser: false,
            content: '历史消息 $index：用于填满滚动区域',
            timestamp: now,
          ),
        ),
      );
      final agentService = _FakeAgentService(
        settingsService: settingsService,
        responseContent: '这是润色建议说明。',
        emitSmartResultCard: true,
      );
      await settingsService.setNoteAiAssistantMode(AIAssistantPageMode.agent);

      await tester.pumpWidget(
        await _buildHarness(
          settingsService: settingsService,
          chatSessionService: chatSessionService,
          agentService: agentService,
          child: AIAssistantPage(
            entrySource: AIAssistantEntrySource.note,
            quote: _buildQuote(),
            session: session,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await _submitInput(tester, '请润色这段文字');
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 220));
      });
      await tester.pump();
      await tester.pumpAndSettle();

      final controller =
          tester.widget<ListView>(find.byType(ListView)).controller!;
      expect(agentService.runCount, 1);
      expect(
        find.byKey(const ValueKey('ai_workflow_result_smart_result')),
        findsOneWidget,
      );
      expect(
        controller.position.pixels,
        moreOrLessEquals(controller.position.maxScrollExtent, epsilon: 1),
      );
    });
  });
}
