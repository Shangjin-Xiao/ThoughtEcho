import 'dart:convert';

import '../models/quote_model.dart';
import 'string_utils.dart';

/// 专门用于提取和格式化笔记纯文本的工具类。
///
/// 纯函数集合，不持有状态，用于剪贴板复制、分享预览和纯文本导出。
abstract final class QuoteTextExtractor {
  /// 提取笔记的干净纯文本正文。
  ///
  /// - 若有富文本 Delta，直接解析 Delta 操作并提取纯文本：
  ///   - 行内粗/斜/色等样式剥离为纯字；
  ///   - 列表项保留语义符号（`• `、`1. `、`[ ] `、`[x] `、`> `）；
  ///   - 行内媒体自动剔除，且保留前后文本在同一行的连续性；
  /// - 剔除富文本可能遗留的 Object Replacement Character (`\uFFFC`)；
  /// - 统一 CRLF/CR 并折叠多余的连续换行（最多保留两个换行符）；
  /// - 遇到任何解析异常时稳妥回退到 `quote.content` 的清洗结果。
  static String extractPlainText(Quote quote) {
    final delta = quote.deltaContent;
    if (delta != null && delta.trim().isNotEmpty) {
      try {
        final extracted = _extractTextFromDelta(delta);
        if (extracted != null && extracted.isNotEmpty) {
          return extracted;
        }
      } catch (_) {
        // 富文本解析异常时回退到纯文本清洗
      }
    }

    final rawContent = StringUtils.removeObjectReplacementChar(quote.content);
    return _normalizeConsecutiveNewlines(rawContent.trim());
  }

  static String? _extractTextFromDelta(String deltaJson) {
    final ops = _decodeOps(deltaJson);
    if (ops == null || ops.isEmpty) return null;

    final buffer = StringBuffer();
    final lineBuffer = StringBuffer();
    var orderedIndex = 0;

    void flushLine(Map<String, dynamic> lineAttributes) {
      final lineText = lineBuffer.toString();
      lineBuffer.clear();

      final listType = lineAttributes['list']?.toString();
      final isQuote = lineAttributes['blockquote'] == true;

      if (listType == 'ordered') {
        orderedIndex++;
        buffer.writeln('$orderedIndex. $lineText');
      } else {
        orderedIndex = 0;
        if (listType == 'bullet') {
          buffer.writeln('• $lineText');
        } else if (listType == 'checked') {
          buffer.writeln('[x] $lineText');
        } else if (listType == 'unchecked') {
          buffer.writeln('[ ] $lineText');
        } else if (isQuote) {
          buffer.writeln('> $lineText');
        } else {
          buffer.writeln(lineText);
        }
      }
    }

    for (final op in ops) {
      if (op is! Map) continue;
      final insert = op['insert'];
      if (insert == null) continue;

      if (insert is! String) {
        // 媒体/嵌入对象：直接跳过，不打断行内前后文字的连接
        continue;
      }

      final text = StringUtils.removeObjectReplacementChar(insert);
      if (text.isEmpty) continue;

      final attributes = op['attributes'];
      final lineAttrs = attributes is Map<String, dynamic>
          ? attributes
          : (attributes is Map
              ? attributes.cast<String, dynamic>()
              : const <String, dynamic>{});

      var start = 0;
      while (start < text.length) {
        final newlineIndex = text.indexOf('\n', start);
        if (newlineIndex == -1) {
          lineBuffer.write(text.substring(start));
          break;
        }

        lineBuffer.write(text.substring(start, newlineIndex));
        flushLine(lineAttrs);
        start = newlineIndex + 1;
      }
    }

    if (lineBuffer.isNotEmpty) {
      flushLine(const {});
    }

    final raw = buffer.toString().trim();
    return _normalizeConsecutiveNewlines(raw);
  }

  static List<Object?>? _decodeOps(String deltaContent) {
    try {
      final decoded = jsonDecode(deltaContent);
      if (decoded is List) return decoded;
      if (decoded is Map && decoded['ops'] is List) {
        return decoded['ops'] as List<Object?>;
      }
    } catch (_) {}
    return null;
  }

  /// 提取笔记来源/出处单行文本。
  ///
  /// 格式化规则：
  /// - 若同时有作者与作品：`——作者 《作品》`
  /// - 若仅有作者：`——作者`
  /// - 若仅有作品：`《作品》`
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
      return '$content\n$sourceLine';
    }

    return content;
  }

  /// 将 Windows CRLF 和单独的 CR 统一转为 LF，并将超过 2 个的连续换行折叠为 2 个换行。
  static String _normalizeConsecutiveNewlines(String text) {
    final normalized = text.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    if (!normalized.contains('\n\n\n')) {
      return normalized;
    }
    return normalized.replaceAll(RegExp(r'\n{3,}'), '\n\n');
  }
}
