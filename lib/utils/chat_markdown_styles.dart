import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

/// 为聊天消息定制的Markdown样式表
class ChatMarkdownStyleSheet {
  /// 创建适合聊天界面的Markdown样式表
  static MarkdownStyleSheet create(ThemeData theme, {bool isDarkMode = false}) {
    final colorScheme = theme.colorScheme;
    final textTheme = theme.textTheme;

    // 基础文本颜色
    final baseColor = colorScheme.onSurface;

    // 代码块背景色
    final codeBlockBg =
        isDarkMode
            ? colorScheme.surface.withValues(alpha: 0.8)
            : colorScheme.surfaceContainerHighest.withValues(alpha: 0.5);

    // 引用块颜色
    final blockquoteBg = colorScheme.primary.withValues(alpha: 0.08);
    final blockquoteBorder = colorScheme.primary.withValues(alpha: 0.3);

    return MarkdownStyleSheet(
      // 段落样式
      p: textTheme.bodyLarge?.copyWith(
        color: baseColor,
        fontSize: 16,
        height: 1.5,
        letterSpacing: 0.1,
      ),

      // 标题样式
      h1: textTheme.headlineLarge?.copyWith(
        color: baseColor,
        fontSize: 24,
        fontWeight: FontWeight.bold,
        height: 1.2,
      ),
      h2: textTheme.headlineMedium?.copyWith(
        color: baseColor,
        fontSize: 20,
        fontWeight: FontWeight.bold,
        height: 1.3,
      ),
      h3: textTheme.headlineSmall?.copyWith(
        color: baseColor,
        fontSize: 18,
        fontWeight: FontWeight.w600,
        height: 1.3,
      ),
      h4: textTheme.titleLarge?.copyWith(
        color: baseColor,
        fontSize: 16,
        fontWeight: FontWeight.w600,
        height: 1.3,
      ),
      h5: textTheme.titleMedium?.copyWith(
        color: baseColor,
        fontSize: 14,
        fontWeight: FontWeight.w600,
        height: 1.3,
      ),
      h6: textTheme.titleSmall?.copyWith(
        color: baseColor,
        fontSize: 13,
        fontWeight: FontWeight.w600,
        height: 1.3,
      ),

      // 文本装饰
      em: TextStyle(color: baseColor, fontStyle: FontStyle.italic),
      strong: TextStyle(color: baseColor, fontWeight: FontWeight.bold),
      del: TextStyle(
        color: baseColor.withValues(alpha: 0.7),
        decoration: TextDecoration.lineThrough,
      ),

      // 链接样式
      a: TextStyle(
        color: colorScheme.primary,
        decoration: TextDecoration.underline,
        decorationColor: colorScheme.primary.withValues(alpha: 0.6),
      ),

      // 引用块样式
      blockquote: textTheme.bodyMedium?.copyWith(
        color: baseColor.withValues(alpha: 0.9),
        fontSize: 15,
        fontStyle: FontStyle.italic,
        height: 1.4,
      ),
      blockquoteDecoration: BoxDecoration(
        color: blockquoteBg,
        borderRadius: BorderRadius.circular(8),
        border: Border(left: BorderSide(color: blockquoteBorder, width: 4)),
      ),
      blockquotePadding: const EdgeInsets.fromLTRB(16, 12, 16, 12),

      // 行内代码样式
      code: TextStyle(
        color: colorScheme.primary,
        backgroundColor: codeBlockBg,
        fontFamily: 'JetBrains Mono, Consolas, Monaco, Courier New, monospace',
        fontSize: 14,
        fontWeight: FontWeight.w500,
        letterSpacing: 0.2,
      ),

      // 代码块样式
      codeblockDecoration: BoxDecoration(
        color: codeBlockBg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: colorScheme.outline.withValues(alpha: 0.2),
          width: 1,
        ),
      ),
      codeblockPadding: const EdgeInsets.all(16),

      // 列表样式
      listBullet: TextStyle(
        color: colorScheme.primary,
        fontSize: 16,
        fontWeight: FontWeight.w600,
      ),
      listIndent: 24,

      // 表格样式
      tableHead: textTheme.bodyMedium?.copyWith(
        color: baseColor,
        fontWeight: FontWeight.w600,
        fontSize: 14,
      ),
      tableBody: textTheme.bodyMedium?.copyWith(color: baseColor, fontSize: 14),
      tableBorder: TableBorder.all(
        color: colorScheme.outline.withValues(alpha: 0.3),
        width: 1,
        borderRadius: BorderRadius.circular(4),
      ),
      tableHeadAlign: TextAlign.left,
      tableCellsPadding: const EdgeInsets.symmetric(
        horizontal: 12,
        vertical: 8,
      ),

      // 分割线样式
      horizontalRuleDecoration: BoxDecoration(
        border: Border(
          top: BorderSide(
            color: colorScheme.outline.withValues(alpha: 0.3),
            width: 1,
          ),
        ),
      ),

      // 其他样式
      textScaler: const TextScaler.linear(1.0),
    );
  }

  /// 创建适合代码显示的样式表
  static MarkdownStyleSheet createCodeFriendly(ThemeData theme) {
    final baseStyleSheet = create(theme);

    return baseStyleSheet.copyWith(
      code: baseStyleSheet.code?.copyWith(
        fontSize: 13,
        fontFamily:
            'JetBrains Mono, SF Mono, Consolas, Monaco, Courier New, monospace',
        letterSpacing: 0.3,
      ),
      codeblockPadding: const EdgeInsets.all(20),
    );
  }
}
