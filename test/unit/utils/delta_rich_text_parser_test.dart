import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/utils/delta_media_extractor.dart';
import 'package:thoughtecho/utils/delta_rich_text_parser.dart';

/// 折叠卡片改用 `Text.rich` 之后，「格式是否 1:1」不再由 Quill 保证，而是由这个
/// 转换器保证。所以属性映射在这里逐项断言——golden 用的是测试默认字体，所有字形
/// 都是同样的方块，粗体/斜体/字体族在图里根本看不出差别，恰好是最需要盯住的几项。
void main() {
  setUp(DeltaRichTextCache.clear);

  String deltaOf(List<Map<String, dynamic>> ops) => jsonEncode(ops);

  RichTextRun singleRun(String delta) {
    final blocks = parseDeltaRichText(delta);
    expect(blocks, hasLength(1));
    expect(blocks.single.runs, hasLength(1));
    return blocks.single.runs.single;
  }

  group('容错', () {
    test('空输入返回空表，不抛异常', () {
      expect(parseDeltaRichText(null), isEmpty);
      expect(parseDeltaRichText(''), isEmpty);
      expect(parseDeltaRichText('[]'), isEmpty);
    });

    test('畸形 delta 不该让卡片崩掉', () {
      expect(parseDeltaRichText('这不是 JSON'), isEmpty);
      expect(parseDeltaRichText('{"ops": "不是数组"}'), isEmpty);
      expect(parseDeltaRichText('null'), isEmpty);
    });

    test('ops 包裹形式和裸数组等价', () {
      const text = '包裹形式\n';
      final wrapped = jsonEncode({
        'ops': [
          {'insert': text},
        ],
      });
      final bare = deltaOf([
        {'insert': text},
      ]);
      expect(parseDeltaRichText(wrapped), parseDeltaRichText(bare));
    });
  });

  group('行属性挂在换行符上', () {
    test('文字与其后换行符分属不同 op 时仍归到同一个块', () {
      // Delta 的定义：行属性挂在 '\n' 自己身上，不在它前面的文字上。
      final blocks = parseDeltaRichText(deltaOf([
        {'insert': '待办一'},
        {
          'insert': '\n',
          'attributes': {'list': 'unchecked'},
        },
      ]));
      expect(blocks, hasLength(1));
      expect(blocks.single.kind, RichTextBlockKind.checkbox);
      expect(blocks.single.checked, isFalse);
      expect(blocks.single.plainText, '待办一');
    });

    test('一个 op 里的多个换行拆成多个块', () {
      final blocks = parseDeltaRichText(deltaOf([
        {'insert': '第一段\n第二段\n'},
      ]));
      expect(blocks.map((b) => b.plainText), ['第一段', '第二段']);
      expect(
        blocks.map((b) => b.kind),
        everyElement(RichTextBlockKind.paragraph),
      );
    });

    test('结尾没有换行符的文字仍然落成一个块', () {
      final blocks = parseDeltaRichText(deltaOf([
        {'insert': '没有结尾换行'},
      ]));
      expect(blocks, hasLength(1));
      expect(blocks.single.plainText, '没有结尾换行');
    });
  });

  group('行内属性映射', () {
    test('粗体', () {
      final run = singleRun(deltaOf([
        {
          'insert': '粗',
          'attributes': {'bold': true},
        },
        {'insert': '\n'},
      ]));
      expect(run.bold, isTrue);
      expect(run.styleOn(null).fontWeight, FontWeight.bold);
    });

    test('斜体', () {
      final run = singleRun(deltaOf([
        {
          'insert': '斜',
          'attributes': {'italic': true},
        },
        {'insert': '\n'},
      ]));
      expect(run.italic, isTrue);
      expect(run.styleOn(null).fontStyle, FontStyle.italic);
    });

    test('删除线用 strike 键，不是 strikethrough', () {
      final run = singleRun(deltaOf([
        {
          'insert': '删',
          'attributes': {'strike': true},
        },
        {'insert': '\n'},
      ]));
      expect(run.strikethrough, isTrue);
      expect(run.styleOn(null).decoration, TextDecoration.lineThrough);
    });

    test('行内代码用 code 键', () {
      final run = singleRun(deltaOf([
        {
          'insert': 'x',
          'attributes': {'code': true},
        },
        {'insert': '\n'},
      ]));
      expect(run.inlineCode, isTrue);
    });

    test('下划线与删除线并存时两条线都在', () {
      final run = singleRun(deltaOf([
        {
          'insert': '双线',
          'attributes': {'underline': true, 'strike': true},
        },
        {'insert': '\n'},
      ]));
      final decoration = run.styleOn(null).decoration!;
      expect(decoration.contains(TextDecoration.underline), isTrue);
      expect(decoration.contains(TextDecoration.lineThrough), isTrue);
    });

    test('字号 token 的绝对值与 flutter_quill 的 DefaultStyles 一致', () {
      // 折叠预览和展开态的 QuillEditor 会出现在同一个列表里，差一号很显眼。
      double? sizeFor(Object token) => singleRun(deltaOf([
            {
              'insert': '字',
              'attributes': {'size': token},
            },
            {'insert': '\n'},
          ])).fontSize;

      expect(sizeFor('small'), 10.0);
      expect(sizeFor('large'), 18.0);
      expect(sizeFor('huge'), 22.0);
      expect(sizeFor('26'), 26.0);
      expect(sizeFor('乱写'), isNull);
      expect(sizeFor('0'), isNull);
    });

    test('字体族', () {
      final run = singleRun(deltaOf([
        {
          'insert': '字',
          'attributes': {'font': 'Courier'},
        },
        {'insert': '\n'},
      ]));
      expect(run.fontFamily, 'Courier');
      expect(run.styleOn(null).fontFamily, 'Courier');
    });

    test('无属性的文字是 plain，不覆盖基准样式', () {
      final run = singleRun(deltaOf([
        {'insert': '普通\n'},
      ]));
      expect(run.isPlain, isTrue);

      const base = TextStyle(
        fontSize: 17,
        height: 1.75,
        fontWeight: FontWeight.w500,
        color: Color(0xFF123456),
      );
      // copyWith(null) 保留基准值——正文颜色、行高、字重令牌都不能被转换器抹掉。
      expect(run.styleOn(base), base);
    });
  });

  group('颜色解析', () {
    test('本项目编辑器写的 #RRGGBB', () {
      final run = singleRun(deltaOf([
        {
          'insert': '红',
          'attributes': {'color': '#FF0000'},
        },
        {'insert': '\n'},
      ]));
      expect(run.colorArgb, 0xFFFF0000);
      expect(run.styleOn(null).color, const Color(0xFFFF0000));
    });

    test('背景色走同一条解析', () {
      final run = singleRun(deltaOf([
        {
          'insert': '底',
          'attributes': {'background': '#00FF00'},
        },
        {'insert': '\n'},
      ]));
      expect(run.backgroundArgb, 0xFF00FF00);
      expect(run.styleOn(null).backgroundColor, const Color(0xFF00FF00));
    });

    test('其它来源可能带的写法', () {
      expect(parseDeltaColor('#abc'), 0xFFAABBCC);
      expect(parseDeltaColor('#80FF0000'), 0x80FF0000);
      expect(parseDeltaColor('rgb(255, 0, 0)'), 0xFFFF0000);
      expect(parseDeltaColor('rgba(255, 0, 0, 0.5)'), 0x80FF0000);
      expect(parseDeltaColor('FF0000'), 0xFFFF0000);
    });

    test('具名色与 flutter_quill 的 stringToColor 对齐', () {
      expect(parseDeltaColor('black'), Colors.black.toARGB32());
      expect(parseDeltaColor('white'), Colors.white.toARGB32());
      expect(parseDeltaColor('red'), Colors.red.toARGB32());
      expect(parseDeltaColor('blueGrey'), Colors.blueGrey.toARGB32());
      expect(parseDeltaColor('transparent'), Colors.transparent.toARGB32());
      expect(parseDeltaColor('lightGreenAccent'),
          Colors.lightGreenAccent.toARGB32());
    });

    test('解不出来返回 null 而不是抛异常', () {
      // quill 的 stringToColor 这时会抛 UnsupportedError。折叠预览是只读展示，
      // 一个坏颜色值不该让整张卡片炸掉，退回正文色才是正确的降级。
      expect(parseDeltaColor('不是颜色'), isNull);
      expect(parseDeltaColor('#12345'), isNull);
      expect(parseDeltaColor('rgb(300, 0, 0)'), isNull);
      expect(parseDeltaColor(null), isNull);
      expect(parseDeltaColor(42), isNull);
    });
  });

  group('块类型', () {
    RichTextBlock blockWith(Map<String, dynamic> lineAttributes) {
      final blocks = parseDeltaRichText(deltaOf([
        {'insert': '内容'},
        {'insert': '\n', 'attributes': lineAttributes},
      ]));
      return blocks.single;
    }

    test('标题层级，超过 3 级夹到 3', () {
      expect(blockWith({'header': 1}).headerLevel, 1);
      expect(blockWith({'header': 3}).headerLevel, 3);
      expect(blockWith({'header': 6}).headerLevel, 3);
      expect(blockWith({'header': 1}).kind, RichTextBlockKind.header);
    });

    test('引用与代码块', () {
      expect(blockWith({'blockquote': true}).kind, RichTextBlockKind.quote);
      expect(blockWith({'code-block': true}).kind, RichTextBlockKind.codeBlock);
    });

    test('三种列表', () {
      expect(blockWith({'list': 'bullet'}).kind, RichTextBlockKind.bullet);
      expect(blockWith({'list': 'ordered'}).kind, RichTextBlockKind.ordered);
      expect(blockWith({'list': 'checked'}).checked, isTrue);
      expect(blockWith({'list': 'unchecked'}).checked, isFalse);
    });

    test('有序列表连号，被别的块打断后重新从 1 开始', () {
      final blocks = parseDeltaRichText(deltaOf([
        {'insert': '一'},
        {
          'insert': '\n',
          'attributes': {'list': 'ordered'},
        },
        {'insert': '二'},
        {
          'insert': '\n',
          'attributes': {'list': 'ordered'},
        },
        {'insert': '打断\n'},
        {'insert': '重新一'},
        {
          'insert': '\n',
          'attributes': {'list': 'ordered'},
        },
      ]));
      final ordered = blocks
          .where((b) => b.kind == RichTextBlockKind.ordered)
          .map((b) => b.orderedIndex)
          .toList();
      expect(ordered, [1, 2, 1]);
    });
  });

  group('媒体', () {
    test('图片按原位落进块序列，前后文字各成一段', () {
      final blocks = parseDeltaRichText(deltaOf([
        {'insert': '图前\n'},
        {
          'insert': {'image': '/tmp/a.png'},
        },
        {'insert': '图后\n'},
      ]));
      expect(blocks.map((b) => b.kind), [
        RichTextBlockKind.paragraph,
        RichTextBlockKind.media,
        RichTextBlockKind.paragraph,
      ]);
      expect(blocks[1].media!.kind, DeltaMediaKind.image);
      expect(blocks[1].media!.source, '/tmp/a.png');
    });

    test('音频嵌在 custom 里，不在顶层', () {
      // 只认顶层 audio 会让折叠态漏掉音频，播放器照旧被实例化。
      final blocks = parseDeltaRichText(deltaOf([
        {
          'insert': {
            'custom': {'audio': '/tmp/a.m4a'},
          },
        },
      ]));
      expect(blocks.single.kind, RichTextBlockKind.media);
      expect(blocks.single.media!.kind, DeltaMediaKind.audio);
    });

    test('媒体紧跟未结束的文字时，文字先落段再插媒体', () {
      final blocks = parseDeltaRichText(deltaOf([
        {'insert': '没有换行就来图'},
        {
          'insert': {'image': '/tmp/a.png'},
        },
      ]));
      expect(blocks.map((b) => b.kind), [
        RichTextBlockKind.paragraph,
        RichTextBlockKind.media,
      ]);
      expect(blocks.first.plainText, '没有换行就来图');
    });

    test('非媒体嵌入（公式）跳过，不留空块', () {
      final blocks = parseDeltaRichText(deltaOf([
        {'insert': '文字\n'},
        {
          'insert': {'formula': 'x^2'},
        },
      ]));
      expect(blocks, hasLength(1));
      expect(blocks.single.kind, RichTextBlockKind.paragraph);
    });
  });

  group('加粗内容优先', () {
    test('带加粗的整行提到前面，其余保持原序', () {
      // 块（行）粒度，不是 op 粒度：一行里只加粗半句时，整行一起提前，句子不断。
      final blocks = parseDeltaRichText(deltaOf([
        {'insert': '普通一\n'},
        {'insert': '前半'},
        {
          'insert': '加粗半句',
          'attributes': {'bold': true},
        },
        {'insert': '后半\n'},
        {'insert': '普通二\n'},
      ]));

      final ordered = prioritizeBoldBlocks(blocks);
      expect(ordered.first.plainText, '前半加粗半句后半');
      expect(
        ordered.map((b) => b.plainText),
        ['前半加粗半句后半', '普通一', '普通二'],
      );
    });

    test('没有加粗时内容原样，且返回值不可修改', () {
      final blocks = parseDeltaRichText(deltaOf([
        {'insert': '甲\n乙\n'},
      ]));
      final ordered = prioritizeBoldBlocks(blocks);
      expect(ordered.map((b) => b.plainText), ['甲', '乙']);
      expect(
        () => ordered.add(
          const RichTextBlock(kind: RichTextBlockKind.paragraph),
        ),
        throwsUnsupportedError,
      );
    });

    test('空行不参与提前，否则预览顶部会堆出一段空白', () {
      final blocks = parseDeltaRichText(deltaOf([
        {'insert': '\n'},
        {
          'insert': '加粗',
          'attributes': {'bold': true},
        },
        {'insert': '\n'},
      ]));
      final ordered = prioritizeBoldBlocks(blocks);
      expect(ordered.first.plainText, '加粗');
    });

    test('媒体块不参与提前，保持在文字之后的原有相对位置', () {
      final blocks = parseDeltaRichText(deltaOf([
        {
          'insert': {'image': '/tmp/a.png'},
        },
        {
          'insert': '加粗',
          'attributes': {'bold': true},
        },
        {'insert': '\n'},
      ]));
      final ordered = prioritizeBoldBlocks(blocks);
      expect(ordered.first.plainText, '加粗');
      expect(ordered.last.isMedia, isTrue);
    });
  });

  group('缓存', () {
    test('同一份内容第二次命中缓存', () {
      final delta = deltaOf([
        {'insert': '缓存我\n'},
      ]);
      final first = DeltaRichTextCache.of(delta);
      final second = DeltaRichTextCache.of(delta);
      expect(identical(first, second), isTrue);
      expect(DeltaRichTextCache.stats['hitCount'], 1);
      expect(DeltaRichTextCache.stats['missCount'], 1);
    });

    test('内容不同不会串味', () {
      final a = DeltaRichTextCache.of(deltaOf([
        {'insert': '甲\n'},
      ]));
      final b = DeltaRichTextCache.of(deltaOf([
        {'insert': '乙\n'},
      ]));
      expect(a.single.plainText, '甲');
      expect(b.single.plainText, '乙');
    });

    test('带 data: 内嵌媒体的笔记不进缓存，避免把 base64 钉在堆上', () {
      final delta = deltaOf([
        {
          'insert': {'image': 'data:image/png;base64,AAAA'},
        },
        {'insert': '说明\n'},
      ]);
      final first = DeltaRichTextCache.of(delta);
      final second = DeltaRichTextCache.of(delta);

      // 内容照常解析出来，只是不留在缓存里。
      expect(first.any((b) => b.isMedia), isTrue);
      expect(identical(first, second), isFalse);
      expect(DeltaRichTextCache.stats['cacheSize'], 0);
    });

    test('大写 scheme 的 data URI 同样跳过缓存', () {
      // scheme 按 RFC 2397 大小写不敏感，只认小写会让 `DATA:` 绕过豁免。
      final delta = deltaOf([
        {
          'insert': {'image': 'DATA:image/png;base64,AAAA'},
        },
        {'insert': '说明\n'},
      ]);
      DeltaRichTextCache.of(delta);
      expect(DeltaRichTextCache.stats['cacheSize'], 0);
    });

    test('插在正文中间的图不会多解出一个空段落', () {
      // delta 里图后面那个 `\n` 是**图这一行**的结束符，不是空段落。当成空段落的
      // 话，折叠预览比原文多一行空白，还白占掉 24px 的折叠盒高度——inline 版式下
      // 足以把图后面的正文整段挤出盒子。
      final blocks = parseDeltaRichText(deltaOf([
        {'insert': '上面一段\n'},
        {
          'insert': {'image': 'https://example.com/a.png'},
        },
        {'insert': '\n下面一段\n'},
      ]));

      expect(blocks.map((b) => b.isMedia ? '[图]' : b.plainText).toList(),
          ['上面一段', '[图]', '下面一段']);
    });

    test('图后面真的空一行时，空段落照常保留', () {
      // 吃掉的只有紧跟在媒体后面的那**一个**换行符。用户自己敲的空行还在。
      final blocks = parseDeltaRichText(deltaOf([
        {
          'insert': {'image': 'https://example.com/a.png'},
        },
        {'insert': '\n\n下面一段\n'},
      ]));

      expect(blocks.map((b) => b.isMedia ? '[图]' : b.plainText).toList(),
          ['[图]', '', '下面一段']);
    });

    test('媒体后同一行还有文字时，紧跟其后的空段落不会被吞掉', () {
      // 媒体那一行只有一个结束符。遇到文字就说明这个换行是文字行的收尾，
      // 状态必须当场清掉——否则下一个换行（用户敲的空行）会被当成媒体的结束符。
      final blocks = parseDeltaRichText(deltaOf([
        {
          'insert': {'image': 'https://example.com/a.png'},
        },
        {'insert': '同行文字\n\n下面一段\n'},
      ]));

      expect(blocks.map((b) => b.isMedia ? '[图]' : b.plainText).toList(),
          ['[图]', '同行文字', '', '下面一段']);
    });

    test('缓存结果不可变，调用方改不动共享的表', () {
      final blocks = DeltaRichTextCache.of(deltaOf([
        {'insert': '只读\n'},
      ]));
      expect(
        () => blocks.add(
          const RichTextBlock(kind: RichTextBlockKind.paragraph),
        ),
        throwsUnsupportedError,
      );
    });
  });
}
