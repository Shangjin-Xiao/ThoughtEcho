import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:openai_dart/openai_dart.dart' as openai;
import 'package:thoughtecho/models/agent_memory.dart';
import 'package:thoughtecho/models/ai_provider_settings.dart';
import 'package:thoughtecho/models/chat_message.dart' as app_chat;
import 'package:thoughtecho/models/multi_ai_settings.dart';
import 'package:thoughtecho/services/agent_service.dart';
import 'package:thoughtecho/utils/agent_history_builder.dart';

import 'agent_tools/memory_tool_harness.dart';

app_chat.ChatMessage _buildOpeningMessage() => app_chat.ChatMessage(
      id: 'open-insight',
      role: 'assistant',
      isUser: false,
      content: '上周你在深夜记录了三次灵感，整体节奏正在放缓。',
      timestamp: DateTime(2026, 8, 10),
      metaJson: jsonEncode({
        'type': 'opening_context',
        'source': 'periodic_insight',
        'period': 'week',
        'periodLabel': '上周',
        'rangeStart': '2026-08-03',
        'rangeEnd': '2026-08-09',
      }),
    );

app_chat.ChatMessage _buildTurnMessage(String role, String content) =>
    app_chat.ChatMessage(
      id: '$role-$content',
      role: role,
      isUser: role == 'user',
      content: content,
      timestamp: DateTime(2026, 8, 10),
    );

List<app_chat.ChatMessage> buildAgentHistoryForOpeningTest(
  List<app_chat.ChatMessage> raw,
) =>
    AgentHistoryBuilder.build(raw);

openai.ChatCompletion _completion(String content) => openai.ChatCompletion(
      object: 'chat.completion',
      model: 'test-model',
      choices: [
        openai.ChatChoice(
          message: openai.AssistantMessage(content: content),
          finishReason: openai.FinishReason.stop,
        ),
      ],
    );

void main() {
  MemoryToolHarness.initializeBinding();
  final harness = MemoryToolHarness();
  setUpAll(harness.setUpAll);
  setUp(harness.setUp);
  tearDown(harness.tearDown);
  tearDownAll(harness.tearDownAll);

  const provider = AIProviderSettings(
    id: 'test-provider',
    name: 'Test provider',
    apiUrl: 'https://example.invalid/v1/chat/completions',
    model: 'test-model',
  );
  const directive = '回复保持简短';
  const extraction = '{"has_memory":true,"kind":"style",'
      '"directive":"$directive","confidence":0.95}';

  test('capture waiting for persistence cannot replace memory after disable',
      () async {
    final original = await harness.memory.rememberProfile(
      kind: AgentMemoryKind.style,
      directive: '使用完整段落',
    );
    final generation = harness.memory.captureGeneration;
    final policyBusy = Completer<void>();
    final releasePolicy = Completer<void>();
    final blocker = harness.settingsService.withAgentMemoryPolicy(() async {
      policyBusy.complete();
      await releasePolicy.future;
    });
    await policyBusy.future;

    final capture = harness.memory.rememberProfileFromCapture(
      generation: generation,
      kind: AgentMemoryKind.style,
      directive: directive,
      replacesId: original.id,
      source: 'post_turn_reflection',
    );
    final disable = harness.settingsService.setAgentMemoryEnabled(false);
    releasePolicy.complete();
    await blocker;

    expect(await capture, isFalse);
    await disable;
    expect(harness.memory.isEnabled, isFalse);
    final entries = await harness.memory.allProfileEntries();
    expect(entries, hasLength(1));
    expect(entries.single.id, original.id);
    expect(entries.single.status, AgentMemoryStatus.active);
  });

  for (final change in [
    'none',
    'disable then enable',
    'clear',
    'clear with queued turn'
  ]) {
    test('post-turn capture respects policy change: $change', () async {
      await harness.settingsService.updateMultiAISettings(
        MultiAISettings(
          providers: const [provider],
          currentProviderId: provider.id,
        ),
      );
      final extractionStarted = Completer<void>();
      final extractionResponse = Completer<openai.ChatCompletion>();
      final nextExtractionStarted = Completer<void>();
      var extractions = 0;
      String? nextDialogue;
      final agent = AgentService(
        settingsService: harness.settingsService,
        memoryService: harness.memory,
        tools: const [],
        apiKeyResolver: (_) async => 'synthetic-key',
        completionRequester: ({
          required provider,
          required messages,
          required tools,
          required temperature,
          required maxTokens,
        }) async {
          if (maxTokens != 300) return _completion('好的');
          if (++extractions == 1) {
            extractionStarted.complete();
            return extractionResponse.future;
          }
          // The capture queue starts this request only after the previous
          // extraction has finished its real database work.
          if (!nextExtractionStarted.isCompleted) {
            nextDialogue = messages.last.toString();
            nextExtractionStarted.complete();
          }
          return _completion('{"has_memory":false}');
        },
      );
      addTearDown(agent.dispose);

      await agent.runAgent(userMessage: '以后回复简短一点');
      await extractionStarted.future;
      if (change == 'clear with queued turn') {
        await agent.runAgent(userMessage: '以后叫我示例用户');
      }
      switch (change) {
        case 'disable then enable':
          await harness.settingsService.setAgentMemoryEnabled(false);
          await harness.settingsService.setAgentMemoryEnabled(true);
        case 'clear':
        case 'clear with queued turn':
          await harness.memory.clearAll();
      }
      extractionResponse.complete(_completion(extraction));
      await agent.runAgent(userMessage: '以后不要主动添加天气信息');
      await nextExtractionStarted.future.timeout(const Duration(seconds: 5));

      expect(nextDialogue, contains('以后不要主动添加天气信息'));
      final entries = await harness.memory.allProfileEntries();
      expect(entries.map((entry) => entry.directive),
          change == 'none' ? [directive] : isEmpty);
    });
  }

  test(
      'pins <opening_context> as structured user data right after <user_profile> across long history without touching systemPrompt, and reports fallback modelLabel',
      () async {
    const geminiProvider = AIProviderSettings(
      id: 'p_gemini',
      name: 'Gemini Service',
      apiUrl: 'https://generativelanguage.googleapis.com/v1beta/openai',
      model: 'gemini-2.5-pro',
      providerSlug: 'google',
    );

    await harness.settingsService.updateMultiAISettings(
      const MultiAISettings(
        providers: [geminiProvider],
        currentProviderId: 'p_gemini',
      ),
    );
    await harness.memory.rememberProfile(
      kind: AgentMemoryKind.style,
      directive: '偏爱温和简洁的表达',
    );

    List<openai.ChatMessage>? capturedMessages;
    final emittedModels = <String>[];
    final rawSessionMessages = [
      //模拟开场周期洞察引用块 + 超长多轮对话（超过历史窗口上限以验证钉住不被裁掉）
      ...(() {
        final list = [
          _buildOpeningMessage(),
        ];
        for (var i = 0; i < 30; i++) {
          list.add(_buildTurnMessage('user', '第 $i 轮提问'));
          list.add(_buildTurnMessage('assistant', '第 $i 轮回答'));
        }
        return list;
      })(),
    ];

    final agent = AgentService(
      settingsService: harness.settingsService,
      memoryService: harness.memory,
      tools: const [],
      apiKeyResolver: (_) async => 'synthetic-key-12345678',
      completionRequester: ({
        required provider,
        required messages,
        required tools,
        required temperature,
        required maxTokens,
      }) async {
        if (maxTokens != 300 && provider.model == 'gemini-2.5-pro') {
          throw Exception('429 quota exceeded');
        }
        if (maxTokens != 300) {
          capturedMessages = messages;
        }
        return _completion('根据上周 8 月 3 日至 8 月 9 日的洞察展开分析。');
      },
    );
    addTearDown(agent.dispose);
    final sub = agent.events.listen((event) {
      if (event is AgentModelSelectedEvent) {
        emittedModels.add(event.modelLabel);
      }
    });
    addTearDown(sub.cancel);

    final history = buildAgentHistoryForOpeningTest(rawSessionMessages);
    final response = await agent.runAgent(
      userMessage: '围绕这段再展开讲讲',
      history: history,
    );

    expect(response.modelLabel, isNot('Gemini Service · gemini-2.5-pro'));
    expect(response.modelLabel, startsWith('Gemini Service · gemini-'));
    expect(agent.lastUsedModelLabel, response.modelLabel);
    expect(emittedModels.first, 'Gemini Service · gemini-2.5-pro');
    expect(emittedModels.last, response.modelLabel);

    expect(capturedMessages, isNotNull);
    final sent = capturedMessages!;
    // [0] systemPrompt must NOT contain untrusted opening text
    expect(sent[0].toString(), isNot(contains('上周你在深夜记录了三次灵感')));
    // [1] <user_profile>
    expect(sent[1].toString(), contains('<user_profile>'));
    // [2] pinned <opening_context> right after <user_profile>, surviving 60+ turns pruning!
    expect(
      sent[2].toString(),
      contains('<opening_context source="periodic_insight">'),
    );
    expect(sent[2].toString(), contains('2026-08-03 ~ 2026-08-09'));
    expect(sent[2].toString(), contains('上周你在深夜记录了三次灵感'));
  });
}
