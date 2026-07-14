import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/utils/ai_request_helper.dart';
import 'package:thoughtecho/models/chat_message.dart';

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
        'createMessagesWithHistory returns only system prompt when history is empty',
        () {
      final helper = AIRequestHelper();
      final messages = helper.createMessagesWithHistory(
        systemPrompt: 'System',
        history: [],
      );

      expect(messages.length, 1);
      expect(messages[0], {'role': 'system', 'content': 'System'});
    });

    test(
        'createMessagesWithHistory properly handles valid history messages and respects singleMessageCap',
        () {
      final helper = AIRequestHelper();
      final history = [
        ChatMessage(
          id: '1',
          content: 'Hello',
          isUser: true,
          timestamp: DateTime.now(),
        ),
        ChatMessage(
          id: '2',
          content: 'Hi there',
          isUser: false,
          timestamp: DateTime.now(),
        ),
        ChatMessage(
          id: '3',
          content: 'Ignored because not included',
          isUser: true,
          includedInContext: false,
          timestamp: DateTime.now(),
        ),
        ChatMessage(
          id: '4',
          content: 'Ignored because loading',
          isUser: false,
          isLoading: true,
          timestamp: DateTime.now(),
        ),
      ];

      final messages = helper.createMessagesWithHistory(
        systemPrompt: 'System',
        history: history,
        singleMessageCap: 5, // Test truncating
      );

      expect(messages.length, 3);
      expect(messages[0], {'role': 'system', 'content': 'System'});
      // Message 1 fits perfectly
      expect(messages[1], {'role': 'user', 'content': 'Hello'});
      // Message 2 should be truncated because length (8) > 5
      expect(messages[2], {'role': 'assistant', 'content': 'Hi th...'});
    });

    test('createMessagesWithHistory drops oldest messages when budget exceeded',
        () {
      final helper = AIRequestHelper();
      final history = [
        ChatMessage(
          id: '1',
          content: '12345',
          isUser: true,
          timestamp: DateTime.now(),
        ),
        ChatMessage(
          id: '2',
          content: '67890',
          isUser: false,
          timestamp: DateTime.now(),
        ),
      ];

      final messages = helper.createMessagesWithHistory(
        systemPrompt: 'System',
        history: history,
        maxChars: 8, // Can fit message 2, but not both
      );

      expect(messages.length, 2);
      expect(messages[0], {'role': 'system', 'content': 'System'});
      expect(messages[1], {'role': 'assistant', 'content': '67890'});
    });
  });
}
