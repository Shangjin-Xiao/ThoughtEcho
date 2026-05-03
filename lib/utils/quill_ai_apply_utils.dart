import 'dart:convert';

import 'package:flutter_quill/flutter_quill.dart' as quill;

/// Utilities for applying AI-generated plain text back into a Quill document.
class QuillAiApplyUtils {
  static final RegExp _mediaMarkerPattern = RegExp(r'\[\[TE_MEDIA_(\d+)]]');

  static String buildPolishInputText(quill.Document document) {
    final buffer = StringBuffer();
    final ops = List<Map<String, dynamic>>.from(document.toDelta().toJson());
    var embedIndex = 0;

    for (final op in ops) {
      final insert = op['insert'];
      if (insert is String) {
        buffer.write(insert);
        continue;
      }

      embedIndex++;
      buffer.write(_markerForIndex(embedIndex));
    }

    return _normalizeText(buffer.toString());
  }

  static quill.Document applyPolishedText({
    required quill.Document originalDocument,
    required String polishedText,
  }) {
    final originalOps = List<Map<String, dynamic>>.from(
      originalDocument.toDelta().toJson(),
    );
    final normalizedText = _normalizeText(polishedText);

    final hasEmbed = originalOps.any((op) => op['insert'] is! String);
    if (!hasEmbed) {
      return quill.Document.fromJson([
        {'insert': normalizedText},
      ]);
    }

    final markerBasedDocument = _tryApplyWithMarkers(
      originalOps: originalOps,
      polishedText: normalizedText,
    );
    if (markerBasedDocument != null) {
      return markerBasedDocument;
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

  static String stripMediaMarkersForDisplay(String text) {
    final withoutMarkers = text.replaceAll(_mediaMarkerPattern, '');
    return withoutMarkers
        .replaceAll(RegExp(r'[ \t]+\n'), '\n')
        .replaceAll(RegExp(r'\n{3,}'), '\n\n')
        .replaceAll(RegExp(r' {2,}'), ' ');
  }

  static String _markerForIndex(int index) => '[[TE_MEDIA_$index]]';

  static quill.Document? _tryApplyWithMarkers({
    required List<Map<String, dynamic>> originalOps,
    required String polishedText,
  }) {
    final matches = _mediaMarkerPattern.allMatches(polishedText).toList();
    if (matches.isEmpty) {
      return null;
    }

    final embedOps = originalOps
        .where((op) => op['insert'] is! String)
        .map(_deepCopyOp)
        .toList();
    if (matches.length != embedOps.length) {
      return null;
    }

    final rebuiltOps = <Map<String, dynamic>>[];
    var cursor = 0;

    for (final match in matches) {
      final markerText = match.group(0);
      final markerIndex = int.tryParse(match.group(1) ?? '');
      if (markerText == null ||
          markerIndex == null ||
          markerIndex < 1 ||
          markerIndex > embedOps.length ||
          markerText != _markerForIndex(markerIndex)) {
        return null;
      }

      final textBeforeMarker = polishedText.substring(cursor, match.start);
      if (textBeforeMarker.isNotEmpty) {
        rebuiltOps.add({'insert': textBeforeMarker});
      }
      rebuiltOps.add(embedOps[markerIndex - 1]);
      cursor = match.end;
    }

    final trailingText = polishedText.substring(cursor);
    if (trailingText.isNotEmpty) {
      rebuiltOps.add({'insert': trailingText});
    }

    _ensureTrailingNewline(rebuiltOps);
    return quill.Document.fromJson(rebuiltOps);
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
        ops.last = {...ops.last, 'insert': '$lastInsert\n'};
      }
      return;
    }

    ops.add({'insert': '\n'});
  }
}
