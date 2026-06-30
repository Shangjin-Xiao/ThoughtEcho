import 'package:flutter_test/flutter_test.dart';
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
  });
}
