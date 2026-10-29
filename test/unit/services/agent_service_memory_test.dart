import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:openai_dart/openai_dart.dart' as openai;
import 'package:thoughtecho/models/agent_memory.dart';
import 'package:thoughtecho/models/ai_provider_settings.dart';
import 'package:thoughtecho/models/multi_ai_settings.dart';
import 'package:thoughtecho/services/agent_service.dart';

import 'agent_tools/memory_tool_harness.dart';

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
}
