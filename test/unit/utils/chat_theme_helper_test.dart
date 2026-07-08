import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/utils/chat_theme_helper.dart';
import 'package:flutter_chat_types/flutter_chat_types.dart' as types;

void main() {
  group('ChatThemeHelper', () {
    testWidgets('createTextMessageBuilder applies correct styles',
        (WidgetTester tester) async {
      final theme = ThemeData(
        colorScheme: const ColorScheme.light(
          primary: Colors.blue,
          onPrimary: Colors.white,
          surface: Colors.grey,
          onSurface: Colors.black,
        ),
      );

      final builder = ChatThemeHelper.createTextMessageBuilder(theme);

      final message = types.TextMessage(
        id: '1',
        author: const types.User(id: '1'),
        text: 'Test message',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                return builder(context, message, 0, isSentByMe: true);
              },
            ),
          ),
        ),
      );

      final container = tester.widget<Container>(find.byType(Container));
      final decoration = container.decoration as BoxDecoration;
      expect(decoration.color, Colors.blue);

      final text = tester.widget<Text>(find.text('Test message'));
      expect(text.style?.color, Colors.white);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                return builder(context, message, 0, isSentByMe: false);
              },
            ),
          ),
        ),
      );

      final container2 = tester.widget<Container>(find.byType(Container));
      final decoration2 = container2.decoration as BoxDecoration;
      expect(decoration2.color, Colors.grey);

      final text2 = tester.widget<Text>(find.text('Test message'));
      expect(text2.style?.color, Colors.black);
    });
  });
}
