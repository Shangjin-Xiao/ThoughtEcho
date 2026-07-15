import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openai_dart/openai_dart.dart' as openai;
import 'package:thoughtecho/models/ai_provider_settings.dart';
import 'package:thoughtecho/models/multi_ai_settings.dart';
import 'package:thoughtecho/models/note_proposal_artifact.dart';
import 'package:thoughtecho/services/agent_service.dart';
import 'package:thoughtecho/services/agent_tool.dart';
import 'package:thoughtecho/services/settings_service.dart';

import '../../test_harness.dart';

class _FakeSettingsService extends ChangeNotifier implements SettingsService {
  _FakeSettingsService(this._provider);

  final AIProviderSettings? _provider;

  @override
  MultiAISettings get multiAISettings => MultiAISettings(
        providers: [if (_provider case final provider?) provider],
        currentProviderId: _provider?.id,
      );

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _CountingTool extends AgentTool {
  _CountingTool({
    required this.toolName,
    required this.resultContent,
    this.artifact,
  });

  final String toolName;
  final String resultContent;
  final AgentArtifact? artifact;
  int executeCount = 0;

  @override
  String get name => toolName;

  @override
  String get description => 'test tool';

  @override
  Map<String, Object?> get parametersSchema => const {
        'type': 'object',
        'properties': {
          'query': {'type': 'string'}
        },
      };

  @override
  Future<ToolResult> execute(ToolCall toolCall) async {
    executeCount++;
    return ToolResult(
      toolCallId: toolCall.id,
      content: resultContent,
      artifact: artifact,
    );
  }
}

class _FailingTool extends AgentTool {
  _FailingTool({
    required this.toolName,
    required this.resultContent,
    this.retryable = false,
  });

  final String toolName;
  final String resultContent;
  final bool retryable;
  int executeCount = 0;

  @override
  String get name => toolName;

  @override
  String get description => 'failing test tool';

  @override
  Map<String, Object?> get parametersSchema => const {
        'type': 'object',
        'properties': {
          'query': {'type': 'string'}
        },
      };

  @override
  Future<ToolResult> execute(ToolCall toolCall) async {
    executeCount++;
    return ToolResult(
      toolCallId: toolCall.id,
      content: resultContent,
      isError: true,
      retryable: retryable,
    );
  }
}

class _DelayedTool extends AgentTool {
  _DelayedTool({
    required this.toolName,
    required this.delay,
    this.readOnly = false,
    this.concurrencySafe = false,
  });

  final String toolName;
  final Duration delay;
  final bool readOnly;
  final bool concurrencySafe;
  int executeCount = 0;

  @override
  String get name => toolName;

  @override
  String get description => 'delayed test tool';

  @override
  Map<String, Object?> get parametersSchema => const {
        'type': 'object',
        'properties': {
          'query': {'type': 'string'}
        },
      };

  @override
  bool get isReadOnly => readOnly;

  @override
  bool get isConcurrencySafe => concurrencySafe;

  @override
  Future<ToolResult> execute(ToolCall toolCall) async {
    executeCount++;
    await Future<void>.delayed(delay);
    return ToolResult(
      toolCallId: toolCall.id,
      content: '$toolName done',
    );
  }
}

openai.ChatCompletion _toolCallCompletion({
  required String callId,
  required String toolName,
  required Map<String, dynamic> args,
}) {
  return openai.ChatCompletion(
    object: 'chat.completion',
    model: 'gpt-test',
    choices: [
      openai.ChatChoice(
        message: openai.AssistantMessage(
          content: null,
          toolCalls: [
            openai.ToolCall.functionCall(
              id: callId,
              call: openai.FunctionCall.fromMap(
                name: toolName,
                arguments: args,
              ),
            ),
          ],
        ),
        finishReason: openai.FinishReason.toolCalls,
      ),
    ],
  );
}

openai.ToolCall _buildToolCall({
  required String callId,
  required String toolName,
  required Map<String, dynamic> args,
}) {
  return openai.ToolCall.functionCall(
    id: callId,
    call: openai.FunctionCall.fromMap(
      name: toolName,
      arguments: args,
    ),
  );
}

openai.ToolCall _buildRawToolCall({
  required String callId,
  required String toolName,
  required String rawArguments,
}) {
  return openai.ToolCall.functionCall(
    id: callId,
    call: openai.FunctionCall(
      name: toolName,
      arguments: rawArguments,
    ),
  );
}

openai.ChatCompletion _multiToolCallCompletion(
    List<openai.ToolCall> toolCalls) {
  return openai.ChatCompletion(
    object: 'chat.completion',
    model: 'gpt-test',
    choices: [
      openai.ChatChoice(
        message: openai.AssistantMessage(
          content: null,
          toolCalls: toolCalls,
        ),
        finishReason: openai.FinishReason.toolCalls,
      ),
    ],
  );
}

openai.ChatCompletion _textCompletion(String content) {
  return openai.ChatCompletion(
    object: 'chat.completion',
    model: 'gpt-test',
    choices: [
      openai.ChatChoice(
        message: openai.AssistantMessage(content: content),
        finishReason: openai.FinishReason.stop,
      ),
    ],
  );
}

String _chatMessageText(openai.ChatMessage message) {
  final dynamic dynamicMessage = message;
  try {
    final content = dynamicMessage.content;
    if (content != null) {
      return content.toString();
    }
  } catch (_) {
    // Fallback to toString below.
  }
  return message.toString();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await TestHarness.initialize();
  });

  group('AgentService native tool loop', () {
    test('preserves one typed proposal artifact in the final response',
        () async {
      final provider = const AIProviderSettings(
        id: 'openai',
        name: 'OpenAI',
        apiUrl: 'https://api.openai.com/v1/chat/completions',
        model: 'gpt-4.1',
      );
      final artifact = NoteProposalArtifact(
        action: NoteProposalAction.create,
        proposalTitle: 'Draft',
        reason: '',
        resultKind: NoteDocumentKind.plain,
        content: 'Body',
        documentOps: null,
        metadata: const {},
        changes: const [],
      );
      final tool = _CountingTool(
        toolName: 'propose_note_create',
        resultContent: 'proposal ready',
        artifact: artifact,
      );
      final responses = <openai.ChatCompletion>[
        _toolCallCompletion(
          callId: 'proposal',
          toolName: tool.name,
          args: const {},
        ),
        _textCompletion('Review it'),
      ];
      final service = AgentService(
        settingsService: _FakeSettingsService(provider),
        tools: [tool],
        apiKeyResolver: (_) async => 'test-key',
        completionRequester: ({
          required provider,
          required messages,
          required tools,
          required temperature,
          required maxTokens,
        }) async =>
            responses.removeAt(0),
      );

      final response = await service.runAgent(userMessage: 'draft');

      expect(response.toolExecutions, hasLength(1));
      expect(response.artifacts.single, same(artifact));
      expect(response.toolExecutions.single.result.content, 'proposal ready');
    });

    test('keeps only the first proposal when a round requests two', () async {
      final provider = const AIProviderSettings(
        id: 'openai',
        name: 'OpenAI',
        apiUrl: 'https://api.openai.com/v1/chat/completions',
        model: 'gpt-4.1',
      );
      NoteProposalArtifact artifact(String title) => NoteProposalArtifact(
            action: NoteProposalAction.create,
            proposalTitle: title,
            reason: '',
            resultKind: NoteDocumentKind.plain,
            content: title,
            documentOps: null,
            metadata: const {},
            changes: const [],
          );
      final first = _CountingTool(
        toolName: 'proposal_a',
        resultContent: 'first',
        artifact: artifact('first'),
      );
      final second = _CountingTool(
        toolName: 'proposal_b',
        resultContent: 'second',
        artifact: artifact('second'),
      );
      final responses = <openai.ChatCompletion>[
        _multiToolCallCompletion([
          _buildToolCall(callId: 'a', toolName: first.name, args: const {}),
          _buildToolCall(callId: 'b', toolName: second.name, args: const {}),
        ]),
        _textCompletion('done'),
      ];
      final service = AgentService(
        settingsService: _FakeSettingsService(provider),
        tools: [first, second],
        apiKeyResolver: (_) async => 'test-key',
        completionRequester: ({
          required provider,
          required messages,
          required tools,
          required temperature,
          required maxTokens,
        }) async =>
            responses.removeAt(0),
      );

      final response = await service.runAgent(userMessage: 'draft');

      expect(response.artifacts, hasLength(1));
      expect(
        (response.artifacts.single as NoteProposalArtifact).proposalTitle,
        'first',
      );
    });

    test('stops when same tool call is repeated', () async {
      final provider = const AIProviderSettings(
        id: 'openai',
        name: 'OpenAI',
        apiUrl: 'https://api.openai.com/v1/chat/completions',
        model: 'gpt-4.1',
      );
      final settings = _FakeSettingsService(provider);
      final tool = _CountingTool(toolName: 'search_notes', resultContent: 'ok');

      final responses = <openai.ChatCompletion>[
        _toolCallCompletion(
          callId: 'call_1',
          toolName: 'search_notes',
          args: const {'query': 'loop'},
        ),
        _toolCallCompletion(
          callId: 'call_2',
          toolName: 'search_notes',
          args: const {'query': 'loop'},
        ),
        _textCompletion('Finished after loop'),
      ];

      final service = AgentService(
        settingsService: settings,
        tools: [tool],
        apiKeyResolver: (_) async => 'test-key',
        completionRequester: ({
          required provider,
          required messages,
          required tools,
          required temperature,
          required maxTokens,
        }) async {
          return responses.removeAt(0);
        },
      );

      final response = await service.runAgent(userMessage: 'test');
      expect(tool.executeCount, 1);
      expect(response.toolCalls.length, 1);
      expect(response.content, isNotEmpty);
      expect(response.reachedMaxRounds, isFalse);
    });

    test('returns final text after tool execution', () async {
      final provider = const AIProviderSettings(
        id: 'openai',
        name: 'OpenAI',
        apiUrl: 'https://api.openai.com/v1/chat/completions',
        model: 'gpt-4.1',
      );
      final settings = _FakeSettingsService(provider);
      final tool = _CountingTool(
          toolName: 'search_notes', resultContent: '{"items": []}');

      final responses = <openai.ChatCompletion>[
        _toolCallCompletion(
          callId: 'call_1',
          toolName: 'search_notes',
          args: const {'query': 'today'},
        ),
        _textCompletion('这是最终回答'),
      ];

      final service = AgentService(
        settingsService: settings,
        tools: [tool],
        apiKeyResolver: (_) async => 'test-key',
        completionRequester: ({
          required provider,
          required messages,
          required tools,
          required temperature,
          required maxTokens,
        }) async {
          return responses.removeAt(0);
        },
      );

      final response = await service.runAgent(userMessage: 'hello');
      expect(tool.executeCount, 1);
      expect(response.content, '这是最终回答');
      expect(response.toolCalls.length, 1);
    });

    test('continues when duplicate historical call appears with new call',
        () async {
      final provider = const AIProviderSettings(
        id: 'openai',
        name: 'OpenAI',
        apiUrl: 'https://api.openai.com/v1/chat/completions',
        model: 'gpt-4.1',
      );
      final settings = _FakeSettingsService(provider);
      final tool = _CountingTool(
        toolName: 'search_notes',
        resultContent: '{"items": []}',
      );

      final responses = <openai.ChatCompletion>[
        _toolCallCompletion(
          callId: 'call_1',
          toolName: 'search_notes',
          args: const {'query': 'loop'},
        ),
        _multiToolCallCompletion([
          _buildToolCall(
            callId: 'call_2',
            toolName: 'search_notes',
            args: const {'query': 'loop'},
          ),
          _buildToolCall(
            callId: 'call_3',
            toolName: 'search_notes',
            args: const {'query': 'fresh'},
          ),
        ]),
        _textCompletion('最终回答'),
      ];

      final service = AgentService(
        settingsService: settings,
        tools: [tool],
        apiKeyResolver: (_) async => 'test-key',
        completionRequester: ({
          required provider,
          required messages,
          required tools,
          required temperature,
          required maxTokens,
        }) async {
          return responses.removeAt(0);
        },
      );

      final response = await service.runAgent(userMessage: 'test');
      expect(tool.executeCount, 2);
      expect(response.content, '最终回答');
      expect(
        response.toolCalls.map((call) => call.arguments['query']).toList(),
        ['loop', 'fresh'],
      );
    });

    test('preserves long search tool payload for follow-up reasoning',
        () async {
      final provider = const AIProviderSettings(
        id: 'openai',
        name: 'OpenAI',
        apiUrl: 'https://api.openai.com/v1/chat/completions',
        model: 'gpt-4.1',
      );
      final settings = _FakeSettingsService(provider);
      final marker = '__TAIL_MARKER__';
      final longBody = List<String>.filled(1500, 'x').join();
      final tool = _CountingTool(
        toolName: 'search_notes',
        resultContent: '{"items":[{"snippet":"$longBody$marker"}]}',
      );

      final responses = <openai.ChatCompletion>[
        _toolCallCompletion(
          callId: 'call_1',
          toolName: 'search_notes',
          args: const {'query': 'keyword'},
        ),
        _textCompletion('done'),
      ];
      var requestCount = 0;
      var forwardedTranscript = '';

      final service = AgentService(
        settingsService: settings,
        tools: [tool],
        apiKeyResolver: (_) async => 'test-key',
        completionRequester: ({
          required provider,
          required messages,
          required tools,
          required temperature,
          required maxTokens,
        }) async {
          requestCount++;
          if (requestCount == 2) {
            forwardedTranscript =
                messages.map(_chatMessageText).join('\n----\n');
          }
          return responses.removeAt(0);
        },
      );

      await service.runAgent(userMessage: 'test');

      expect(forwardedTranscript, contains(marker));
    });

    test(
        'asks model to repair malformed tool arguments once without forwarding raw payload',
        () async {
      final provider = const AIProviderSettings(
        id: 'openai',
        name: 'OpenAI',
        apiUrl: 'https://api.openai.com/v1/chat/completions',
        model: 'gpt-4.1',
      );
      final settings = _FakeSettingsService(provider);
      final tool = _CountingTool(
        toolName: 'search_notes',
        resultContent: '{"items": []}',
      );
      const malformedArguments = '{}{"limit":10}';
      final responses = <openai.ChatCompletion>[
        _multiToolCallCompletion([
          _buildRawToolCall(
            callId: 'call_bad',
            toolName: 'search_notes',
            rawArguments: malformedArguments,
          ),
        ]),
        _toolCallCompletion(
          callId: 'call_fixed',
          toolName: 'search_notes',
          args: const {'query': 'fixed', 'limit': 10},
        ),
        _textCompletion('修正后完成'),
      ];
      var requestCount = 0;
      var correctionTranscript = '';

      final service = AgentService(
        settingsService: settings,
        tools: [tool],
        apiKeyResolver: (_) async => 'test-key',
        completionRequester: ({
          required provider,
          required messages,
          required tools,
          required temperature,
          required maxTokens,
        }) async {
          requestCount++;
          if (requestCount == 2) {
            correctionTranscript =
                messages.map(_chatMessageText).join('\n----\n');
          }
          return responses.removeAt(0);
        },
      );

      final response = await service.runAgent(userMessage: 'test');

      expect(tool.executeCount, 1);
      expect(response.content, '修正后完成');
      expect(correctionTranscript, contains('参数不是有效的 JSON 对象'));
      expect(correctionTranscript, isNot(contains(malformedArguments)));
    });

    test('stops after one malformed argument repair attempt', () async {
      final provider = const AIProviderSettings(
        id: 'openai',
        name: 'OpenAI',
        apiUrl: 'https://api.openai.com/v1/chat/completions',
        model: 'gpt-4.1',
      );
      final settings = _FakeSettingsService(provider);
      final tool = _CountingTool(
        toolName: 'search_notes',
        resultContent: '{"items": []}',
      );
      final responses = <openai.ChatCompletion>[
        for (final id in ['call_bad_1', 'call_bad_2'])
          _multiToolCallCompletion([
            _buildRawToolCall(
              callId: id,
              toolName: 'search_notes',
              rawArguments: '{}{"limit":10}',
            ),
          ]),
      ];

      final service = AgentService(
        settingsService: settings,
        tools: [tool],
        apiKeyResolver: (_) async => 'test-key',
        completionRequester: ({
          required provider,
          required messages,
          required tools,
          required temperature,
          required maxTokens,
        }) async {
          return responses.removeAt(0);
        },
      );
      await expectLater(
        () => service.runAgent(userMessage: 'test'),
        throwsA(
          isA<AgentRequestException>().having(
            (error) => error.failureType,
            'failureType',
            AgentFailureType.toolExecutionFailed,
          ),
        ),
      );

      expect(tool.executeCount, 0);
    });

    test(
        'does not continue to suggestion cards after non-retryable tool failure',
        () async {
      final provider = const AIProviderSettings(
        id: 'openai',
        name: 'OpenAI',
        apiUrl: 'https://api.openai.com/v1/chat/completions',
        model: 'gpt-4.1',
      );
      final settings = _FakeSettingsService(provider);
      final tool = _FailingTool(
        toolName: 'propose_new_note',
        resultContent: '保存失败：数据库不可写',
      );
      final responses = <openai.ChatCompletion>[
        _toolCallCompletion(
          callId: 'call_1',
          toolName: 'propose_new_note',
          args: const {'title': 't', 'content': 'c'},
        ),
        _textCompletion('```smart_result\n{"type":"smart_result"}\n```'),
      ];
      var requestCount = 0;

      final service = AgentService(
        settingsService: settings,
        tools: [tool],
        apiKeyResolver: (_) async => 'test-key',
        completionRequester: ({
          required provider,
          required messages,
          required tools,
          required temperature,
          required maxTokens,
        }) async {
          requestCount++;
          return responses.removeAt(0);
        },
      );
      final events = <AgentEvent>[];
      final subscription = service.events.listen(events.add);

      await expectLater(
        () => service.runAgent(userMessage: 'test'),
        throwsA(
          isA<AgentRequestException>().having(
            (error) => error.failureType,
            'failureType',
            AgentFailureType.toolExecutionFailed,
          ),
        ),
      );

      expect(tool.executeCount, 1);
      expect(requestCount, 1);
      final toolResultEvent =
          events.whereType<AgentToolCallResultEvent>().single;
      expect(toolResultEvent.isError, isTrue);
      expect(toolResultEvent.result, isEmpty);
      await subscription.cancel();
      service.dispose();
    });

    test('does not return retryable failed proposal calls as suggestions',
        () async {
      const proposalTools = <String>[
        'propose_edit',
        'propose_rich_edit',
        'propose_new_note',
      ];

      for (final toolName in proposalTools) {
        final provider = const AIProviderSettings(
          id: 'openai',
          name: 'OpenAI',
          apiUrl: 'https://api.openai.com/v1/chat/completions',
          model: 'gpt-4.1',
        );
        final tool = _FailingTool(
          toolName: toolName,
          resultContent: 'proposal failed',
          retryable: true,
        );
        final responses = <openai.ChatCompletion>[
          _toolCallCompletion(
            callId: '$toolName-call',
            toolName: toolName,
            args: const {'title': 'suggestion', 'content': 'draft'},
          ),
          _textCompletion('retry completed without a proposal'),
        ];
        final service = AgentService(
          settingsService: _FakeSettingsService(provider),
          tools: [tool],
          apiKeyResolver: (_) async => 'test-key',
          completionRequester: ({
            required provider,
            required messages,
            required tools,
            required temperature,
            required maxTokens,
          }) async =>
              responses.removeAt(0),
        );

        final response = await service.runAgent(userMessage: 'test');

        expect(tool.executeCount, 1, reason: toolName);
        expect(response.content, 'retry completed without a proposal',
            reason: toolName);
        expect(response.toolCalls, isEmpty, reason: toolName);
        service.dispose();
      }
    });

    test('keeps events stream active across consecutive runs', () async {
      final provider = const AIProviderSettings(
        id: 'openai',
        name: 'OpenAI',
        apiUrl: 'https://api.openai.com/v1/chat/completions',
        model: 'gpt-4.1',
      );
      final settings = _FakeSettingsService(provider);
      final responses = <openai.ChatCompletion>[
        _textCompletion('first'),
        _textCompletion('second'),
      ];

      final service = AgentService(
        settingsService: settings,
        tools: const <AgentTool>[],
        apiKeyResolver: (_) async => 'test-key',
        completionRequester: ({
          required provider,
          required messages,
          required tools,
          required temperature,
          required maxTokens,
        }) async {
          return responses.removeAt(0);
        },
      );

      var responseEvents = 0;
      final subscription = service.events.listen((event) {
        if (event is AgentResponseEvent) {
          responseEvents++;
        }
      });

      await service.runAgent(userMessage: 'first');
      await service.runAgent(userMessage: 'second');
      await Future<void>.delayed(const Duration(milliseconds: 20));

      await subscription.cancel();
      service.dispose();

      expect(responseEvents, 2);
    });

    test('returns max-rounds summary when tool loop never converges', () async {
      final provider = const AIProviderSettings(
        id: 'openai',
        name: 'OpenAI',
        apiUrl: 'https://api.openai.com/v1/chat/completions',
        model: 'gpt-4.1',
      );
      final settings = _FakeSettingsService(provider);
      final tool = _CountingTool(toolName: 'search_notes', resultContent: 'ok');

      final responses = <openai.ChatCompletion>[
        for (var i = 0; i < AgentService.maxToolRounds; i++)
          _toolCallCompletion(
            callId: 'call_$i',
            toolName: 'search_notes',
            args: {'query': 'q_$i'},
          ),
        _textCompletion('summary answer'),
      ];

      final service = AgentService(
        settingsService: settings,
        tools: [tool],
        apiKeyResolver: (_) async => 'test-key',
        completionRequester: ({
          required provider,
          required messages,
          required tools,
          required temperature,
          required maxTokens,
        }) async {
          return responses.removeAt(0);
        },
      );

      final response = await service.runAgent(userMessage: 'test');
      expect(tool.executeCount, AgentService.maxToolRounds);
      expect(response.reachedMaxRounds, isTrue);
      expect(response.content, 'summary answer');
    });

    test('reports an empty max-rounds summary as a typed failure', () async {
      final provider = const AIProviderSettings(
        id: 'openai',
        name: 'OpenAI',
        apiUrl: 'https://api.openai.com/v1/chat/completions',
        model: 'gpt-4.1',
      );
      final tool = _CountingTool(toolName: 'search_notes', resultContent: 'ok');
      final responses = <openai.ChatCompletion>[
        for (var i = 0; i < AgentService.maxToolRounds; i++)
          _toolCallCompletion(
            callId: 'call_$i',
            toolName: 'search_notes',
            args: {'query': 'q_$i'},
          ),
        _textCompletion(''),
      ];
      final service = AgentService(
        settingsService: _FakeSettingsService(provider),
        tools: [tool],
        apiKeyResolver: (_) async => 'test-key',
        completionRequester: ({
          required provider,
          required messages,
          required tools,
          required temperature,
          required maxTokens,
        }) async =>
            responses.removeAt(0),
      );

      await expectLater(
        () => service.runAgent(userMessage: 'test'),
        throwsA(
          isA<AgentRequestException>().having(
            (error) => error.failureType,
            'failureType',
            AgentFailureType.unknown,
          ),
        ),
      );

      expect(tool.executeCount, AgentService.maxToolRounds);
      service.dispose();
    });

    test('emits error event when completion request fails', () async {
      final provider = const AIProviderSettings(
        id: 'openai',
        name: 'OpenAI',
        apiUrl: 'https://api.openai.com/v1/chat/completions',
        model: 'gpt-4.1',
      );
      final settings = _FakeSettingsService(provider);
      final service = AgentService(
        settingsService: settings,
        tools: const <AgentTool>[],
        apiKeyResolver: (_) async => 'test-key',
        completionRequester: ({
          required provider,
          required messages,
          required tools,
          required temperature,
          required maxTokens,
        }) async {
          throw Exception('api down');
        },
      );

      final events = <AgentEvent>[];
      final subscription = service.events.listen(events.add);

      await expectLater(
        () => service.runAgent(userMessage: 'test'),
        throwsException,
      );

      await Future<void>.delayed(const Duration(milliseconds: 20));
      await subscription.cancel();
      service.dispose();

      expect(
        events.whereType<AgentErrorEvent>().single.failureType,
        AgentFailureType.unknown,
      );
    });

    test('classifies a missing provider without exposing its configuration',
        () async {
      final service = AgentService(
        settingsService: _FakeSettingsService(null),
        tools: const <AgentTool>[],
      );
      final events = <AgentEvent>[];
      final subscription = service.events.listen(events.add);

      await expectLater(
        () => service.runAgent(userMessage: 'test'),
        throwsA(
          isA<AgentRequestException>().having(
            (error) => error.failureType,
            'failureType',
            AgentFailureType.noProvider,
          ),
        ),
      );

      await subscription.cancel();
      service.dispose();
      expect(
        events.whereType<AgentErrorEvent>().single.failureType,
        AgentFailureType.noProvider,
      );
    });

    test('classifies a missing API key without exposing key details', () async {
      final provider = const AIProviderSettings(
        id: 'openai',
        name: 'OpenAI',
        apiUrl: 'https://api.openai.com/v1/chat/completions',
        model: 'gpt-4.1',
      );
      final service = AgentService(
        settingsService: _FakeSettingsService(provider),
        tools: const <AgentTool>[],
        apiKeyResolver: (_) async => '',
      );
      final events = <AgentEvent>[];
      final subscription = service.events.listen(events.add);

      await expectLater(
        () => service.runAgent(userMessage: 'test'),
        throwsA(
          isA<AgentRequestException>().having(
            (error) => error.failureType,
            'failureType',
            AgentFailureType.missingApiKey,
          ),
        ),
      );

      await subscription.cancel();
      service.dispose();
      expect(
        events.whereType<AgentErrorEvent>().single.failureType,
        AgentFailureType.missingApiKey,
      );
    });

    test('classifies an unsupported Agent provider before resolving its key',
        () async {
      final provider = const AIProviderSettings(
        id: 'anthropic',
        name: 'Anthropic',
        apiUrl: 'https://api.anthropic.com/v1/messages',
        model: 'claude-3-5-sonnet',
      );
      final service = AgentService(
        settingsService: _FakeSettingsService(provider),
        tools: const <AgentTool>[],
        apiKeyResolver: (_) async =>
            throw StateError('key resolver should not run'),
      );
      final events = <AgentEvent>[];
      final subscription = service.events.listen(events.add);

      await expectLater(
        () => service.runAgent(userMessage: 'test'),
        throwsA(
          isA<AgentRequestException>().having(
            (error) => error.failureType,
            'failureType',
            AgentFailureType.unsupportedProvider,
          ),
        ),
      );

      await subscription.cancel();
      service.dispose();
      expect(
        events.whereType<AgentErrorEvent>().single.failureType,
        AgentFailureType.unsupportedProvider,
      );
    });

    test('runs read-only concurrency-safe tools in parallel', () async {
      final provider = const AIProviderSettings(
        id: 'openai',
        name: 'OpenAI',
        apiUrl: 'https://api.openai.com/v1/chat/completions',
        model: 'gpt-4.1',
      );
      final settings = _FakeSettingsService(provider);
      final firstTool = _DelayedTool(
        toolName: 'search_notes',
        delay: const Duration(milliseconds: 120),
        readOnly: true,
        concurrencySafe: true,
      );
      final secondTool = _DelayedTool(
        toolName: 'get_tags',
        delay: const Duration(milliseconds: 120),
        readOnly: true,
        concurrencySafe: true,
      );

      final responses = <openai.ChatCompletion>[
        _multiToolCallCompletion([
          _buildToolCall(
            callId: 'call_1',
            toolName: 'search_notes',
            args: const {'query': 'camp'},
          ),
          _buildToolCall(
            callId: 'call_2',
            toolName: 'get_tags',
            args: const {'query': 'camp'},
          ),
        ]),
        _textCompletion('done'),
      ];

      final service = AgentService(
        settingsService: settings,
        tools: [firstTool, secondTool],
        apiKeyResolver: (_) async => 'test-key',
        completionRequester: ({
          required provider,
          required messages,
          required tools,
          required temperature,
          required maxTokens,
        }) async {
          return responses.removeAt(0);
        },
      );

      final stopwatch = Stopwatch()..start();
      final response = await service.runAgent(userMessage: 'test');
      stopwatch.stop();

      expect(response.content, 'done');
      expect(firstTool.executeCount, 1);
      expect(secondTool.executeCount, 1);
      expect(stopwatch.elapsedMilliseconds, lessThan(220));
    });

    test('requestStop prevents agent from continuing to final response',
        () async {
      final provider = const AIProviderSettings(
        id: 'openai',
        name: 'OpenAI',
        apiUrl: 'https://api.openai.com/v1/chat/completions',
        model: 'gpt-4.1',
      );
      final settings = _FakeSettingsService(provider);
      final tool = _DelayedTool(
        toolName: 'search_notes',
        delay: const Duration(milliseconds: 120),
        readOnly: true,
        concurrencySafe: true,
      );

      var requestCount = 0;
      final service = AgentService(
        settingsService: settings,
        tools: [tool],
        apiKeyResolver: (_) async => 'test-key',
        completionRequester: ({
          required provider,
          required messages,
          required tools,
          required temperature,
          required maxTokens,
        }) async {
          requestCount++;
          if (requestCount == 1) {
            return _toolCallCompletion(
              callId: 'call_1',
              toolName: 'search_notes',
              args: const {'query': 'camp'},
            );
          }
          return _textCompletion('should not happen');
        },
      );

      final future = service.runAgent(userMessage: 'test');
      await Future<void>.delayed(const Duration(milliseconds: 20));
      service.requestStop();
      final response = await future;

      expect(response.content, isEmpty);
      expect(requestCount, 1);
    });

    test(
        'starts a new run after stopping an unresolved request without emitting stale events',
        () async {
      final provider = const AIProviderSettings(
        id: 'openai',
        name: 'OpenAI',
        apiUrl: 'https://api.openai.com/v1/chat/completions',
        model: 'gpt-4.1',
      );
      final firstCompletion = Completer<openai.ChatCompletion>();
      var requestCount = 0;
      final service = AgentService(
        settingsService: _FakeSettingsService(provider),
        tools: const <AgentTool>[],
        apiKeyResolver: (_) async => 'test-key',
        completionRequester: ({
          required provider,
          required messages,
          required tools,
          required temperature,
          required maxTokens,
        }) {
          requestCount++;
          return requestCount == 1
              ? firstCompletion.future
              : Future<openai.ChatCompletion>.value(_textCompletion('new'));
        },
      );
      final responseEvents = <String>[];
      final subscription = service.events.listen((event) {
        if (event is AgentResponseEvent) {
          responseEvents.add(event.content);
        }
      });

      final firstRun = service.runAgent(userMessage: 'old');
      await Future<void>.delayed(Duration.zero);
      service.requestStop();
      final secondRun = service.runAgent(userMessage: 'new');
      firstCompletion.complete(_textCompletion('stale'));

      final responses = await Future.wait([firstRun, secondRun]);
      await Future<void>.delayed(Duration.zero);

      expect(responses[0].content, isEmpty);
      expect(responses[1].content, 'new');
      expect(responseEvents, ['new']);

      await subscription.cancel();
      service.dispose();
    });
  });
}
