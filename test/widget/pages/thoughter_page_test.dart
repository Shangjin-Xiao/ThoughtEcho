import 'dart:convert';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:thoughtecho/gen_l10n/app_localizations.dart';
import 'package:thoughtecho/models/thoughter_entry.dart';
import 'package:thoughtecho/models/ai_provider_settings.dart';
import 'package:thoughtecho/models/chat_message.dart' as app_chat;
import 'package:thoughtecho/models/chat_session.dart';
import 'package:thoughtecho/models/multi_ai_settings.dart';
import 'package:thoughtecho/models/note_proposal_artifact.dart';
import 'package:thoughtecho/models/note_tag.dart';
import 'package:thoughtecho/models/quote_model.dart';
import 'package:thoughtecho/pages/thoughter_page.dart';
import 'package:thoughtecho/services/agent_service.dart';
import 'package:thoughtecho/services/agent_tool.dart';
import 'package:thoughtecho/services/ai_service.dart';
import 'package:thoughtecho/services/chat_session_service.dart';
import 'package:thoughtecho/services/database_service.dart';
import 'package:thoughtecho/services/location_service.dart';
import 'package:thoughtecho/services/settings_service.dart';
import 'package:thoughtecho/services/weather_service.dart';
import 'package:thoughtecho/widgets/ai/experimental_badge.dart';
import 'package:thoughtecho/widgets/ai/tool_progress_panel.dart';

import '../../test_harness.dart';

Quote _buildQuote() => Quote(
      id: 'note-1',
      content: '今天的笔记内容',
      date: DateTime(2026, 4, 5).toIso8601String(),
    );

/// 结果卡片的 key 绑定了消息 ID（ai_workflow_result_smart_result_<id>），
/// 用前缀匹配定位，避免测试依赖具体消息 ID。
Finder _smartResultCardKey() => find.byWidgetPredicate(
      (widget) =>
          widget.key is ValueKey<String> &&
          (widget.key! as ValueKey<String>)
              .value
              .startsWith('ai_workflow_result_smart_result'),
    );

/// 提案卡片同理（ai_workflow_result_note_proposal_<id>）。
Finder _noteProposalCardKey() => find.byWidgetPredicate(
      (widget) =>
          widget.key is ValueKey<String> &&
          (widget.key! as ValueKey<String>)
              .value
              .startsWith('ai_workflow_result_note_proposal'),
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

  /// 落库消息（按会话），用于断言开场白确实写进了库。
  Map<String, List<app_chat.ChatMessage>> get storedMessages => _messages;
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
    this.proposalMetadata = const <String, Object?>{},
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

  /// 提案 artifact 的 metadata，用来构造带标签的提案。
  final Map<String, Object?> proposalMetadata;
  final String responseContent;
  final List<String> responseChunks;
  final Duration responseChunkDelay;
  final String? preToolText;
  final Duration toolProgressDelay;
  final Duration postToolDelay;
  final String toolName;
  final String toolResult;
  final Object? error;
  AgentNoteContext? lastNoteContext;
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
    AgentNoteContext? noteContext,
  }) async {
    runCount++;
    lastNoteContext = noteContext;
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

    // 真实协议：agent 通过 propose_note_edit 工具产出 NoteProposalArtifact，
    // 页面据 response.artifacts 渲染提案卡（死工具 propose_edit 已删除）。
    final toolExecutions = emitSmartResultCard
        ? <ToolExecution>[
            ToolExecution(
              call: ToolCall(
                id: 'tool-call-2',
                name: 'propose_note_edit',
                arguments: const <String, Object?>{'note_id': 'note-1'},
              ),
              result: ToolResult(
                toolCallId: 'tool-call-2',
                content: '提案已生成',
                artifact: NoteProposalArtifact(
                  action: NoteProposalAction.edit,
                  proposalTitle: '润色结果',
                  reason: '',
                  noteId: 'note-1',
                  resultKind: NoteDocumentKind.plain,
                  content: '这是可应用的新内容',
                  documentOps: null,
                  metadata: proposalMetadata,
                  changes: const <NoteProposalChange>[],
                ),
              ),
            ),
          ]
        : const <ToolExecution>[];
    final toolCalls =
        toolExecutions.map((execution) => execution.call).toList();

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
    return AgentResponse(
      content: responseContent,
      toolCalls: toolCalls,
      toolExecutions: toolExecutions,
    );
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
    AgentNoteContext? noteContext,
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

/// 只提供标签流的假数据库：提案卡要靠它把 tag_ids 还原成带图标的标签。
class _TagOnlyDatabaseService extends DatabaseService {
  _TagOnlyDatabaseService(this._tags) : super.forTesting();

  final List<NoteTag> _tags;

  @override
  Stream<List<NoteTag>> watchTags() => Stream<List<NoteTag>>.value(_tags);

  @override
  Future<List<NoteTag>> getTags() async => _tags;
}

Future<Widget> _buildHarness({
  required SettingsService settingsService,
  required ChatSessionService chatSessionService,
  _FakeAIService? aiService,
  AgentService? agentService,
  DatabaseService? databaseService,
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
      if (databaseService != null)
        ChangeNotifierProvider<DatabaseService>.value(value: databaseService),
    ],
    child: MaterialApp(
      locale: const Locale('zh'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: ThemeData(splashFactory: InkRipple.splashFactory),
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

/// 推完一轮 Agent。事件订阅的 cancel 要在真实事件循环里才会完成，光靠 pump
/// 推不动这一轮的收尾（最终回答、操作行都排在它后面）。
Future<void> _settleAgentTurn(WidgetTester tester) async {
  for (var i = 0; i < 3; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump(const Duration(milliseconds: 100));
  }
}

AppLocalizations _l10n(WidgetTester tester) {
  return AppLocalizations.of(tester.element(find.byType(ThoughterPage)));
}

void main() {
  group('ThoughterPage', () {
    late SettingsService settingsService;
    late _InMemoryChatSessionService chatSessionService;

    setUp(() async {
      await TestHarness.initialize();
      settingsService = await SettingsService.create();
      await settingsService.setDontShowAgentExperimentalNotice(true);
      chatSessionService = _InMemoryChatSessionService();
      // 等待 AI 响应时列表末尾有一枚一直闪的光标，pumpAndSettle 永远等不到
      // 静止。打开"减弱动态效果"把它定住——真机上这项设置本来也该定住它。
      TestWidgetsFlutterBinding
              .instance.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
    });

    tearDown(() async {
      TestWidgetsFlutterBinding.instance.platformDispatcher
          .clearAccessibilityFeaturesTestValue();
      await TestHarness.tearDown();
    });

    testWidgets('explore entry defaults to agent without mode toggle',
        (tester) async {
      await tester.pumpWidget(
        await _buildHarness(
          settingsService: settingsService,
          chatSessionService: chatSessionService,
          child: const ThoughterPage(
            key: ValueKey('explore_default_page'),
            entrySource: ThoughterEntrySource.explore,
          ),
        ),
      );
      await tester.pumpAndSettle();

      final l10n = _l10n(tester);
      expect(find.text(l10n.aiModeChat), findsNothing);
      expect(find.text(l10n.aiModeAgent), findsNothing);
      expect(find.widgetWithText(ActionChip, '/润色'), findsNothing);
    });

    // 每日提示 / 周期洞察这类「手上已有正文」的入口，用 openingMessage 开场：
    // 既是对话第一句，也必须进模型上下文——exploreGuideSummary 是
    // includedInContext: false，只显示不入参，模型收不到。
    testWidgets('openingMessage opens the chat and enters model context',
        (tester) async {
      const opening = '午后多云，适合把最近的焦虑写下来。';
      await tester.pumpWidget(
        await _buildHarness(
          settingsService: settingsService,
          chatSessionService: chatSessionService,
          child: const ThoughterPage(
            key: ValueKey('opening_message_page'),
            entrySource: ThoughterEntrySource.explore,
            openingMessage: opening,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 第一句就是传进来的正文
      expect(find.text(opening), findsOneWidget);

      final state = tester.state(find.byType(ThoughterPage));
      final messages =
          (state as dynamic).debugMessagesForTest as List<app_chat.ChatMessage>;
      expect(messages, isNotEmpty);
      final first = messages.first;
      expect(first.content, opening);
      expect(first.isUser, isFalse);
      // 关键断言：必须进上下文，否则模型不知道开场说了什么
      expect(first.includedInContext, isTrue);
    });

    // 会话是延迟创建的（首条用户消息才建），开场白比会话早出生。
    // 它必须被补写进库，否则用户杀掉重进这个会话，第一句连同上下文一起消失。
    testWidgets('openingMessage is persisted once the session gets created',
        (tester) async {
      const opening = '午后多云，适合把最近的焦虑写下来。';
      await tester.pumpWidget(
        await _buildHarness(
          settingsService: settingsService,
          chatSessionService: chatSessionService,
          child: const ThoughterPage(
            key: ValueKey('opening_message_persist_page'),
            entrySource: ThoughterEntrySource.explore,
            openingMessage: opening,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 还没说话：不该凭空建出一个空会话来占「最近对话」的位置
      expect(chatSessionService.storedMessages, isEmpty);

      await _submitInput(tester, '那我从哪儿写起？');

      expect(chatSessionService.storedMessages, hasLength(1));
      final persisted = chatSessionService.storedMessages.values.single;
      expect(persisted.first.content, opening);
      expect(persisted.first.includedInContext, isTrue);
      // 顺序不能倒：开场白必须排在用户第一句之前
      expect(persisted[1].content, '那我从哪儿写起？');
      expect(persisted[1].isUser, isTrue);
    });

    testWidgets('does not offer attachments that Agent cannot consume',
        (tester) async {
      await tester.pumpWidget(
        await _buildHarness(
          settingsService: settingsService,
          chatSessionService: chatSessionService,
          child: const ThoughterPage(
            entrySource: ThoughterEntrySource.explore,
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
        ThoughterPageMode.agent,
      );

      await tester.pumpWidget(
        await _buildHarness(
          settingsService: settingsService,
          chatSessionService: chatSessionService,
          child: const ThoughterPage(
            entrySource: ThoughterEntrySource.explore,
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
          child: ThoughterPage(
            key: const ValueKey('note_default_page'),
            entrySource: ThoughterEntrySource.note,
            quote: _buildQuote(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final l10n = _l10n(tester);
      expect(find.text(l10n.aiModeChat), findsNothing);
      expect(find.text(l10n.aiModeAgent), findsNothing);
      // 笔记上下文横幅已移除，标题也不再按入口分叉显示「问笔记」；
      // 笔记身份是否真的送到 Agent 由下一条测试覆盖
      expect(
        find.descendant(
          of: find.byType(AppBar),
          matching: find.text(l10n.aiAssistantLabel),
        ),
        findsOneWidget,
      );
    });

    // 笔记入口默认接着上次聊。这条不变量曾经悄悄失效：恢复分支上带着
    // !_isAgentMode，而入口配置只允许 agent 一种模式，条件恒为假，
    // 每次点「问 Thoughter」都从白纸开始。
    testWidgets('note entry resumes the latest session for that note',
        (tester) async {
      final now = DateTime(2026, 7, 30, 9);
      chatSessionService.seedSession(
        ChatSession(
          id: 'note-session-1',
          sessionType: 'agent',
          noteId: 'note-1',
          title: '上次聊过的',
          createdAt: now,
          lastActiveAt: now,
        ),
        <app_chat.ChatMessage>[
          app_chat.ChatMessage(
            id: 'm1',
            content: '上次我们聊到哪儿了',
            isUser: true,
            role: 'user',
            timestamp: now,
          ),
          app_chat.ChatMessage(
            id: 'm2',
            content: '聊到你想把这条笔记拆成两段',
            isUser: false,
            role: 'assistant',
            timestamp: now,
          ),
        ],
      );

      await tester.pumpWidget(
        await _buildHarness(
          settingsService: settingsService,
          chatSessionService: chatSessionService,
          child: ThoughterPage(
            key: const ValueKey('note_resume_page'),
            entrySource: ThoughterEntrySource.note,
            quote: _buildQuote(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('聊到你想把这条笔记拆成两段'), findsOneWidget);
    });

    testWidgets('note entry sends structured note identity to Agent',
        (tester) async {
      final agentService = _FakeAgentService(
        settingsService: settingsService,
      );
      await settingsService.setNoteAiAssistantMode(ThoughterPageMode.agent);
      await tester.pumpWidget(
        await _buildHarness(
          settingsService: settingsService,
          chatSessionService: chatSessionService,
          agentService: agentService,
          child: ThoughterPage(
            entrySource: ThoughterEntrySource.note,
            quote: _buildQuote(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await _submitInput(tester, '帮我找出表达不清楚的地方');

      expect(agentService.runCount, 1);
      expect(agentService.lastNoteContext?.noteId, 'note-1');
      expect(agentService.lastNoteContext?.content, '今天的笔记内容');
      expect(
          agentService.lastNoteContext?.documentKind, NoteDocumentKind.plain);
      expect(agentService.lastNoteContext?.documentRevision, isNotEmpty);
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
          child: const ThoughterPage(
            entrySource: ThoughterEntrySource.explore,
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
        ThoughterPageMode.agent,
      );
      await settingsService.setNoteAiAssistantMode(
        ThoughterPageMode.noteChat,
      );

      await tester.pumpWidget(
        await _buildHarness(
          settingsService: settingsService,
          chatSessionService: chatSessionService,
          child: const ThoughterPage(
            key: ValueKey('explore_memory_page'),
            entrySource: ThoughterEntrySource.explore,
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
          child: ThoughterPage(
            key: const ValueKey('note_memory_page'),
            entrySource: ThoughterEntrySource.note,
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
          child: ThoughterPage(
            entrySource: ThoughterEntrySource.explore,
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

    testWidgets('keyboard animation keeps the last message above the keyboard',
        (tester) async {
      final now = DateTime.now();
      final session = ChatSession(
        id: 'keyboard-session',
        sessionType: 'general',
        title: '键盘遮挡测试',
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
      addTearDown(tester.view.resetViewInsets);
      await tester.pumpWidget(
        await _buildHarness(
          settingsService: settingsService,
          chatSessionService: chatSessionService,
          child: ThoughterPage(
            entrySource: ThoughterEntrySource.explore,
            session: session,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byType(TextField).last);
      await tester.pump();

      final listController =
          tester.widget<ListView>(find.byType(ListView)).controller!;
      // 键盘是逐帧上推的：每一帧长高后都应重新贴底，否则最后一条被吃掉
      for (final inset in <double>[120, 240, 360]) {
        tester.view.viewInsets = FakeViewPadding(
          bottom: inset * tester.view.devicePixelRatio,
        );
        await tester.pump();
        await tester.pump();
        expect(
          listController.position.pixels,
          moreOrLessEquals(listController.position.maxScrollExtent, epsilon: 1),
          reason: '键盘高度 $inset 时列表没有贴底',
        );
      }
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
      await settingsService.setExploreAiAssistantMode(ThoughterPageMode.agent);
      await tester.pumpWidget(
        await _buildHarness(
          settingsService: settingsService,
          chatSessionService: chatSessionService,
          agentService: agentService,
          child: const ThoughterPage(
            entrySource: ThoughterEntrySource.explore,
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

    testWidgets(
        'agent tool progress remains briefly after completion without placeholder',
        (tester) async {
      final agentService = _FakeAgentService(
        settingsService: settingsService,
        simulateToolProgress: true,
      );
      await settingsService.setExploreAiAssistantMode(ThoughterPageMode.agent);

      await tester.pumpWidget(
        await _buildHarness(
          settingsService: settingsService,
          chatSessionService: chatSessionService,
          agentService: agentService,
          child: const ThoughterPage(
            entrySource: ThoughterEntrySource.explore,
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
      await settingsService.setExploreAiAssistantMode(ThoughterPageMode.agent);

      await tester.pumpWidget(
        await _buildHarness(
          settingsService: settingsService,
          chatSessionService: chatSessionService,
          agentService: agentService,
          child: const ThoughterPage(
            entrySource: ThoughterEntrySource.explore,
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
      await settingsService.setExploreAiAssistantMode(ThoughterPageMode.agent);

      await tester.pumpWidget(
        await _buildHarness(
          settingsService: settingsService,
          chatSessionService: chatSessionService,
          agentService: agentService,
          child: const ThoughterPage(
            entrySource: ThoughterEntrySource.explore,
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
      await settingsService.setExploreAiAssistantMode(ThoughterPageMode.agent);

      await tester.pumpWidget(
        await _buildHarness(
          settingsService: settingsService,
          chatSessionService: chatSessionService,
          agentService: agentService,
          child: const ThoughterPage(
            entrySource: ThoughterEntrySource.explore,
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

    // AI 先说一句、再调工具、最后给结论，是一轮不是两轮。每段正文各挂一行
    // 复制/重试会把一轮从中间切开。
    testWidgets('one agent turn shows a single action row', (tester) async {
      final agentService = _FakeAgentService(
        settingsService: settingsService,
        simulateToolProgress: true,
        preToolText: '让我先看看最近的记录。',
        responseContent: '你最近写的多是深夜的自省。',
        toolProgressDelay: const Duration(milliseconds: 40),
      );
      await settingsService.setExploreAiAssistantMode(ThoughterPageMode.agent);

      await tester.pumpWidget(
        await _buildHarness(
          settingsService: settingsService,
          chatSessionService: chatSessionService,
          agentService: agentService,
          child: const ThoughterPage(
            entrySource: ThoughterEntrySource.explore,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await _submitInput(tester, '帮我看看我最近都写了什么内容');
      await _settleAgentTurn(tester);

      // 两段正文都在
      expect(find.textContaining('让我先看看最近的记录。'), findsOneWidget);
      expect(find.textContaining('你最近写的多是深夜的自省。'), findsOneWidget);
      // 但操作行只有一行，且挂在收尾那条后面
      expect(find.byIcon(Icons.content_copy_outlined), findsOneWidget);
      expect(find.byIcon(Icons.refresh), findsOneWidget);
    });

    // 开场白是调用方塞进来的引子，不是模型对着用户说的一轮回答：
    // 重试无从谈起（它前面没有提问），也不该长得和 AI 回复一样。
    testWidgets('opening message carries no copy or regenerate actions',
        (tester) async {
      await tester.pumpWidget(
        await _buildHarness(
          settingsService: settingsService,
          chatSessionService: chatSessionService,
          child: const ThoughterPage(
            entrySource: ThoughterEntrySource.explore,
            openingMessage: '午后多云，适合把最近的焦虑写下来。',
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('午后多云'), findsOneWidget);
      expect(find.byIcon(Icons.content_copy_outlined), findsNothing);
      expect(find.byIcon(Icons.refresh), findsNothing);
    });

    // 流式消息要收到第一个 token 才建出来。在那之前（发出提问、工具在跑）
    // 对话流末尾必须有光标顶着，否则看起来像没反应。
    testWidgets('waiting for the first token shows a cursor', (tester) async {
      final agentService = _FakeAgentService(
        settingsService: settingsService,
        simulateToolProgress: true,
        toolProgressDelay: const Duration(milliseconds: 400),
      );
      await settingsService.setExploreAiAssistantMode(ThoughterPageMode.agent);

      await tester.pumpWidget(
        await _buildHarness(
          settingsService: settingsService,
          chatSessionService: chatSessionService,
          agentService: agentService,
          child: const ThoughterPage(
            entrySource: ThoughterEntrySource.explore,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await _submitInput(tester, '帮我看看我最近都写了什么内容');
      await tester.pump(const Duration(milliseconds: 40));

      // 工具还在跑，一个 token 都没到：末尾得有光标顶着
      expect(
        find.byKey(const ValueKey('ai_assistant_waiting')),
        findsOneWidget,
      );

      await _settleAgentTurn(tester);
      // 回答落定后不该还留着光标
      expect(find.byKey(const ValueKey('ai_assistant_waiting')), findsNothing);
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
      await settingsService.setExploreAiAssistantMode(ThoughterPageMode.agent);

      await tester.pumpWidget(
        await _buildHarness(
          settingsService: settingsService,
          chatSessionService: chatSessionService,
          agentService: agentService,
          child: const ThoughterPage(
            entrySource: ThoughterEntrySource.explore,
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

    // 从历史恢复的消息本来就是完成态，不必把一整轮 agent 跑到底。
    void seedAnsweredSession(_InMemoryChatSessionService service) {
      final now = DateTime(2026, 8, 1, 10);
      service.seedSession(
        ChatSession(
          id: 'note-session-actions',
          sessionType: 'agent',
          noteId: 'note-1',
          title: '聊过的',
          createdAt: now,
          lastActiveAt: now,
        ),
        <app_chat.ChatMessage>[
          app_chat.ChatMessage(
            id: 'm-user',
            content: '帮我做一次分析',
            isUser: true,
            role: 'user',
            timestamp: now,
          ),
          app_chat.ChatMessage(
            id: 'm-tools',
            content: '',
            isUser: false,
            role: 'assistant',
            timestamp: now,
            metaJson: jsonEncode(<String, Object?>{
              'type': 'tool_progress',
              'inProgress': false,
              'items': <Map<String, Object?>>[
                <String, Object?>{
                  'toolCallId': 'tc-1',
                  'toolName': 'search_notes',
                  'status': 'completed',
                  'result': '找到 2 条笔记',
                },
              ],
            }),
          ),
          app_chat.ChatMessage(
            id: 'm-answer',
            content: '第一次回答',
            isUser: false,
            role: 'assistant',
            timestamp: now,
          ),
        ],
      );
    }

    testWidgets('completed reply offers copy, regenerate and process actions',
        (tester) async {
      seedAnsweredSession(chatSessionService);
      await settingsService.setNoteAiAssistantMode(ThoughterPageMode.agent);

      await tester.pumpWidget(
        await _buildHarness(
          settingsService: settingsService,
          chatSessionService: chatSessionService,
          agentService: _FakeAgentService(settingsService: settingsService),
          child: ThoughterPage(
            entrySource: ThoughterEntrySource.note,
            quote: _buildQuote(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final l10n = _l10n(tester);
      expect(find.byTooltip(l10n.copy), findsOneWidget);
      expect(find.byTooltip(l10n.regenerate), findsOneWidget);

      // 「查看过程」走的是折叠行同一个抽屉
      final processAction = find.byTooltip(l10n.viewToolProcess);
      expect(processAction, findsOneWidget);
      await tester.tap(processAction);
      await tester.pumpAndSettle();
      expect(find.text('找到 2 条笔记'), findsOneWidget);
    });

    testWidgets('regenerating drops the old answer and re-asks the question',
        (tester) async {
      seedAnsweredSession(chatSessionService);
      await settingsService.setNoteAiAssistantMode(ThoughterPageMode.agent);
      final agentService = _FakeAgentService(
        settingsService: settingsService,
        responseChunks: const <String>['第二次回答'],
      );

      await tester.pumpWidget(
        await _buildHarness(
          settingsService: settingsService,
          chatSessionService: chatSessionService,
          agentService: agentService,
          child: ThoughterPage(
            entrySource: ThoughterEntrySource.note,
            quote: _buildQuote(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(agentService.runCount, 0);
      expect(find.textContaining('第一次回答'), findsOneWidget);

      final l10n = _l10n(tester);
      await tester.tap(find.byTooltip(l10n.regenerate));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      // 用户那条提问必须留着——removeRange 差一位就会把问题一起删掉
      expect(agentService.runCount, 1);
      expect(find.text('帮我做一次分析'), findsOneWidget);
      // 旧回答和它那一轮的工具进度一起被清掉，换成新生成的
      expect(find.textContaining('第一次回答'), findsNothing);
      expect(find.textContaining('第二次回答'), findsOneWidget);
      await tester.pump(const Duration(seconds: 1));
    });

    testWidgets('agent stop button interrupts pending tool run',
        (tester) async {
      final agentService = _FakeAgentService(
        settingsService: settingsService,
        simulateToolProgress: true,
        toolProgressDelay: const Duration(milliseconds: 300),
        responseContent: '这段回复不应该出现',
      );
      await settingsService.setExploreAiAssistantMode(ThoughterPageMode.agent);

      await tester.pumpWidget(
        await _buildHarness(
          settingsService: settingsService,
          chatSessionService: chatSessionService,
          agentService: agentService,
          child: const ThoughterPage(
            entrySource: ThoughterEntrySource.explore,
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
      await tester.tap(find.byIcon(Icons.stop_rounded).last);
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
        ThoughterPageMode.agent,
      );

      await tester.pumpWidget(
        await _buildHarness(
          settingsService: settingsService,
          chatSessionService: chatSessionService,
          agentService: agentService,
          child: const ThoughterPage(
            entrySource: ThoughterEntrySource.explore,
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
      await tester.tap(find.byIcon(Icons.stop_rounded).last);
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
      expect(find.byIcon(Icons.stop_rounded), findsAtLeastNWidgets(1));
    });

    testWidgets('disposing an Agent page stops its pending run',
        (tester) async {
      final agentService = _FakeAgentService(
        settingsService: settingsService,
        simulateToolProgress: true,
        toolProgressDelay: const Duration(milliseconds: 300),
      );
      await settingsService.setExploreAiAssistantMode(
        ThoughterPageMode.agent,
      );

      await tester.pumpWidget(
        await _buildHarness(
          settingsService: settingsService,
          chatSessionService: chatSessionService,
          agentService: agentService,
          child: const ThoughterPage(
            entrySource: ThoughterEntrySource.explore,
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
        ThoughterPageMode.agent,
      );

      await tester.pumpWidget(
        await _buildHarness(
          settingsService: settingsService,
          chatSessionService: chatSessionService,
          agentService: agentService,
          child: const ThoughterPage(
            entrySource: ThoughterEntrySource.explore,
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
        ThoughterPageMode.agent,
      );

      await tester.pumpWidget(
        await _buildHarness(
          settingsService: settingsService,
          chatSessionService: chatSessionService,
          agentService: agentService,
          child: const ThoughterPage(
            entrySource: ThoughterEntrySource.explore,
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
        ThoughterPageMode.agent,
      );

      await tester.pumpWidget(
        await _buildHarness(
          settingsService: settingsService,
          chatSessionService: chatSessionService,
          agentService: agentService,
          child: const ThoughterPage(
            entrySource: ThoughterEntrySource.explore,
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
      await settingsService.setNoteAiAssistantMode(ThoughterPageMode.agent);

      await tester.pumpWidget(
        await _buildHarness(
          settingsService: settingsService,
          chatSessionService: chatSessionService,
          agentService: agentService,
          child: ThoughterPage(
            entrySource: ThoughterEntrySource.note,
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
        _noteProposalCardKey(),
        findsOneWidget,
      );
    });

    testWidgets('proposal card tags carry the icon from the tag table',
        (tester) async {
      // artifact 里只有 id 和一个过时的名字，图标和最新名字都得从标签表来。
      final agentService = _FakeAgentService(
        settingsService: settingsService,
        responseContent: '这是提案说明。',
        emitSmartResultCard: true,
        proposalMetadata: const <String, Object?>{
          'tag_ids': <String>['tag-1'],
          'tag_names': <String>['旧名字'],
        },
      );
      await settingsService.setNoteAiAssistantMode(ThoughterPageMode.agent);

      await tester.pumpWidget(
        await _buildHarness(
          settingsService: settingsService,
          chatSessionService: chatSessionService,
          agentService: agentService,
          databaseService: _TagOnlyDatabaseService([
            NoteTag(id: 'tag-1', name: '读书', iconName: '📚'),
          ]),
          child: ThoughterPage(
            entrySource: ThoughterEntrySource.note,
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

      expect(_noteProposalCardKey(), findsOneWidget);
      expect(find.text('📚'), findsOneWidget);
      expect(find.text('读书'), findsOneWidget);
      expect(find.text('旧名字'), findsNothing);
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
      await settingsService.setNoteAiAssistantMode(ThoughterPageMode.agent);

      await tester.pumpWidget(
        await _buildHarness(
          settingsService: settingsService,
          chatSessionService: chatSessionService,
          agentService: agentService,
          child: ThoughterPage(
            entrySource: ThoughterEntrySource.note,
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
        _smartResultCardKey(),
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
      await settingsService.setNoteAiAssistantMode(ThoughterPageMode.agent);

      await tester.pumpWidget(
        await _buildHarness(
          settingsService: settingsService,
          chatSessionService: chatSessionService,
          agentService: agentService,
          child: ThoughterPage(
            entrySource: ThoughterEntrySource.note,
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
        _noteProposalCardKey(),
        findsOneWidget,
      );
      expect(
        controller.position.pixels,
        moreOrLessEquals(controller.position.maxScrollExtent, epsilon: 1),
      );
    });

    testWidgets(
        'auto shows experimental notice dialog when enabled and allows closing with dontShowAgain',
        (WidgetTester tester) async {
      await settingsService.setDontShowAgentExperimentalNotice(false);
      final agentService = _FakeAgentService(settingsService: settingsService);

      final harness = await _buildHarness(
        settingsService: settingsService,
        chatSessionService: chatSessionService,
        agentService: agentService,
        child: const ThoughterPage(
          entrySource: ThoughterEntrySource.explore,
        ),
      );

      await tester.pumpWidget(harness);
      await tester.pumpAndSettle();

      // Dialog is auto-shown
      expect(find.byType(Dialog), findsOneWidget);
      expect(find.text('Thoughter 实验性功能说明'), findsOneWidget);

      // Check "不再自动提示"
      final checkbox = find.byType(Checkbox);
      expect(checkbox, findsOneWidget);
      await tester.tap(checkbox);
      await tester.pumpAndSettle();

      // Tap close button (Icons.close inside Dialog header)
      final closeButton = find.descendant(
        of: find.byType(Dialog),
        matching: find.byIcon(Icons.close),
      );
      expect(closeButton, findsOneWidget);
      await tester.tap(closeButton);
      await tester.pumpAndSettle();

      expect(find.byType(Dialog), findsNothing);
      expect(settingsService.dontShowAgentExperimentalNotice, isTrue);
    });

    testWidgets(
        'shows notice dialog when tapping ExperimentalBadge tag in app bar',
        (WidgetTester tester) async {
      await settingsService.setDontShowAgentExperimentalNotice(true);
      final agentService = _FakeAgentService(settingsService: settingsService);

      final harness = await _buildHarness(
        settingsService: settingsService,
        chatSessionService: chatSessionService,
        agentService: agentService,
        child: const ThoughterPage(
          entrySource: ThoughterEntrySource.explore,
        ),
      );

      await tester.pumpWidget(harness);
      await tester.pumpAndSettle();

      // Initially no dialog because dontShow is true
      expect(find.byType(Dialog), findsNothing);

      // Tap on ExperimentalBadge tag in AppBar
      final badgeFinder = find.byType(ExperimentalBadge);
      expect(badgeFinder, findsOneWidget);
      await tester.tap(badgeFinder);
      await tester.pumpAndSettle();

      // Dialog pops up
      expect(find.byType(Dialog), findsOneWidget);
      expect(find.text('Thoughter 实验性功能说明'), findsOneWidget);
    });
  });
}
