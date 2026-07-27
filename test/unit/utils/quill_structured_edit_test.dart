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

  group('QuillStructuredEdit 多级匹配流水线', () {
    const document = '第一行内容\n  缩进的第二行  \n他说“你好”，然后——离开了…\n多个   空格   的一行\n';

    test('第 1 级：精确匹配只 yield 原样文本', () {
      expect(
        QuillStructuredEdit.exactCandidates(document, '第一行内容').toList(),
        ['第一行内容'],
      );
      expect(
        QuillStructuredEdit.exactCandidates(document, '不存在的文本').toList(),
        isEmpty,
      );
    });

    test('第 2 级：中文标点归一化后 yield 文档里的原文', () {
      expect(
        QuillStructuredEdit.punctuationCandidates(document, '他说"你好"').toList(),
        ['他说“你好”'],
      );
      expect(
        QuillStructuredEdit.punctuationCandidates(document, '然后--离开了...')
            .toList(),
        ['然后——离开了…'],
      );
    });

    test('第 3 级：逐行 trim 匹配忽略行首尾空白', () {
      expect(
        QuillStructuredEdit.lineTrimmedCandidates(document, '缩进的第二行').toList(),
        ['  缩进的第二行  '],
      );
    });

    test('第 4 级：空白归一化匹配连续空格', () {
      expect(
        QuillStructuredEdit.whitespaceCandidates(document, '多个 空格 的一行')
            .toList(),
        ['多个   空格   的一行'],
      );
    });

    test('locate 报告归一化命中并返回原文', () {
      final match = QuillStructuredEdit.locate(document, '他说"你好"');
      expect(match.text, '他说“你好”');
      expect(match.normalized, isTrue);
      expect(document.substring(match.offset, match.offset + match.text.length),
          '他说“你好”');
    });

    test('locate 精确命中时不标记归一化', () {
      final match = QuillStructuredEdit.locate(document, '第一行内容');
      expect(match.normalized, isFalse);
    });

    test('未找到时的错误说明下一步动作', () {
      expect(
        () => QuillStructuredEdit.locate(document, '完全不存在'),
        throwsA(
          isA<RichTextEditMatchFailure>()
              .having((e) => e.matchCount, 'matchCount', 0)
              .having((e) => e.toString(), 'message',
                  contains('请检查空白与标点是否与原文完全一致')),
        ),
      );
    });

    test('多处匹配时报告具体匹配数并要求补充上下文', () {
      expect(
        () => QuillStructuredEdit.locate('重复\n重复\n', '重复'),
        throwsA(
          isA<RichTextEditMatchFailure>()
              .having((e) => e.matchCount, 'matchCount', 2)
              .having((e) => e.toString(), 'message', contains('找到 2 处匹配')),
        ),
      );
    });

    test('靠归一化命中时写入文本的标点风格跟随原文', () {
      final original = <Map<String, dynamic>>[
        {'insert': '他说“你好”，然后走了。\n'},
      ];
      final request = RichTextEditRequest(
        baseRevision: QuillStructuredEdit.revisionOf(original),
        operations: const [
          RichTextEditOperation.replace(
            oldText: '他说"你好"',
            blocks: [
              RichTextBlock.paragraph([RichTextRun(text: '她说"再见"')]),
            ],
          ),
        ],
      );

      final result = QuillStructuredEdit.apply(
        originalOps: original,
        request: request,
      );

      expect(result.preview.single.oldText, '他说“你好”');
      expect(result.preview.single.newText, '她说“再见”');
    });

    test('逐行 trim 命中时替换掉整行原文', () {
      final original = <Map<String, dynamic>>[
        {'insert': '标题\n   待润色的一行   \n结尾\n'},
      ];
      final request = RichTextEditRequest(
        baseRevision: QuillStructuredEdit.revisionOf(original),
        operations: const [
          RichTextEditOperation.replace(
            oldText: '待润色的一行',
            blocks: [
              RichTextBlock.paragraph([RichTextRun(text: '润色后的一行')]),
            ],
          ),
        ],
      );

      final result = QuillStructuredEdit.apply(
        originalOps: original,
        request: request,
      );

      expect(
        QuillStructuredEdit.plainTextOf(result.ops).trimRight(),
        '标题\n   润色后的一行   \n结尾',
      );
    });
  });
}
