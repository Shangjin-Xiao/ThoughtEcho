import 'package:flutter_quill/flutter_quill.dart' as quill;
import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/utils/quill_ai_apply_utils.dart';
import 'package:thoughtecho/utils/string_utils.dart';

void main() {
  group('QuillAiApplyUtils', () {
    test('builds stable media markers for AI polishing', () {
      final originalDocument = quill.Document.fromJson([
        {'insert': 'Before image '},
        {
          'insert': {'image': '/tmp/image.png'},
        },
        {'insert': ' after image '},
        {
          'insert': {'video': '/tmp/video.mp4'},
        },
        {'insert': ' after video '},
        {
          'insert': {
            'custom': {'audio': '/tmp/audio.m4a'},
          },
        },
        {'insert': ' done.\n'},
      ]);

      final polishInput = QuillAiApplyUtils.buildPolishInputText(
        originalDocument,
      );

      expect(
        polishInput,
        'Before image [[TE_MEDIA_1]] after image \n[[TE_MEDIA_2]]\n after video [[TE_MEDIA_3]] done.\n',
      );
    });

    test('restores media at exact marker positions when applying polished text',
        () {
      final originalDocument = quill.Document.fromJson([
        {'insert': 'Before image '},
        {
          'insert': {'image': '/tmp/image.png'},
        },
        {'insert': ' after image '},
        {
          'insert': {'video': '/tmp/video.mp4'},
        },
        {'insert': ' after video '},
        {
          'insert': {
            'custom': {'audio': '/tmp/audio.m4a'},
          },
        },
        {'insert': ' done.\n'},
      ]);

      final mergedDocument = QuillAiApplyUtils.applyPolishedText(
        originalDocument: originalDocument,
        polishedText:
            'Polished opening [[TE_MEDIA_1]] refined middle [[TE_MEDIA_2]] tightened ending [[TE_MEDIA_3]] complete.',
      );

      final mergedOps = mergedDocument.toDelta().toJson();

      expect(
        mergedOps.where(
          (op) => op['insert'] is Map && op['insert']['image'] != null,
        ),
        hasLength(1),
      );
      expect(
        mergedOps.where(
          (op) => op['insert'] is Map && op['insert']['video'] != null,
        ),
        hasLength(1),
      );
      expect(
        mergedOps.where(
          (op) =>
              op['insert'] is Map &&
              op['insert']['custom'] is Map &&
              op['insert']['custom']['audio'] != null,
        ),
        hasLength(1),
      );
      expect(
        QuillAiApplyUtils.buildPolishInputText(mergedDocument),
        'Polished opening [[TE_MEDIA_1]] refined middle \n[[TE_MEDIA_2]]\n tightened ending [[TE_MEDIA_3]] complete.\n',
      );
      expect(
        StringUtils.removeObjectReplacementChar(
          mergedDocument.toPlainText().trim(),
        ).replaceAll(RegExp(r'\s+'), ' ').trim(),
        'Polished opening refined middle tightened ending complete.',
      );
    });

    test('strips media markers from preview text', () {
      const rawText =
          'Polished opening [[TE_MEDIA_1]] refined middle \n[[TE_MEDIA_2]]\n tightened ending [[TE_MEDIA_3]] complete.\n';

      final displayText = QuillAiApplyUtils.stripMediaMarkersForDisplay(
        rawText,
      );

      expect(displayText, isNot(contains('[[TE_MEDIA_1]]')));
      expect(displayText, isNot(contains('[[TE_MEDIA_2]]')));
      expect(displayText, isNot(contains('[[TE_MEDIA_3]]')));
      expect(
        displayText.replaceAll(RegExp(r'\s+'), ' ').trim(),
        'Polished opening refined middle tightened ending complete.',
      );
    });

    test('applyPolishedText handles documents without embeds', () {
      final originalDocument = quill.Document.fromJson([
        {'insert': 'Just some plain text.\n'},
      ]);

      final mergedDocument = QuillAiApplyUtils.applyPolishedText(
        originalDocument: originalDocument,
        polishedText: 'New polished text.',
      );

      final mergedOps = mergedDocument.toDelta().toJson();
      expect(mergedOps, hasLength(1));
      expect(mergedOps[0]['insert'], 'New polished text.\n');
    });

    test(
        'applyPolishedText handles missing/altered markers (proportional text splitting)',
        () {
      final originalDocument = quill.Document.fromJson([
        {'insert': 'Start '},
        {
          'insert': {'image': 'img.png'}
        },
        {'insert': ' middle '},
        {
          'insert': {'video': 'vid.mp4'}
        },
        {'insert': ' end.\n'},
      ]);

      final mergedDocument = QuillAiApplyUtils.applyPolishedText(
        originalDocument: originalDocument,
        polishedText: 'Completely new text without markers.',
      );

      final mergedOps = mergedDocument.toDelta().toJson();

      expect(mergedOps.where((op) => op['insert'] is Map), hasLength(2));

      expect(
        StringUtils.removeObjectReplacementChar(
          mergedDocument.toPlainText().trim(),
        ).replaceAll(RegExp(r'\s+'), ''),
        contains('Completelynewtextwithoutmarkers.'),
      );
    });

    test('applyPolishedText handles documents with only embeds and no text',
        () {
      final originalOps = [
        {
          'insert': {'image': 'img.png'}
        },
        {
          'insert': {'video': 'vid.mp4'}
        },
        {'insert': '\n'}
      ];
      final originalDocument = quill.Document.fromJson(originalOps);

      final mergedDocument = QuillAiApplyUtils.applyPolishedText(
        originalDocument: originalDocument,
        polishedText: 'Some new polished text.',
      );

      final mergedOps = mergedDocument.toDelta().toJson();
      expect(mergedOps, isNot(equals(originalOps)));
      expect(mergedOps.where((op) => op['insert'] is Map), hasLength(2));
      expect(mergedOps.last['insert'], contains('Some new polished text.'));
    });

    test('applyPolishedText fallback triggers when marker count mismatches',
        () {
      final originalDocument = quill.Document.fromJson([
        {'insert': 'Text '},
        {
          'insert': {'image': 'img.png'}
        },
        {'insert': '.\n'},
      ]);

      final mergedDocument = QuillAiApplyUtils.applyPolishedText(
        originalDocument: originalDocument,
        polishedText: 'Polished [[TE_MEDIA_1]] and [[TE_MEDIA_2]]',
      );

      final mergedOps = mergedDocument.toDelta().toJson();

      // When marker count mismatches, _tryApplyWithMarkers returns null.
      // It falls back to proportional text distribution.
      // The original document had an embed, so the merged ops should retain the embed
      // and insert the text (which contains the raw markers).
      expect(mergedOps.where((op) => op['insert'] is Map), hasLength(1));
      expect(
          mergedOps.where((op) =>
              op['insert'] is String &&
              (op['insert'] as String).contains('[[TE_MEDIA_1]]')),
          isNotEmpty);
    });

    test(
        'applyPolishedText handles trailing newline correctly when polishedText is empty',
        () {
      final originalDocument = quill.Document.fromJson([
        {'insert': 'Text\n'},
      ]);

      final mergedDocument = QuillAiApplyUtils.applyPolishedText(
        originalDocument: originalDocument,
        polishedText: '',
      );

      final mergedOps = mergedDocument.toDelta().toJson();
      expect(mergedOps.last['insert'], endsWith('\n'));
    });

    test(
        'applyPolishedText handles trailing newline correctly for documents ending in embed',
        () {
      final originalDocument = quill.Document.fromJson([
        {'insert': 'Text '},
        {
          'insert': {'image': 'img.png'}
        },
        {'insert': '\n'}
      ]);

      final mergedDocument = QuillAiApplyUtils.applyPolishedText(
        originalDocument: originalDocument,
        polishedText: '[[TE_MEDIA_1]]',
      );

      final mergedOps = mergedDocument.toDelta().toJson();
      expect(mergedOps.last['insert'], '\n');
    });

    test('applyPolishedText fallback triggers when marker index is invalid',
        () {
      final originalDocument = quill.Document.fromJson([
        {'insert': 'Text '},
        {
          'insert': {'image': 'img.png'}
        },
        {'insert': '.\n'},
      ]);

      final mergedDocument = QuillAiApplyUtils.applyPolishedText(
        originalDocument: originalDocument,
        polishedText: 'Polished [[TE_MEDIA_999]]',
      );

      final mergedOps = mergedDocument.toDelta().toJson();
      expect(mergedOps.length, greaterThan(0));
    });
  });
}
