import '../models/quote_model.dart';
import 'delta_rich_text_parser.dart';
import 'string_utils.dart';

/// 专门用于提取和格式化笔记纯文本的工具类。
///
/// 纯函数集合，不持有状态，用于剪贴板复制、分享预览和纯文本导出。
abstract final class QuoteTextExtractor {
  /// 提取笔记的干净纯文本正文。
  ///
  /// - 若有富文本 Delta，复用 [parseDeltaRichText] 提取：
  ///   - 行内粗/斜/色等样式剥离为纯字；
  ///   - 列表项保留语义符号（`• `、`1. `、`[ ] `、`[x] `、`> `）；
  ///   - 媒体嵌入（图片等）自动剔除；
  /// - 剔除富文本可能遗留的 Object Replacement Character (`\uFFFC`)；
  /// - 折叠多余的连续换行（最多保留两个换行符）；
  /// - 遇到任何解析异常时稳妥回退到 `quote.content` 的清洗结果。
  static String extractPlainText(Quote quote) {
    final delta = quote.deltaContent;
    if (delta != null && delta.trim().isNotEmpty) {
      try {
        final blocks = parseDeltaRichText(delta);
        if (blocks.isNotEmpty) {
          final buffer = StringBuffer();
          for (final block in blocks) {
            if (block.isMedia) continue;
            final text = StringUtils.removeObjectReplacementChar(
              block.plainText,
            );
            if (text.isEmpty && block.kind == RichTextBlockKind.paragraph) {
              buffer.writeln();
              continue;
            }

            switch (block.kind) {
              case RichTextBlockKind.bullet:
                buffer.writeln('• $text');
              case RichTextBlockKind.ordered:
                buffer.writeln('${block.orderedIndex}. $text');
              case RichTextBlockKind.checkbox:
                final checkMark = block.checked ? '[x]' : '[ ]';
                buffer.writeln('$checkMark $text');
              case RichTextBlockKind.quote:
                buffer.writeln('> $text');
              case RichTextBlockKind.paragraph:
              case RichTextBlockKind.header:
              case RichTextBlockKind.codeBlock:
              case RichTextBlockKind.media:
                buffer.writeln(text);
            }
          }

          final result =
              _normalizeConsecutiveNewlines(buffer.toString().trim());
          if (result.isNotEmpty) {
            return result;
          }
        }
      } catch (_) {
        // 富文本解析异常时回退到纯文本清洗
      }
    }

    final rawContent = StringUtils.removeObjectReplacementChar(quote.content);
    return _normalizeConsecutiveNewlines(rawContent.trim());
  }

  /// 提取笔记来源/出处单行文本。
  ///
  /// 格式化规则：
  /// - 若同时有作者与作品：`——作者 《作品》`
  /// - 若仅有作者：`——作者`
  /// - 若仅有作品：` 《作品》`
  /// - 否则回退到兼容字段 `quote.source`
  static String? formatSource(Quote quote) {
    final author = quote.sourceAuthor?.trim() ?? '';
    final work = quote.sourceWork?.trim() ?? '';

    if (author.isNotEmpty || work.isNotEmpty) {
      final buffer = StringBuffer();
      if (author.isNotEmpty) {
        buffer.write('——$author');
      }
      if (work.isNotEmpty) {
        if (author.isNotEmpty) {
          buffer.write(' ');
        }
        buffer.write('《$work》');
      }
      return buffer.toString();
    }

    final source = quote.source?.trim();
    if (source != null && source.isNotEmpty) {
      return source;
    }

    return null;
  }

  /// 格式化用于复制到剪贴板的完整文本。
  ///
  /// 若笔记包含作者或出处，末尾附带出处行；纯图片或空内容返回空字符串。
  static String formatForCopy(Quote quote) {
    final content = extractPlainText(quote);
    if (content.isEmpty) {
      return '';
    }

    final sourceLine = formatSource(quote);
    if (sourceLine != null && sourceLine.isNotEmpty) {
      return '$content\n\n$sourceLine';
    }

    return content;
  }

  /// 折叠超过 2 个的连续空行
  static String _normalizeConsecutiveNewlines(String text) {
    if (!text.contains('\n\n\n')) {
      return text;
    }
    return text.replaceAll(RegExp(r'\n{3,}'), '\n\n');
  }
}
