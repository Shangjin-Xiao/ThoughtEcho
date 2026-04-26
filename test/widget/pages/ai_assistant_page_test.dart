import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:thoughtecho/gen_l10n/app_localizations.dart';
import 'package:thoughtecho/models/ai_assistant_entry.dart';
import 'package:thoughtecho/models/chat_message.dart' as app_chat;
import 'package:thoughtecho/models/chat_session.dart';
import 'package:thoughtecho/models/quote_model.dart';
import 'package:thoughtecho/pages/ai_assistant_page.dart';
import 'package:thoughtecho/services/agent_service.dart';
import 'package:thoughtecho/services/agent_tool.dart';
import 'package:thoughtecho/services/ai_service.dart';
import 'package:thoughtecho/services/chat_session_service.dart';
import 'package:thoughtecho/services/settings_service.dart';
import 'package:thoughtecho/widgets/ai/tool_progress_panel.dart';

import '../../test_setup.dart';

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
    this.preToolText,
    this.toolProgressDelay = const Duration(milliseconds: 12),
    this.toolName = 'search_notes',
    Map<String, Object?>? toolArguments,
    this.toolResult = '搜索结果',
  })  : effectiveToolArguments = Map<String, Object?>.unmodifiable(
          toolArguments ?? const <String, Object?>{},
        ),
        super(tools: const []);

  final Map<String, Object?> effectiveToolArguments;

  int runCount = 0;
  final bool simulateToolProgress;
  final bool emitSmartResultCard;
  final String responseContent;
  final String? preToolText;
  final Duration toolProgressDelay;
  final String toolName;
  final String toolResult;
  bool _mockIsRunning = false;
  String _mockStatusKey = '';
  bool stopRequested = false;
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
    _setMockState(isRunning: false, statusKey: '');
  }

  @override
  Future<AgentResponse> runAgent({
    required String userMessage,
    List<app_chat.ChatMessage>? history,
    String? noteContext,
  }) async {
    runCount++;
    _setMockState(isRunning: true, statusKey: 'agentThinking');

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
      await Future<void>.delayed(toolProgressDelay);
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
              },
            ),
          ]
        : const <ToolCall>[];

    await Future<void>.delayed(const Duration(milliseconds: 12));
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
    _eventController.close();
    super.dispose();
  }
}

Future<Widget> _buildHarness({
  required SettingsService settingsService,
  required ChatSessionService chatSessionService,
  _FakeAIService? aiService,
  _FakeAgentService? agentService,
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
      await TestSetup.setupAll();
      settingsService = await SettingsService.create();
      chatSessionService = _InMemoryChatSessionService();
    });

    tearDown(() async {
      await TestSetup.teardown();
    });

    testWidgets('explore entry defaults to chat mode with toggle',
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
      expect(find.text(l10n.aiModeChat), findsOneWidget);
      expect(find.widgetWithText(ActionChip, '/润色'), findsNothing);
    });

    testWidgets('note entry keeps note context and defaults to note chat',
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
      expect(find.text(l10n.aiModeChat), findsOneWidget);
      expect(find.textContaining(l10n.currentNoteContext), findsOneWidget);
    });

    testWidgets(
        'explore entry renders guide summary welcome as first system message',
        (tester) async {
      const summary = '本周你写了 3 条记录，情绪更稳定。';
      await tester.pumpWidget(
        await _buildHarness(
          settingsService: settingsService,
          chatSessionService: chatSessionService,
          child: const AIAssistantPage(
            entrySource: AIAssistantEntrySource.explore,
            exploreGuideSummary: summary,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining(summary), findsOneWidget);
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
      expect(find.text(l10n.aiModeAgent), findsOneWidget);

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
      expect(find.text(noteL10n.aiModeChat), findsOneWidget);
    });

    testWidgets('slash commands show only when input starts with slash',
        (tester) async {
      await tester.pumpWidget(
        await _buildHarness(
          settingsService: settingsService,
          chatSessionService: chatSessionService,
          child: const AIAssistantPage(
            key: ValueKey('explore_slash_page'),
            entrySource: AIAssistantEntrySource.explore,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
          find.byKey(const ValueKey('slash_commands_hidden')), findsOneWidget);
      expect(find.widgetWithText(ActionChip, '/润色'), findsNothing);
      await tester.enterText(find.byType(TextField), '/');
      await tester.pumpAndSettle();
      expect(
          find.byKey(const ValueKey('slash_commands_visible')), findsOneWidget);
      expect(find.widgetWithText(ActionChip, '/润色'), findsOneWidget);
      expect(find.widgetWithText(ActionChip, '/续写'), findsOneWidget);
      expect(find.widgetWithText(ActionChip, '/深度分析'), findsOneWidget);
      expect(find.widgetWithText(ActionChip, '/分析来源'), findsOneWidget);
      expect(find.widgetWithText(ActionChip, '/智能洞察'), findsOneWidget);
    });

    testWidgets('slash command list filters by current input', (tester) async {
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

      await tester.enterText(find.byType(TextField), '/分');
      await tester.pumpAndSettle();

      expect(
          find.byKey(const ValueKey('slash_commands_visible')), findsOneWidget);
      expect(find.widgetWithText(ActionChip, '/分析来源'), findsOneWidget);
      expect(find.widgetWithText(ActionChip, '/润色'), findsNothing);
      expect(find.widgetWithText(ActionChip, '/续写'), findsNothing);
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

    testWidgets('agent tool panel keeps pre-tool thinking text inline',
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
      expect(find.text('让我先看看最近的记录。'), findsOneWidget);

      await tester.pump(const Duration(milliseconds: 220));
      expect(find.textContaining(l10n.executedNOperations(1)), findsOneWidget);
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

      expect(find.text('正在查找“露营”相关记录...'), findsAtLeastNWidgets(1));

      await tester.pump(const Duration(milliseconds: 220));

      final l10n = _l10n(tester);
      final completedHeaderFinder =
          find.textContaining(l10n.executedNOperations(1));
      expect(completedHeaderFinder, findsOneWidget);
      await tester.tap(completedHeaderFinder);
      await tester.pumpAndSettle();

      expect(find.text('已找到 2 条相关记录，可继续往下看'), findsOneWidget);
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
      expect(find.text('这段回复不应该出现'), findsNothing);
      expect(find.byIcon(Icons.arrow_upward), findsAtLeastNWidgets(1));
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
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      final smartResultCard =
          find.byKey(const ValueKey('ai_workflow_result_smart_result'));
      await tester.pump();
      await tester.pumpAndSettle();

      expect(agentService.runCount, 1);
      expect(smartResultCard, findsOneWidget);
      expect(
        find.textContaining('这是可应用的新内容', findRichText: true),
        findsOneWidget,
      );
      expect(find.text('替换原文'), findsOneWidget);
      expect(find.text('追加到末尾'), findsOneWidget);
    });
  });
}
