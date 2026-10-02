import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/models/quote_model.dart';
import 'package:thoughtecho/utils/quote_text_extractor.dart';

void main() {
  group('QuoteTextExtractor', () {
    test('纯文本笔记：提取干净正文并去除首尾空格', () {
      final quote = Quote(
        content: '   这是一段纯文本笔记。  \n\n ',
        date: '2026-10-02T10:00:00Z',
      );

      final extracted = QuoteTextExtractor.extractPlainText(quote);
      expect(extracted, '这是一段纯文本笔记。');
    });

    test('纯文本笔记：折叠超过 2 个的连续换行（LF 及 CRLF）', () {
      final quoteLf = Quote(
        content: '第一段。\n\n\n\n第二段。',
        date: '2026-10-02T10:00:00Z',
      );
      expect(
        QuoteTextExtractor.extractPlainText(quoteLf),
        '第一段。\n\n第二段。',
      );

      final quoteCrlf = Quote(
        content: '第一段。\r\n\r\n\r\n\r\n第二段。',
        date: '2026-10-02T10:00:00Z',
      );
      expect(
        QuoteTextExtractor.extractPlainText(quoteCrlf),
        '第一段。\n\n第二段。',
      );
    });

    test('纯文本笔记：剔除可能包含的 U+FFFC 媒体占位符', () {
      final quote = Quote(
        content: '图片前\uFFFC图片后\uFFFC',
        date: '2026-10-02T10:00:00Z',
      );

      final extracted = QuoteTextExtractor.extractPlainText(quote);
      expect(extracted, '图片前图片后');
    });

    test('富文本笔记：行内媒体保留前后文字在同一行的连贯性，不插入额外换行', () {
      final delta = jsonEncode([
        {'insert': '这是前半句，'},
        {
          'insert': {'image': 'content://media/external/images/inline'},
        },
        {'insert': '这是后半句。\n'},
      ]);

      final quote = Quote(
        content: '这是前半句，\uFFFC这是后半句。\n',
        deltaContent: delta,
        date: '2026-10-02T10:00:00Z',
      );

      final extracted = QuoteTextExtractor.extractPlainText(quote);
      expect(extracted, '这是前半句，这是后半句。');
    });

    test('富文本笔记：行内加粗、斜体、颜色等样式平铺剥离为纯字', () {
      final delta = jsonEncode([
        {
          'insert': '普通文字，',
        },
        {
          'insert': '重要加粗',
          'attributes': {'bold': true},
        },
        {
          'insert': '，',
        },
        {
          'insert': '红色斜体',
          'attributes': {'italic': true, 'color': '#ff0000'},
        },
        {
          'insert': '。\n',
        },
      ]);

      final quote = Quote(
        content: '普通文字，重要加粗，红色斜体。\n',
        deltaContent: delta,
        date: '2026-10-02T10:00:00Z',
      );

      final extracted = QuoteTextExtractor.extractPlainText(quote);
      expect(extracted, '普通文字，重要加粗，红色斜体。');
    });

    test('富文本笔记：列表项语义符号正确还原（无序、有序、待办、引用）', () {
      final delta = jsonEncode([
        {
          'insert': '第一项\n',
          'attributes': {'list': 'bullet'}
        },
        {
          'insert': '第二项\n',
          'attributes': {'list': 'bullet'}
        },
        {
          'insert': '步骤一\n',
          'attributes': {'list': 'ordered'}
        },
        {
          'insert': '步骤二\n',
          'attributes': {'list': 'ordered'}
        },
        {
          'insert': '未完成待办\n',
          'attributes': {'list': 'unchecked'}
        },
        {
          'insert': '已完成待办\n',
          'attributes': {'list': 'checked'}
        },
        {
          'insert': '引用的名言警句\n',
          'attributes': {'blockquote': true}
        },
      ]);

      final quote = Quote(
        content: '第一项\n第二项\n步骤一\n步骤二\n未完成待办\n已完成待办\n引用的名言警句\n',
        deltaContent: delta,
        date: '2026-10-02T10:00:00Z',
      );

      final extracted = QuoteTextExtractor.extractPlainText(quote);
      final expected = [
        '• 第一项',
        '• 第二项',
        '1. 步骤一',
        '2. 步骤二',
        '[ ] 未完成待办',
        '[x] 已完成待办',
        '> 引用的名言警句',
      ].join('\n');

      expect(extracted, expected);
    });

    test('富文本笔记：媒体嵌入被安全过滤且不留 U+FFFC', () {
      final delta = jsonEncode([
        {'insert': '这是第一段正文。\n'},
        {
          'insert': {'image': 'content://media/external/images/media/12345'},
        },
        {'insert': '\n这是第二段正文。\n'},
      ]);

      final quote = Quote(
        content: '这是第一段正文。\n\uFFFC\n这是第二段正文。\n',
        deltaContent: delta,
        date: '2026-10-02T10:00:00Z',
      );

      final extracted = QuoteTextExtractor.extractPlainText(quote);
      expect(extracted, '这是第一段正文。\n\n这是第二段正文。');
    });

    test('纯图片笔记：无文字内容时提取结果为空字符串', () {
      final delta = jsonEncode([
        {
          'insert': {'image': 'file:///path/to/image.png'},
        },
        {'insert': '\n'},
      ]);

      final quote = Quote(
        content: '\uFFFC\n',
        deltaContent: delta,
        date: '2026-10-02T10:00:00Z',
      );

      final extracted = QuoteTextExtractor.extractPlainText(quote);
      expect(extracted, isEmpty);
    });

    test('畸形 Delta JSON：优雅回退到 content 纯文本清洗', () {
      final quote = Quote(
        content: '兜底的纯文本正文\uFFFC',
        deltaContent: 'invalid { json delta',
        date: '2026-10-02T10:00:00Z',
      );

      final extracted = QuoteTextExtractor.extractPlainText(quote);
      expect(extracted, '兜底的纯文本正文');
    });

    group('formatSource 出处格式化', () {
      test('同时有作者与作品名', () {
        final quote = Quote(
          content: '时间就是金钱。',
          date: '2026-10-02T10:00:00Z',
          sourceAuthor: '本杰明·富兰克林',
          sourceWork: '给一个年轻商人的忠告',
        );

        expect(
          QuoteTextExtractor.formatSource(quote),
          '——本杰明·富兰克林 《给一个年轻商人的忠告》',
        );
      });

      test('仅有作者', () {
        final quote = Quote(
          content: '知行合一。',
          date: '2026-10-02T10:00:00Z',
          sourceAuthor: '王阳明',
        );

        expect(QuoteTextExtractor.formatSource(quote), '——王阳明');
      });

      test('仅有作品名', () {
        final quote = Quote(
          content: '生存还是毁灭，这是一个问题。',
          date: '2026-10-02T10:00:00Z',
          sourceWork: '哈姆雷特',
        );

        expect(QuoteTextExtractor.formatSource(quote), '《哈姆雷特》');
      });

      test('回退到兼容 source 字段', () {
        final quote = Quote(
          content: '念念不忘，必有回响。',
          date: '2026-10-02T10:00:00Z',
          source: '民间谚语',
        );

        expect(QuoteTextExtractor.formatSource(quote), '民间谚语');
      });

      test('无出处时返回 null', () {
        final quote = Quote(
          content: '今天散步遇到了小猫。',
          date: '2026-10-02T10:00:00Z',
        );

        expect(QuoteTextExtractor.formatSource(quote), isNull);
      });
    });

    group('formatForCopy 剪贴板内容完整格式化', () {
      test('有出处时拼接在正文后方空一行', () {
        final quote = Quote(
          content: '人类的全部智慧就包含在这两个词中：等待和希望。',
          date: '2026-10-02T10:00:00Z',
          sourceAuthor: '大仲马',
          sourceWork: '基督山伯爵',
        );

        final copyText = QuoteTextExtractor.formatForCopy(quote);
        expect(
          copyText,
          '人类的全部智慧就包含在这两个词中：等待和希望。\n\n——大仲马 《基督山伯爵》',
        );
      });

      test('无出处时只包含纯正文', () {
        final quote = Quote(
          content: '喝了杯很不错的黑咖啡。',
          date: '2026-10-02T10:00:00Z',
        );

        final copyText = QuoteTextExtractor.formatForCopy(quote);
        expect(copyText, '喝了杯很不错的黑咖啡。');
      });

      test('纯图或无正文时返回空字符串', () {
        final quote = Quote(
          content: '   \uFFFC  \n',
          date: '2026-10-02T10:00:00Z',
          sourceAuthor: '某摄影师',
        );

        final copyText = QuoteTextExtractor.formatForCopy(quote);
        expect(copyText, isEmpty);
      });
    });
  });
}
