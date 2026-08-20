import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/gen_l10n/app_localizations.dart';
import 'package:thoughtecho/utils/delta_rich_text_parser.dart';
import 'package:thoughtecho/widgets/note_list/collapsed_rich_text.dart';

/// 折叠卡片富文本渲染的 golden 基线。
///
/// **这些 golden 管的是几何和颜色**：换行位置、列表符号列的宽度与对齐、引用左线、
/// 块间距、字色与背景色。`flutter_test` 的默认字体把每个字形都画成同样的方块，
/// 所以粗体 / 斜体 / 字体族在图里**看不出差别**——恰好是「要 1:1」清单上最要紧的
/// 几项。那几项由 `test/unit/utils/delta_rich_text_parser_test.dart` 逐项断言
/// `TextStyle`，比截图更严格，也不会因为字体版本变化而漂。
///
/// 两者合起来才是完整的防线：属性映射靠单测，排版结果靠 golden。
///
/// 基线用 `flutter test --update-goldens <本文件>` 重录。图变了要先看清是修好了
/// 还是弄坏了，别顺手重录。
void main() {
  /// 折叠盒的典型宽度，取自卡片正文区。
  const double contentWidth = 320;

  /// golden 的截取目标。
  ///
  /// **不能用 `find.byType(RepaintBoundary).last`**：`MaterialApp`、`Scaffold`
  /// 都会在内部插 `RepaintBoundary`，媒体块将来也可能引入自己的。按类型取「最后
  /// 一个」会在某天悄悄改成只截一小块子树，而基线照旧存在、测试照旧通过。
  const Key goldenBoundaryKey = ValueKey('collapsed_rich_text_golden');
  const TextStyle baseStyle = TextStyle(fontSize: 16, height: 1.5);

  Widget wrap(String delta, {bool showMedia = false, Brightness? brightness}) {
    final blocks = parseDeltaRichText(delta);
    final plan = CollapsedRichTextMetrics.plan(
      blocks: blocks,
      baseStyle: baseStyle,
      maxWidth: contentWidth,
      limit: 160,
      showMedia: showMedia,
    );

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      // 媒体块要读 l10n（占位的读屏标签），缺了 delegate 会在 build 里炸。
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('zh'),
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF6750A4),
          brightness: brightness ?? Brightness.light,
        ),
      ),
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: contentWidth,
            child: RepaintBoundary(
              key: goldenBoundaryKey,
              child: CollapsedRichText(plan: plan, baseStyle: baseStyle),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> expectGolden(
    WidgetTester tester,
    Widget app,
    String name,
  ) async {
    await tester.pumpWidget(app);
    await tester.pump();
    await expectLater(
      find.byKey(goldenBoundaryKey),
      matchesGoldenFile('goldens/$name.png'),
    );
  }

  testWidgets('段落与行内样式', (tester) async {
    final delta = jsonEncode([
      {'insert': '普通文本，'},
      {
        'insert': '粗体',
        'attributes': {'bold': true},
      },
      {'insert': '与'},
      {
        'insert': '斜体',
        'attributes': {'italic': true},
      },
      {'insert': '、'},
      {
        'insert': '下划线',
        'attributes': {'underline': true},
      },
      {'insert': '、'},
      {
        'insert': '删除线',
        'attributes': {'strike': true},
      },
      {'insert': '。\n'},
    ]);
    await expectGolden(tester, wrap(delta), 'collapsed_rich_text_inline');
  });

  testWidgets('字色与背景色', (tester) async {
    final delta = jsonEncode([
      {
        'insert': '红字',
        'attributes': {'color': '#FF0000'},
      },
      {'insert': '，'},
      {
        'insert': '黄底',
        'attributes': {'background': '#FFFF00'},
      },
      {'insert': '，'},
      {
        'insert': '两者兼有',
        'attributes': {'color': '#0000FF', 'background': '#DDDDDD'},
      },
      {'insert': '。\n'},
    ]);
    await expectGolden(tester, wrap(delta), 'collapsed_rich_text_colors');
  });

  testWidgets('字号层级', (tester) async {
    final delta = jsonEncode([
      {
        'insert': '小',
        'attributes': {'size': 'small'},
      },
      {'insert': '常规'},
      {
        'insert': '大',
        'attributes': {'size': 'large'},
      },
      {
        'insert': '超大',
        'attributes': {'size': 'huge'},
      },
      {'insert': '\n'},
    ]);
    await expectGolden(tester, wrap(delta), 'collapsed_rich_text_sizes');
  });

  testWidgets('列表符号与悬挂缩进', (tester) async {
    final delta = jsonEncode([
      {'insert': '无序一'},
      {
        'insert': '\n',
        'attributes': {'list': 'bullet'},
      },
      {'insert': '有序一'},
      {
        'insert': '\n',
        'attributes': {'list': 'ordered'},
      },
      {'insert': '有序二，这一条足够长，会折到第二行来验证悬挂缩进是否对齐'},
      {
        'insert': '\n',
        'attributes': {'list': 'ordered'},
      },
      {'insert': '已勾选'},
      {
        'insert': '\n',
        'attributes': {'list': 'checked'},
      },
      {'insert': '未勾选'},
      {
        'insert': '\n',
        'attributes': {'list': 'unchecked'},
      },
    ]);
    await expectGolden(tester, wrap(delta), 'collapsed_rich_text_lists');
  });

  testWidgets('引用左线与标题', (tester) async {
    final delta = jsonEncode([
      {'insert': '三级标题'},
      {
        'insert': '\n',
        'attributes': {'header': 3},
      },
      {'insert': '一段被引用的话，长到会换行，用来看左线是不是贴着整段而不是只有第一行'},
      {
        'insert': '\n',
        'attributes': {'blockquote': true},
      },
      {'insert': '正文收尾。\n'},
    ]);
    await expectGolden(tester, wrap(delta), 'collapsed_rich_text_quote');
  });

  testWidgets('超长正文按行数预算截断', (tester) async {
    final delta = jsonEncode([
      {'insert': '${'这段正文很长，长到远远超过折叠盒能显示的范围。' * 20}\n'},
    ]);
    await expectGolden(tester, wrap(delta), 'collapsed_rich_text_overflow');
  });

  testWidgets('inline 版式：媒体按原位交错，且高度固定', (tester) async {
    // 音视频走占位图标路径，不需要真实资源，出图稳定。这里钉住的是媒体块的固定
    // 高度和它与文字块之间的间距——都属于本文件声明要管的「几何」。
    final delta = jsonEncode([
      {'insert': '图前一行\n'},
      {
        'insert': {
          'custom': {'audio': '/tmp/a.m4a'},
        },
      },
      {'insert': '图后一行\n'},
    ]);
    await expectGolden(
      tester,
      wrap(delta, showMedia: true),
      'collapsed_rich_text_inline_media',
    );
  });

  testWidgets('暗色模式下引用左线与代码块底色仍然可读', (tester) async {
    // quill 的 DefaultStyles 在这两处用的是固定浅色（grey.shade300 /
    // grey.shade100 / blue.shade900），暗色模式下会变成刺眼白块或对比度不足。
    // 折叠卡片改用 surface / outline 令牌，这张图钉住那个决定。
    final delta = jsonEncode([
      {'insert': '引用行'},
      {
        'insert': '\n',
        'attributes': {'blockquote': true},
      },
      {'insert': 'const x = 1;'},
      {
        'insert': '\n',
        'attributes': {'code-block': true},
      },
    ]);
    await expectGolden(
      tester,
      wrap(delta, brightness: Brightness.dark),
      'collapsed_rich_text_dark',
    );
  });

  test('后面的块放不下时整个不排，计划高度不会撑破折叠盒', () {
    // 「至少画一行」只对第一个块成立。对后面的块也强画一行的话，剩余空间只有几个
    // 像素时照样塞一整行进去，`Column` 会真的溢出（debug 下画黄黑警示带），
    // `ClipRect` 裁掉的也不再是「多排出来的余量」而是实打实的越界。
    final delta = jsonEncode([
      {'insert': '第一行\n第二行\n第三行\n第四行\n第五行\n第六行\n第七行\n'},
    ]);
    final plan = CollapsedRichTextMetrics.plan(
      blocks: parseDeltaRichText(delta),
      baseStyle: baseStyle,
      maxWidth: contentWidth,
      limit: 160,
      showMedia: false,
    );

    expect(plan.height, lessThanOrEqualTo(160.5));
    expect(plan.truncated, isTrue);
  });

  test('第一个块再高也要排，否则纯标题笔记会得到空计划', () {
    final delta = jsonEncode([
      {
        'insert': '很大的标题\n',
        'attributes': {'header': 1},
      },
    ]);
    final plan = CollapsedRichTextMetrics.plan(
      blocks: parseDeltaRichText(delta),
      baseStyle: baseStyle,
      maxWidth: 40, // 窄到标题要折很多行
      limit: 20, // 盒子比一行还矮
      showMedia: false,
    );

    expect(plan.entries, isNotEmpty);
    expect(plan.entries.first.maxLines, greaterThanOrEqualTo(1));
  });
}
