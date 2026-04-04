import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openai_dart/openai_dart.dart' as openai;
import 'package:thoughtecho/models/ai_provider_settings.dart';
import 'package:thoughtecho/models/multi_ai_settings.dart';
import 'package:thoughtecho/services/agent_service.dart';
import 'package:thoughtecho/services/agent_tool.dart';
import 'package:thoughtecho/services/settings_service.dart';

class _FakeSettingsService extends ChangeNotifier implements SettingsService {
  _FakeSettingsService(this._provider);

  final AIProviderSettings _provider;

  @override
  MultiAISettings get multiAISettings => MultiAISettings(
        providers: [_provider],
        currentProviderId: _provider.id,
      );

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _CountingTool extends AgentTool {
  _CountingTool({
    required this.toolName,
    required this.resultContent,
  });

  final String toolName;
  final String resultContent;
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

void main() {
  group('AgentService native tool loop', () {
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
  });
}
