import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/models/chat_message.dart';
import 'package:thoughtecho/utils/agent_history_builder.dart';

ChatMessage _text(String role, String content) => ChatMessage(
      id: '$role-$content',
      role: role,
      isUser: role == 'user',
      content: content,
      timestamp: DateTime(2026, 7, 31),
    );

ChatMessage _toolProgress(List<Map<String, Object?>> items) => ChatMessage(
      id: 'tool-progress',
      role: 'assistant',
      isUser: false,
      content: '',
      timestamp: DateTime(2026, 7, 31),
      metaJson: jsonEncode({
        'type': 'tool_progress',
        'items': items,
        'inProgress': false,
      }),
    );

void main() {
  group('AgentHistoryBuilder.build', () {
    test('保留普通文本消息', () {
      final history = AgentHistoryBuilder.build([
        _text('user', '帮我找找关于咖啡的笔记'),
        _text('assistant', '找到了 3 条'),
      ]);

      expect(history.map((m) => m.content), [
        '帮我找找关于咖啡的笔记',
        '找到了 3 条',
      ]);
    });

    test('把工具轨迹压成摘要而不是整条丢弃', () {
      // 回归：以前 `metaJson != null` 的消息被整体排除，agent 完全不知道
      // 自己上一轮查过什么。
      final history = AgentHistoryBuilder.build([
        _text('user', '我最近写了什么'),
        _toolProgress([
          {
            'toolName': 'explore_notes',
            'description': '关键词：咖啡',
            'status': 'success',
            'result': '找到 3 条笔记，均提到手冲',
          },
        ]),
        _text('assistant', '你最近写了 3 条关于手冲的笔记'),
      ]);

      expect(history.length, 3);
      final trace = history[1].content;
      expect(trace, startsWith(AgentHistoryBuilder.traceHeader));
      expect(trace, contains('explore_notes'));
      expect(trace, contains('关键词：咖啡'));
      expect(trace, contains('找到 3 条笔记，均提到手冲'));
    });

    test('工具失败也要写进轨迹，让模型知道此路不通', () {
      final history = AgentHistoryBuilder.build([
        _toolProgress([
          {
            'toolName': 'get_note_detail',
            'status': 'error',
            'result': '笔记不存在: abc',
          },
        ]),
      ]);

      expect(history.single.content, contains('失败'));
      expect(history.single.content, contains('笔记不存在: abc'));
    });

    test('跳过仍在执行中的条目', () {
      final history = AgentHistoryBuilder.build([
        _toolProgress([
          {'toolName': 'web_search', 'status': 'running'},
        ]),
      ]);

      expect(history, isEmpty);
    });

    test('没有可用条目的工具消息不产生空摘要', () {
      final history = AgentHistoryBuilder.build([
        _toolProgress(const []),
        _text('user', '在吗'),
      ]);

      expect(history.map((m) => m.content), ['在吗']);
    });

    test('按上限截断过长的工具结果', () {
      final history = AgentHistoryBuilder.build(
        [
          _toolProgress([
            {
              'toolName': 'web_fetch',
              'status': 'success',
              'result': 'x' * 5000,
            },
          ]),
        ],
        toolResultCap: 50,
      );

      expect(history.single.content.length, lessThan(200));
      expect(history.single.content, contains('已截断'));
    });

    test('保留提案卡片的正文', () {
      final proposal = ChatMessage(
        id: 'proposal',
        role: 'assistant',
        isUser: false,
        content: '建议新建一条笔记：今天的手冲记录',
        timestamp: DateTime(2026, 7, 31),
        metaJson: jsonEncode({'type': 'note_proposal'}),
      );

      final history = AgentHistoryBuilder.build([proposal]);

      expect(history.single.content, '建议新建一条笔记：今天的手冲记录');
    });

    test('跳过 system 消息、加载中消息和空消息', () {
      final history = AgentHistoryBuilder.build([
        _text('system', '你是助手'),
        ChatMessage(
          id: 'loading',
          role: 'assistant',
          isUser: false,
          content: '',
          timestamp: DateTime(2026, 7, 31),
          isLoading: true,
        ),
        _text('assistant', '   '),
        _text('user', '你好'),
      ]);

      expect(history.map((m) => m.content), ['你好']);
    });

    test('ask_user 未完成时不产生历史条目', () {
      final incomplete = ChatMessage(
        id: 'ask-1',
        role: 'assistant',
        isUser: false,
        content: '请选择分类',
        timestamp: DateTime(2026, 7, 31),
        metaJson: jsonEncode({
          'type': 'ask_user',
          'question': '请选择分类',
          'isCompleted': false,
        }),
      );

      final history = AgentHistoryBuilder.build([incomplete]);
      expect(history, isEmpty);
    });

    test('ask_user 完成选项选择后压缩成代表用户的选择摘要', () {
      final completed = ChatMessage(
        id: 'ask-2',
        role: 'assistant',
        isUser: false,
        content: '请选择分类',
        timestamp: DateTime(2026, 7, 31),
        metaJson: jsonEncode({
          'type': 'ask_user',
          'question': '请选择笔记分类',
          'isCompleted': true,
          'selectedOptions': ['生活随笔', '读书笔记'],
        }),
      );

      final history = AgentHistoryBuilder.build([completed]);
      expect(history.length, 1);
      final msg = history.single;
      expect(msg.isUser, isTrue);
      expect(msg.role, 'user');
      expect(msg.content, startsWith(AgentHistoryBuilder.askUserHeader));
      expect(msg.content, contains('请选择笔记分类'));
      expect(msg.content, contains('生活随笔、读书笔记'));
    });

    test('ask_user 完成自定义输入后压缩成用户回复', () {
      final completed = ChatMessage(
        id: 'ask-3',
        role: 'assistant',
        isUser: false,
        content: '请选择分类',
        timestamp: DateTime(2026, 7, 31),
        metaJson: jsonEncode({
          'type': 'ask_user',
          'question': '请选择分类',
          'isCompleted': true,
          'customText': '我想按项目分类',
        }),
      );

      final history = AgentHistoryBuilder.build([completed]);
      expect(history.single.content, contains('我想按项目分类'));
    });

    test('ask_user 取消选择后压缩成取消记录', () {
      final cancelled = ChatMessage(
        id: 'ask-4',
        role: 'assistant',
        isUser: false,
        content: '请选择分类',
        timestamp: DateTime(2026, 7, 31),
        metaJson: jsonEncode({
          'type': 'ask_user',
          'question': '请选择分类',
          'isCompleted': true,
          'isCancelled': true,
        }),
      );

      final history = AgentHistoryBuilder.build([cancelled]);
      expect(history.single.content, contains('用户取消了选择'));
    });
  });
}
