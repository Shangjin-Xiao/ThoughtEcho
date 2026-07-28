import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/models/chat_message.dart';
import 'package:thoughtecho/utils/ai_request_helper.dart';

void main() {
  group('AIRequestHelper', () {
    test('createMessages returns correct format', () {
      final helper = AIRequestHelper();
      final messages = helper.createMessages(
        systemPrompt: 'You are a helpful assistant.',
        userMessage: 'Hello world!',
      );

      expect(messages.length, 2);
      expect(messages[0],
          {'role': 'system', 'content': 'You are a helpful assistant.'});
      expect(messages[1], {'role': 'user', 'content': 'Hello world!'});
    });

    test('singleton instance is same', () {
      final helper1 = AIRequestHelper();
      final helper2 = AIRequestHelper();

      expect(identical(helper1, helper2), isTrue);
    });

    test(
        'createMessagesWithHistory appends system prompt hint for applied proposals',
        () {
      final helper = AIRequestHelper();
      final history = [
        ChatMessage(
          id: '1',
          content: 'Here is a proposal',
          isUser: false,
          role: 'assistant',
          timestamp: DateTime.now(),
          metaJson: '{"saved_note_id":"note_123","applied":true}',
        ),
      ];

      final messages = helper.createMessagesWithHistory(
        systemPrompt: 'System',
        history: history,
      );

      expect(messages.length, 2);
      expect(messages[1]['role'], 'assistant');
      expect(messages[1]['content'], contains('[系统提示：用户已采纳并应用了上述提案/编辑建议]'));
    });
  });
}
