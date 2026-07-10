import 'dart:convert';

/// Quill Delta操作的构建工具类
/// 用于AI修改笔记时，正确处理纯文本→Delta转换、并保留嵌入式内容（图片等）
class DeltaBuilder {
  /// 将纯文本内容转换为基础的Delta操作数组
  static List<Map<String, dynamic>> textToDelta(String text) {
    if (text.isEmpty) {
      return [];
    }
    // 简单的纯文本→Delta转换
    return [
      {"insert": text},
      {"insert": "\n"}
    ];
  }

  /// 将受控 Markdown 子集转换成程序可校验的 Quill Delta。
  /// 模型不直接生成 Delta，未知语法按普通文本保留。
  static List<Map<String, dynamic>> markdownToDelta(String markdown) {
    if (markdown.isEmpty) return [];
    final ops = <Map<String, dynamic>>[];
    var inCodeBlock = false;
    for (final line in markdown.replaceAll('\r\n', '\n').split('\n')) {
      if (line.trimLeft().startsWith('```')) {
        inCodeBlock = !inCodeBlock;
        continue;
      }
      final heading = RegExp(r'^(#{1,6})\s+(.+)$').firstMatch(line);
      final bullet = RegExp(r'^\s*[-*+]\s+(.+)$').firstMatch(line);
      final ordered = RegExp(r'^\s*\d+[.)]\s+(.+)$').firstMatch(line);
      final quote = RegExp(r'^\s*>\s?(.*)$').firstMatch(line);
      final body = heading?.group(2) ??
          bullet?.group(1) ??
          ordered?.group(1) ??
          quote?.group(1) ??
          line;
      _appendInlineMarkdown(ops, body);
      final attributes = <String, dynamic>{
        if (inCodeBlock) 'code-block': true,
        if (heading != null) 'header': heading.group(1)!.length,
        if (bullet != null) 'list': 'bullet',
        if (ordered != null) 'list': 'ordered',
        if (quote != null) 'blockquote': true,
      };
      ops.add({
        'insert': '\n',
        if (attributes.isNotEmpty) 'attributes': attributes,
      });
    }
    return ops;
  }

  static void _appendInlineMarkdown(
    List<Map<String, dynamic>> ops,
    String text,
  ) {
    final pattern = RegExp(
      r'(\*\*|__)(.+?)\1|\*([^*\n]+)\*|`([^`\n]+)`|~~(.+?)~~|\[([^\]]+)\]\(([^)]+)\)',
    );
    var cursor = 0;
    for (final match in pattern.allMatches(text)) {
      if (match.start > cursor) {
        ops.add({'insert': text.substring(cursor, match.start)});
      }
      final attributes = <String, dynamic>{};
      late final String value;
      if (match.group(2) != null) {
        value = match.group(2)!;
        attributes['bold'] = true;
      } else if (match.group(3) != null) {
        value = match.group(3)!;
        attributes['italic'] = true;
      } else if (match.group(4) != null) {
        value = match.group(4)!;
        attributes['code'] = true;
      } else if (match.group(5) != null) {
        value = match.group(5)!;
        attributes['strike'] = true;
      } else {
        value = match.group(6)!;
        attributes['link'] = match.group(7)!;
      }
      ops.add({'insert': value, 'attributes': attributes});
      cursor = match.end;
    }
    if (cursor < text.length) ops.add({'insert': text.substring(cursor)});
  }

  static String markdownToPlainText(String markdown) =>
      markdownToDelta(markdown)
          .map((op) => op['insert'])
          .whereType<String>()
          .join()
          .replaceFirst(RegExp(r'\n$'), '');

  static bool hasMarkdownFormatting(String markdown) => RegExp(
        r'(^|\n)\s*(#{1,6}\s|[-*+]\s|\d+[.)]\s|>\s|```)|\*\*|__|~~|`[^`]+`|\[[^\]]+\]\([^)]+\)',
      ).hasMatch(markdown);

  static List<Map<String, dynamic>> appendMarkdownToDelta({
    required String? originalDeltaJson,
    required String markdown,
  }) =>
      [
        ...?deltaFromJson(originalDeltaJson),
        ...markdownToDelta(markdown),
      ];

  static List<Map<String, dynamic>> replaceMarkdownInDelta({
    required String? originalDeltaJson,
    required String markdown,
  }) {
    final ops = markdownToDelta(markdown);
    final embeds = deltaFromJson(originalDeltaJson)
            ?.where((op) => op['insert'] is Map)
            .map((op) => Map<String, dynamic>.from(op))
            .toList() ??
        const <Map<String, dynamic>>[];
    if (embeds.isNotEmpty) {
      ops.insertAll(ops.isEmpty ? 0 : ops.length - 1, embeds);
    }
    return ops;
  }

  /// 在现有Delta基础上append新的纯文本
  /// 用于append模式：新文本总是在末尾，且保持所有原始ops的顺序
  static List<Map<String, dynamic>> appendTextToDelta({
    required String? originalDeltaJson,
    required String newText,
  }) {
    if (originalDeltaJson == null || originalDeltaJson.isEmpty) {
      return textToDelta(newText);
    }

    try {
      final decoded = jsonDecode(originalDeltaJson);
      final originalOps = (decoded is List)
          ? decoded
          : (decoded is Map ? decoded['ops'] ?? [] : []);

      final ops = <Map<String, dynamic>>[];
      for (final op in originalOps) {
        if (op is Map) {
          ops.add(Map<String, dynamic>.from(op));
        }
      }
      ops.addAll(textToDelta(newText));
      return ops;
    } catch (e) {
      return textToDelta(newText);
    }
  }

  /// 替换Delta中的纯文本部分，且根据相对位置保留所有embed
  static List<Map<String, dynamic>> replaceTextInDelta({
    required String? originalDeltaJson,
    required String newText,
  }) {
    if (originalDeltaJson == null || originalDeltaJson.isEmpty) {
      return textToDelta(newText);
    }

    try {
      final decoded = jsonDecode(originalDeltaJson);
      final originalOps = (decoded is List)
          ? decoded
          : (decoded is Map ? decoded['ops'] ?? [] : []);

      // 1. 提取所有 embeds 及其在原始纯文本中的偏移量，同时计算原始纯文本总长度
      final embeds = <_EmbedInfo>[];
      int originalTextLength = 0;

      for (final op in originalOps) {
        if (op is Map && op.containsKey('insert')) {
          final insert = op['insert'];
          if (insert is Map) {
            // 这是一个 embed
            embeds.add(_EmbedInfo(
              op: Map<String, dynamic>.from(op),
              originalOffset: originalTextLength,
            ));
          } else if (insert is String) {
            originalTextLength += insert.length;
          }
        }
      }

      // 如果原始文本没有 embeds，直接返回新文本
      if (embeds.isEmpty) {
        return textToDelta(newText);
      }

      // 2. 映射每个 embed 到新文本中的偏移量
      final mappedEmbeds = <_MappedEmbed>[];
      for (final embed in embeds) {
        final newOffset = originalTextLength > 0
            ? (embed.originalOffset * newText.length) ~/ originalTextLength
            : 0;
        final safeOffset = newOffset.clamp(0, newText.length);
        mappedEmbeds.add(_MappedEmbed(op: embed.op, offset: safeOffset));
      }

      // 按照新偏移量从小到大排序
      mappedEmbeds.sort((a, b) => a.offset.compareTo(b.offset));

      // 3. 根据映射的偏移量重新构建 ops 列表
      final ops = <Map<String, dynamic>>[];
      int currentTextIndex = 0;

      for (final embed in mappedEmbeds) {
        // 插入当前位置到 embed 偏移量之间的文本
        if (embed.offset > currentTextIndex) {
          final segment = newText.substring(currentTextIndex, embed.offset);
          ops.add({"insert": segment});
          currentTextIndex = embed.offset;
        }
        // 插入 embed
        ops.add(embed.op);
      }

      // 插入剩余的文本
      if (currentTextIndex < newText.length) {
        final remaining = newText.substring(currentTextIndex);
        ops.add({"insert": remaining});
      }

      // 确保整个文档以 \n 结尾
      bool endsWithNewline = false;
      if (ops.isNotEmpty) {
        final lastOp = ops.last;
        if (lastOp.containsKey('insert') && lastOp['insert'] is String) {
          final lastText = lastOp['insert'] as String;
          if (lastText.endsWith('\n')) {
            endsWithNewline = true;
          }
        }
      }
      if (!endsWithNewline) {
        ops.add({"insert": "\n"});
      }

      return ops;
    } catch (e) {
      return textToDelta(newText);
    }
  }

  /// 将Delta操作数组转换为JSON字符串
  static String deltaToJson(List<Map<String, dynamic>> ops) {
    return jsonEncode({"ops": ops});
  }

  /// 从JSON字符串解析Delta操作数组
  static List<Map<String, dynamic>>? deltaFromJson(String? json) {
    if (json == null || json.isEmpty) {
      return null;
    }
    try {
      final decoded = jsonDecode(json);
      if (decoded is List) {
        return List<Map<String, dynamic>>.from(decoded);
      }
      if (decoded is Map && decoded['ops'] is List) {
        return List<Map<String, dynamic>>.from(decoded['ops']);
      }
    } catch (e) {
      return null;
    }
    return null;
  }

  /// 从Delta提取纯文本内容
  static String extractTextFromDelta(String? deltaJson) {
    if (deltaJson == null || deltaJson.isEmpty) {
      return '';
    }

    final ops = deltaFromJson(deltaJson);
    if (ops == null) {
      return '';
    }

    final buffer = StringBuffer();
    for (final op in ops) {
      if (op.containsKey('insert')) {
        final insert = op['insert'];
        if (insert is String) {
          buffer.write(insert);
        } else if (insert is Map) {
          // embed类型，根据类型生成占位符
          if (insert.containsKey('image')) {
            buffer.write('[图片]');
          } else if (insert.containsKey('video')) {
            buffer.write('[视频]');
          } else {
            buffer.write('[嵌入内容]');
          }
        }
      }
    }

    return buffer.toString();
  }
}

class _EmbedInfo {
  final Map<String, dynamic> op;
  final int originalOffset;

  _EmbedInfo({required this.op, required this.originalOffset});
}

class _MappedEmbed {
  final Map<String, dynamic> op;
  final int offset;

  _MappedEmbed({required this.op, required this.offset});
}
