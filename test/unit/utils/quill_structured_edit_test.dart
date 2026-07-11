import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/models/rich_text_edit.dart';
import 'package:thoughtecho/utils/quill_structured_edit.dart';

void main() {
  group('QuillStructuredEdit', () {
    test('replaces one unique range and preserves untouched formatting', () {
      final original = <Map<String, dynamic>>[
        {
          'insert': '保留的标题',
          'attributes': {'bold': true},
        },
        {
          'insert': '\n',
          'attributes': {'header': 1},
        },
        {'insert': '需要润色的段落。\n'},
        {
          'insert': {'image': '/tmp/photo.jpg'},
        },
        {'insert': '\n尾段\n'},
      ];
      final revision = QuillStructuredEdit.revisionOf(original);
      final request = RichTextEditRequest(
        baseRevision: revision,
        operations: const [
          RichTextEditOperation.replace(
            oldText: '需要润色的段落。',
            blocks: [
              RichTextBlock.paragraph([
                RichTextRun(text: '润色后的'),
                RichTextRun(text: '重点', bold: true),
                RichTextRun(text: '段落。'),
              ]),
            ],
          ),
        ],
      );

      final result = QuillStructuredEdit.apply(
        originalOps: original,
        request: request,
      );

      expect(result.preview.single.oldText, '需要润色的段落。');
      expect(result.preview.single.newText, '润色后的重点段落。');
      expect(result.ops.first, original.first);
      expect(result.ops[1], original[1]);
      expect(
        result.ops.any(
          (op) =>
              op['insert'] == '重点' &&
              (op['attributes'] as Map?)?['bold'] == true,
        ),
        isTrue,
      );
      expect(
        result.ops.where((op) => op['insert'] is Map),
        hasLength(1),
      );
    });

    test('rejects stale revision before applying any operation', () {
      final original = <Map<String, dynamic>>[
        {'insert': '当前内容\n'},
      ];
      final request = RichTextEditRequest(
        baseRevision: 'stale-revision',
        operations: const [
          RichTextEditOperation.replace(
            oldText: '当前内容',
            blocks: [
              RichTextBlock.paragraph([RichTextRun(text: '新内容')]),
            ],
          ),
        ],
      );

      expect(
        () => QuillStructuredEdit.apply(
          originalOps: original,
          request: request,
        ),
        throwsA(isA<RichTextEditConflict>()),
      );
    });

    test('rejects ambiguous old text', () {
      final original = <Map<String, dynamic>>[
        {'insert': '重复段落\n重复段落\n'},
      ];
      final request = RichTextEditRequest(
        baseRevision: QuillStructuredEdit.revisionOf(original),
        operations: const [
          RichTextEditOperation.replace(
            oldText: '重复段落',
            blocks: [
              RichTextBlock.paragraph([RichTextRun(text: '替换')]),
            ],
          ),
        ],
      );

      expect(
        () => QuillStructuredEdit.apply(
          originalOps: original,
          request: request,
        ),
        throwsA(
          isA<RichTextEditMatchFailure>().having(
            (error) => error.matchCount,
            'matchCount',
            2,
          ),
        ),
      );
    });
  });
}
