import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;
import 'package:provider/provider.dart';
import 'package:thoughtecho/gen_l10n/app_localizations.dart';
import 'package:thoughtecho/models/app_settings.dart';
import 'package:thoughtecho/models/quote_model.dart';
import 'package:thoughtecho/services/settings_service.dart';
import 'package:thoughtecho/utils/quill_editor_extensions.dart';
import 'package:thoughtecho/widgets/motion_photo_preview_page.dart';
import 'package:thoughtecho/widgets/note_list/collapsed_media_banner.dart';
import 'package:thoughtecho/widgets/note_list/collapsed_media_image.dart';
import 'package:thoughtecho/widgets/note_list/collapsed_media_thumbnail.dart';
import 'package:thoughtecho/widgets/note_list/collapsed_rich_text.dart';
import 'package:thoughtecho/widgets/quote_content_widget.dart';
import 'package:thoughtecho/widgets/quote_item_widget.dart';
import 'package:visibility_detector/visibility_detector.dart';

class _TestSettingsService extends ChangeNotifier implements SettingsService {
  bool _prioritizeBold;
  String _mediaStyle;

  _TestSettingsService({
    bool prioritizeBold = false,
    String mediaStyle = NoteCardMediaStyle.thumbnail,
  })  : _prioritizeBold = prioritizeBold,
        _mediaStyle = mediaStyle;

  @override
  bool get prioritizeBoldContentInCollapse => _prioritizeBold;

  @override
  Future<void> setPrioritizeBoldContentInCollapse(bool enabled) async {
    _prioritizeBold = enabled;
    notifyListeners();
  }

  @override
  String get noteCardMediaStyle => _mediaStyle;

  @override
  Future<void> setNoteCardMediaStyle(String style) async {
    _mediaStyle = style;
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
    // QuoteContent 的 Document / Controller 缓存是静态的，用例之间会通过它耦合：
    // 下面几条只有版式不同、笔记完全相同，不统一清就会读到上一个版式的缓存文档，
    // 而且这种耦合会随着新增用例或调整顺序悄悄失效。
    QuoteContent.clearCacheForTesting();
    QuoteItemWidget.clearExpansionCache();
    isListScrolling.value = false;
    isListDragActive.value = false;
  });

  tearDown(() {
    isListScrolling.value = false;
    isListDragActive.value = false;
  });

  Widget buildTestApp(
    Quote quote, {
    bool prioritizeBold = false,
    bool showFullContent = false,
    bool? needsExpansionOverride,
    double? contentWidth,
    String mediaStyle = NoteCardMediaStyle.thumbnail,
  }) {
    return ChangeNotifierProvider<SettingsService>.value(
      value: _TestSettingsService(
        prioritizeBold: prioritizeBold,
        mediaStyle: mediaStyle,
      ),
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

  testWidgets('thumbnail 版式：折叠卡片不建 QuillEditor，媒体走独立缩略图', (tester) async {
    final quote = createDeltaQuoteWithImage();

    await tester.pumpWidget(
      buildTestApp(quote, needsExpansionOverride: true, contentWidth: 320),
    );
    await tester.pump();

    // 这是阶段 D 的核心断言：折叠态**一个 QuillEditor 都不建**。没有编辑器就没有
    // 20~48ms 的冷首布局，也就不需要占位、每帧额度和恢复队列那一整套时序机制。
    expect(find.byType(quill.QuillEditor), findsNothing);
    expect(find.byType(CollapsedRichText), findsOneWidget);
    expect(find.byType(CollapsedMediaThumbnail), findsOneWidget);

    // 媒体摘出正文之后，正文本身不该再画任何媒体。
    final richText = tester.widget<CollapsedRichText>(
      find.byType(CollapsedRichText),
    );
    expect(richText.showMedia, isFalse);
  });

  testWidgets('inline 版式把媒体留在正文原位，且不实例化播放器', (tester) async {
    final quote = createDeltaQuoteWithImage();

    await tester.pumpWidget(
      buildTestApp(
        quote,
        needsExpansionOverride: true,
        contentWidth: 320,
        mediaStyle: NoteCardMediaStyle.inline,
      ),
    );
    await tester.pump();

    expect(find.byType(quill.QuillEditor), findsNothing);
    expect(find.byType(CollapsedMediaThumbnail), findsNothing);

    final richText = tester.widget<CollapsedRichText>(
      find.byType(CollapsedRichText),
    );
    expect(richText.showMedia, isTrue);
    // 媒体块按原位留在块序列里，正文因此是「文字段, 媒体, 文字段…」的交错。
    expect(
      richText.blocks.any((block) => block.isMedia),
      isTrue,
    );
  });

  testWidgets('banner 版式把媒体画在卡片顶部且正文不含媒体', (tester) async {
    final quote = createDeltaQuoteWithImage();

    await tester.pumpWidget(
      buildTestApp(
        quote,
        needsExpansionOverride: true,
        contentWidth: 320,
        mediaStyle: NoteCardMediaStyle.banner,
      ),
    );
    await tester.pump();

    expect(find.byType(quill.QuillEditor), findsNothing);
    expect(find.byType(CollapsedMediaBanner), findsOneWidget);
    expect(find.byType(CollapsedMediaThumbnail), findsNothing);

    final richText = tester.widget<CollapsedRichText>(
      find.byType(CollapsedRichText),
    );
    expect(richText.showMedia, isFalse);
  });

  testWidgets('切换版式立刻改变正文渲染，不会读到上一版式的结果', (tester) async {
    final quote = createDeltaQuoteWithImage();

    await tester.pumpWidget(
      buildTestApp(
        quote,
        needsExpansionOverride: true,
        contentWidth: 320,
        mediaStyle: NoteCardMediaStyle.inline,
      ),
    );
    await tester.pump();
    expect(
      tester
          .widget<CollapsedRichText>(find.byType(CollapsedRichText))
          .showMedia,
      isTrue,
    );

    await tester.pumpWidget(
      buildTestApp(
        quote,
        needsExpansionOverride: true,
        contentWidth: 320,
        mediaStyle: NoteCardMediaStyle.thumbnail,
      ),
    );
    await tester.pump();
    expect(
      tester
          .widget<CollapsedRichText>(find.byType(CollapsedRichText))
          .showMedia,
      isFalse,
    );
    expect(find.byType(CollapsedMediaThumbnail), findsOneWidget);
  });

  testWidgets('点击缩略图打开大图预览', (tester) async {
    final quote = createDeltaQuoteWithImage();

    await tester.pumpWidget(
      buildTestApp(
        quote,
        needsExpansionOverride: true,
        contentWidth: 320,
      ),
    );
    await tester.pump();

    await tester.tap(find.byType(CollapsedMediaThumbnail));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byType(MotionPhotoPreviewPage), findsOneWidget);
  });

  testWidgets('只有音视频时不安装点击手势，避免空操作吞掉卡片交互', (tester) async {
    final quote = Quote(
      id: 'rich_audio_only',
      content: '只有音频的笔记',
      date: '2025-01-01T00:00:00.000Z',
      editSource: 'fullscreen',
      deltaContent: jsonEncode([
        {
          'insert': {
            'custom': {'audio': '/path/rec.m4a'},
          },
        },
        {'insert': '\n'},
        {'insert': '音频说明'},
        {'insert': '\n'},
      ]),
    );

    await tester.pumpWidget(
      buildTestApp(
        quote,
        needsExpansionOverride: true,
        contentWidth: 320,
      ),
    );
    await tester.pump();

    final thumbnail = tester.widget<CollapsedMediaThumbnail>(
      find.byType(CollapsedMediaThumbnail),
    );
    expect(thumbnail.onTap, isNull);
  });

  testWidgets('媒体被摘走后折叠盒按内容收缩，不再留一大块空白', (tester) async {
    // 带图笔记必然折叠（高度估算里一张图算 200px > 160px），但摘掉图之后正文
    // 可能只剩一两行。折叠盒若维持定高 160px，差额就是卡片里那块突兀的空白。
    final quote = createDeltaQuoteWithImage();

    await tester.pumpWidget(
      buildTestApp(
        quote,
        needsExpansionOverride: true,
        contentWidth: 320,
      ),
    );
    await tester.pump();

    final wrapperHeight =
        tester.getSize(find.byKey(QuoteContent.collapsedWrapperKey)).height;
    expect(
      wrapperHeight,
      lessThan(QuoteContent.collapsedContentMaxHeight),
      reason: '短正文不该被撑到折叠上限',
    );
    expect(wrapperHeight, greaterThan(0));
  });

  testWidgets('纯文本长笔记的折叠盒仍然定高，不受收缩逻辑影响', (tester) async {
    final quote = createPlainQuote('A' * 400);

    await tester.pumpWidget(buildTestApp(quote, contentWidth: 320));
    await tester.pump();

    expect(
      tester.getSize(find.byKey(QuoteContent.collapsedWrapperKey)).height,
      QuoteContent.collapsedContentMaxHeight,
    );
  });

  testWidgets('折叠缩略图与卡片同时挂载，不等富文本物化', (tester) async {
    // 这是整套改动的核心不变量：滚动中 Quill 走占位不物化，但缩略图必须已经在树里。
    // 「空白 → 灰框 → 图片」三段式的前两段就是图片被挡在富文本物化时序后面造成的。
    //
    // 冷启动场景由 setUp 里的统一清缓存保证：控制器缓存命中时按设计会跳过延迟
    // 物化（见 _buildRichTextContent 里的 contains 判断）。
    isListScrolling.value = true;
    addTearDown(() => isListScrolling.value = false);

    final quote = createDeltaQuoteWithImage();

    await tester.pumpWidget(
      buildTestApp(
        quote,
        needsExpansionOverride: true,
        contentWidth: 320,
      ),
    );
    await tester.pump();

    expect(find.byType(quill.QuillEditor), findsNothing);
    expect(find.byType(CollapsedMediaThumbnail), findsOneWidget);
  });

  testWidgets('展开态仍由 Quill 渲染完整图文混排', (tester) async {
    final quote = createDeltaQuoteWithImage();

    await tester.pumpWidget(
      buildTestApp(quote, showFullContent: true, contentWidth: 320),
    );
    await tester.pump();

    final editor = tester.widget<quill.QuillEditor>(
      find.byType(quill.QuillEditor),
    );
    final embedCount = editor.controller.document
        .toDelta()
        .toJson()
        .where((op) => op['insert'] is Map)
        .length;
    expect(embedCount, 1);
    expect(find.byType(CollapsedMediaThumbnail), findsNothing);
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

  testWidgets('滚动期间折叠卡片照常渲染正文，不再有占位→富文本两段式', (tester) async {
    // 阶段 D 之前，滚动中的折叠卡片显示的是 `Text(quote.content)` 轻量占位，停下
    // 才换成 Quill 文档——「停下闪一下」就是这么来的。现在正文从第一帧起就是最终
    // 形态，滚动信号对它不再有任何影响。
    final longText = '滚动期间也要看到真正的正文。' * 40;
    final quote = Quote(
      id: 'rich_no_deferral',
      content: longText,
      date: '2025-01-01T00:00:00.000Z',
      editSource: 'fullscreen',
      deltaContent: jsonEncode([
        {'insert': longText},
        {'insert': '\n'},
      ]),
    );

    isListScrolling.value = true;
    isListDragActive.value = true;

    await tester.pumpWidget(
      buildTestApp(quote, needsExpansionOverride: true, contentWidth: 320),
    );
    await tester.pump();

    expect(find.byType(CollapsedRichText), findsOneWidget);
    expect(find.byType(quill.QuillEditor), findsNothing);

    // 滚动停止不改变任何东西：没有需要「恢复」的东西了。
    final duringScroll = tester.widget<CollapsedRichText>(
      find.byType(CollapsedRichText),
    );
    isListScrolling.value = false;
    isListDragActive.value = false;
    await tester.pump();
    final afterScroll = tester.widget<CollapsedRichText>(
      find.byType(CollapsedRichText),
    );
    expect(afterScroll.plan.entries.length, duringScroll.plan.entries.length);
    expect(afterScroll.plan.height, duringScroll.plan.height);
  });

  testWidgets('排版工作量有上界：超长笔记也只排折叠盒装得下的那几行', (tester) async {
    // 旧实现每加一个 op 就把已累积的全部 span 重新 layout 一次（O(n²)，单次最坏
    // 实测 14.5ms，且发生在滚动帧内）。现在改成给每个块一个行数预算，预算和正文
    // 长度无关。
    final hugeText = '这段正文非常长，长到远远超过折叠盒能显示的范围。' * 400;
    final quote = Quote(
      id: 'rich_huge',
      content: hugeText,
      date: '2025-01-01T00:00:00.000Z',
      editSource: 'fullscreen',
      deltaContent: jsonEncode([
        {'insert': hugeText},
        {'insert': '\n'},
      ]),
    );

    await tester.pumpWidget(
      buildTestApp(quote, needsExpansionOverride: true, contentWidth: 320),
    );
    await tester.pump();

    final richText = tester.widget<CollapsedRichText>(
      find.byType(CollapsedRichText),
    );
    // 160px 的盒子按 16×1.5 的行高最多 11 行；预算再宽也不该到两位数以上。
    expect(richText.plan.entries, hasLength(1));
    expect(richText.plan.entries.single.maxLines, lessThanOrEqualTo(12));
    expect(richText.plan.entries.single.maxLines, greaterThan(0));
  });

  testWidgets('折叠态不会为看不见的媒体建图片组件', (tester) async {
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
        mediaStyle: NoteCardMediaStyle.inline,
      ),
    );
    await tester.pump();

    // 正文已经把行数预算用完，后面两张图根本不该进 widget 树。
    expect(find.byType(CollapsedMediaImage), findsNothing);

    // 展开态仍然由 Quill 渲染完整图文混排，两张图一张不少。
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

  testWidgets('折叠盒宽度变化会重新测量，不会沿用上一次宽度的高度', (tester) async {
    final delta = jsonEncode([
      {'insert': '中等长度的一段正文，窄一点就会多折几行。' * 6},
      {'insert': '\n'},
    ]);
    final quote = Quote(
      id: 'rich_width_sensitive',
      content: '中等长度的一段正文',
      date: '2025-01-01T00:00:00.000Z',
      editSource: 'fullscreen',
      deltaContent: delta,
    );

    Future<double> boxHeightAt(double width) async {
      QuoteContent.clearCacheForTesting();
      await tester.pumpWidget(
        buildTestApp(quote, needsExpansionOverride: true, contentWidth: width),
      );
      await tester.pump();
      return tester
          .getSize(find.byKey(QuoteContent.collapsedWrapperKey))
          .height;
    }

    final wide = await boxHeightAt(480);
    final narrow = await boxHeightAt(200);

    // 同一段正文变窄会折更多行，盒子只会更高（封顶 160）。
    expect(narrow, greaterThanOrEqualTo(wide));
    expect(narrow, lessThanOrEqualTo(QuoteContent.collapsedContentMaxHeight));
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
