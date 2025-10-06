import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:thoughtecho/models/quote_model.dart';
import 'package:thoughtecho/services/settings_service.dart';
import 'package:thoughtecho/widgets/quote_content_widget.dart';
import 'package:thoughtecho/widgets/quote_item_widget.dart';

class _TestSettingsService extends ChangeNotifier implements SettingsService {
  bool _prioritizeBold;

  _TestSettingsService({bool prioritizeBold = false})
      : _prioritizeBold = prioritizeBold;

  @override
  bool get prioritizeBoldContentInCollapse => _prioritizeBold;

  @override
  Future<void> setPrioritizeBoldContentInCollapse(bool enabled) async {
    _prioritizeBold = enabled;
    notifyListeners();
  }

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  setUp(() {
    QuoteItemWidget.clearExpansionCache();
  });

  Widget buildTestApp(Quote quote, {bool prioritizeBold = false}) {
    return ChangeNotifierProvider<SettingsService>.value(
      value: _TestSettingsService(prioritizeBold: prioritizeBold),
      child: MaterialApp(
        home: Scaffold(
          body: QuoteContent(
            quote: quote,
            style: const TextStyle(fontSize: 16, height: 1.5),
            showFullContent: false,
          ),
        ),
      ),
    );
  }

  Quote createPlainQuote(String content) {
    return Quote(
      id: 'plain_${content.hashCode}',
      content: content,
      date: '2025-01-01T00:00:00.000Z',
    );
  }

  Quote createDeltaQuoteWithImage() {
    final delta = jsonEncode([
      {
        'insert': {
          'image': 'https://example.com/image.png',
        }
      },
      {'insert': '\n'},
      {'insert': '配图说明'},
      {'insert': '\n'},
    ]);

    return Quote(
      id: 'rich_image',
      content: '包含图片的笔记',
      date: '2025-01-01T00:00:00.000Z',
      editSource: 'fullscreen',
      deltaContent: delta,
    );
  }

  testWidgets('折叠状态下长文本会使用裁剪包装器', (tester) async {
    final quote = createPlainQuote('A' * 400);
    await tester.pumpWidget(buildTestApp(quote));

    expect(find.byKey(QuoteContent.collapsedWrapperKey), findsOneWidget);
  });

  testWidgets('短文本不会启用折叠裁剪', (tester) async {
    final quote = createPlainQuote('简短内容');

    await tester.pumpWidget(buildTestApp(quote));

    expect(find.byKey(QuoteContent.collapsedWrapperKey), findsNothing);
  });

  test('富文本图片内容需要折叠', () {
    final quote = createDeltaQuoteWithImage();

    expect(QuoteContent.exceedsCollapsedHeight(quote), isTrue);
    expect(QuoteItemWidget.needsExpansionFor(quote), isTrue);
  });

  test('纯文本与富文本高度判定保持一致', () {
    final longText = '这是一段超过折叠阈值的文本' * 60;
    final plainQuote = createPlainQuote(longText);
    final deltaText = jsonEncode([
      {
        'insert': longText,
      },
    ]);
    final richQuote = Quote(
      id: 'rich_text',
      content: plainQuote.content,
      date: plainQuote.date,
      editSource: 'fullscreen',
      deltaContent: deltaText,
    );

    expect(QuoteItemWidget.needsExpansionFor(plainQuote), isTrue);
    expect(QuoteItemWidget.needsExpansionFor(richQuote), isTrue);
  });
}
