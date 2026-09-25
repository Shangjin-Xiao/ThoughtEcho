import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/services/agent_tool.dart';
import 'package:thoughtecho/services/agent_tools/ask_user_tool.dart';

ToolCall _toolCall(Map<String, Object?> arguments, {String id = 'call_1'}) {
  return ToolCall(
    id: id,
    name: 'ask_user',
    arguments: arguments,
  );
}

Map<String, Object?> _question(
  String question, {
  String? header,
  required List<Object?> options,
  bool multiSelect = false,
}) {
  return {
    'question': question,
    if (header != null) 'header': header,
    'options': options,
    'multi_select': multiSelect,
  };
}

Map<String, Object?> _option(String label, [String description = '']) {
  return {
    'label': label,
    if (description.isNotEmpty) 'description': description,
  };
}

void main() {
  group('AskUserTool - 静态定义与元数据', () {
    late AskUserTool tool;

    setUp(() {
      tool = AskUserTool();
    });

    test('工具名称与特性契约', () {
      expect(tool.name, 'ask_user');
      expect(tool.isReadOnly, isTrue);
      expect(tool.isConcurrencySafe, isFalse);
      expect(tool.isInteractive, isTrue);
    });

    test('参数 Schema 声明 questions 与单问题兼容字段', () {
      final schema = tool.parametersSchema;
      expect(schema['type'], 'object');
      final properties = schema['properties'] as Map<String, Object?>;
      expect(properties.containsKey('questions'), isTrue);
      expect(properties.containsKey('question'), isTrue);
      expect(properties.containsKey('header'), isTrue);
      expect(properties.containsKey('options'), isTrue);
      expect(properties.containsKey('multi_select'), isTrue);
    });

    test('上限常量与 Claude Code 对齐', () {
      expect(AskUserTool.maxQuestions, 4);
      expect(AskUserTool.minOptions, 2);
      expect(AskUserTool.maxOptions, 4);
      expect(AskUserTool.maxHeaderLength, 12);
    });
  });

  group('AskUserTool - 参数校验', () {
    late AskUserTool tool;

    setUp(() {
      tool = AskUserTool();
    });

    test('两种写法都缺失时报错', () async {
      final result = await tool.execute(_toolCall({}));
      expect(result.isError, isTrue);
      expect(result.content, contains('questions'));
      expect(result.content, contains('question'));
    });

    test('question 为空字符串时报错', () async {
      final result = await tool.execute(_toolCall({
        'question': '   ',
        'options': ['选项A', '选项B'],
      }));
      expect(result.isError, isTrue);
      expect(result.content, contains('question'));
    });

    test('缺少 options 参数时报错', () async {
      final result = await tool.execute(_toolCall({
        'question': '你喜欢什么？',
      }));
      expect(result.isError, isTrue);
      expect(result.content, contains('options'));
    });

    test('options 不是数组时报错', () async {
      final result = await tool.execute(_toolCall({
        'question': '你喜欢什么？',
        'options': '不是数组',
      }));
      expect(result.isError, isTrue);
    });

    test('options 少于 2 个选项时报错', () async {
      final result = await tool.execute(_toolCall({
        'question': '请选择',
        'options': ['只有一项'],
      }));
      expect(result.isError, isTrue);
      expect(result.content, contains('2 到 4 个有效选项'));
    });

    test('options 超过 4 个选项时报错', () async {
      final result = await tool.execute(_toolCall({
        'question': '请选择',
        'options': ['A', 'B', 'C', 'D', 'E'],
      }));
      expect(result.isError, isTrue);
      expect(result.content, contains('2 到 4 个有效选项'));
    });

    test('options 包含重复项时报错', () async {
      final result = await tool.execute(_toolCall({
        'question': '请选择',
        'options': ['重复项', '重复项'],
      }));
      expect(result.isError, isTrue);
      expect(result.content, contains('不能重复'));
    });

    test('options 里手写 Other 兜底选项时报错', () async {
      final result = await tool.execute(_toolCall({
        'question': '请选择',
        'options': ['A', 'Other'],
      }));
      expect(result.isError, isTrue);
      expect(result.content, contains('自定义输入'));
    });

    test('header 超过 12 个字符时报错', () async {
      final result = await tool.execute(_toolCall({
        'question': '请选择',
        'header': '这是一个超长的分类标题文本',
        'options': ['A', 'B'],
      }));
      expect(result.isError, isTrue);
      expect(result.content, contains('header'));
    });

    test('questions 超过 4 个问题时报错', () async {
      final result = await tool.execute(_toolCall({
        'questions': [
          for (var i = 0; i < 5; i++) _question('问题$i？', options: ['A', 'B']),
        ],
      }));
      expect(result.isError, isTrue);
      expect(result.content, contains('最多包含 4 个问题'));
    });

    test('questions 存在重复问题时报错', () async {
      final result = await tool.execute(_toolCall({
        'questions': [
          _question('相同的问题？', options: ['A', 'B']),
          _question('相同的问题？', options: ['C', 'D']),
        ],
      }));
      expect(result.isError, isTrue);
      expect(result.content, contains('重复的问题'));
    });

    test('questions 中某个问题选项不足时定位到该问题', () async {
      final result = await tool.execute(_toolCall({
        'questions': [
          _question('第一个问题？', options: ['A', 'B']),
          _question('第二个问题？', options: ['只有一项']),
        ],
      }));
      expect(result.isError, isTrue);
      expect(result.content, contains('第 2 个问题'));
    });

    test('选项对象缺少 label 时视为无效选项', () async {
      final result = await tool.execute(_toolCall({
        'questions': [
          _question('请选择？', options: [
            {'description': '没有标题的选项'},
          ]),
        ],
      }));
      expect(result.isError, isTrue);
      expect(result.content, contains('有效选项'));
    });
  });

  group('AskUserTool - 交互与回复处理', () {
    test('未配置 promptHandler 时返回友好错误提示', () async {
      final tool = AskUserTool();
      final result = await tool.execute(_toolCall({
        'question': '请选择风格',
        'options': ['纸墨', '素笺'],
      }));
      expect(result.isError, isTrue);
      expect(result.content, contains('未配置用户交互处理程序'));
    });

    test('单选选项回复正常转换为工具结果', () async {
      AskUserRequest? capturedRequest;
      final tool = AskUserTool(
        promptHandler: (request) async {
          capturedRequest = request;
          return AskUserResponse.selected(['纸墨']);
        },
      );

      final result = await tool.execute(_toolCall({
        'header': '风格设置',
        'question': '请选择主题风格',
        'options': ['纸墨', '素笺', '现代'],
        'multi_select': false,
      }));

      expect(result.isError, isFalse);
      expect(result.content, '用户选择了：纸墨');
      expect(capturedRequest?.header, '风格设置');
      expect(capturedRequest?.question, '请选择主题风格');
      expect(capturedRequest?.options, ['纸墨', '素笺', '现代']);
      expect(capturedRequest?.multiSelect, isFalse);
    });

    test('选项对象携带的 description 正确透传给处理程序', () async {
      AskUserRequest? capturedRequest;
      final tool = AskUserTool(
        promptHandler: (request) async {
          capturedRequest = request;
          return AskUserResponse.selected(['OAuth']);
        },
      );

      final result = await tool.execute(_toolCall({
        'questions': [
          _question('用哪种鉴权？', header: '鉴权', options: [
            _option('OAuth', '行业标准，支持多供应商'),
            _option('JWT', '无状态，适合 API'),
          ]),
        ],
      }));

      expect(result.isError, isFalse);
      expect(result.content, '用户选择了：OAuth');
      final captured = capturedRequest!;
      expect(captured.questions.length, 1);
      expect(
        captured.questions.first.options.first,
        const AskUserOption(label: 'OAuth', description: '行业标准，支持多供应商'),
      );
    });

    test('多选选项回复正常格式化为中文顿号拼接', () async {
      final tool = AskUserTool(
        promptHandler: (request) async {
          expect(request.multiSelect, isTrue);
          return AskUserResponse.selected(['生活随笔', '读书笔记']);
        },
      );

      final result = await tool.execute(_toolCall({
        'question': '选择包含的分类',
        'options': ['工作复盘', '生活随笔', '读书笔记'],
        'multi_select': true,
      }));

      expect(result.isError, isFalse);
      expect(result.content, '用户选择了：生活随笔、读书笔记');
    });

    test('多问题一次返回各问题答案并逐条格式化', () async {
      final tool = AskUserTool(
        promptHandler: (request) async {
          expect(request.questions.length, 2);
          return const AskUserResponse(
            answers: [
              AskUserAnswer(selectedOptions: ['OAuth']),
              AskUserAnswer(customText: '用公司统一的 SSO'),
            ],
          );
        },
      );

      final result = await tool.execute(_toolCall({
        'questions': [
          _question('用哪种鉴权？', options: ['OAuth', 'JWT']),
          _question('还有什么补充？', options: ['无', '稍后定']),
        ],
      }));

      expect(result.isError, isFalse);
      expect(
        result.content,
        '用户回答了 2 个问题：\n'
        '1. 「用哪种鉴权？」→选择了：OAuth\n'
        '2. 「还有什么补充？」→回复：用公司统一的 SSO',
      );
    });

    test('多问题中未作答的问题标记为未作答', () async {
      final tool = AskUserTool(
        promptHandler: (request) async {
          return const AskUserResponse(
            answers: [
              AskUserAnswer(selectedOptions: ['A']),
              AskUserAnswer(),
            ],
          );
        },
      );

      final result = await tool.execute(_toolCall({
        'questions': [
          _question('第一问？', options: ['A', 'B']),
          _question('第二问？', options: ['C', 'D']),
        ],
      }));

      expect(result.isError, isFalse);
      expect(result.content, contains('2. 「第二问？」→未作答'));
    });

    test('自定义文本回复正常返回', () async {
      final tool = AskUserTool(
        promptHandler: (request) async {
          return AskUserResponse.custom('我想做年度目标规划');
        },
      );

      final result = await tool.execute(_toolCall({
        'question': '请选择笔记主题',
        'options': ['生活', '工作'],
      }));

      expect(result.isError, isFalse);
      expect(result.content, '用户输入了自定义回复：我想做年度目标规划');
    });

    test('同一问题同时有选项与自定义时自定义优先（互斥）', () async {
      final tool = AskUserTool(
        promptHandler: (request) async {
          return const AskUserResponse(
            answers: [
              AskUserAnswer(
                selectedOptions: ['读书随笔'],
                customText: '关于《百年孤独》的随笔',
              ),
            ],
          );
        },
      );

      final result = await tool.execute(_toolCall({
        'question': '请选择类型',
        'options': ['生活随笔', '读书随笔'],
      }));

      expect(result.isError, isFalse);
      expect(result.content, '用户输入了自定义回复：关于《百年孤独》的随笔');
    });

    test('用户取消选择时返回清晰的取消结果', () async {
      final tool = AskUserTool(
        promptHandler: (request) async {
          return AskUserResponse.cancelled();
        },
      );

      final result = await tool.execute(_toolCall({
        'question': '是否继续？',
        'options': ['确认', '放弃'],
      }));

      expect(result.isError, isFalse);
      expect(result.content, '用户取消了本次选择。');
    });

    test('cancelActivePrompt 在等待期间调用能触发取消完成', () async {
      final completer = Completer<void>();
      final tool = AskUserTool(
        promptHandler: (request) async {
          completer.complete();
          // 挂起不返回，等待外部取消
          await Completer<void>().future;
          return AskUserResponse.selected(['A']);
        },
      );

      final futureResult = tool.execute(_toolCall({
        'question': '请选择？',
        'options': ['A', 'B'],
      }));

      await completer.future;
      tool.cancelActivePrompt();

      final result = await futureResult.timeout(const Duration(seconds: 3));
      expect(result.content, '用户取消了本次选择。');
    });

    test('cancel() 方法正确委托给 cancelActivePrompt()', () async {
      final completer = Completer<void>();
      final tool = AskUserTool(
        promptHandler: (request) async {
          completer.complete();
          await Completer<void>().future;
          return AskUserResponse.selected(['A']);
        },
      );

      final futureResult = tool.execute(_toolCall({
        'question': '请选择？',
        'options': ['A', 'B'],
      }));

      await completer.future;
      tool.cancel();

      final result = await futureResult.timeout(const Duration(seconds: 3));
      expect(result.content, '用户取消了本次选择。');
    });

    test('promptHandler 内部抛出异常时捕获并返回错误结果', () async {
      final tool = AskUserTool(
        promptHandler: (request) async {
          throw Exception('UI 交互异常崩溃');
        },
      );

      final result = await tool.execute(_toolCall({
        'question': '请选择',
        'options': ['A', 'B'],
      }));

      expect(result.isError, isTrue);
      expect(result.content, contains('用户交互处理异常'));
    });

    test('用户既未选择选项也未输入自定义内容且未取消时返回明确提示', () async {
      final tool = AskUserTool(
        promptHandler: (request) async {
          return const AskUserResponse();
        },
      );

      final result = await tool.execute(_toolCall({
        'question': '请选择类型',
        'options': ['生活随笔', '读书随笔'],
      }));

      expect(result.isError, isFalse);
      expect(result.content, '用户未做出有效选择。');
    });

    test('handler 同步抛错时能够被捕获并清理 _activeCompleter', () async {
      final tool = AskUserTool();
      tool.setPromptHandler((request) {
        throw StateError('同步异常测试');
      });

      final call = ToolCall(
        id: 'call-sync-err',
        name: 'ask_user',
        arguments: {
          'question': '测试？',
          'options': ['A', 'B'],
        },
      );

      final result = await tool.execute(call);
      expect(result.isError, isTrue);
      expect(result.content, contains('用户交互处理异常'));
      expect(tool.hasActivePrompt, isFalse);
    });

    test('外部 handler 返回非法选项时返回错误并拦截', () async {
      final tool = AskUserTool();
      tool.setPromptHandler((request) async => AskUserResponse(
            answers: const [
              AskUserAnswer(selectedOptions: ['C'])
            ],
          ));

      final call = ToolCall(
        id: 'call-invalid-opt',
        name: 'ask_user',
        arguments: {
          'question': '测试？',
          'options': ['A', 'B'],
        },
      );

      final result = await tool.execute(call);
      expect(result.isError, isTrue);
      expect(result.content, contains('包含无效选项：C'));
    });

    test('外部 handler 返回重复选项时返回错误并拦截', () async {
      final tool = AskUserTool();
      tool.setPromptHandler((request) async => AskUserResponse(
            answers: const [
              AskUserAnswer(selectedOptions: ['A', 'A'])
            ],
          ));

      final call = ToolCall(
        id: 'call-dup-opt',
        name: 'ask_user',
        arguments: {
          'question': '测试？',
          'options': ['A', 'B'],
          'multi_select': true,
        },
      );

      final result = await tool.execute(call);
      expect(result.isError, isTrue);
      expect(result.content, contains('包含重复选项：A'));
    });

    test('单选模式下外部 handler 返回多个选项时返回错误并拦截', () async {
      final tool = AskUserTool();
      tool.setPromptHandler((request) async => AskUserResponse(
            answers: const [
              AskUserAnswer(selectedOptions: ['A', 'B'])
            ],
          ));

      final call = ToolCall(
        id: 'call-multi-err',
        name: 'ask_user',
        arguments: {
          'question': '测试？',
          'options': ['A', 'B'],
          'multi_select': false,
        },
      );

      final result = await tool.execute(call);
      expect(result.isError, isTrue);
      expect(result.content, contains('单选模式下不能选择多个选项'));
    });

    test('多问题中超量回答时返回错误', () async {
      final tool = AskUserTool();
      tool.setPromptHandler((request) async => const AskUserResponse(
            answers: [
              AskUserAnswer(selectedOptions: ['A']),
              AskUserAnswer(selectedOptions: ['C']),
              AskUserAnswer(selectedOptions: ['A']),
            ],
          ));

      final result = await tool.execute(_toolCall({
        'questions': [
          _question('第一问？', options: ['A', 'B']),
          _question('第二问？', options: ['C', 'D']),
        ],
      }));

      expect(result.isError, isTrue);
      expect(result.content, contains('超过了问题数量'));
    });
  });

  group('AskUserTool - 模型值语义', () {
    test('AskUserOption 解析字符串与对象两种形态', () {
      expect(
        AskUserOption.tryParse(' 纸墨 '),
        const AskUserOption(label: '纸墨'),
      );
      expect(
        AskUserOption.tryParse({'label': 'OAuth', 'description': '标准'}),
        const AskUserOption(label: 'OAuth', description: '标准'),
      );
      expect(AskUserOption.tryParse('   '), isNull);
      expect(AskUserOption.tryParse({'description': '无标题'}), isNull);
      expect(AskUserOption.tryParse(42), isNull);
    });

    test('AskUserRequest 单问题便捷访问与相等性', () {
      final req1 = AskUserRequest.single(
        toolCallId: 'call-1',
        question: 'Q',
        header: 'H',
        options: ['A', 'B'],
        multiSelect: true,
      );
      final req2 = AskUserRequest.single(
        toolCallId: 'call-1',
        question: 'Q',
        header: 'H',
        options: ['A', 'B'],
        multiSelect: true,
      );

      expect(identical(req1, req2), isFalse);
      expect(req1, equals(req2));
      expect(req1.hashCode, equals(req2.hashCode));
      expect(req1.question, 'Q');
      expect(req1.options, ['A', 'B']);
      expect(req1.multiSelect, isTrue);
      expect(req1.toString(), contains('toolCallId: call-1'));

      expect(
        req1 ==
            AskUserRequest.single(
              toolCallId: 'call-diff',
              question: 'Q',
              options: ['A', 'B'],
            ),
        isFalse,
      );
      expect(
        req1 ==
            AskUserRequest(
              toolCallId: 'call-1',
              questions: const [
                AskUserQuestion(
                  question: 'Q-diff',
                  options: [AskUserOption(label: 'A')],
                ),
              ],
            ),
        isFalse,
      );
    });

    test('AskUserResponse 兼容工厂与相等性', () {
      final resp1 = AskUserResponse.selected(['A']);
      final resp2 = AskUserResponse(
        answers: const [
          AskUserAnswer(selectedOptions: ['A'])
        ],
      );
      expect(resp1, equals(resp2));
      expect(resp1.hashCode, equals(resp2.hashCode));
      expect(resp1.selectedOptions, ['A']);
      expect(resp1.customText, isNull);
      expect(resp1.toString(), contains('selectedOptions: [A]'));

      expect(
        AskUserResponse.custom('C'),
        equals(
          const AskUserResponse(
            answers: [AskUserAnswer(customText: 'C')],
          ),
        ),
      );

      final cancelledResp1 = AskUserResponse.cancelled();
      const cancelledResp2 = AskUserResponse(isCancelled: true);
      expect(cancelledResp1, equals(cancelledResp2));
      expect(cancelledResp1.hashCode, equals(cancelledResp2.hashCode));

      expect(
        resp1 == const AskUserResponse(answers: [AskUserAnswer()]),
        isFalse,
      );
    });

    test('AskUserAnswer 有效自定义文本识别', () {
      expect(
        const AskUserAnswer(customText: '  hi  ').effectiveCustomText,
        'hi',
      );
      expect(
        const AskUserAnswer(customText: '   ').effectiveCustomText,
        isNull,
      );
      expect(const AskUserAnswer().effectiveCustomText, isNull);
    });
  });
}
