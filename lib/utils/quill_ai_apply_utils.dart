import 'dart:convert';

import 'package:flutter_quill/flutter_quill.dart' as quill;

/// Utilities for applying AI-generated plain text back into a Quill document.
class QuillAiApplyUtils {
  static quill.Document applyPolishedText({
    required quill.Document originalDocument,
    required String polishedText,
  }) {
    final normalizedText = _normalizeText(polishedText);
    final originalOps = List<Map<String, dynamic>>.from(
      originalDocument.toDelta().toJson(),
    );

    final hasEmbed = originalOps.any((op) => op['insert'] is! String);
    if (!hasEmbed) {
      return quill.Document.fromJson([
        {'insert': normalizedText},
      ]);
    }

    final totalTextLength = originalOps.fold<int>(0, (sum, op) {
      final insert = op['insert'];
      return insert is String ? sum + insert.length : sum;
    });

    if (totalTextLength == 0) {
      return quill.Document.fromJson(originalOps);
    }

    final mergedOps = <Map<String, dynamic>>[];
    var consumedOriginalLength = 0;
    var consumedPolishedLength = 0;

    for (final op in originalOps) {
      final insert = op['insert'];
      if (insert is String) {
        consumedOriginalLength += insert.length;
        final nextBoundary =
            ((consumedOriginalLength / totalTextLength) * normalizedText.length)
                .round()
                .clamp(consumedPolishedLength, normalizedText.length);
        final textChunk = normalizedText.substring(
          consumedPolishedLength,
          nextBoundary,
        );
        consumedPolishedLength = nextBoundary;

        if (textChunk.isNotEmpty) {
          mergedOps.add({'insert': textChunk});
        }
        continue;
      }

      mergedOps.add(_deepCopyOp(op));
    }

    if (consumedPolishedLength < normalizedText.length) {
      mergedOps.add({
        'insert': normalizedText.substring(consumedPolishedLength),
      });
    }

    _ensureTrailingNewline(mergedOps);
    return quill.Document.fromJson(mergedOps);
  }

  static String _normalizeText(String text) {
    return text.endsWith('\n') ? text : '$text\n';
  }

  static Map<String, dynamic> _deepCopyOp(Map<String, dynamic> op) {
    return Map<String, dynamic>.from(jsonDecode(jsonEncode(op)) as Map);
  }

  static void _ensureTrailingNewline(List<Map<String, dynamic>> ops) {
    if (ops.isEmpty) {
      ops.add({'insert': '\n'});
      return;
    }

    final lastInsert = ops.last['insert'];
    if (lastInsert is String) {
      if (!lastInsert.endsWith('\n')) {
        ops.last = {
          ...ops.last,
          'insert': '$lastInsert\n',
        };
      }
      return;
    }

    ops.add({'insert': '\n'});
  }
}
