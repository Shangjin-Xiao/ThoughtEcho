import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:thoughtecho/gen_l10n/app_localizations.dart';
import 'package:thoughtecho/models/ai_assistant_entry.dart';
import 'package:thoughtecho/models/chat_message.dart' as app_chat;
import 'package:thoughtecho/models/quote_model.dart';
import 'package:thoughtecho/pages/ai_assistant_page.dart';
import 'package:thoughtecho/services/agent_service.dart';
import 'package:thoughtecho/services/agent_tool.dart';
import 'package:thoughtecho/services/ai_service.dart';
import 'package:thoughtecho/services/chat_session_service.dart';
import 'package:thoughtecho/services/settings_service.dart';
import 'package:provider/provider.dart';

import '../../test_setup.dart';

class _FakeDatabase implements Database {
  _FakeDatabase() {
    unblockWrites.complete();
  }

  final Completer<void> unblockWrites = Completer<void>();

  @override
  Future<int> insert(
    String table,
    Map<String, Object?> values, {
    String? nullColumnHack,
    ConflictAlgorithm? conflictAlgorithm,
  }) async {
    await unblockWrites.future;
    return 1;
  }

  @override
  Future<List<Map<String, Object?>>> query(
    String table, {
    bool? distinct,
    List<String>? columns,
    String? where,
    List<Object?>? whereArgs,
    String? groupBy,
    String? having,
    String? orderBy,
    int? limit,
    int? offset,
  }) async {
    return const <Map<String, Object?>>[];
  }

  @override
  Future<int> update(
    String table,
    Map<String, Object?> values, {
    String? where,
    List<Object?>? whereArgs,
    ConflictAlgorithm? conflictAlgorithm,
  }) async {
    await unblockWrites.future;
    return 1;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Quote _buildQuote() => Quote(
      id: 'note-1',
      content: '今天的笔记内容',
      date: DateTime(2026, 4, 5).toIso8601String(),
    );

class _FakeAIService extends AIService {
  _FakeAIService({required super.settingsService});

  @override
  Stream<String> streamPolishText(String content) => Stream.value('已润色内容');

  @override
  Stream<String> streamContinueText(String content) => Stream.value('续写内容');

  @override
  Stream<String> streamSummarizeNote(Quote quote, {List<String>? tagNames}) =>
      Stream.value('深度分析结果');

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
    List<app_chat.ChatMessage>? history,
  }) =>
      Stream.value('笔记问答结果');

  @override
  Stream<String> streamGeneralConversation(
    String question, {
    List<app_chat.ChatMessage>? history,
    String? systemContext,
  }) =>
      Stream.value('普通对话结果');
}

class _FakeAgentService extends AgentService {
  _FakeAgentService({required super.settingsService}) : super(tools: const []);

  @override
  Future<AgentResponse> runAgent({
    required String userMessage,
    List<app_chat.ChatMessage>? history,
    String? noteContext,
  }) async {
    return AgentResponse(content: 'Agent 响应');
  }
}

Future<Widget> _buildHarness({
  required SettingsService settingsService,
  required ChatSessionService chatSessionService,
  required Widget child,
}) async {
  final agentService = _FakeAgentService(settingsService: settingsService);
  final aiService = _FakeAIService(settingsService: settingsService);

  return MultiProvider(
    providers: [
      ChangeNotifierProvider<SettingsService>.value(value: settingsService),
      ChangeNotifierProvider<ChatSessionService>.value(
          value: chatSessionService),
      ChangeNotifierProvider<AgentService>.value(value: agentService),
      ChangeNotifierProvider<AIService>.value(value: aiService),
    ],
    child: MaterialApp(
      locale: const Locale('zh'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: child,
    ),
  );
}

void main() {
  group('AIAssistantPage', () {
    late SettingsService settingsService;
    late ChatSessionService chatSessionService;

    setUp(() async {
      await TestSetup.setupAll();
      settingsService = await SettingsService.create();
      chatSessionService = ChatSessionService()..setDatabase(_FakeDatabase());
    });

    tearDown(() async {
      await TestSetup.teardown();
    });

    testWidgets('explore entry defaults to chat mode with toggle', (
      tester,
    ) async {
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

      final chatChip = tester.widget<ChoiceChip>(
        find.byKey(const ValueKey('ai_mode_chat_button')),
      );
      final agentChip = tester.widget<ChoiceChip>(
        find.byKey(const ValueKey('ai_mode_agent_button')),
      );

      expect(chatChip.selected, isTrue);
      expect(agentChip.selected, isFalse);
      expect(find.text('输入 / 查看功能，或直接对话'), findsOneWidget);
    });

    testWidgets('note entry keeps note context and defaults to note chat', (
      tester,
    ) async {
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

      final chatChip = tester.widget<ChoiceChip>(
        find.byKey(const ValueKey('ai_mode_chat_button')),
      );
      final agentChip = tester.widget<ChoiceChip>(
        find.byKey(const ValueKey('ai_mode_agent_button')),
      );

      expect(chatChip.selected, isTrue);
      expect(agentChip.selected, isFalse);
      expect(find.textContaining('当前笔记上下文'), findsOneWidget);
    });

    testWidgets('remembered mode is isolated between explore and note entry', (
      tester,
    ) async {
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

      expect(
        tester
            .widget<ChoiceChip>(
              find.byKey(const ValueKey('ai_mode_agent_button')),
            )
            .selected,
        isTrue,
      );

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

      expect(
        tester
            .widget<ChoiceChip>(
              find.byKey(const ValueKey('ai_mode_chat_button')),
            )
            .selected,
        isTrue,
      );
      expect(
        tester
            .widget<ChoiceChip>(
              find.byKey(const ValueKey('ai_mode_agent_button')),
            )
            .selected,
        isFalse,
      );
    });

    testWidgets('explore entry shows all workflow command chips', (
      tester,
    ) async {
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

      expect(find.widgetWithText(ActionChip, '/润色'), findsOneWidget);
      expect(find.widgetWithText(ActionChip, '/续写'), findsOneWidget);
      expect(find.widgetWithText(ActionChip, '/深度分析'), findsOneWidget);
      expect(find.widgetWithText(ActionChip, '/分析来源'), findsOneWidget);
      expect(find.widgetWithText(ActionChip, '/智能洞察'), findsOneWidget);
    });

    testWidgets('note entry shows workflow chips and note context together', (
      tester,
    ) async {
      await tester.pumpWidget(
        await _buildHarness(
          settingsService: settingsService,
          chatSessionService: chatSessionService,
          child: AIAssistantPage(
            key: const ValueKey('note_polish_page'),
            entrySource: AIAssistantEntrySource.note,
            quote: _buildQuote(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('当前笔记上下文'), findsOneWidget);
      expect(find.widgetWithText(ActionChip, '/润色'), findsOneWidget);
      expect(find.widgetWithText(ActionChip, '/续写'), findsOneWidget);
    });
  });
}
