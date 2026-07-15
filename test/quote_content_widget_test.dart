import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;
import 'package:provider/provider.dart';
import 'package:thoughtecho/gen_l10n/app_localizations.dart';
import 'package:thoughtecho/models/quote_model.dart';
import 'package:thoughtecho/services/settings_service.dart';
import 'package:thoughtecho/utils/quill_editor_extensions.dart';
import 'package:thoughtecho/widgets/quote_content_widget.dart';
import 'package:thoughtecho/widgets/quote_item_widget.dart';
import 'package:visibility_detector/visibility_detector.dart';

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
  setUpAll(() {
    VisibilityDetectorController.instance.updateInterval = Duration.zero;
  });

  setUp(() {
    QuoteItemWidget.clearExpansionCache();
    isListScrolling.value = false;
  });

  tearDown(() {
    isListScrolling.value = false;
  });

  Widget buildTestApp(
    Quote quote, {
    bool prioritizeBold = false,
    bool showFullContent = false,
    bool? needsExpansionOverride,
    double? contentWidth,
  }) {
    return ChangeNotifierProvider<SettingsService>.value(
      value: _TestSettingsService(prioritizeBold: prioritizeBold),
      child: MaterialApp(
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('zh'),
        home: Scaffold(
          body: SizedBox(
            width: contentWidth,
            child: QuoteContent(
              quote: quote,
              style: const TextStyle(fontSize: 16, height: 1.5),
              showFullContent: showFullContent,
              needsExpansionOverride: needsExpansionOverride,
            ),
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
        'insert': {'image': 'https://example.com/image.png'},
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

  testWidgets('折叠裁剪不会让不可见内容进行无界高度布局', (tester) async {
    final quote = createPlainQuote('A' * 400);
    await tester.pumpWidget(buildTestApp(quote));

    final collapsedWrapper = find.byKey(QuoteContent.collapsedWrapperKey);
    expect(collapsedWrapper, findsOneWidget);
    expect(
      find.descendant(
        of: collapsedWrapper,
        matching: find.byType(OverflowBox),
      ),
      findsNothing,
    );
  });

  testWidgets('短文本不会启用折叠裁剪', (tester) async {
    final quote = createPlainQuote('简短内容');

    await tester.pumpWidget(buildTestApp(quote));

    expect(find.byKey(QuoteContent.collapsedWrapperKey), findsNothing);
  });

  testWidgets('外层布局测量可覆盖静态折叠判定', (tester) async {
    final quote = createPlainQuote('简短内容');

    await tester.pumpWidget(
      buildTestApp(quote, needsExpansionOverride: true),
    );

    expect(find.byKey(QuoteContent.collapsedWrapperKey), findsOneWidget);
  });

  test('富文本图片内容需要折叠', () {
    final quote = createDeltaQuoteWithImage();

    expect(QuoteContent.exceedsCollapsedHeight(quote), isTrue);
    expect(QuoteItemWidget.needsExpansionFor(quote), isTrue);
  });

  testWidgets('折叠前缀保留与可见区域相交的图片', (tester) async {
    final quote = createDeltaQuoteWithImage();

    await tester.pumpWidget(
      buildTestApp(
        quote,
        needsExpansionOverride: true,
        contentWidth: 320,
      ),
    );
    await tester.pump();

    final editor = tester.widget<quill.QuillEditor>(
      find.byType(quill.QuillEditor),
    );
    final imageCount = editor.controller.document
        .toDelta()
        .toJson()
        .where((op) => op['insert'] is Map)
        .length;
    expect(imageCount, 1);
  });

  testWidgets('折叠状态下长富文本仍使用裁剪包装器', (tester) async {
    final delta = jsonEncode([
      {'insert': '这是一段很长的图片前正文。' * 80},
      {
        'insert': {'image': 'https://example.com/folded-image.png'},
      },
      {'insert': '\n'},
    ]);
    final quote = Quote(
      id: 'rich_text_then_image',
      content: '长正文后带图片的笔记',
      date: '2025-01-01T00:00:00.000Z',
      editSource: 'fullscreen',
      deltaContent: delta,
    );

    await tester.pumpWidget(buildTestApp(quote));
    await tester.pump();

    expect(find.byKey(QuoteContent.collapsedWrapperKey), findsOneWidget);
  });

  testWidgets('高速滚动中新出现的折叠富文本会等列表停下再创建 Quill', (tester) async {
    final longText = '滚动期间只显示轻量预览。' * 80;
    final quote = Quote(
      id: 'rich_deferred_while_scrolling',
      content: longText,
      date: '2025-01-01T00:00:00.000Z',
      editSource: 'fullscreen',
      deltaContent: jsonEncode([
        {
          'insert': longText,
          'attributes': {'bold': true},
        },
        {'insert': '\n'},
      ]),
    );
    QuoteContent.clearCacheForTesting();
    isListScrolling.value = true;

    await tester.pumpWidget(
      buildTestApp(
        quote,
        needsExpansionOverride: true,
        contentWidth: 320,
      ),
    );
    await tester.pump();

    expect(find.byType(quill.QuillEditor), findsNothing);
    expect(find.byKey(QuoteContent.collapsedWrapperKey), findsOneWidget);
    final placeholderText = tester.widget<Text>(
      find.descendant(
        of: find.byKey(QuoteContent.collapsedWrapperKey),
        matching: find.byType(Text),
      ),
    );
    expect(placeholderText.data!.length, lessThan(longText.length));
    expect(
      QuoteContent.debugCacheStats()['controller'],
      containsPair('createCount', 0),
    );
    expect(
      QuoteContent.debugCacheStats()['document'],
      allOf(
        containsPair('missCount', 0),
        containsPair('workMicros', 0),
      ),
    );

    isListScrolling.value = false;
    await tester.pump();

    expect(find.byType(quill.QuillEditor), findsOneWidget);

    isListScrolling.value = true;
    await tester.pump();

    expect(find.byType(quill.QuillEditor), findsOneWidget);
  });

  testWidgets('滚动停止后冷富文本会逐帧恢复而不是同一帧集中创建', (tester) async {
    final longText = '停止后逐帧恢复富文本。' * 80;
    final quotes = List<Quote>.generate(
      3,
      (index) => Quote(
        id: 'rich_staggered_$index',
        content: longText,
        date: '2025-01-01T00:00:0$index.000Z',
        editSource: 'fullscreen',
        deltaContent: jsonEncode([
          {'insert': '$longText\n'},
        ]),
      ),
    );
    QuoteContent.clearCacheForTesting();
    isListScrolling.value = true;

    await tester.pumpWidget(
      ChangeNotifierProvider<SettingsService>.value(
        value: _TestSettingsService(),
        child: MaterialApp(
          home: Scaffold(
            body: Column(
              children: quotes
                  .map(
                    (quote) => SizedBox(
                      width: 320,
                      height: QuoteContent.collapsedContentMaxHeight,
                      child: QuoteContent(
                        quote: quote,
                        style: const TextStyle(fontSize: 16, height: 1.5),
                        needsExpansionOverride: true,
                      ),
                    ),
                  )
                  .toList(),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.byType(quill.QuillEditor), findsNothing);

    isListScrolling.value = false;
    await tester.pump();
    expect(find.byType(quill.QuillEditor), findsOneWidget);

    await tester.pump();
    expect(find.byType(quill.QuillEditor), findsNWidgets(2));

    await tester.pump();
    expect(find.byType(quill.QuillEditor), findsNWidgets(3));
  });

  testWidgets('滚动停止后优先恢复屏幕内的冷富文本', (tester) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    final longText = '可见卡片应当先恢复富文本。' * 80;
    final quotes = List<Quote>.generate(
      3,
      (index) => Quote(
        id: 'rich_visible_first_$index',
        content: longText,
        date: '2025-01-01T00:00:0$index.000Z',
        editSource: 'fullscreen',
        deltaContent: jsonEncode([
          {'insert': '$longText\n'},
        ]),
      ),
    );
    QuoteContent.clearCacheForTesting();
    isListScrolling.value = true;

    await tester.pumpWidget(
      ChangeNotifierProvider<SettingsService>.value(
        value: _TestSettingsService(),
        child: MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.topCenter,
              child: SizedBox(
                width: 320,
                height: QuoteContent.collapsedContentMaxHeight,
                child: SingleChildScrollView(
                  controller: controller,
                  child: Column(
                    children: List<Widget>.generate(
                      quotes.length,
                      (index) => SizedBox(
                        key: ValueKey('deferred-rich-$index'),
                        height: QuoteContent.collapsedContentMaxHeight,
                        child: QuoteContent(
                          quote: quotes[index],
                          style: const TextStyle(fontSize: 16, height: 1.5),
                          needsExpansionOverride: true,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    controller.jumpTo(controller.position.maxScrollExtent);
    await tester.pump();

    isListScrolling.value = false;
    await tester.pump();

    expect(
      find.descendant(
        of: find.byKey(const ValueKey('deferred-rich-2')),
        matching: find.byType(quill.QuillEditor),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('deferred-rich-0')),
        matching: find.byType(quill.QuillEditor),
      ),
      findsNothing,
    );
  });

  testWidgets('折叠态长富文本只给 QuillEditor 截断 Document', (tester) async {
    final longText = '一段很长的富文本内容' * 80;
    final delta = jsonEncode([
      {
        'insert': longText,
        'attributes': {'bold': true},
      },
      {'insert': '\n后续不可见内容' * 40},
    ]);
    final quote = Quote(
      id: 'rich_truncated_document',
      content: '$longText${'后续不可见内容' * 40}',
      date: '2025-01-01T00:00:00.000Z',
      editSource: 'fullscreen',
      deltaContent: delta,
    );

    await tester.pumpWidget(
      buildTestApp(quote, needsExpansionOverride: true),
    );
    await tester.pump();

    final collapsedEditor = tester.widget<quill.QuillEditor>(
      find.byType(quill.QuillEditor),
    );
    final collapsedDelta =
        collapsedEditor.controller.document.toDelta().toJson();
    final collapsedText =
        collapsedDelta.map((op) => op['insert']).whereType<String>().join();

    expect(find.byKey(QuoteContent.collapsedWrapperKey), findsOneWidget);
    expect(collapsedText.length, lessThan(quote.content.length));

    QuoteContent.clearCacheForTesting();
    await tester.pumpWidget(
      buildTestApp(
        quote,
        showFullContent: true,
        needsExpansionOverride: true,
      ),
    );
    await tester.pump();

    final fullEditor = tester.widget<quill.QuillEditor>(
      find.byType(quill.QuillEditor),
    );
    final fullDelta = fullEditor.controller.document.toDelta().toJson();
    final fullText =
        fullDelta.map((op) => op['insert']).whereType<String>().join();

    expect(find.byKey(QuoteContent.collapsedWrapperKey), findsNothing);
    expect(fullText.length, greaterThan(collapsedText.length));
  });

  testWidgets('折叠态不会把可见正文之后的图片交给 Quill 布局', (tester) async {
    final longText = '这段正文足以填满折叠预览。' * 25;
    final delta = jsonEncode([
      {'insert': longText},
      {'insert': '\n'},
      {
        'insert': {'image': 'https://example.com/invisible-1.png'},
      },
      {'insert': '\n'},
      {
        'insert': {'image': 'https://example.com/invisible-2.png'},
      },
      {'insert': '\n'},
    ]);
    final quote = Quote(
      id: 'rich_invisible_images',
      content: longText,
      date: '2025-01-01T00:00:00.000Z',
      editSource: 'fullscreen',
      deltaContent: delta,
    );

    await tester.pumpWidget(
      buildTestApp(
        quote,
        needsExpansionOverride: true,
        contentWidth: 320,
      ),
    );
    await tester.pump();

    final collapsedEditor = tester.widget<quill.QuillEditor>(
      find.byType(quill.QuillEditor),
    );
    final collapsedImages = collapsedEditor.controller.document
        .toDelta()
        .toJson()
        .where((op) => op['insert'] is Map)
        .length;
    expect(collapsedImages, 0);

    QuoteContent.clearCacheForTesting();
    await tester.pumpWidget(
      buildTestApp(
        quote,
        showFullContent: true,
        needsExpansionOverride: true,
        contentWidth: 320,
      ),
    );
    await tester.pump();

    final expandedEditor = tester.widget<quill.QuillEditor>(
      find.byType(quill.QuillEditor),
    );
    final expandedImages = expandedEditor.controller.document
        .toDelta()
        .toJson()
        .where((op) => op['insert'] is Map)
        .length;
    expect(expandedImages, 2);
  });

  testWidgets('折叠前缀与完整 Quill 的可见区域像素一致', (tester) async {
    final delta = jsonEncode([
      {
        'insert': '粗体开头',
        'attributes': {'bold': true},
      },
      {
        'insert': '和小字号正文共同组成第一段。' * 35,
        'attributes': {'size': 'small'},
      },
      {'insert': '\n'},
      {
        'insert': '不可见的后续内容',
        'attributes': {'italic': true},
      },
      {'insert': '\n'},
    ]);
    final quote = Quote(
      id: 'rich_visible_pixels',
      content: '粗体开头和普通正文共同组成第一段。',
      date: '2025-01-01T00:00:00.000Z',
      editSource: 'fullscreen',
      deltaContent: delta,
    );
    final collapsedKey = GlobalKey();
    final fullKey = GlobalKey();

    await tester.pumpWidget(
      ChangeNotifierProvider<SettingsService>.value(
        value: _TestSettingsService(),
        child: MaterialApp(
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('zh'),
          home: Scaffold(
            body: Column(
              children: [
                RepaintBoundary(
                  key: collapsedKey,
                  child: SizedBox(
                    width: 320,
                    height: QuoteContent.collapsedContentMaxHeight,
                    child: QuoteContent(
                      quote: quote,
                      style: const TextStyle(fontSize: 16, height: 1.5),
                      needsExpansionOverride: true,
                    ),
                  ),
                ),
                RepaintBoundary(
                  key: fullKey,
                  child: ClipRect(
                    child: SizedBox(
                      width: 320,
                      height: QuoteContent.collapsedContentMaxHeight,
                      child: QuoteContent(
                        quote: quote,
                        style: const TextStyle(fontSize: 16, height: 1.5),
                        needsExpansionOverride: false,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    Future<List<int>> pixelsFor(GlobalKey key) async {
      final boundary =
          key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 1);
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      image.dispose();
      return data!.buffer.asUint8List();
    }

    final collapsedPixels = await tester.runAsync(
      () => pixelsFor(collapsedKey),
    );
    final fullPixels = await tester.runAsync(
      () => pixelsFor(fullKey),
    );
    expect(collapsedPixels, fullPixels);
  });

  testWidgets('折叠前缀缓存按实际宽度区分', (tester) async {
    final longText = '宽屏应当保留更多可见正文。' * 50;
    final quote = Quote(
      id: 'rich_width_cache',
      content: longText,
      date: '2025-01-01T00:00:00.000Z',
      editSource: 'fullscreen',
      deltaContent: jsonEncode([
        {'insert': longText},
        {'insert': '\n'},
      ]),
    );

    Future<int> collapsedTextLength(double width) async {
      await tester.pumpWidget(
        buildTestApp(
          quote,
          needsExpansionOverride: true,
          contentWidth: width,
        ),
      );
      await tester.pump();
      final editor = tester.widget<quill.QuillEditor>(
        find.byType(quill.QuillEditor),
      );
      return editor.controller.document
          .toDelta()
          .toJson()
          .map((op) => op['insert'])
          .whereType<String>()
          .join()
          .length;
    }

    final narrowLength = await collapsedTextLength(280);
    final wideLength = await collapsedTextLength(560);

    expect(wideLength, greaterThan(narrowLength));
  });

  test('纯文本与富文本高度判定保持一致', () {
    final longText = '这是一段超过折叠阈值的文本' * 60;
    final plainQuote = createPlainQuote(longText);
    final deltaText = jsonEncode([
      {'insert': longText},
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
