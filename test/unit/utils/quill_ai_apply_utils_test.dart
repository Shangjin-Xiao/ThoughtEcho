import 'package:flutter_quill/flutter_quill.dart' as quill;
import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/utils/quill_ai_apply_utils.dart';
import 'package:thoughtecho/utils/string_utils.dart';

void main() {
  group('QuillAiApplyUtils', () {
    test('preserves media embeds when applying polished text', () {
      final originalDocument = quill.Document.fromJson([
        {'insert': 'Before image\n'},
        {
          'insert': {'image': '/tmp/image.png'},
        },
        {'insert': '\nBetween media\n'},
        {
          'insert': {'video': '/tmp/video.mp4'},
        },
        {'insert': '\nAfter media\n'},
        {
          'insert': {
            'custom': {'audio': '/tmp/audio.m4a'},
          },
        },
        {'insert': '\n'},
      ]);

      final mergedDocument = QuillAiApplyUtils.applyPolishedText(
        originalDocument: originalDocument,
        polishedText: 'Polished content with media still attached.',
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
        StringUtils.removeObjectReplacementChar(
          mergedDocument.toPlainText(),
        ).replaceAll(RegExp(r'\s+'), ''),
        'Polishedcontentwithmediastillattached.',
      );
    });
  });
}
