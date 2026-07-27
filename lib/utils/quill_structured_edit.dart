import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../models/rich_text_edit.dart';

/// 一次成功的匹配：文档中实际存在的原文、其偏移，以及是否靠归一化才命中。
class EditMatch {
  const EditMatch({
    required this.offset,
    required this.text,
    required this.normalized,
  });

  final int offset;
  final String text;
  final bool normalized;
}

/// 归一化后的文本及其每个字符到原文下标的映射。
class _NormalizedText {
  const _NormalizedText(this.text, this.sourceIndex);

  final String text;
  final List<int> sourceIndex;
}

class _MatchStrategy {
  const _MatchStrategy({required this.candidates, required this.normalizing});

  /// 返回「文档中实际存在的原文」候选。
  final Iterable<String> Function(String content, String target) candidates;

  /// 该级是否属于宽松匹配（命中后需要让写入文本跟随原文风格）。
  final bool normalizing;
}

class QuillStructuredEdit {
  const QuillStructuredEdit._();

  static String revisionOf(List<Map<String, dynamic>> ops) =>
      sha256.convert(utf8.encode(jsonEncode(ops))).toString();

  static List<Map<String, dynamic>> documentFromBlocks(
    List<RichTextBlock> blocks,
  ) =>
      _blocksToOps(blocks);

  static String plainTextOf(List<Map<String, dynamic>> ops) =>
      _plainText(ops).replaceFirst(RegExp(r'\n$'), '');

  static RichTextEditResult apply({
    required List<Map<String, dynamic>> originalOps,
    required RichTextEditRequest request,
  }) {
    final actualRevision = revisionOf(originalOps);
    if (request.baseRevision != actualRevision) {
      throw const RichTextEditConflict('笔记已发生变化，请重新读取后再修改。');
    }
    if (request.operations.isEmpty) {
      throw const FormatException('富文本修改不能为空。');
    }

    var ops = originalOps.map(_copyOp).toList(growable: true);
    final preview = <RichTextEditPreview>[];
    for (final operation in request.operations) {
      final plainText = _plainText(ops);
      switch (operation.type) {
        case RichTextEditOperationType.replaceDocument:
          final replacement = _replacementOps(
            operation,
            trailingNewline: true,
          );
          preview.add(RichTextEditPreview(
            type: operation.type,
            oldText: plainText.replaceFirst(RegExp(r'\n$'), ''),
            newText: _plainText(replacement).replaceFirst(RegExp(r'\n$'), ''),
          ));
          ops = replacement;
        case RichTextEditOperationType.replace:
        case RichTextEditOperationType.delete:
          final match = locate(plainText, operation.oldText ?? '');
          var replacement = operation.type == RichTextEditOperationType.delete
              ? const <Map<String, dynamic>>[]
              : _replacementOps(
                  operation,
                  trailingNewline: match.text.endsWith('\n'),
                );
          if (match.normalized && replacement.isNotEmpty) {
            replacement = _alignOpsStyle(replacement, match.text);
          }
          ops = _splice(ops, match.offset, match.text.length, replacement);
          preview.add(RichTextEditPreview(
            type: operation.type,
            oldText: match.text,
            newText: _plainText(replacement),
          ));
        case RichTextEditOperationType.insertBefore:
        case RichTextEditOperationType.insertAfter:
          final match = locate(plainText, operation.anchorText ?? '');
          final offset =
              operation.type == RichTextEditOperationType.insertBefore
                  ? match.offset
                  : match.offset + match.text.length;
          var insertion = _replacementOps(operation);
          if (match.normalized) {
            insertion = _alignOpsStyle(insertion, match.text);
          }
          ops = _splice(ops, offset, 0, insertion);
          preview.add(RichTextEditPreview(
            type: operation.type,
            oldText: match.text,
            newText: _plainText(insertion),
          ));
        case RichTextEditOperationType.append:
          final insertion = _replacementOps(operation);
          final offset = plainText.endsWith('\n')
              ? plainText.length - 1
              : plainText.length;
          ops = _splice(ops, offset, 0, insertion);
          preview.add(RichTextEditPreview(
            type: operation.type,
            oldText: '',
            newText: _plainText(insertion),
          ));
      }
    }

    return RichTextEditResult(ops: ops, preview: preview);
  }

  static List<Map<String, dynamic>> _replacementOps(
    RichTextEditOperation operation, {
    bool trailingNewline = true,
  }) {
    if (operation.insertOps.isNotEmpty) {
      return operation.insertOps.map(_copyOp).toList(growable: false);
    }
    return _blocksToOps(operation.blocks, trailingNewline: trailingNewline);
  }

  /// 多级匹配流水线：精确 → 中文标点归一化 → 逐行 trim → 空白归一化。
  ///
  /// 每级策略是一个 `sync*` generator，**yield 的是文档里实际存在的原文**；
  /// 定位与唯一性检查由 [locate] 统一完成，宽松匹配与精确替换因此解耦，
  /// 每级都能独立测试。
  static const List<_MatchStrategy> _matchStrategies = <_MatchStrategy>[
    _MatchStrategy(candidates: exactCandidates, normalizing: false),
    _MatchStrategy(candidates: punctuationCandidates, normalizing: true),
    _MatchStrategy(candidates: lineTrimmedCandidates, normalizing: true),
    _MatchStrategy(candidates: whitespaceCandidates, normalizing: true),
  ];

  /// 在 [content] 中定位 [target]，返回文档中的实际原文与偏移。
  ///
  /// 找不到或找到多处都抛 [RichTextEditMatchFailure]，两种失败给出不同的纠错指引。
  static EditMatch locate(String content, String target) {
    if (target.isEmpty) {
      throw const FormatException('old_text 或 anchor_text 不能为空。');
    }
    for (final strategy in _matchStrategies) {
      final offsets = <int, String>{};
      for (final candidate in strategy.candidates(content, target)) {
        if (candidate.isEmpty) continue;
        var cursor = 0;
        while (true) {
          final found = content.indexOf(candidate, cursor);
          if (found < 0) break;
          offsets[found] = candidate;
          cursor = found + candidate.length;
        }
      }
      if (offsets.isEmpty) {
        continue;
      }
      if (offsets.length > 1) {
        throw RichTextEditMatchFailure(
          target: target,
          matchCount: offsets.length,
        );
      }
      final offset = offsets.keys.single;
      return EditMatch(
        offset: offset,
        text: offsets[offset]!,
        normalized: strategy.normalizing && offsets[offset] != target,
      );
    }
    throw RichTextEditMatchFailure(target: target, matchCount: 0);
  }

  /// 第 1 级：精确匹配。
  static Iterable<String> exactCandidates(String content, String target) sync* {
    if (content.contains(target)) {
      yield target;
    }
  }

  /// 第 2 级：中文标点归一化（弯/直引号、破折号、省略号、全角空格）。
  static Iterable<String> punctuationCandidates(
    String content,
    String target,
  ) =>
      _mappedCandidates(content, target, _normalizePunctuation);

  /// 第 3 级：逐行 trim 匹配（缩进/行尾空白不一致时仍能命中）。
  static Iterable<String> lineTrimmedCandidates(
    String content,
    String target,
  ) sync* {
    final targetLines = target.split('\n');
    while (targetLines.isNotEmpty && targetLines.last.trim().isEmpty) {
      targetLines.removeLast();
    }
    if (targetLines.isEmpty) return;

    final contentLines = content.split('\n');
    // 每行在原文中的起始偏移
    final lineStarts = <int>[];
    var cursor = 0;
    for (final line in contentLines) {
      lineStarts.add(cursor);
      cursor += line.length + 1;
    }

    for (var start = 0;
        start + targetLines.length <= contentLines.length;
        start++) {
      var matched = true;
      for (var offset = 0; offset < targetLines.length; offset++) {
        if (contentLines[start + offset].trim() != targetLines[offset].trim()) {
          matched = false;
          break;
        }
      }
      if (!matched) continue;
      final last = start + targetLines.length - 1;
      final end = lineStarts[last] + contentLines[last].length;
      yield content.substring(lineStarts[start], end);
    }
  }

  /// 第 4 级：空白归一化（连续空白折叠为单个空格）。
  static Iterable<String> whitespaceCandidates(
    String content,
    String target,
  ) =>
      _mappedCandidates(content, target, _normalizeWhitespace);

  /// 用「归一化 + 索引映射」找出原文中的对应片段。
  static Iterable<String> _mappedCandidates(
    String content,
    String target,
    _NormalizedText Function(String) normalize,
  ) sync* {
    final normalizedContent = normalize(content);
    final normalizedTarget = normalize(target).text;
    if (normalizedTarget.isEmpty) return;

    var cursor = 0;
    while (true) {
      final found = normalizedContent.text.indexOf(normalizedTarget, cursor);
      if (found < 0) break;
      final end = found + normalizedTarget.length;
      final originalStart = normalizedContent.sourceIndex[found];
      final originalEnd = end < normalizedContent.sourceIndex.length
          ? normalizedContent.sourceIndex[end]
          : content.length;
      yield content.substring(originalStart, originalEnd);
      cursor = found + normalizedTarget.length;
    }
  }

  static const Map<String, String> _punctuationMap = <String, String>{
    '“': '"', // “
    '”': '"', // ”
    '‘': "'", // ‘
    '’': "'", // ’
    '—': '-', // —（破折号 —— 归一化为 --）
    '…': '...', // …
    '　': ' ', // 全角空格
  };

  static _NormalizedText _normalizePunctuation(String input) {
    final buffer = StringBuffer();
    final sourceIndex = <int>[];
    for (var index = 0; index < input.length; index++) {
      final char = input[index];
      final replacement = _punctuationMap[char] ?? char;
      buffer.write(replacement);
      for (var i = 0; i < replacement.length; i++) {
        sourceIndex.add(index);
      }
    }
    return _NormalizedText(buffer.toString(), sourceIndex);
  }

  static _NormalizedText _normalizeWhitespace(String input) {
    final buffer = StringBuffer();
    final sourceIndex = <int>[];
    var index = 0;
    while (index < input.length) {
      final char = input[index];
      if (_isWhitespace(char)) {
        final start = index;
        while (index < input.length && _isWhitespace(input[index])) {
          index++;
        }
        buffer.write(' ');
        sourceIndex.add(start);
        continue;
      }
      buffer.write(char);
      sourceIndex.add(index);
      index++;
    }
    return _NormalizedText(buffer.toString(), sourceIndex);
  }

  static bool _isWhitespace(String char) =>
      char == ' ' ||
      char == '\t' ||
      char == '\n' ||
      char == '\r' ||
      char == '　';

  /// 靠归一化才命中时，让写入文本的标点风格跟随原文
  /// （claude-code `preserveQuoteStyle` 的简化版）。
  static String alignPunctuationStyle(String replacement, String original) {
    final originalCurly = RegExp('[“”‘’]').hasMatch(original);
    final originalStraight = RegExp('["\']').hasMatch(original);
    var result = replacement;

    if (originalCurly && !originalStraight) {
      result = _toCurlyQuotes(result);
    } else if (originalStraight && !originalCurly) {
      result = result
          .replaceAll('“', '"')
          .replaceAll('”', '"')
          .replaceAll('‘', "'")
          .replaceAll('’', "'");
    }

    if (original.contains('—') && !original.contains('--')) {
      result = result.replaceAll('--', '——');
    }
    if (original.contains('…') && !original.contains('...')) {
      result = result.replaceAll('...', '…');
    }
    return result;
  }

  static String _toCurlyQuotes(String input) {
    final buffer = StringBuffer();
    var doubleOpen = true;
    var singleOpen = true;
    for (var index = 0; index < input.length; index++) {
      final char = input[index];
      if (char == '"') {
        buffer.write(doubleOpen ? '“' : '”');
        doubleOpen = !doubleOpen;
      } else if (char == "'") {
        buffer.write(singleOpen ? '‘' : '’');
        singleOpen = !singleOpen;
      } else {
        buffer.write(char);
      }
    }
    return buffer.toString();
  }

  static List<Map<String, dynamic>> _alignOpsStyle(
    List<Map<String, dynamic>> ops,
    String original,
  ) =>
      ops.map((op) {
        final insert = op['insert'];
        if (insert is! String) return op;
        return <String, dynamic>{
          ...op,
          'insert': alignPunctuationStyle(insert, original),
        };
      }).toList(growable: false);

  static List<Map<String, dynamic>> _blocksToOps(
    List<RichTextBlock> blocks, {
    bool trailingNewline = true,
  }) {
    if (blocks.isEmpty) {
      throw const FormatException('替换或插入内容不能为空。');
    }
    final ops = <Map<String, dynamic>>[];
    for (var index = 0; index < blocks.length; index++) {
      final block = blocks[index];
      for (final child in block.children) {
        if (child.text.isEmpty) continue;
        final attributes = <String, dynamic>{
          if (child.bold) 'bold': true,
          if (child.italic) 'italic': true,
          if (child.underline) 'underline': true,
          if (child.strike) 'strike': true,
          if (child.code) 'code': true,
          if (child.link?.isNotEmpty == true) 'link': child.link,
        };
        ops.add({
          'insert': child.text,
          if (attributes.isNotEmpty) 'attributes': attributes,
        });
      }
      final isLast = index == blocks.length - 1;
      if (!isLast || trailingNewline) {
        final lineAttributes = _lineAttributes(block);
        ops.add({
          'insert': '\n',
          if (lineAttributes.isNotEmpty) 'attributes': lineAttributes,
        });
      }
    }
    return ops;
  }

  static Map<String, dynamic> _lineAttributes(RichTextBlock block) =>
      switch (block.type) {
        'paragraph' => const {},
        'heading' => {'header': (block.level ?? 1).clamp(1, 6)},
        'bullet' => const {'list': 'bullet'},
        'ordered' => const {'list': 'ordered'},
        'quote' => const {'blockquote': true},
        'code' => const {'code-block': true},
        _ => throw FormatException('不支持的富文本块: ${block.type}'),
      };

  static List<Map<String, dynamic>> _splice(
    List<Map<String, dynamic>> ops,
    int offset,
    int deleteLength,
    List<Map<String, dynamic>> insertion,
  ) =>
      [
        ..._slice(ops, 0, offset),
        ...insertion.map(_copyOp),
        ..._slice(ops, offset + deleteLength, _length(ops)),
      ];

  static List<Map<String, dynamic>> _slice(
    List<Map<String, dynamic>> ops,
    int start,
    int end,
  ) {
    final result = <Map<String, dynamic>>[];
    var cursor = 0;
    for (final op in ops) {
      final insert = op['insert'];
      final length = insert is String ? insert.length : 1;
      final opStart = cursor;
      final opEnd = cursor + length;
      cursor = opEnd;
      if (opEnd <= start || opStart >= end) continue;
      if (insert is String) {
        final localStart = (start - opStart).clamp(0, length);
        final localEnd = (end - opStart).clamp(0, length);
        final value = insert.substring(localStart, localEnd);
        if (value.isNotEmpty) {
          result.add({..._copyOp(op), 'insert': value});
        }
      } else {
        result.add(_copyOp(op));
      }
    }
    return result;
  }

  static int _length(List<Map<String, dynamic>> ops) => ops.fold(
        0,
        (length, op) =>
            length +
            (op['insert'] is String ? (op['insert'] as String).length : 1),
      );

  static String _plainText(List<Map<String, dynamic>> ops) => ops
      .map((op) => op['insert'] is String ? op['insert'] as String : '\uFFFC')
      .join();

  static Map<String, dynamic> _copyOp(Map<String, dynamic> op) =>
      Map<String, dynamic>.from(jsonDecode(jsonEncode(op)) as Map);
}
