import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openai_dart/openai_dart.dart' as openai;
import 'package:thoughtecho/models/ai_provider_settings.dart';
import 'package:thoughtecho/models/multi_ai_settings.dart';
import 'package:thoughtecho/services/agent_service.dart';
import 'package:thoughtecho/services/agent_tool.dart';
import 'package:thoughtecho/services/agent_tools/ask_user_tool.dart';
import 'package:thoughtecho/services/settings_service.dart';

class _FakeSettingsService extends ChangeNotifier implements SettingsService {
  _FakeSettingsService(this._provider);

  final AIProviderSettings _provider;

  @override
  String? get localeCode => 'zh';

  @override
  MultiAISettings get multiAISettings => MultiAISettings(
        providers: [_provider],
        currentProviderId: _provider.id,
      );

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

openai.ToolCall _rawToolCall({
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

openai.ChatCompletion _toolCallCompletion(List<openai.ToolCall> toolCalls) {
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
  const provider = AIProviderSettings(
    id: 'openai',
    name: 'OpenAI',
    apiUrl: 'https://api.openai.com/v1/chat/completions',
    model: 'gpt-4o',
  );

  group('AgentService 与 AskUserTool 集成', () {
    test('findTool 穿透截断装饰器正确获取 AskUserTool 并设置 handler', () {
      final askTool = AskUserTool();
      final service = AgentService(
        settingsService: _FakeSettingsService(provider),
        tools: [askTool],
      );

      expect(service.findTool<AskUserTool>(), isNotNull);
      expect(service.findTool<AskUserTool>()?.name, 'ask_user');

      var handlerCalled = false;
      service.setAskUserHandler((request) async {
        handlerCalled = true;
        return AskUserResponse.selected(['A']);
      });

      // 验证 handler 已成功挂载到底层 AskUserTool
      askTool.execute(ToolCall(
        id: '1',
        name: 'ask_user',
        arguments: {
          'question': '测试问题',
          'options': ['A', 'B'],
        },
      ));

      expect(handlerCalled, isTrue);
    });

    test('Agent 循环中成功触发 ask_user 并将用户选项送入下一轮', () async {
      final askTool = AskUserTool();
      var round = 0;
      late List<openai.ChatMessage> secondRoundMessages;

      final service = AgentService(
        settingsService: _FakeSettingsService(provider),
        tools: [askTool],
        apiKeyResolver: (_) async => 'test-key',
        completionRequester: ({
          required provider,
          required messages,
          required tools,
          required temperature,
          required maxTokens,
        }) async {
          round++;
          if (round == 1) {
            return _toolCallCompletion([
              _rawToolCall(
                callId: 'call_ask_1',
                toolName: 'ask_user',
                rawArguments: jsonEncode({
                  'question': '你想创建哪种类型的笔记？',
                  'options': ['工作复盘', '读书随笔'],
                }),
              ),
            ]);
          } else {
            secondRoundMessages = messages;
            return _textCompletion('好的，我为你创建工作复盘笔记。');
          }
        },
      );

      service.setAskUserHandler((request) async {
        expect(request.question, '你想创建哪种类型的笔记？');
        expect(request.options, ['工作复盘', '读书随笔']);
        return AskUserResponse.selected(['工作复盘']);
      });

      final response = await service.runAgent(userMessage: '帮我起草一篇笔记');

      expect(response.content, '好的，我为你创建工作复盘笔记。');
      expect(round, 2);

      // 验证回喂给模型的工具消息内容包含用户选择
      final toolMsg = secondRoundMessages.firstWhere(
        (m) => m is openai.ToolMessage,
      ) as openai.ToolMessage;
      expect(toolMsg.content, contains('用户选择了：工作复盘'));
    });

    test('交互式工具不受 45 秒单工具超时拦截', () async {
      final askTool = AskUserTool();
      expect(askTool.isInteractive, isTrue);

      final service = AgentService(
        settingsService: _FakeSettingsService(provider),
        tools: [askTool],
        apiKeyResolver: (_) async => 'test-key',
        completionRequester: ({
          required provider,
          required messages,
          required tools,
          required temperature,
          required maxTokens,
        }) async {
          return _toolCallCompletion([
            _rawToolCall(
              callId: 'call_ask_2',
              toolName: 'ask_user',
              rawArguments: jsonEncode({
                'question': '请选择分类',
                'options': ['A', 'B'],
              }),
            ),
          ]);
        },
      );

      // 模拟耗时等待（在 fakeAsync 下推进时间）
      service.setAskUserHandler((request) async {
        return AskUserResponse.selected(['A']);
      });

      final toolResult = await askTool.execute(ToolCall(
        id: 'call_ask_2',
        name: 'ask_user',
        arguments: {
          'question': '请选择分类',
          'options': ['A', 'B'],
        },
      ));

      expect(toolResult.isError, isFalse);
      expect(toolResult.content, '用户选择了：A');
    });

    test('requestStop() 干净利落地取消正在挂起的交互式提问', () async {
      final askTool = AskUserTool();
      final hangingPromptStarted = Completer<void>();

      final service = AgentService(
        settingsService: _FakeSettingsService(provider),
        tools: [askTool],
        apiKeyResolver: (_) async => 'test-key',
        completionRequester: ({
          required provider,
          required messages,
          required tools,
          required temperature,
          required maxTokens,
        }) async {
          return _toolCallCompletion([
            _rawToolCall(
              callId: 'call_ask_3',
              toolName: 'ask_user',
              rawArguments: jsonEncode({
                'question': '请确认是否保存？',
                'options': ['保存', '舍弃'],
              }),
            ),
          ]);
        },
      );

      service.setAskUserHandler((request) async {
        hangingPromptStarted.complete();
        // 挂起等待外部取消
        await Completer<void>().future;
        return AskUserResponse.selected(['保存']);
      });

      final agentFuture = service.runAgent(userMessage: '开始');

      await hangingPromptStarted.future;
      expect(service.isRunning, isTrue);

      // 调用 requestStop
      service.requestStop();

      // Agent 循环应迅速退出，而不是挂死或等 10 秒超时
      final response = await agentFuture.timeout(const Duration(seconds: 3));
      expect(response, isNotNull);
      expect(service.isRunning, isFalse);
    });
  });
}
