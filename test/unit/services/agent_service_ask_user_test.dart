import 'dart:async';
import 'dart:convert';

import 'package:fake_async/fake_async.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openai_dart/openai_dart.dart' as openai;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:thoughtecho/models/agent_memory.dart';
import 'package:thoughtecho/models/ai_provider_settings.dart';
import 'package:thoughtecho/models/multi_ai_settings.dart';
import 'package:thoughtecho/services/agent_memory_service.dart';
import 'package:thoughtecho/services/agent_service.dart';
import 'package:thoughtecho/services/agent_tool.dart';
import 'package:thoughtecho/services/agent_tools/ask_user_tool.dart';
import 'package:thoughtecho/services/agent_tools/remember_tool.dart';
import 'package:thoughtecho/services/agent_tools/truncating_agent_tool.dart';
import 'package:thoughtecho/services/settings_service.dart';

import 'agent_tools/memory_tool_harness.dart';

class _FakeSettingsService extends ChangeNotifier implements SettingsService {
  _FakeSettingsService(this._provider);

  final AIProviderSettings _provider;

  @override
  String? get localeCode => 'zh';

  @override
  bool get agentMemoryEnabled => true;

  @override
  String get userNickname => '';

  @override
  MultiAISettings get multiAISettings => MultiAISettings(
        providers: [_provider],
        currentProviderId: _provider.id,
      );

  @override
  void setIdentityAliasesProvider(Set<String> Function()? provider) {}

  @override
  void refreshIdentityAliases() {}

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
  setUpAll(() {
    MemoryToolHarness.initializeBinding();
  });

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

  group('AgentService ask_user 与待确认笔名/称谓闭环', () {
    late _FakeSettingsService settingsService;
    late AgentMemoryService memory;

    setUp(() async {
      settingsService = _FakeSettingsService(provider);
      memory = AgentMemoryService(
        settingsService: settingsService,
        databasePath: inMemoryDatabasePath,
      );
    });

    tearDown(() async {
      memory.dispose();
    });

    test('系统提示词包含存疑/待确认笔名通过 ask_user 核实与 remember 闭环的指导', () {
      final askTool = AskUserTool();
      final service = AgentService(
        settingsService: settingsService,
        tools: [askTool],
        memoryService: memory,
      );

      final prompt = service.buildSystemPrompt(memoryEnabled: true);
      expect(prompt, contains('待确认笔名'));
      expect(prompt, contains('（存疑，待确认）'));
      expect(prompt, contains('ask_user'));
      expect(prompt, contains('replaces_id'));
    });

    test('Agent 流程检测到存疑笔名画像时，通过 ask_user 向用户核实并调用 remember 完成闭环更新', () async {
      // 1. 初始化画像中的存疑待确认别名
      final pendingEntry = await memory.rememberProfile(
        kind: AgentMemoryKind.identity,
        directive: '待确认笔名：阿澈（存疑，待确认）',
      );
      expect(pendingEntry, isNotNull);

      final askTool = AskUserTool();
      final rememberTool = RememberTool(memory);

      var round = 0;
      late List<openai.ChatMessage> firstRoundMessages;
      late List<openai.ChatMessage> secondRoundMessages;

      final service = AgentService(
        settingsService: settingsService,
        tools: [askTool, rememberTool],
        memoryService: memory,
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
            firstRoundMessages = messages;
            // 第一轮：模型根据存疑画像与提示词指导，调用 ask_user 发起核实
            return _toolCallCompletion([
              _rawToolCall(
                callId: 'call_ask_alias',
                toolName: 'ask_user',
                rawArguments: jsonEncode({
                  'question': '注意到您的笔记中经常署名阿澈，请问这是您的笔名或常用称谓吗？',
                  'options': ['是的，这是我的笔名', '不是我的笔名'],
                }),
              ),
            ]);
          } else if (round == 2) {
            secondRoundMessages = messages;
            // 第二轮：收到确认选项后，调用 remember 传入 replaces_id 确认为正式笔名
            return _toolCallCompletion([
              _rawToolCall(
                callId: 'call_remember_alias',
                toolName: 'remember',
                rawArguments: jsonEncode({
                  'action': 'add',
                  'layer': 'profile',
                  'kind': 'identity',
                  'content': '笔名为「阿澈」',
                  'replaces_id': pendingEntry.id,
                }),
              ),
            ]);
          } else {
            return _textCompletion('好的，已为您确认笔名为阿澈，后续交流我会以此称呼您。');
          }
        },
      );

      service.setAskUserHandler((request) async {
        expect(request.question, contains('署名阿澈'));
        expect(request.options, contains('是的，这是我的笔名'));
        return AskUserResponse.selected(['是的，这是我的笔名']);
      });

      final response = await service.runAgent(userMessage: '你好，帮我看看最近的笔记');

      expect(response.content, contains('已为您确认笔名为阿澈'));
      expect(round, 3);

      // 验证第一轮输入包含了系统提示词指导与存疑画像
      final systemMsg = firstRoundMessages.first as openai.SystemMessage;
      expect(systemMsg.content, contains('待确认笔名'));
      expect(systemMsg.content, contains('ask_user'));
      expect(
        firstRoundMessages.any((m) =>
            m is openai.UserMessage &&
            m.content.toString().contains('待确认笔名：阿澈（存疑，待确认）')),
        isTrue,
      );

      // 验证第二轮回喂了 ask_user 的选择结果
      final askToolMsg = secondRoundMessages.firstWhere(
        (m) => m is openai.ToolMessage && m.toolCallId == 'call_ask_alias',
      ) as openai.ToolMessage;
      expect(askToolMsg.content, contains('是的，这是我的笔名'));

      // 验证最终记忆状态：存疑条目被正式笔名 supersede
      final activeProfile = await memory.activeProfile();
      expect(activeProfile.any((e) => e.directive == '笔名为「阿澈」'), isTrue);
      expect(
        activeProfile.any((e) => e.directive.contains('（存疑，待确认）')),
        isFalse,
      );
    });

    test('Agent 流程中用户否认存疑笔名时，通过 remember 清除该条目', () async {
      final pendingEntry = await memory.rememberProfile(
        kind: AgentMemoryKind.identity,
        directive: '待确认笔名：阿澈（存疑，待确认）',
      );
      expect(pendingEntry, isNotNull);

      final askTool = AskUserTool();
      final rememberTool = RememberTool(memory);

      var round = 0;
      final service = AgentService(
        settingsService: settingsService,
        tools: [askTool, rememberTool],
        memoryService: memory,
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
                callId: 'call_ask_deny',
                toolName: 'ask_user',
                rawArguments: jsonEncode({
                  'question': '注意到您的笔记中署名阿澈，请问这是您的笔名吗？',
                  'options': ['是的，这是我的笔名', '不是我的笔名'],
                }),
              ),
            ]);
          } else if (round == 2) {
            return _toolCallCompletion([
              _rawToolCall(
                callId: 'call_delete_alias',
                toolName: 'remember',
                rawArguments: jsonEncode({
                  'action': 'delete',
                  'id': pendingEntry.id,
                }),
              ),
            ]);
          } else {
            return _textCompletion('好的，已清除该候选笔名，不会以此称呼您。');
          }
        },
      );

      service.setAskUserHandler((request) async {
        return AskUserResponse.selected(['不是我的笔名']);
      });

      final response = await service.runAgent(userMessage: '你好');

      expect(response.content, contains('已清除该候选笔名'));
      expect(round, 3);

      final activeProfile = await memory.activeProfile();
      expect(
        activeProfile.any((e) => e.directive.contains('阿澈')),
        isFalse,
      );
    });
  });
}
