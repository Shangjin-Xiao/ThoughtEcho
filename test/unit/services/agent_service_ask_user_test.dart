import 'dart:async';
import 'dart:convert';

import 'package:fake_async/fake_async.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openai_dart/openai_dart.dart' as openai;
import 'package:thoughtecho/models/ai_provider_settings.dart';
import 'package:thoughtecho/models/multi_ai_settings.dart';
import 'package:thoughtecho/services/agent_service.dart';
import 'package:thoughtecho/services/agent_tool.dart';
import 'package:thoughtecho/services/agent_tools/ask_user_tool.dart';
import 'package:thoughtecho/services/agent_tools/truncating_agent_tool.dart';
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

class _SlowNonInteractiveTool extends AgentTool {
  @override
  String get name => 'slow_tool';

  @override
  String get description => 'A slow test tool';

  @override
  Map<String, dynamic> get parametersSchema => {
        'type': 'object',
        'properties': {},
      };

  @override
  Future<ToolResult> execute(ToolCall call) async {
    await Future<void>.delayed(const Duration(seconds: 10));
    return ToolResult(toolCallId: call.id, content: '完成');
  }
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
    test('findTool 穿透截断装饰器正确获取 AskUserTool 并设置 handler', () async {
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
      final result = await askTool.execute(ToolCall(
        id: '1',
        name: 'ask_user',
        arguments: {
          'question': '测试问题',
          'options': ['A', 'B'],
        },
      ));

      expect(result.isError, isFalse);
      expect(handlerCalled, isTrue);
    });

    test('findTool 支持穿透多层装饰器嵌套获取目标工具', () {
      final askTool = AskUserTool();
      final multiWrapped = TruncatingAgentTool(
        TruncatingAgentTool(
          TruncatingAgentTool(
            askTool,
            maxChars: 500,
          ),
          maxChars: 1000,
        ),
        maxChars: 2000,
      );
      final service = AgentService(
        settingsService: _FakeSettingsService(provider),
        tools: [_SlowNonInteractiveTool(), multiWrapped],
      );

      expect(service.findTool<AskUserTool>(), isNotNull);
      expect(identical(service.findTool<AskUserTool>(), askTool), isTrue);
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

    test('非交互式工具受单工具超时限制并回喂超时错误', () {
      fakeAsync((async) {
        final slowTool = _SlowNonInteractiveTool();
        var round = 0;
        AgentResponse? response;
        late List<openai.ChatMessage> secondRoundMessages;

        final service = AgentService(
          settingsService: _FakeSettingsService(provider),
          tools: [slowTool],
          singleToolTimeout: const Duration(seconds: 5),
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
                  callId: 'call_slow_1',
                  toolName: 'slow_tool',
                  rawArguments: '{}',
                ),
              ]);
            } else {
              secondRoundMessages = messages;
              return _textCompletion('工具超时后正常恢复');
            }
          },
        );

        service.runAgent(userMessage: '执行慢任务').then((res) {
          response = res;
        });

        // 推进 6 秒（超过 5 秒单工具超时）
        async.elapse(const Duration(seconds: 6));

        expect(response, isNotNull);
        expect(response!.content, '工具超时后正常恢复');
        expect(round, 2);
        final toolMsg = secondRoundMessages.firstWhere(
          (m) => m is openai.ToolMessage,
        ) as openai.ToolMessage;
        expect(toolMsg.content, contains('工具执行超时'));
      });
    });

    test('交互式工具不受单工具超时拦截并完成 runAgent 完整链路', () {
      fakeAsync((async) {
        final askTool = AskUserTool();
        expect(askTool.isInteractive, isTrue);
        var round = 0;
        AgentResponse? response;

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
                  callId: 'call_ask_2',
                  toolName: 'ask_user',
                  rawArguments: jsonEncode({
                    'question': '请选择分类',
                    'options': ['A', 'B'],
                  }),
                ),
              ]);
            } else {
              return _textCompletion('已完成分类');
            }
          },
        );

        service.setAskUserHandler((request) async {
          // 模拟用户思考 60 秒（超过 45 秒默认单工具超时限制）
          await Future<void>.delayed(const Duration(seconds: 60));
          return AskUserResponse.selected(['A']);
        });

        service.runAgent(userMessage: '请帮忙分类').then((res) {
          response = res;
        });

        // 推进 65 秒（超过 45 秒单工具超时）
        async.elapse(const Duration(seconds: 65));

        expect(response, isNotNull);
        expect(response!.content, '已完成分类');
        expect(
          response!.toolExecutions
              .any((e) => e.call.name == 'ask_user' && !e.result.isError),
          isTrue,
        );
        expect(
          response!.toolExecutions.any((e) => e.result.isError),
          isFalse,
        );
        expect(round, 2);
      });
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
