import 'package:flutter_test/flutter_test.dart';
import 'package:openai_dart/openai_dart.dart' as openai;
import 'package:thoughtecho/models/chat_message.dart';
import 'package:thoughtecho/services/openai_stream_service.dart';

/// ThoughtEcho AI 功能回归测试
///
/// 验证以下修复：
/// 1. ChatMessage.toMap() 不包含数据库不存在列
/// 2. extractTextFromCompletion 对 reasoning-only 模型回退到 reasoning
///
/// 运行：flutter test test/debug/ai_regression_test.dart
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Unit Tests', () {
    test('ChatMessage.toMap() does not include nonexistent db columns', () {
      final msg = ChatMessage(
        id: 'test-id',
        content: 'hello',
        isUser: true,
        role: 'user',
        timestamp: DateTime.now(),
        contentFormat: 'markdown',
        deltaJson: '{}',
      );
      final map = msg.toMap('session-1');

      expect(map.containsKey('content_format'), isFalse,
          reason: 'content_format column does not exist in chat_messages table');
      expect(map.containsKey('delta_json'), isFalse,
          reason: 'delta_json column does not exist in chat_messages table');
      expect(map.containsKey('id'), isTrue);
      expect(map.containsKey('session_id'), isTrue);
      expect(map.containsKey('content'), isTrue);
    });

    test('extractTextFromCompletion falls back to reasoning', () {
      final completion = openai.ChatCompletion(
        model: 'test',
        object: 'chat.completion',
        choices: [
          openai.ChatChoice(
            index: 0,
            message: openai.AssistantMessage(
              content: '',
              reasoning: 'This is the reasoning text',
            ),
          ),
        ],
      );

      final text = OpenAIStreamService.extractTextFromCompletion(completion);
      expect(text, equals('This is the reasoning text'));
    });

    test('extractTextFromCompletion prefers content over reasoning', () {
      final completion = openai.ChatCompletion(
        model: 'test',
        object: 'chat.completion',
        choices: [
          openai.ChatChoice(
            index: 0,
            message: openai.AssistantMessage(
              content: 'Actual answer',
              reasoning: 'Thinking process',
            ),
          ),
        ],
      );

      final text = OpenAIStreamService.extractTextFromCompletion(completion);
      expect(text, equals('Actual answer'));
    });

    test('extractTextFromCompletion falls back to reasoningContent', () {
      final completion = openai.ChatCompletion(
        model: 'test',
        object: 'chat.completion',
        choices: [
          openai.ChatChoice(
            index: 0,
            message: openai.AssistantMessage(
              content: '',
              reasoningContent: 'DeepSeek reasoning',
            ),
          ),
        ],
      );

      final text = OpenAIStreamService.extractTextFromCompletion(completion);
      expect(text, equals('DeepSeek reasoning'));
    });
  });
}
