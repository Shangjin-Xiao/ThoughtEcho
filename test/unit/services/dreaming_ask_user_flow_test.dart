import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openai_dart/openai_dart.dart' as openai;
import 'package:thoughtecho/models/agent_memory.dart';
import 'package:thoughtecho/models/ai_provider_settings.dart';
import 'package:thoughtecho/models/multi_ai_settings.dart';
import 'package:thoughtecho/models/quote_model.dart';
import 'package:thoughtecho/services/agent_service.dart';
import 'package:thoughtecho/services/agent_tools/ask_user_tool.dart';
import 'package:thoughtecho/services/agent_tools/remember_tool.dart';
import 'package:thoughtecho/services/dreaming_service.dart';
import 'package:thoughtecho/services/settings_service.dart';

import 'agent_tools/memory_tool_harness.dart';

class _FlowTestSettingsService extends ChangeNotifier
    implements SettingsService {
  _FlowTestSettingsService({
    required this.provider,
    bool memoryEnabled = true,
  }) : _agentMemoryEnabled = memoryEnabled;

  final AIProviderSettings provider;
  bool _agentMemoryEnabled;
  DateTime? _lastDreamingAt;

  @override
  bool get agentMemoryEnabled => _agentMemoryEnabled;

  @override
  Future<void> setAgentMemoryEnabled(bool enabled) async {
    _agentMemoryEnabled = enabled;
    notifyListeners();
  }

  @override
  DateTime? get lastDreamingAt => _lastDreamingAt;

  @override
  Future<void> setLastDreamingAt(DateTime? at) async {
    _lastDreamingAt = at;
    notifyListeners();
  }

  @override
  String get userNickname => '';

  @override
  String get defaultAuthor => '';

  @override
  String get defaultSource => '';

  @override
  Set<String> get userAliases => const <String>{};

  @override
  String? get localeCode => 'zh';

  @override
  MultiAISettings get multiAISettings => MultiAISettings(
        providers: [provider],
        currentProviderId: provider.id,
      );

  @override
  void setIdentityAliasesProvider(Set<String> Function()? provider) {}

  @override
  void refreshIdentityAliases() {}

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

openai.ToolCall _funcCall({
  required String callId,
  required String toolName,
  required Map<String, dynamic> arguments,
}) {
  return openai.ToolCall.functionCall(
    id: callId,
    call: openai.FunctionCall(
      name: toolName,
      arguments: jsonEncode(arguments),
    ),
  );
}

openai.ChatCompletion _toolCompletion(List<openai.ToolCall> toolCalls) {
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

  group('Dreaming 到 ask_user 笔名确认闭环端到端集成测试', () {
    final harness = MemoryToolHarness();

    setUp(harness.setUp);
    tearDown(harness.tearDown);
    tearDownAll(harness.tearDownAll);

    const provider = AIProviderSettings(
      id: 'openai-test',
      name: 'Test Provider',
      apiUrl: 'https://api.openai.com/v1/chat/completions',
      model: 'gpt-4o',
    );

    test(
        'Dreaming 提取存疑笔名 -> unconfirmed 画像条目 -> Thoughter 触发 ask_user -> 用户确认 -> remember(replaces_id) 正式转正',
        () async {
      final settings = _FlowTestSettingsService(provider: provider);

      // 1. 构造中置信度笔名笔记集合：
      // - 7 篇名家经典摘录（外部作者与出版物）
      // - 3 篇署名为「小舟」的笔记，其中 1 篇为个人随笔（selfMarkerCount=1），2 篇无个人出处与外部出处（externalWorkCount=0）
      // 触发 Dreaming inferAliasesDetailed 的 moderateConfidence 条件（count>=3, selfMarker>=1, external=0）
      final now = DateTime(2026, 9, 13, 10, 0, 0);
      final notes = <Quote>[
        // 名家经典摘录 (7 篇)
        ...List.generate(
          7,
          (i) => Quote(
            id: 'excerpt-$i',
            content: '经典作品摘录片段第 $i 段文字。',
            date: now.subtract(Duration(days: 10 + i)).toIso8601String(),
            sourceAuthor: '加缪',
            sourceWork: '夏天集',
          ),
        ),
        // 小舟署名笔记 (3 篇：1篇含个人出处随笔，2篇为碎片生活)
        Quote(
          id: 'zhou-1',
          content: '夜跑操场跑了五圈，深秋夜风很凉爽。——小舟随笔',
          date: now.subtract(const Duration(days: 2)).toIso8601String(),
          sourceAuthor: '小舟',
          sourceWork: '随笔',
        ),
        Quote(
          id: 'zhou-2',
          content: '今天在大学城自习室复习高数微积分。',
          date: now.subtract(const Duration(days: 3)).toIso8601String(),
          sourceAuthor: '小舟',
        ),
        Quote(
          id: 'zhou-3',
          content: '食堂二楼的生煎包刚出锅，香气扑鼻。',
          date: now.subtract(const Duration(days: 4)).toIso8601String(),
          sourceAuthor: '小舟',
        ),
      ];

      // 2. 执行 DreamingService 离线提炼
      const dreamingOutput = '''
{
  "taste": "偏好加缪等存在主义文学名篇与经典散文",
  "voice": "日常习惯记录 30-80 字真诚的校园生活碎句",
  "recent": "近期在操场夜跑与自习备考",
  "user_alias": null
}
''';

      final dreamingService = DreamingService(
        settingsService: settings,
        memoryService: harness.memory,
        loadNotes: ({required start, required end, required limit}) async =>
            notes,
        complete: ({required systemPrompt, required userMessage}) async =>
            dreamingOutput,
      );

      final dreamingResult = await dreamingService.run(now: now);
      expect(dreamingResult, DreamingOutcome.updated);

      // 3. 验证 Dreaming 写入了存疑笔名画像（unconfirmed 状态）
      final profileBeforeChat = await harness.memory.activeProfile();
      final pendingEntry = profileBeforeChat.firstWhere(
        (e) =>
            e.kind == AgentMemoryKind.identity &&
            e.directive.contains('待确认笔名：小舟'),
      );
      expect(pendingEntry.directive, '待确认笔名：小舟（存疑，待确认）');
      expect(pendingEntry.source, 'dreaming_statistical_moderate');
      expect(pendingEntry.status, AgentMemoryStatus.active);

      // 4. 构建 AgentService，挂载 AskUserTool 与 RememberTool
      final askUserTool = AskUserTool();
      final rememberTool = RememberTool(harness.memory);

      var round = 0;
      final agentService = AgentService(
        settingsService: settings,
        memoryService: harness.memory,
        tools: [askUserTool, rememberTool],
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
            // 第 1 轮：模型在 user_profile 中看到存疑笔名，按照规范调用 ask_user 询问用户
            final sysMsg = messages.firstWhere((m) => m is openai.SystemMessage)
                as openai.SystemMessage;
            expect(sysMsg.content, contains('待确认笔名/称谓核实闭环'));

            return _toolCompletion([
              _funcCall(
                callId: 'call_ask_user_01',
                toolName: 'ask_user',
                arguments: {
                  'question': '注意到您的笔记中经常署名小舟，请问这是您的笔名或常用称谓吗？',
                  'options': ['是的，这是我的笔名', '不是我的笔名'],
                },
              ),
            ]);
          } else if (round == 2) {
            // 第 2 轮：用户确认后，模型调用 remember 工具，传入待确认条目的 ID 进行原位替换 (replaces_id)
            return _toolCompletion([
              _funcCall(
                callId: 'call_remember_02',
                toolName: 'remember',
                arguments: {
                  'action': 'add',
                  'kind': 'identity',
                  'content': '称呼用户为「小舟」',
                  'replaces_id': pendingEntry.id,
                },
              ),
            ]);
          } else {
            // 第 3 轮：模型收到 remember 成功执行结果，输出友好文本响应
            return _textCompletion('好的，小舟！已为您正式记录好称呼。');
          }
        },
      );

      // 模拟用户交互回调：用户选择「是的，这是我的笔名」
      var askUserHandlerInvoked = false;
      agentService.setAskUserHandler((request) async {
        askUserHandlerInvoked = true;
        expect(request.question, contains('小舟'));
        expect(request.options, contains('是的，这是我的笔名'));
        return AskUserResponse.selected(['是的，这是我的笔名']);
      });

      // 5. 执行对话
      final response = await agentService.runAgent(userMessage: '嗨，今天复习好累呀');
      expect(askUserHandlerInvoked, isTrue);
      expect(response.content, contains('小舟'));

      // 6. 核心断言：验证画像状态闭环转正
      final profileAfterChat = await harness.memory.activeProfile();

      // 旧的「待确认笔名：小舟（存疑，待确认）」必须不再 active
      expect(
        profileAfterChat.any((e) => e.directive.contains('（存疑，待确认）')),
        isFalse,
      );

      // 新的「称呼用户为「小舟」」必须已成为 active 身份画像
      final confirmedEntry = profileAfterChat.firstWhere(
        (e) => e.kind == AgentMemoryKind.identity && e.directive == '称呼用户为「小舟」',
      );
      expect(confirmedEntry.status, AgentMemoryStatus.active);

      // 验证历史条目中，旧条目的状态已被标记为 superseded（原位覆盖），且被正确关联
      final allEntries = await harness.memory.allProfileEntries();
      final oldEntryInDb =
          allEntries.firstWhere((e) => e.id == pendingEntry.id);
      expect(oldEntryInDb.status, AgentMemoryStatus.superseded);
    });

    test(
        'Dreaming 提取存疑笔名 -> unconfirmed 画像条目 -> Thoughter 触发 ask_user -> 用户否认 -> remember 删除存疑条目',
        () async {
      final settings = _FlowTestSettingsService(provider: provider);

      // 1. 直接预先写入一条存疑条目
      await harness.memory.registerInferredAlias(
        '神秘客',
        source: 'dreaming_statistical_moderate',
        unconfirmed: true,
      );

      final profileBefore = await harness.memory.activeProfile();
      final pendingEntry = profileBefore.firstWhere(
        (e) => e.directive == '待确认笔名：神秘客（存疑，待确认）',
      );

      final askUserTool = AskUserTool();
      final rememberTool = RememberTool(harness.memory);

      var round = 0;
      final agentService = AgentService(
        settingsService: settings,
        memoryService: harness.memory,
        tools: [askUserTool, rememberTool],
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
            return _toolCompletion([
              _funcCall(
                callId: 'call_ask_user_deny',
                toolName: 'ask_user',
                arguments: {
                  'question': '请问「神秘客」是您的笔名吗？',
                  'options': ['是的，这是我的笔名', '不是我的笔名'],
                },
              ),
            ]);
          } else if (round == 2) {
            // 用户否认，模型调用 remember delete 清除该待确认条目
            return _toolCompletion([
              _funcCall(
                callId: 'call_remember_delete',
                toolName: 'remember',
                arguments: {
                  'action': 'delete',
                  'kind': 'identity',
                  'id': pendingEntry.id,
                },
              ),
            ]);
          } else {
            return _textCompletion('明白了，已清除该误记的笔名候选。');
          }
        },
      );

      agentService.setAskUserHandler((request) async {
        return AskUserResponse.selected(['不是我的笔名']);
      });

      final reply = await agentService.runAgent(userMessage: '你好');
      expect(reply.content, contains('已清除'));

      // 验证存疑条目已不再活跃
      final profileAfter = await harness.memory.activeProfile();
      expect(profileAfter.any((e) => e.directive.contains('神秘客')), isFalse);

      final allEntries = await harness.memory.allProfileEntries();
      expect(allEntries.any((e) => e.id == pendingEntry.id), isFalse);
    });
  });
}
