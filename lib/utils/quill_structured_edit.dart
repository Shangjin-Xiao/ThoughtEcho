import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../models/rich_text_edit.dart';

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
          final oldText = operation.oldText ?? '';
          final offset = _uniqueOffset(plainText, oldText);
          final replacement = operation.type == RichTextEditOperationType.delete
              ? const <Map<String, dynamic>>[]
              : _replacementOps(
                  operation,
                  trailingNewline: oldText.endsWith('\n'),
                );
          ops = _splice(ops, offset, oldText.length, replacement);
          preview.add(RichTextEditPreview(
            type: operation.type,
            oldText: oldText,
            newText: _plainText(replacement),
          ));
        case RichTextEditOperationType.insertBefore:
        case RichTextEditOperationType.insertAfter:
          final anchor = operation.anchorText ?? '';
          final anchorOffset = _uniqueOffset(plainText, anchor);
          final offset =
              operation.type == RichTextEditOperationType.insertBefore
                  ? anchorOffset
                  : anchorOffset + anchor.length;
          final insertion = _replacementOps(operation);
          ops = _splice(ops, offset, 0, insertion);
          preview.add(RichTextEditPreview(
            type: operation.type,
            oldText: anchor,
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

  static int _uniqueOffset(String content, String target) {
    if (target.isEmpty) {
      throw const FormatException('old_text 或 anchor_text 不能为空。');
    }
    var count = 0;
    var offset = -1;
    var cursor = 0;
    while (true) {
      final found = content.indexOf(target, cursor);
      if (found < 0) break;
      count++;
      offset = found;
      cursor = found + target.length;
    }
    if (count != 1) {
      throw RichTextEditMatchFailure(target: target, matchCount: count);
    }
    return offset;
  }

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
