import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';
import 'package:thoughtecho/models/app_settings.dart';
import 'package:thoughtecho/models/note_tag.dart';
import 'package:thoughtecho/models/quote_model.dart';
import 'package:thoughtecho/services/settings_service.dart';
import 'package:thoughtecho/widgets/note_list/collapsed_media_thumbnail.dart';
import 'package:thoughtecho/widgets/note_list/collapsed_rich_text.dart';
import 'package:thoughtecho/widgets/quote_item_widget.dart';
import 'package:thoughtecho/gen_l10n/app_localizations.dart';

class _FakeSettingsService extends ChangeNotifier implements SettingsService {
  bool _prioritizeBoldContentInCollapse = false;
  bool _showExactTime = false;
  bool _showNoteEditTime = false;

  @override
  bool get prioritizeBoldContentInCollapse => _prioritizeBoldContentInCollapse;

  set prioritizeBoldContentInCollapse(bool value) {
    if (_prioritizeBoldContentInCollapse != value) {
      _prioritizeBoldContentInCollapse = value;
      notifyListeners();
    }
  }

  @override
  bool get showExactTime => _showExactTime;

  set showExactTime(bool value) {
    if (_showExactTime != value) {
      _showExactTime = value;
      notifyListeners();
    }
  }

  @override
  bool get showNoteEditTime => _showNoteEditTime;

  @override
  bool get noteListDisableCardShadows => false;

  @override
  bool get noteListDisableBackdropBlur => false;

  @override
  String get exportFormat => 'card';

  @override
  String get noteCardMediaStyle => NoteCardMediaStyle.thumbnail;

  set showNoteEditTime(bool value) {
    if (_showNoteEditTime != value) {
      _showNoteEditTime = value;
      notifyListeners();
    }
  }

  // 不需要的方法抛出未实现异常，确保测试中不会被误用。
  @override
  noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('SettingsService.${invocation.memberName} 未实现');
}

Quote _buildQuote({
  String id = 'q1',
  String content = 'This is a test note content.',
  String? deltaContent,
  String editSource = 'fullscreen',
  String? date,
  String? lastModified,
  String? sourceAuthor,
}) {
  return Quote(
    id: id,
    content: content,
    date: date ?? DateTime.now().toIso8601String(),
    deltaContent: deltaContent,
    editSource: editSource,
    dayPeriod: 'morning',
    lastModified: lastModified,
    sourceAuthor: sourceAuthor,
  );
}

const String _longContentChunk =
    '这是一个非常非常长的笔记内容，用于验证折叠逻辑是否生效，包含了足够的文字来超过默认的折叠高度。';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(QuoteItemWidget.clearExpansionCacheForTest);

  group('QuoteItemWidget', () {
    test('缓存统计包含已缓存的可展开数量', () {
      final shortQuote = _buildQuote(
        id: 'short',
        content: '短笔记',
        editSource: 'inline',
      );
      final longQuote = _buildQuote(
        id: 'long',
        content: List.filled(6, _longContentChunk).join('\n'),
        editSource: 'inline',
      );

      expect(QuoteItemWidget.needsExpansionFor(shortQuote), isFalse);
      expect(QuoteItemWidget.needsExpansionFor(longQuote), isTrue);

      expect(
        QuoteItemWidget.getCacheStats(),
        containsPair('expandableCount', 1),
      );
    });

    testWidgets('重复卡片头部文本测宽复用缓存', (tester) async {
      final quote = _buildQuote(
        id: 'same-header-1',
        date: DateTime(2025, 6, 21, 9, 0).toIso8601String(),
        editSource: 'inline',
      );

      await tester.pumpWidget(
        ChangeNotifierProvider<SettingsService>.value(
          value: _FakeSettingsService(),
          child: MaterialApp(
            localizationsDelegates: const [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
            ],
            supportedLocales: AppLocalizations.supportedLocales,
            locale: const Locale('zh'),
            home: Material(
              child: Column(
                children: [
                  QuoteItemWidget(
                    quote: quote,
                    tagMap: const {},
                    isExpanded: false,
                    onToggleExpanded: (_) {},
                    onEdit: () {},
                    onDelete: () {},
                    onAskAI: () {},
                  ),
                  QuoteItemWidget(
                    quote: quote.copyWith(id: 'same-header-2'),
                    tagMap: const {},
                    isExpanded: false,
                    onToggleExpanded: (_) {},
                    onEdit: () {},
                    onDelete: () {},
                    onAskAI: () {},
                  ),
                ],
              ),
            ),
          ),
        ),
      );

      final stats = QuoteItemWidget.getHeaderTextWidthCacheStats();
      expect(stats['cacheSize'], greaterThanOrEqualTo(1));
      expect(stats['cacheMisses'], greaterThanOrEqualTo(1));
      expect(stats['cacheHits'], greaterThanOrEqualTo(1));
    });

    testWidgets('普通折叠卡片使用非动画外壳', (tester) async {
      final quote = _buildQuote(editSource: 'inline');

      await tester.pumpWidget(
        ChangeNotifierProvider<SettingsService>.value(
          value: _FakeSettingsService(),
          child: MaterialApp(
            localizationsDelegates: const [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
            ],
            supportedLocales: AppLocalizations.supportedLocales,
            locale: const Locale('zh'),
            home: Material(
              child: QuoteItemWidget(
                quote: quote,
                tagMap: const {},
                isExpanded: false,
                onToggleExpanded: (_) {},
                onEdit: () {},
                onDelete: () {},
                onAskAI: () {},
              ),
            ),
          ),
        ),
      );

      expect(find.byType(AnimatedContainer), findsNothing);
    });

    testWidgets('卡片外边距非负且首条上边距单独收紧', (tester) async {
      // 负 margin/padding 会命中 RenderSliverPadding 的 assert(isNonNegative)，
      // release 关断言看不出来，debug 与测试里 ListView 一挂载就抛异常。
      Future<EdgeInsets> pumpAndReadMargin(double? topMarginOverride) async {
        final quote = _buildQuote(editSource: 'inline');
        await tester.pumpWidget(
          ChangeNotifierProvider<SettingsService>.value(
            value: _FakeSettingsService(),
            child: MaterialApp(
              localizationsDelegates: const [
                AppLocalizations.delegate,
                GlobalMaterialLocalizations.delegate,
                GlobalCupertinoLocalizations.delegate,
                GlobalWidgetsLocalizations.delegate,
              ],
              supportedLocales: AppLocalizations.supportedLocales,
              locale: const Locale('zh'),
              home: Material(
                child: QuoteItemWidget(
                  quote: quote,
                  tagMap: const {},
                  isExpanded: false,
                  onToggleExpanded: (_) {},
                  onEdit: () {},
                  onDelete: () {},
                  onAskAI: () {},
                  topMarginOverride: topMarginOverride,
                ),
              ),
            ),
          ),
        );

        final container = tester.widget<Container>(
          find
              .descendant(
                of: find.byType(RepaintBoundary),
                matching: find.byType(Container),
              )
              .first,
        );
        return container.margin! as EdgeInsets;
      }

      final defaultMargin = await pumpAndReadMargin(null);
      expect(defaultMargin.top, QuoteItemWidget.defaultCardMarginVertical);
      expect(defaultMargin.bottom, QuoteItemWidget.defaultCardMarginVertical);
      expect(defaultMargin.isNonNegative, isTrue);

      final firstItemMargin = await pumpAndReadMargin(
        QuoteItemWidget.firstItemTopMargin,
      );
      expect(firstItemMargin.top, QuoteItemWidget.firstItemTopMargin);
      // 不锁死具体数值——这个值按观感反复调过（6.0 → 4.0 → 2.67 → 4.0 → 12.0，
      // 中间几轮其实是列表自己补了状态栏高度）。这里只锁真正的不变量：为正、
      // 不超过两张卡片之间的间距（否则首条就比列表内部还松），
      // 且下边距和左右都不受影响。
      expect(QuoteItemWidget.firstItemTopMargin, greaterThan(0));
      expect(
        QuoteItemWidget.firstItemTopMargin,
        lessThanOrEqualTo(QuoteItemWidget.defaultCardMarginVertical * 2),
      );
      expect(
        firstItemMargin.bottom,
        QuoteItemWidget.defaultCardMarginVertical,
      );
      expect(firstItemMargin.left, defaultMargin.left);
      expect(firstItemMargin.right, defaultMargin.right);
      expect(firstItemMargin.isNonNegative, isTrue);
    });

    testWidgets('展开卡片保留动画外壳', (tester) async {
      final quote = _buildQuote(
        content: List.filled(6, _longContentChunk).join('\n'),
        editSource: 'inline',
      );

      await tester.pumpWidget(
        ChangeNotifierProvider<SettingsService>.value(
          value: _FakeSettingsService(),
          child: MaterialApp(
            localizationsDelegates: const [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
            ],
            supportedLocales: AppLocalizations.supportedLocales,
            locale: const Locale('zh'),
            home: Material(
              child: QuoteItemWidget(
                quote: quote,
                tagMap: const {},
                isExpanded: true,
                onToggleExpanded: (_) {},
                onEdit: () {},
                onDelete: () {},
                onAskAI: () {},
              ),
            ),
          ),
        ),
      );

      expect(find.byType(AnimatedContainer), findsOneWidget);
    });

    testWidgets('默认状态下展示截断内容并显示提示', (tester) async {
      final quote = _buildQuote(
        content: List.filled(6, _longContentChunk).join('\n'),
        editSource: 'inline',
      );

      expect(QuoteItemWidget.needsExpansionFor(quote), isTrue);

      await tester.pumpWidget(
        ChangeNotifierProvider<SettingsService>.value(
          value: _FakeSettingsService(),
          child: MaterialApp(
            localizationsDelegates: const [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
            ],
            supportedLocales: AppLocalizations.supportedLocales,
            locale: const Locale('zh'),
            home: Material(
              child: QuoteItemWidget(
                quote: quote,
                tagMap: const {},
                isExpanded: false,
                onToggleExpanded: (_) {},
                onEdit: () {},
                onDelete: () {},
                onAskAI: () {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('非常长的笔记内容'), findsOneWidget);
      expect(find.text('双击查看全文'), findsOneWidget);
    });

    // 手动换行的短行笔记：正文自身宽度远小于卡片宽度，内容区和它下面的提示行
    // 都不能跟着正文收缩。两个测试共用这一份夹具。
    Future<void> pumpShortLineCard(WidgetTester tester) async {
      final quote = _buildQuote(
        id: 'short-lines',
        content: List.filled(12, '短句').join('\n'),
        editSource: 'inline',
      );

      await tester.pumpWidget(
        ChangeNotifierProvider<SettingsService>.value(
          value: _FakeSettingsService(),
          child: MaterialApp(
            localizationsDelegates: const [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
            ],
            supportedLocales: AppLocalizations.supportedLocales,
            locale: const Locale('zh'),
            home: Material(
              child: Center(
                child: SizedBox(
                  width: 400,
                  child: QuoteItemWidget(
                    quote: quote,
                    tagMap: const {},
                    isExpanded: false,
                    onToggleExpanded: (_) {},
                    onEdit: () {},
                    onDelete: () {},
                    onAskAI: () {},
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('每行都未占满宽度时折叠提示仍贴住内容区右缘', (tester) async {
      await pumpShortLineCard(tester);

      expect(find.text('双击查看全文'), findsOneWidget);

      final cardRect = tester.getRect(find.byType(QuoteItemWidget));
      final contentRect = tester.getRect(
        find.byKey(const ValueKey('quote_item.double_tap_region')),
      );
      final hintRect = tester.getRect(find.text('双击查看全文'));

      // 正文自身只有 “短句” 两字宽，但内容区必须撑满卡片，
      // 否则提示行会跟着塌缩到文字宽度上、贴在正文右边而不是卡片右边。
      // 差值只应来自卡片内边距（约 60），而不是塌缩到文字宽度（约 33）。
      expect(contentRect.width, greaterThan(cardRect.width - 80));
      expect(hintRect.right, closeTo(contentRect.right, 8.0));
    });

    testWidgets('有来源时折叠提示并进来源行，不再自己占一行', (tester) async {
      // 提示是右对齐的一小行灰字，来源行是左对齐的一行灰字，两者从来不会争同一段
      // 横向空间。分成两行等于为几个字多撑出一整行——而这种卡片本来就是「内容多到
      // 放不下」的那类，最不该再浪费纵向空间。
      final quote = _buildQuote(
        id: 'truncated-with-source',
        content: List.filled(6, _longContentChunk).join('\n'),
        editSource: 'inline',
        sourceAuthor: '示例作者',
      );

      await tester.pumpWidget(
        ChangeNotifierProvider<SettingsService>.value(
          value: _FakeSettingsService(),
          child: MaterialApp(
            localizationsDelegates: const [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
            ],
            supportedLocales: AppLocalizations.supportedLocales,
            locale: const Locale('zh'),
            home: Material(
              child: Center(
                child: SizedBox(
                  width: 400,
                  child: QuoteItemWidget(
                    quote: quote,
                    tagMap: const {},
                    isExpanded: false,
                    onToggleExpanded: (_) {},
                    onEdit: () {},
                    onDelete: () {},
                    onAskAI: () {},
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final hintRect = tester.getRect(find.text('双击查看全文'));
      final sourceRect = tester.getRect(find.text('——示例作者'));

      // 同一行：两个矩形在纵向上必须相交，而不是一上一下。
      expect(hintRect.top, lessThan(sourceRect.bottom));
      expect(sourceRect.top, lessThan(hintRect.bottom));
      // 来源贴左、提示贴右，中间不重叠。
      expect(sourceRect.right, lessThan(hintRect.left));
    });

    testWidgets('没有来源的笔记，折叠提示仍然自己占一行', (tester) async {
      // 硬凑一行空来源出来反而比提示自己占一行还高，所以这条路径要留着。
      await pumpShortLineCard(tester);

      expect(find.text('双击查看全文'), findsOneWidget);
      expect(find.textContaining('——'), findsNothing);
    });

    testWidgets('折叠提示画在正文下方，不压在正文上', (tester) async {
      // 这一条守的是这次改动的核心：提示不再是盖在正文最后一行上的浮层。
      // 只断言「不在内容区上方」是不够的——压在正文上同样满足那个条件。
      await pumpShortLineCard(tester);

      final bodyRect = tester.getRect(find.textContaining('短句').first);
      final hintRect = tester.getRect(find.text('双击查看全文'));

      expect(hintRect.top, greaterThanOrEqualTo(bodyRect.bottom - 1.0));
    });

    // 右侧缩略图按正文高度分档：短笔记用小档 72，正文排满折叠盒的长笔记放到 96，
    // 一个字都没有的纯图笔记用 132 的居中方图。三条各测一种，共用这份夹具。
    Future<CollapsedMediaThumbnail> pumpMediaCard(
      WidgetTester tester, {
      required String id,
      required String text,
    }) async {
      final delta = jsonEncode([
        if (text.isNotEmpty) {'insert': '$text\n'},
        {
          'insert': {'image': 'https://example.com/photo.png'},
        },
        {'insert': '\n'},
      ]);
      final quote = _buildQuote(
        id: id,
        content: text,
        deltaContent: delta,
        editSource: 'fullscreen',
      );

      await tester.pumpWidget(
        ChangeNotifierProvider<SettingsService>.value(
          value: _FakeSettingsService(),
          child: MaterialApp(
            localizationsDelegates: const [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
            ],
            supportedLocales: AppLocalizations.supportedLocales,
            locale: const Locale('zh'),
            home: Material(
              child: Center(
                child: SizedBox(
                  width: 400,
                  child: QuoteItemWidget(
                    quote: quote,
                    tagMap: const {},
                    isExpanded: false,
                    onToggleExpanded: (_) {},
                    onEdit: () {},
                    onDelete: () {},
                    onAskAI: () {},
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      return tester.widget<CollapsedMediaThumbnail>(
        find.byType(CollapsedMediaThumbnail),
      );
    }

    testWidgets('正文只有一行时右侧缩略图用小档，且不显示折叠提示', (tester) async {
      // 带媒体的笔记一律可展开，但正文一个字都没少——这种卡片不该有提示。
      // 图也不该反过来撑高卡片：一行字配一张大方图，上下各空一截谁也填不满。
      final thumbnail = await pumpMediaCard(
        tester,
        id: 'short-with-image',
        text: '只有一行字的笔记',
      );

      expect(thumbnail.size, CollapsedMediaThumbnail.defaultSize);
      expect(find.text('双击查看全文'), findsNothing);
    });

    testWidgets('正文排满折叠盒时缩略图用最大档，并显示折叠提示', (tester) async {
      final thumbnail = await pumpMediaCard(
        tester,
        id: 'long-with-image',
        text: List.filled(6, _longContentChunk).join(),
      );

      expect(thumbnail.size, CollapsedMediaThumbnail.tallNoteSize);
      expect(find.text('双击查看全文'), findsOneWidget);
    });

    testWidgets('正文越长缩略图越大，不会倒过来', (tester) async {
      // 这一条守的是方向本身：正文短的那张卡片，缩略图不能比正文长的那张还大。
      // 最早的版式正好相反（短笔记 96、长笔记 72），卡片列表看上去就是「越没内容
      // 的笔记占的地方越大」。
      final short = await pumpMediaCard(
        tester,
        id: 'direction-short',
        text: '只有一行字的笔记',
      );
      final long = await pumpMediaCard(
        tester,
        id: 'direction-long',
        text: List.filled(6, _longContentChunk).join(),
      );

      expect(short.size, lessThan(long.size));
    });

    testWidgets('一个字都没有的纯图笔记用更大的方图', (tester) async {
      final thumbnail = await pumpMediaCard(
        tester,
        id: 'image-only',
        text: '',
      );

      expect(thumbnail.size, CollapsedMediaThumbnail.soloMediaSize);
      expect(find.text('双击查看全文'), findsNothing);
    });

    testWidgets('宽布局下实际未溢出的边界文本不显示展开提示', (tester) async {
      final quote = _buildQuote(
        id: 'wide-boundary',
        content: List.filled(170, '界').join(),
        editSource: 'inline',
      );

      expect(QuoteItemWidget.needsExpansionFor(quote), isTrue);

      bool toggled = false;
      await tester.pumpWidget(
        ChangeNotifierProvider<SettingsService>.value(
          value: _FakeSettingsService(),
          child: MaterialApp(
            localizationsDelegates: const [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
            ],
            supportedLocales: AppLocalizations.supportedLocales,
            locale: const Locale('zh'),
            home: Material(
              child: Center(
                child: SizedBox(
                  width: 720,
                  child: QuoteItemWidget(
                    quote: quote,
                    tagMap: const {},
                    isExpanded: false,
                    onToggleExpanded: (_) {
                      toggled = true;
                    },
                    onEdit: () {},
                    onDelete: () {},
                    onAskAI: () {},
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('双击查看全文'), findsNothing);

      final contentGesture = find.byKey(
        const ValueKey('quote_item.double_tap_region'),
      );
      await tester.tap(contentGesture);
      await tester.pump(const Duration(milliseconds: 40));
      await tester.tap(contentGesture);
      await tester.pumpAndSettle();

      expect(toggled, isFalse);
    });

    testWidgets('折叠卡片不再构建模糊遮罩层', (tester) async {
      // 正文按整行截断之后盒底不留半行残字，也就没有东西需要一条模糊带去盖。
      // 每张折叠卡片一个 `BackdropFilter` 的合成开销随之消失——这一条守住它，
      // 免得遮罩哪天又被顺手加回来。
      final quote = _buildQuote(
        content: List.filled(6, _longContentChunk).join('\n'),
        editSource: 'inline',
      );

      await tester.pumpWidget(
        ChangeNotifierProvider<SettingsService>.value(
          value: _FakeSettingsService(),
          child: MaterialApp(
            localizationsDelegates: const [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
            ],
            supportedLocales: AppLocalizations.supportedLocales,
            locale: const Locale('zh'),
            home: Material(
              child: QuoteItemWidget(
                quote: quote,
                tagMap: const {},
                isExpanded: false,
                onToggleExpanded: (_) {},
                onEdit: () {},
                onDelete: () {},
                onAskAI: () {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('双击查看全文'), findsOneWidget);
      expect(
        find.byType(BackdropFilter, skipOffstage: false),
        findsNothing,
      );
    });

    testWidgets('折叠提示文案进入语义树', (tester) async {
      final quote = _buildQuote(
        content: List.filled(6, _longContentChunk).join('\n'),
        editSource: 'inline',
      );

      await tester.pumpWidget(
        ChangeNotifierProvider<SettingsService>.value(
          value: _FakeSettingsService(),
          child: MaterialApp(
            localizationsDelegates: const [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
            ],
            supportedLocales: AppLocalizations.supportedLocales,
            locale: const Locale('zh'),
            home: Material(
              child: QuoteItemWidget(
                quote: quote,
                tagMap: const {},
                isExpanded: false,
                onToggleExpanded: (_) {},
                onEdit: () {},
                onDelete: () {},
                onAskAI: () {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.ancestor(
          of: find.text('双击查看全文'),
          matching: find.byType(ExcludeSemantics),
        ),
        findsNothing,
      );
    });

    testWidgets('展开状态显示完整内容且截断提示消失', (tester) async {
      final quote = _buildQuote(
        content:
            '第一段内容很长很长很长很长很长\n第二段内容也很长很长很长很长很长\n第三段继续很长很长很长很长很长\n第四段也不短\n第五段应该被完整展示',
        editSource: 'inline',
      );

      await tester.pumpWidget(
        ChangeNotifierProvider<SettingsService>.value(
          value: _FakeSettingsService(),
          child: MaterialApp(
            localizationsDelegates: const [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
            ],
            supportedLocales: AppLocalizations.supportedLocales,
            locale: const Locale('zh'),
            home: Material(
              child: QuoteItemWidget(
                quote: quote,
                tagMap: const {},
                isExpanded: true,
                onToggleExpanded: (_) {},
                onEdit: () {},
                onDelete: () {},
                onAskAI: () {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('第五段应该被完整展示'), findsOneWidget);
      expect(find.text('双击查看全文'), findsNothing);
    });

    testWidgets('双击触发展开回调', (tester) async {
      final quote = _buildQuote(
        content: List.filled(6, _longContentChunk).join('\n'),
        editSource: 'inline',
      );

      bool toggled = false;

      await tester.pumpWidget(
        ChangeNotifierProvider<SettingsService>.value(
          value: _FakeSettingsService(),
          child: MaterialApp(
            localizationsDelegates: const [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
            ],
            supportedLocales: AppLocalizations.supportedLocales,
            locale: const Locale('zh'),
            home: Material(
              child: QuoteItemWidget(
                quote: quote,
                tagMap: const {},
                isExpanded: false,
                onToggleExpanded: (expanded) {
                  toggled = expanded;
                },
                onEdit: () {},
                onDelete: () {},
                onAskAI: () {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(QuoteItemWidget.needsExpansionFor(quote), isTrue);

      final contentGesture = find.byKey(
        const ValueKey('quote_item.double_tap_region'),
      );

      await tester.tap(contentGesture);
      await tester.pump(const Duration(milliseconds: 40));
      await tester.tap(contentGesture);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(toggled, isTrue);
    });

    testWidgets('双击时显示高亮反馈', (tester) async {
      final quote = _buildQuote(
        content: List.filled(6, _longContentChunk).join('\n'),
        editSource: 'inline',
      );

      expect(QuoteItemWidget.needsExpansionFor(quote), isTrue);

      await tester.pumpWidget(
        ChangeNotifierProvider<SettingsService>.value(
          value: _FakeSettingsService(),
          child: MaterialApp(
            localizationsDelegates: const [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
            ],
            supportedLocales: AppLocalizations.supportedLocales,
            locale: const Locale('zh'),
            home: Material(
              child: QuoteItemWidget(
                quote: quote,
                tagMap: const {},
                isExpanded: false,
                onToggleExpanded: (_) {},
                onEdit: () {},
                onDelete: () {},
                onAskAI: () {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final gestureDetector = find.byKey(
        const ValueKey('quote_item.double_tap_region'),
      );

      await tester.tap(gestureDetector);
      await tester.pump(const Duration(milliseconds: 40));
      await tester.tap(gestureDetector);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 80));

      expect(
        find.byKey(const ValueKey('quote_item.double_tap_overlay')),
        findsOneWidget,
      );
    });

    testWidgets('富文本默认显示 deltaContent', (tester) async {
      final delta = jsonEncode([
        {
          'insert': '粗体文本',
          'attributes': {'bold': true},
        },
        {'insert': '\n正常文本\n'},
        {
          'insert': {'image': 'https://example.com/img.png'},
        },
      ]);

      final quote = _buildQuote(
        content: 'fallback content',
        deltaContent: delta,
        editSource: 'fullscreen',
      );

      await tester.pumpWidget(
        ChangeNotifierProvider<SettingsService>.value(
          value: _FakeSettingsService(),
          child: MaterialApp(
            localizationsDelegates: const [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
            ],
            supportedLocales: AppLocalizations.supportedLocales,
            locale: const Locale('zh'),
            home: Material(
              child: QuoteItemWidget(
                quote: quote,
                tagMap: const {},
                isExpanded: false,
                onToggleExpanded: (_) {},
                onEdit: () {},
                onDelete: () {},
                onAskAI: () {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 列表卡片走 `Text.rich` 预览而不是 QuillEditor（阶段 D：折叠态彻底不跑
      // Quill）。展示的是 delta 的富文本内容，不是 content 兜底串。
      expect(find.text('fallback content'), findsNothing);
      expect(find.byType(quill.QuillEditor), findsNothing);
      expect(find.byType(CollapsedRichText), findsOneWidget);
    });

    testWidgets('列表富文本正文压平为单一摘要语义节点，且由 Text.rich 渲染', (tester) async {
      final delta = jsonEncode([
        {'insert': '第一段\n'},
        {'insert': '第二段\n'},
      ]);
      final quote = _buildQuote(
        content: '第一段\n第二段',
        deltaContent: delta,
        editSource: 'fullscreen',
      );

      await tester.pumpWidget(
        ChangeNotifierProvider<SettingsService>.value(
          value: _FakeSettingsService(),
          child: MaterialApp(
            localizationsDelegates: const [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
            ],
            supportedLocales: AppLocalizations.supportedLocales,
            locale: const Locale('zh'),
            home: Material(
              child: QuoteItemWidget(
                quote: quote,
                tagMap: const {},
                isExpanded: false,
                onToggleExpanded: (_) {},
                onEdit: () {},
                onDelete: () {},
                onAskAI: () {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final semantics = find.byKey(
        const ValueKey('quote_content.rich_text_semantics'),
      );
      expect(semantics, findsOneWidget);

      final semanticsWidget = tester.widget<Semantics>(semantics);
      expect(semanticsWidget.container, isTrue);
      expect(semanticsWidget.properties.label, quote.content);
      expect(
        find.descendant(
          of: semantics,
          matching: find.byType(ExcludeSemantics),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
            of: semantics, matching: find.byType(CollapsedRichText)),
        findsOneWidget,
      );
      expect(
        find.descendant(
            of: semantics, matching: find.byType(quill.QuillEditor)),
        findsNothing,
      );
    });

    testWidgets('开启后在时间与正文之间轻量显示编辑时间', (tester) async {
      final settings = _FakeSettingsService()..showNoteEditTime = true;
      final quote = _buildQuote(
        date: DateTime(2025, 6, 21, 9, 0).toIso8601String(),
        lastModified: DateTime(2025, 6, 22, 10, 30).toIso8601String(),
      );

      await tester.pumpWidget(
        ChangeNotifierProvider<SettingsService>.value(
          value: settings,
          child: MaterialApp(
            localizationsDelegates: const [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
            ],
            supportedLocales: AppLocalizations.supportedLocales,
            locale: const Locale('zh'),
            home: Material(
              child: QuoteItemWidget(
                quote: quote,
                tagMap: const {},
                isExpanded: false,
                onToggleExpanded: (_) {},
                onEdit: () {},
                onDelete: () {},
                onAskAI: () {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('编辑于'), findsOneWidget);
      expect(find.textContaining('2025-06-22'), findsOneWidget);
    });

    testWidgets('关闭时不显示编辑时间', (tester) async {
      final settings = _FakeSettingsService()..showNoteEditTime = false;
      final quote = _buildQuote(
        date: DateTime(2025, 6, 21, 9, 0).toIso8601String(),
        lastModified: DateTime(2025, 6, 22, 10, 30).toIso8601String(),
      );

      await tester.pumpWidget(
        ChangeNotifierProvider<SettingsService>.value(
          value: settings,
          child: MaterialApp(
            localizationsDelegates: const [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
            ],
            supportedLocales: AppLocalizations.supportedLocales,
            locale: const Locale('zh'),
            home: Material(
              child: QuoteItemWidget(
                quote: quote,
                tagMap: const {},
                isExpanded: false,
                onToggleExpanded: (_) {},
                onEdit: () {},
                onDelete: () {},
                onAskAI: () {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('编辑于'), findsNothing);
    });

    testWidgets('编辑时间与创建时间一致或无效时不显示编辑时间', (tester) async {
      final settings = _FakeSettingsService()..showNoteEditTime = true;
      final createdAt = DateTime(2025, 6, 21, 9, 0);
      final sameTimeQuote = _buildQuote(
        id: 'q2',
        date: createdAt.toIso8601String(),
        lastModified: createdAt.toIso8601String(),
      );
      final invalidTimeQuote = _buildQuote(
        id: 'q3',
        date: createdAt.toIso8601String(),
        lastModified: 'invalid-date',
      );

      await tester.pumpWidget(
        ChangeNotifierProvider<SettingsService>.value(
          value: settings,
          child: MaterialApp(
            localizationsDelegates: const [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
            ],
            supportedLocales: AppLocalizations.supportedLocales,
            locale: const Locale('zh'),
            home: Material(
              child: Column(
                children: [
                  QuoteItemWidget(
                    quote: sameTimeQuote,
                    tagMap: const {},
                    isExpanded: false,
                    onToggleExpanded: (_) {},
                    onEdit: () {},
                    onDelete: () {},
                    onAskAI: () {},
                  ),
                  QuoteItemWidget(
                    quote: invalidTimeQuote,
                    tagMap: const {},
                    isExpanded: false,
                    onToggleExpanded: (_) {},
                    onEdit: () {},
                    onDelete: () {},
                    onAskAI: () {},
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('编辑于'), findsNothing);
    });

    testWidgets('渲染心形按钮及紧凑型计数气泡', (tester) async {
      final quote = _buildQuote(
        id: 'q-fav',
        editSource: 'inline',
      ).copyWith(favoriteCount: 5);

      await tester.pumpWidget(
        ChangeNotifierProvider<SettingsService>.value(
          value: _FakeSettingsService(),
          child: MaterialApp(
            localizationsDelegates: const [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
            ],
            supportedLocales: AppLocalizations.supportedLocales,
            locale: const Locale('zh'),
            home: Material(
              child: QuoteItemWidget(
                quote: quote,
                tagMap: const {},
                isExpanded: false,
                onToggleExpanded: (_) {},
                onEdit: () {},
                onDelete: () {},
                onAskAI: () {},
                onFavorite: () {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 验证心形图标已渲染
      expect(find.byIcon(Icons.favorite), findsOneWidget);

      // 验证计数文本 '5' 已渲染
      expect(find.text('5'), findsOneWidget);

      // 验证 Badge 气泡容器的约束和样式
      final containerFinder = find
          .ancestor(
            of: find.text('5'),
            matching: find.byType(Container),
          )
          .first;
      expect(containerFinder, findsOneWidget);

      final containerWidget = tester.widget<Container>(containerFinder);
      final constraints = containerWidget.constraints;
      expect(constraints?.minWidth, 14.0);
      expect(constraints?.minHeight, 14.0);

      final textWidget = tester.widget<Text>(find.text('5'));
      expect(textWidget.style?.fontSize, 9.0);
      expect(textWidget.style?.fontWeight, FontWeight.bold);
    });
    testWidgets('动作按钮的触控尺寸与改造前一致', (tester) async {
      // 心形 36、更多 48 —— 这两个数原本由 `Padding(8)+图标20` 和 `IconButton`
      // 的 48dp 触控内衬撑出来。换成轻量按钮后必须显式给回来，
      // 否则底部这一行会变矮，每张卡片的高度跟着变。
      await _pumpCard(
        tester,
        _buildQuote(id: 'q-size', editSource: 'inline'),
        onFavorite: () {},
      );

      expect(
        tester.getSize(
            _actionButtonAncestorOf(find.byIcon(Icons.favorite_border))),
        const Size(36, 36),
      );
      expect(
        tester.getSize(_actionButtonAncestorOf(find.byIcon(Icons.more_vert))),
        const Size(48, 48),
      );
    });

    testWidgets('更多按钮弹出菜单并回调对应动作', (tester) async {
      var edited = false;
      await _pumpCard(
        tester,
        _buildQuote(id: 'q-menu', editSource: 'inline'),
        onEdit: () => edited = true,
      );

      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();

      final l10n = await AppLocalizations.delegate.load(const Locale('zh'));
      expect(find.text(l10n.editNoteMenu), findsOneWidget);
      expect(find.text(l10n.askAIMenu), findsOneWidget);
      expect(find.text(l10n.deleteNoteMenu), findsOneWidget);

      await tester.tap(find.text(l10n.editNoteMenu));
      await tester.pumpAndSettle();
      expect(edited, isTrue);
    });

    testWidgets('触摸端动作按钮不挂 Tooltip，无障碍名称仍在', (tester) async {
      await _pumpCard(
        tester,
        _buildQuote(id: 'q-tooltip', editSource: 'inline'),
        onFavorite: () {},
      );

      // 触摸端的 Tooltip 只能长按弹出，而长按位已被"清除收藏"占着；
      // 名称改由 Semantics 单独给，读屏不受影响。
      expect(find.byType(Tooltip), findsNothing);
      final l10n = await AppLocalizations.delegate.load(const Locale('zh'));
      expect(
        find.bySemanticsLabel(l10n.actionFavorite),
        findsOneWidget,
      );
      expect(find.bySemanticsLabel(l10n.moreOptions), findsOneWidget);
    });

    testWidgets('标签放得下时不挂滚动视图，放不下才退回', (tester) async {
      await _pumpCard(
        tester,
        _buildQuote(id: 'q-tags-short', editSource: 'inline')
            .copyWith(tagIds: const ['t1', 't2']),
        tagMap: {
          't1': NoteTag(id: 't1', name: '短'),
          't2': NoteTag(id: 't2', name: '标签'),
        },
      );
      expect(
        find.byType(SingleChildScrollView),
        findsNothing,
        reason: '两个短标签一行放得下，不该为它挂一整个 Scrollable',
      );

      await _pumpCard(
        tester,
        _buildQuote(id: 'q-tags-long', editSource: 'inline')
            .copyWith(tagIds: const ['t1', 't2', 't3', 't4', 't5', 't6']),
        tagMap: {
          for (var i = 1; i <= 6; i++)
            't$i': NoteTag(id: 't$i', name: '这是一个相当长的标签名 $i'),
        },
        width: 320,
      );
      expect(find.byType(SingleChildScrollView), findsOneWidget);
    });
  });
}

/// 轻量动作按钮的外层尺寸盒。按钮本身是私有类型，按图标往上找它的 SizedBox。
Finder _actionButtonAncestorOf(Finder icon) =>
    find.ancestor(of: icon, matching: find.byType(SizedBox)).first;

Future<void> _pumpCard(
  WidgetTester tester,
  Quote quote, {
  Map<String, NoteTag> tagMap = const {},
  VoidCallback? onFavorite,
  VoidCallback? onEdit,
  double width = 800,
}) async {
  await tester.pumpWidget(
    ChangeNotifierProvider<SettingsService>.value(
      value: _FakeSettingsService(),
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
            width: width,
            child: QuoteItemWidget(
              quote: quote,
              tagMap: tagMap,
              isExpanded: false,
              onToggleExpanded: (_) {},
              onEdit: onEdit ?? () {},
              onDelete: () {},
              onAskAI: () {},
              onFavorite: onFavorite,
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}
