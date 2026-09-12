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

    test('参数 Schema 声明', () {
      final schema = tool.parametersSchema;
      expect(schema['type'], 'object');
      final properties = schema['properties'] as Map<String, Object?>;
      expect(properties.containsKey('question'), isTrue);
      expect(properties.containsKey('header'), isTrue);
      expect(properties.containsKey('options'), isTrue);
      expect(properties.containsKey('multi_select'), isTrue);
      final required = schema['required'] as List;
      expect(required, contains('question'));
      expect(required, contains('options'));
    });
  });

  group('AskUserTool - 参数校验', () {
    late AskUserTool tool;

    setUp(() {
      tool = AskUserTool();
    });

    test('缺少 question 参数时报错', () async {
      final result = await tool.execute(_toolCall({
        'options': ['选项A', '选项B'],
      }));
      expect(result.isError, isTrue);
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

    test('用户同时提供选项选择与自定义补充回复时完整保留两者', () async {
      final tool = AskUserTool(
        promptHandler: (request) async {
          return const AskUserResponse(
            selectedOptions: ['读书随笔'],
            customText: '关于《百年孤独》的随笔',
          );
        },
      );

      final result = await tool.execute(_toolCall({
        'question': '请选择类型',
        'options': ['生活随笔', '读书随笔'],
      }));

      expect(result.isError, isFalse);
      expect(
        result.content,
        '用户选择了：读书随笔，并补充回复：关于《百年孤独》的随笔',
      );
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

    test('parametersSchema 包含 minItems 和 maxItems 约束', () {
      final tool = AskUserTool();
      final optionsSchema = (tool.parametersSchema['properties']
          as Map<String, dynamic>)['options'] as Map<String, dynamic>;

      expect(optionsSchema['minItems'], 2);
      expect(optionsSchema['maxItems'], 4);
    });

    test('AskUserRequest 与 AskUserResponse 值相等性与 toString 正常工作', () {
      const req1 = AskUserRequest(
        toolCallId: 'call-1',
        question: 'Q',
        options: ['A', 'B'],
        header: 'H',
        multiSelect: true,
      );
      const req2 = AskUserRequest(
        toolCallId: 'call-1',
        question: 'Q',
        options: ['A', 'B'],
        header: 'H',
        multiSelect: true,
      );
      const req3 = AskUserRequest(
        toolCallId: 'call-2',
        question: 'Q',
        options: ['A', 'B'],
      );

      expect(req1, equals(req2));
      expect(req1.hashCode, equals(req2.hashCode));
      expect(req1 == req3, isFalse);
      expect(req1.toString(), contains('toolCallId: call-1'));

      const resp1 = AskUserResponse(
        selectedOptions: ['A'],
        customText: 'C',
        isCancelled: false,
      );
      const resp2 = AskUserResponse(
        selectedOptions: ['A'],
        customText: 'C',
        isCancelled: false,
      );
      const resp3 = AskUserResponse(isCancelled: true);

      expect(resp1, equals(resp2));
      expect(resp1.hashCode, equals(resp2.hashCode));
      expect(resp1 == resp3, isFalse);
      expect(resp1.toString(), contains('selectedOptions: [A]'));
    });
  });
}
