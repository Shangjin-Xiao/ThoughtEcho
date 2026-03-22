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
          mergedDocument.toPlainText(),
        ).replaceAll(RegExp(r'\s+'), ' ').trim(),
        'Polished opening refined middle tightened ending complete.',
      );
    });
  });
}
