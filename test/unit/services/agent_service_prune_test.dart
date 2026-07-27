import 'package:flutter_test/flutter_test.dart';
import 'package:openai_dart/openai_dart.dart' as openai;
import 'package:thoughtecho/services/agent_service.dart';

openai.ChatMessage _assistantToolCall(String id) =>
    openai.ChatMessage.assistant(
      toolCalls: [
        openai.ToolCall.functionCall(
          id: id,
          call: openai.FunctionCall(name: 'explore_notes', arguments: '{}'),
        ),
      ],
    );

openai.ChatMessage _toolResult(String id, String content) =>
    openai.ChatMessage.tool(toolCallId: id, content: content);

List<openai.ChatMessage> _transcript(int rounds, String payload) => [
      openai.ChatMessage.system('system prompt'),
      openai.ChatMessage.user('用户问题'),
      for (var i = 0; i < rounds; i++) ...[
        _assistantToolCall('call_$i'),
        _toolResult('call_$i', '$payload$i'),
      ],
    ];

void main() {
  group('AgentService.pruneMessages', () {
    test('estimates tokens from a single conservative formula', () {
      expect(AgentService.estimateTokens(''), 0);
      expect(AgentService.estimateTokens('x' * 22), 14);
    });

    test('keeps short transcripts untouched', () {
      final messages = _transcript(3, '短结果');
      final before = List<openai.ChatMessage>.from(messages);

      expect(AgentService.pruneMessages(messages), isFalse);
      expect(messages, orderedEquals(before));
    });

    test('replaces only older tool results and protects the recent rounds', () {
      final messages = _transcript(10, '很长的工具结果' * 2000);

      expect(AgentService.pruneMessages(messages), isTrue);

      final toolMessages = messages.whereType<openai.ToolMessage>().toList();
      expect(toolMessages, hasLength(10));
      final pruned = toolMessages
          .where((m) => m.content == AgentService.prunedToolResultPlaceholder)
          .length;
      expect(pruned, 6, reason: '最近 4 轮完整保留');
      // 消息条数与顺序不变：assistant(tool_calls) 与其 tool 消息组不能被拆散
      expect(messages, hasLength(22));
      for (var i = 2; i < messages.length; i += 2) {
        expect(messages[i], isA<openai.AssistantMessage>());
        expect(messages[i + 1], isA<openai.ToolMessage>());
      }
    });

    test('is idempotent', () {
      final messages = _transcript(10, '很长的工具结果' * 2000);
      expect(AgentService.pruneMessages(messages), isTrue);
      expect(AgentService.pruneMessages(messages), isFalse);
    });

    test('never prunes system or user messages', () {
      final messages = _transcript(10, '很长的工具结果' * 2000);
      AgentService.pruneMessages(messages);
      expect(messages.first, isA<openai.SystemMessage>());
      expect(messages[1], isA<openai.UserMessage>());
    });
  });
}
