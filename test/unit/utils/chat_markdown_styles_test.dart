import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/utils/chat_markdown_styles.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ChatMarkdownStyleSheet', () {
    // 准备一个测试用的 ThemeData
    final lightTheme = ThemeData(
      brightness: Brightness.light,
      colorScheme: const ColorScheme.light(
        onSurface: Colors.black87,
        surfaceContainerHighest: Color(0xFFEEEEEE),
        primary: Colors.blue,
        outline: Colors.grey,
      ),
      textTheme: const TextTheme(
        bodyLarge: TextStyle(fontSize: 16, color: Colors.black),
        bodyMedium: TextStyle(fontSize: 14, color: Colors.black54),
        headlineLarge: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
      ),
    );

    final darkTheme = ThemeData(
      brightness: Brightness.dark,
      colorScheme: const ColorScheme.dark(
        onSurface: Colors.white70,
        surface: Color(0xFF333333),
        primary: Colors.lightBlue,
        outline: Colors.white24,
      ),
      textTheme: const TextTheme(
        bodyLarge: TextStyle(fontSize: 16, color: Colors.white),
        bodyMedium: TextStyle(fontSize: 14, color: Colors.white54),
        headlineLarge: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
      ),
    );

    test('create generates styles correctly for light mode', () {
      final styleSheet =
          ChatMarkdownStyleSheet.create(lightTheme, isDarkMode: false);

      // 验证基础颜色
      expect(styleSheet.p?.color, equals(lightTheme.colorScheme.onSurface));

      // 验证代码块背景色 (浅色模式使用 surfaceContainerHighest with alpha 0.5)
      final expectedCodeBg =
          lightTheme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5);
      expect(styleSheet.code?.backgroundColor, equals(expectedCodeBg));
      expect((styleSheet.codeblockDecoration as BoxDecoration).color,
          equals(expectedCodeBg));

      // 验证引用块样式
      final expectedBlockquoteBg =
          lightTheme.colorScheme.primary.withValues(alpha: 0.08);
      expect((styleSheet.blockquoteDecoration as BoxDecoration).color,
          equals(expectedBlockquoteBg));
      expect(styleSheet.blockquotePadding,
          equals(const EdgeInsets.fromLTRB(16, 12, 16, 12)));

      // 验证其他基础属性
      expect(styleSheet.codeblockPadding, equals(const EdgeInsets.all(16)));
      expect(styleSheet.p?.fontSize, equals(16));
      expect(styleSheet.h1?.fontSize, equals(24));
    });

    test('create generates styles correctly for dark mode', () {
      final styleSheet =
          ChatMarkdownStyleSheet.create(darkTheme, isDarkMode: true);

      // 验证基础颜色
      expect(styleSheet.p?.color, equals(darkTheme.colorScheme.onSurface));

      // 验证代码块背景色 (深色模式使用 surface with alpha 0.8)
      final expectedCodeBg =
          darkTheme.colorScheme.surface.withValues(alpha: 0.8);
      expect(styleSheet.code?.backgroundColor, equals(expectedCodeBg));
      expect((styleSheet.codeblockDecoration as BoxDecoration).color,
          equals(expectedCodeBg));

      // 验证引用块样式
      final expectedBlockquoteBg =
          darkTheme.colorScheme.primary.withValues(alpha: 0.08);
      expect((styleSheet.blockquoteDecoration as BoxDecoration).color,
          equals(expectedBlockquoteBg));
    });

    test('createCodeFriendly overrides code styles correctly', () {
      final styleSheet = ChatMarkdownStyleSheet.createCodeFriendly(lightTheme);

      // 验证重写后的 code 字体属性
      expect(styleSheet.code?.fontSize, equals(13));
      expect(
        styleSheet.code?.fontFamily,
        equals(
            'JetBrains Mono, SF Mono, Consolas, Monaco, Courier New, monospace'),
      );
      expect(styleSheet.code?.letterSpacing, equals(0.3));

      // 验证重写后的 padding
      expect(styleSheet.codeblockPadding, equals(const EdgeInsets.all(20)));

      // 验证基础样式没有丢失
      expect(styleSheet.p?.color, equals(lightTheme.colorScheme.onSurface));
    });
  });
}
