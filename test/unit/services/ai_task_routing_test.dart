import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openai_dart/openai_dart.dart' as openai;
import 'package:thoughtecho/gen_l10n/app_localizations.dart';
import 'package:thoughtecho/models/ai_model_metadata.dart';
import 'package:thoughtecho/models/ai_provider_settings.dart';
import 'package:thoughtecho/models/ai_task.dart';
import 'package:thoughtecho/models/multi_ai_settings.dart';
import 'package:thoughtecho/models/quote_model.dart';
import 'package:thoughtecho/services/ai_analysis_database_service.dart';
import 'package:thoughtecho/services/ai_service.dart';
import 'package:thoughtecho/services/api_key_manager.dart';
import 'package:thoughtecho/services/database_service.dart';
import 'package:thoughtecho/services/dreaming_service.dart';
import 'package:thoughtecho/services/insight_history_service.dart';
import 'package:thoughtecho/services/openai_stream_service.dart';

import 'agent_tools/memory_tool_harness.dart';

class _InMemoryApiKeyManager extends Fake implements APIKeyManager {
  _InMemoryApiKeyManager(this._keys);

  final Map<String, String> _keys;

  @override
  Future<String> getProviderApiKey(String providerId) async =>
      _keys[providerId] ?? '';

  @override
  Future<bool> hasValidProviderApiKey(String providerId) async {
    final key = _keys[providerId] ?? '';
    return key.trim().length >= 8;
  }

  @override
  bool isValidApiKeyFormat(String apiKey) => apiKey.trim().length >= 8;
}

class _CapturedOpenAICall {
  const _CapturedOpenAICall({
    required this.method,
    required this.provider,
    this.maxTokens,
    this.enableThinking,
  });

  final String method;
  final AIProviderSettings provider;
  final int? maxTokens;
  final bool? enableThinking;
}

class _CapturingOpenAIStreamService extends OpenAIStreamService {
  final List<_CapturedOpenAICall> calls = <_CapturedOpenAICall>[];
  String streamReply = '流式测试正文';
  String completionReply =
      '{"taste":"偏爱凝练随笔","voice":"短句留白","recent":"近期关注路由架构"}';

  @override
  Stream<String> streamChat({
    required AIProviderSettings provider,
    required List<openai.ChatMessage> messages,
    double? temperature,
    int? maxTokens,
  }) {
    calls.add(
      _CapturedOpenAICall(
        method: 'streamChat',
        provider: provider,
        maxTokens: maxTokens,
      ),
    );
    return Stream<String>.value(streamReply);
  }

  @override
  Stream<String> streamChatWithThinking({
    required AIProviderSettings provider,
    required List<openai.ChatMessage> messages,
    double? temperature,
    int? maxTokens,
    bool? enableThinking,
    void Function(String thinkingContent)? onThinking,
  }) {
    calls.add(
      _CapturedOpenAICall(
        method: 'streamChatWithThinking',
        provider: provider,
        maxTokens: maxTokens,
        enableThinking: enableThinking,
      ),
    );
    return Stream<String>.value(streamReply);
  }

  @override
  Future<String> chatCompletion({
    required AIProviderSettings provider,
    required List<openai.ChatMessage> messages,
    double? temperature,
    int? maxTokens,
    bool? enableThinking,
    Duration? timeout,
  }) async {
    calls.add(
      _CapturedOpenAICall(
        method: 'chatCompletion',
        provider: provider,
        maxTokens: maxTokens,
        enableThinking: enableThinking,
      ),
    );
    return completionReply;
  }
}

class _FakeDatabaseService extends DatabaseService {
  _FakeDatabaseService(this._quotes) : super.forTesting();

  final List<Quote> _quotes;

  @override
  Future<List<Quote>> getUserQuotes({
    List<String>? tagIds,
    String? categoryId,
    int offset = 0,
    int limit = 10,
    String orderBy = 'date DESC',
    String? searchQuery,
    List<String>? selectedWeathers,
    List<String>? selectedDayPeriods,
    bool excludeHiddenNotes = true,
    String? dateStart,
    String? dateEnd,
    bool includeDeleted = false,
  }) async =>
      _quotes.take(limit).toList(growable: false);
}

class _InMemoryAnalysisDb extends Fake implements AIAnalysisDatabaseService {
  final List<PeriodicInsight> saved = <PeriodicInsight>[];

  @override
  Future<List<PeriodicInsight>> getPeriodicInsights({int limit = 50}) async =>
      List<PeriodicInsight>.from(saved.take(limit));

  @override
  Future<void> savePeriodicInsight(
    PeriodicInsight insight, {
    int maxRetention = 50,
  }) async {
    saved.removeWhere((e) =>
        insight.dataSignature != null &&
        e.dataSignature == insight.dataSignature);
    saved.insert(0, insight);
  }
}

List<Quote> _sampleQuotes({int count = 12}) {
  return List<Quote>.generate(count, (i) {
    return Quote(
      id: 'q-$i',
      content: '第 $i 条用于测试任务路由的日常随笔片段',
      date: DateTime(2026, 8, 10).toIso8601String(),
      sourceAuthor: i.isEven ? '鲁迅' : null,
    );
  });
}

void main() {
  MemoryToolHarness.initializeBinding();

  group('AIService & DreamingService stateless per-task routing', () {
    final harness = MemoryToolHarness();
    late AppLocalizations l10n;

    const defaultProvider = AIProviderSettings(
      id: 'p_default',
      name: 'Default GPT',
      apiUrl: 'https://api.openai.com/v1',
      model: 'gpt-4o-mini',
      providerSlug: 'openai',
    );
    const dailyFastProvider = AIProviderSettings(
      id: 'p_daily',
      name: 'Daily Flash',
      apiUrl: 'https://open.bigmodel.cn/api/paas/v4',
      model: 'glm-4-flash',
      providerSlug: 'zhipuai',
    );
    const periodicBalancedProvider = AIProviderSettings(
      id: 'p_periodic',
      name: 'Periodic Balanced',
      apiUrl: 'https://dashscope.aliyuncs.com/compatible-mode/v1',
      model: 'qwen-plus',
      providerSlug: 'alibaba-cn',
    );
    const dreamingReasonerProvider = AIProviderSettings(
      id: 'p_dreaming',
      name: 'Dreaming Reasoner',
      apiUrl: 'https://api.deepseek.com/v1',
      model: 'deepseek-reasoner',
      providerSlug: 'deepseek',
      modelMetadata: AIModelMetadata(reasoning: true),
    );
    const agentProProvider = AIProviderSettings(
      id: 'p_agent',
      name: 'Agent Sonnet',
      apiUrl: 'https://openrouter.ai/api/v1',
      model: 'anthropic/claude-sonnet-4-5',
      providerSlug: 'openrouter',
    );

    setUpAll(() async {
      await harness.setUpAll();
      l10n = await AppLocalizations.delegate.load(const Locale('zh'));
    });

    setUp(harness.setUp);
    tearDown(harness.tearDown);
    tearDownAll(harness.tearDownAll);

    test(
        'routes dailyInsight, periodicInsight, dreaming, and agent independently without mutating currentProviderId',
        () async {
      await harness.settingsService.saveMultiAISettings(
        MultiAISettings(
          providers: const [
            defaultProvider,
            dailyFastProvider,
            periodicBalancedProvider,
            dreamingReasonerProvider,
            agentProProvider,
          ],
          currentProviderId: 'p_default',
          taskProviderIds: const {
            AITask.dailyInsight: 'p_daily',
            AITask.periodicInsight: 'p_periodic',
            AITask.dreaming: 'p_dreaming',
            AITask.agent: 'p_agent',
          },
        ),
      );

      final keyManager = _InMemoryApiKeyManager({
        'p_default': 'sk-default-key-1234',
        'p_daily': 'sk-daily-key-1234',
        'p_periodic': 'sk-periodic-key-1234',
        'p_dreaming': 'sk-dreaming-key-1234',
        'p_agent': 'sk-agent-key-1234',
      });
      final streamService = _CapturingOpenAIStreamService();
      final aiService = AIService(
        settingsService: harness.settingsService,
        memoryService: harness.memory,
        apiKeyManager: keyManager,
        openAIStreamService: streamService,
      );

      await aiService.streamGenerateDailyPrompt(l10n).join();
      await aiService
          .streamReportInsight(
            periodLabel: '本周',
            activeDays: 3,
            noteCount: 3,
            totalWordCount: 120,
            fullNotesContent: '第 1 条随笔',
          )
          .join();
      await aiService.completeForBackgroundSummary(
        systemPrompt: 'sys',
        userMessage: 'usr',
      );
      await aiService.streamGeneralConversation('你好').join();

      expect(streamService.calls, hasLength(4));
      expect(streamService.calls[0].provider.id, 'p_daily');
      expect(streamService.calls[0].provider.apiKey, 'sk-daily-key-1234');
      expect(streamService.calls[1].provider.id, 'p_periodic');
      expect(streamService.calls[1].provider.apiKey, 'sk-periodic-key-1234');
      expect(streamService.calls[2].provider.id, 'p_dreaming');
      expect(streamService.calls[2].provider.apiKey, 'sk-dreaming-key-1234');
      expect(streamService.calls[3].provider.id, 'p_agent');
      expect(streamService.calls[3].provider.apiKey, 'sk-agent-key-1234');

      // Stateless guarantee: global default currentProviderId was never mutated.
      expect(harness.settingsService.multiAISettings.currentProviderId,
          'p_default');
    });

    test(
        'periodic insight persistence triggers Dreaming handoff using independent task providers without mutating currentProviderId',
        () async {
      await harness.settingsService.saveMultiAISettings(
        MultiAISettings(
          providers: const [
            defaultProvider,
            dailyFastProvider,
            dreamingReasonerProvider,
          ],
          currentProviderId: 'p_default',
          taskProviderIds: const {
            AITask.periodicInsight: 'p_daily',
            AITask.dreaming: 'p_dreaming',
          },
        ),
      );

      final keyManager = _InMemoryApiKeyManager({
        'p_default': 'sk-default-key-1234',
        'p_daily': 'sk-cheap-insight-key-1234',
        'p_dreaming': 'sk-strong-dream-key-1234',
      });
      final streamService = _CapturingOpenAIStreamService();
      final aiService = AIService(
        settingsService: harness.settingsService,
        memoryService: harness.memory,
        apiKeyManager: keyManager,
        openAIStreamService: streamService,
      );
      final dbService = _FakeDatabaseService(_sampleQuotes(count: 14));
      final dreamingService = DreamingService.fromServices(
        settingsService: harness.settingsService,
        memoryService: harness.memory,
        databaseService: dbService,
        aiService: aiService,
      );

      final analysisDb = _InMemoryAnalysisDb();
      final insightHistory = InsightHistoryService(
        settingsService: harness.settingsService,
        aiAnalysisDbService: analysisDb,
      );
      final dreamingDone = Completer<DreamingOutcome>();
      insightHistory.onAiInsightPersisted = () async {
        final outcome = await dreamingService.run();
        if (!dreamingDone.isCompleted) {
          dreamingDone.complete(outcome);
        }
      };

      // 1. Generate periodic insight -> uses cheap fast model (p_daily)
      final insightText = await aiService
          .streamReportInsight(
            periodLabel: '本周',
            activeDays: 4,
            noteCount: 4,
            totalWordCount: 180,
            fullNotesContent: '第 1 条随笔\n第 2 条随笔',
          )
          .join();
      expect(insightText, isNotEmpty);

      // 2. Persist periodic insight -> triggers background Dreaming -> uses p_dreaming
      await insightHistory.addInsight(
        insight: insightText,
        periodType: 'week',
        periodLabel: '本周',
        dataSignature: 'sig_week_1',
      );
      final outcome = await dreamingDone.future;
      expect(outcome, DreamingOutcome.updated);

      expect(streamService.calls, hasLength(2));
      expect(streamService.calls[0].provider.id, 'p_daily');
      expect(streamService.calls[1].provider.id, 'p_dreaming');
      expect(
        harness.settingsService.multiAISettings.currentProviderId,
        'p_default',
      );
    });

    test(
        'completeForBackgroundSummary relaxes maxTokens to >= 4096 for reasoning models while keeping enableThinking false',
        () async {
      final keyManager = _InMemoryApiKeyManager({
        'p_default': 'sk-default-key-1234',
        'p_dreaming': 'sk-dreaming-key-1234',
      });
      final streamService = _CapturingOpenAIStreamService();
      final aiService = AIService(
        settingsService: harness.settingsService,
        memoryService: harness.memory,
        apiKeyManager: keyManager,
        openAIStreamService: streamService,
      );

      // Case 1: Pure reasoning model assigned to dreaming -> 700 relaxed to 4096, enableThinking remains false
      await harness.settingsService.saveMultiAISettings(
        MultiAISettings(
          providers: const [defaultProvider, dreamingReasonerProvider],
          currentProviderId: 'p_default',
          taskProviderIds: const {AITask.dreaming: 'p_dreaming'},
        ),
      );

      await aiService.completeForBackgroundSummary(
        systemPrompt: 'sys',
        userMessage: 'usr',
      );
      expect(streamService.calls.last.provider.id, 'p_dreaming');
      expect(
        streamService.calls.last.maxTokens,
        AIService.dreamingReasoningMinMaxTokens,
      );
      expect(streamService.calls.last.maxTokens, greaterThanOrEqualTo(4096));
      expect(streamService.calls.last.enableThinking, isFalse);

      // Explicit larger maxTokens (e.g. 8192) is preserved as-is
      await aiService.completeForBackgroundSummary(
        systemPrompt: 'sys',
        userMessage: 'usr',
        maxTokens: 8192,
      );
      expect(streamService.calls.last.maxTokens, 8192);
      expect(streamService.calls.last.enableThinking, isFalse);

      // Case 2: Non-reasoning model (gpt-4o-mini) keeps compact 700 maxTokens
      await harness.settingsService.saveMultiAISettings(
        const MultiAISettings(
          providers: [defaultProvider],
          currentProviderId: 'p_default',
        ),
      );
      await aiService.completeForBackgroundSummary(
        systemPrompt: 'sys',
        userMessage: 'usr',
      );
      expect(streamService.calls.last.provider.id, 'p_default');
      expect(streamService.calls.last.maxTokens, 700);
      expect(streamService.calls.last.enableThinking, isFalse);
    });

    test(
        'generateSessionTitle routes via AITask.sessionTitle instead of leaking first message to default provider',
        () async {
      await harness.settingsService.saveMultiAISettings(
        const MultiAISettings(
          providers: [defaultProvider, dailyFastProvider, agentProProvider],
          currentProviderId: 'p_default',
          routingMode: AIRoutingMode.custom,
          taskProviderIds: {
            AITask.agent: 'p_agent',
            AITask.sessionTitle: 'p_daily',
          },
        ),
      );

      final keyManager = _InMemoryApiKeyManager({
        'p_default': 'sk-default-key-1234',
        'p_daily': 'sk-title-fast-key-1234',
        'p_agent': 'sk-agent-private-key-1234',
      });
      final streamService = _CapturingOpenAIStreamService()
        ..completionReply = '私密灵感对话标题';
      final aiService = AIService(
        settingsService: harness.settingsService,
        memoryService: harness.memory,
        apiKeyManager: keyManager,
        openAIStreamService: streamService,
      );

      final title = await aiService.generateSessionTitle(
        '这是一条用于测试会话标题专属模型路由的首条消息',
      );

      expect(title, '私密灵感对话标题');
      expect(streamService.calls, hasLength(1));
      expect(streamService.calls.single.method, 'chatCompletion');
      expect(streamService.calls.single.provider.id, 'p_daily');
      expect(
        streamService.calls.single.provider.apiKey,
        'sk-title-fast-key-1234',
      );
      expect(streamService.calls.single.enableThinking, isFalse);
      expect(
        harness.settingsService.multiAISettings.currentProviderId,
        'p_default',
      );

      // Even when p_default has no API key, generateSessionTitle still succeeds via AITask.sessionTitle.
      final titleOnlyKeyManager = _InMemoryApiKeyManager({
        'p_daily': 'sk-title-fast-key-1234',
      });
      final titleOnlyAiService = AIService(
        settingsService: harness.settingsService,
        memoryService: harness.memory,
        apiKeyManager: titleOnlyKeyManager,
        openAIStreamService: streamService,
      );
      streamService.calls.clear();
      final secondTitle = await titleOnlyAiService.generateSessionTitle(
        '默认服务无密钥时依然通过标题专属服务生成标题',
      );
      expect(secondTitle, '私密灵感对话标题');
      expect(streamService.calls, hasLength(1));
      expect(streamService.calls.single.provider.id, 'p_daily');
    });

    test(
        'tiered mode routes cardGeneration/periodicInsight to primary and dailyInsight/sessionTitle/dreaming to lightProvider',
        () async {
      await harness.settingsService.saveMultiAISettings(
        const MultiAISettings(
          providers: [agentProProvider, dailyFastProvider],
          currentProviderId: 'p_agent',
          routingMode: AIRoutingMode.tiered,
          lightProviderId: 'p_daily',
        ),
      );

      final keyManager = _InMemoryApiKeyManager({
        'p_agent': 'sk-primary-key-1234',
        'p_daily': 'sk-light-key-1234',
      });
      final streamService = _CapturingOpenAIStreamService()
        ..completionReply =
            '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 400 600"><text>卡片测试</text></svg>';
      final aiService = AIService(
        settingsService: harness.settingsService,
        memoryService: harness.memory,
        apiKeyManager: keyManager,
        openAIStreamService: streamService,
      );

      // Primary tier: cardGeneration + periodicInsight
      final svg = await aiService.generateSVG('测试生成分享卡片');
      expect(svg, contains('<svg'));
      await aiService
          .streamReportInsight(
            periodLabel: '本周',
            activeDays: 2,
            noteCount: 2,
            totalWordCount: 80,
            fullNotesContent: '随笔内容',
          )
          .join();

      // Light tier: dailyInsight + sessionTitle + dreaming
      await aiService.streamGenerateDailyPrompt(l10n).join();
      streamService.completionReply = '轻量标题';
      await aiService.generateSessionTitle('测试轻量模型标题生成');
      streamService.completionReply = '{"taste":"凝练"}';
      await aiService.completeForBackgroundSummary(
        systemPrompt: 'sys',
        userMessage: 'usr',
      );

      expect(streamService.calls.map((c) => c.provider.id).toList(), [
        'p_agent', // generateSVG (cardGeneration -> primary)
        'p_agent', // streamReportInsight (periodicInsight -> primary)
        'p_daily', // streamGenerateDailyPrompt (dailyInsight -> light)
        'p_daily', // generateSessionTitle (sessionTitle -> light)
        'p_daily', // completeForBackgroundSummary (dreaming -> light)
      ]);
    });

    test(
        'keyless local Ollama preset runs light-tier tasks without stored API key, and custom agent-only config keeps sessionTitle on agent provider',
        () async {
      const localOllama = AIProviderSettings(
        id: 'p_ollama_local',
        name: 'Ollama (Local)',
        apiUrl: 'http://localhost:11434/v1',
        model: 'qwen3:8b',
        providerSlug: 'ollama',
      );
      await harness.settingsService.saveMultiAISettings(
        const MultiAISettings(
          providers: [agentProProvider, localOllama],
          currentProviderId: 'p_agent',
          routingMode: AIRoutingMode.tiered,
          lightProviderId: 'p_ollama_local',
        ),
      );

      final keyManager = _InMemoryApiKeyManager({
        'p_agent': 'sk-primary-key-1234',
      });
      final streamService = _CapturingOpenAIStreamService()
        ..completionReply = '本地免密模型标题';
      final aiService = AIService(
        settingsService: harness.settingsService,
        memoryService: harness.memory,
        apiKeyManager: keyManager,
        openAIStreamService: streamService,
      );

      expect(
        await aiService.hasValidApiKeyAsync(task: AITask.sessionTitle),
        isTrue,
      );
      await aiService.streamGenerateDailyPrompt(l10n).join();
      final title = await aiService.generateSessionTitle('测试本地免密轻量模型标题');
      expect(title, '本地免密模型标题');
      streamService.completionReply = '{"taste":"简洁"}';
      await aiService.completeForBackgroundSummary(
        systemPrompt: 'sys',
        userMessage: 'usr',
      );

      expect(streamService.calls.map((c) => c.provider.id).toList(), [
        'p_ollama_local',
        'p_ollama_local',
        'p_ollama_local',
      ]);

      // Custom mode with dedicated agent provider and unset sessionTitle -> stays on agent provider
      streamService.calls.clear();
      streamService.completionReply = '私密专属标题';
      await harness.settingsService.saveMultiAISettings(
        const MultiAISettings(
          providers: [defaultProvider, localOllama],
          currentProviderId: 'p_default',
          routingMode: AIRoutingMode.custom,
          taskProviderIds: {AITask.agent: 'p_ollama_local'},
        ),
      );
      final privateTitle = await aiService.generateSessionTitle('私密对话首句内容');
      expect(privateTitle, '私密专属标题');
      expect(streamService.calls.single.provider.id, 'p_ollama_local');
    });
  });
}
