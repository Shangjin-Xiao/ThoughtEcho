import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;
import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/gen_l10n/app_localizations.dart';
import 'package:thoughtecho/utils/quill_editor_extensions.dart';
import 'package:thoughtecho/widgets/media_player_widget.dart';

/// 富文本段落基准样式不能跟着调用点在树里的深浅变。
///
/// 历史故障：[QuillThemeTypography.paragraphStyle] 曾经拿
/// `DefaultTextStyle.of(context)` 当基准。`Material` 里面那是正常正文样式，可
/// `MaterialApp` 在 `Navigator` 外面铺的是一份「你还没设过样式」的报警样式
/// （红色 `0xD0FF0000` + `bold` + `monospace` + 48px + 黄色双下划线）。全屏编辑器
/// 的 `build(context)` 正好在 `Scaffold` 外面，于是整篇正文被渲染成红色粗体——
/// 字号被覆盖、下划线被清掉，最扎眼的两项（颜色、字重）反而全留了下来。
void main() {
  /// `MaterialApp` 那份报警样式的颜色，见 `WidgetsApp.textStyle` 的默认值。
  const appFallbackColor = Color(0xD0FF0000);

  testWidgets('Scaffold 之外算出的段落样式不会吃到 MaterialApp 的报警样式', (tester) async {
    late TextStyle paragraph;
    late TextStyle bodyLarge;
    late Color onSurface;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            // 前提校验：这一层的 DefaultTextStyle 确实不是正文样式（现在是那份
            // 报警样式），否则这条用例根本没在测东西。只比「不等于正文」，
            // 不钉报警样式的具体取值——那是 framework 的内部常量。
            expect(
              DefaultTextStyle.of(context).style.color,
              isNot(Theme.of(context).textTheme.bodyLarge!.color),
              reason: '这一层若已经是正常正文样式，说明用例没复刻全屏编辑器的位置',
            );
            // 全屏编辑器就是在这个位置（Scaffold 之外）算段落样式的。
            paragraph = QuillThemeTypography.paragraphStyle(context);
            bodyLarge = Theme.of(context).textTheme.bodyLarge!;
            onSurface = Theme.of(context).colorScheme.onSurface;
            return const Scaffold();
          },
        ),
      ),
    );

    expect(paragraph.color, isNot(appFallbackColor));
    expect(paragraph.color, bodyLarge.color ?? onSurface);
    expect(paragraph.fontWeight, bodyLarge.fontWeight);
    expect(paragraph.fontFamily, bodyLarge.fontFamily);
    expect(paragraph.fontSize, bodyLarge.fontSize);
    expect(paragraph.height, bodyLarge.height);
    expect(paragraph.decoration, TextDecoration.none);
  });

  testWidgets('Material 内外算出的段落样式必须一模一样', (tester) async {
    late TextStyle outside;
    late TextStyle inside;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (outerContext) {
            outside = QuillThemeTypography.paragraphStyle(outerContext);
            return Scaffold(
              body: Builder(
                builder: (innerContext) {
                  // 笔记卡片走的是这条（Material 内部）。两边必须同一份样式，
                  // 否则同一条笔记「写的时候」和「读的时候」长得不一样。
                  inside = QuillThemeTypography.paragraphStyle(innerContext);
                  return const SizedBox.shrink();
                },
              ),
            );
          },
        ),
      ),
    );

    expect(inside, outside);
  });

  testWidgets('主题没给正文颜色时兜底到 onSurface', (tester) async {
    // `TextLine` 用的 `RichText` 不继承 `DefaultTextStyle`，段落样式整体替换后
    // 缺 color 会在暗色模式下画黑字，所以 `paragraphStyle` 有一条 onSurface 兜底。
    // 默认主题的 `bodyLarge` 永远带颜色，那条分支平时走不到，这里显式造出来。
    //
    // `inherit: false` 不是凑巧：`ThemeData` 会把传入的 `textTheme` merge 到
    // 默认那套上，而 `TextStyle.merge` 只有在 `inherit` 为 false 时才整体替换。
    // 写成普通的 `TextStyle()`，null 的颜色会被默认值填回来，这条用例就白测了。
    const onSurface = Color(0xFF00FF00);
    final theme = ThemeData(
      colorScheme: const ColorScheme.light(onSurface: onSurface),
      textTheme: const TextTheme(
        bodyLarge: TextStyle(inherit: false, fontSize: 16),
      ),
    );
    late TextStyle paragraph;

    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        home: Builder(
          builder: (context) {
            expect(
              Theme.of(context).textTheme.bodyLarge!.color,
              isNull,
              reason: '前提：这套主题的正文确实没有颜色，否则测不到兜底分支',
            );
            paragraph = QuillThemeTypography.paragraphStyle(context);
            return const Scaffold();
          },
        ),
      ),
    );

    expect(paragraph.color, onSurface);
  });

  testWidgets('base 给了的项优先，下划线仍被清掉', (tester) async {
    late TextStyle paragraph;
    const base = TextStyle(
      fontSize: 21,
      height: 2.0,
      color: Color(0xFF123456),
      decoration: TextDecoration.underline,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            paragraph = QuillThemeTypography.paragraphStyle(
              context,
              base: base,
            );
            return const Scaffold();
          },
        ),
      ),
    );

    expect(paragraph.fontSize, 21);
    expect(paragraph.height, 2.0);
    expect(paragraph.color, const Color(0xFF123456));
    expect(paragraph.decoration, TextDecoration.none);
  });

  group('QuillEditorExtensions.getEmbedBuilders', () {
    test('optimizedImages 为 true 时使用 _OptimizedImageEmbedBuilder', () {
      final builders = QuillEditorExtensions.getEmbedBuilders(
        optimizedImages: true,
      );
      final imageBuilder = builders.firstWhere((b) => b.key == 'image');
      expect(
        imageBuilder.runtimeType.toString(),
        '_OptimizedImageEmbedBuilder',
      );
    });

    test('默认参数使用 _OptimizedImageEmbedBuilder', () {
      final builders = QuillEditorExtensions.getEmbedBuilders();
      final imageBuilder = builders.firstWhere((b) => b.key == 'image');
      expect(
        imageBuilder.runtimeType.toString(),
        '_OptimizedImageEmbedBuilder',
      );
    });

    test('optimizedImages 为 false 时保留默认图片构建器', () {
      final builders = QuillEditorExtensions.getEmbedBuilders(
        optimizedImages: false,
      );
      final imageBuilder = builders.firstWhere((b) => b.key == 'image');
      expect(
        imageBuilder.runtimeType.toString(),
        isNot('_OptimizedImageEmbedBuilder'),
      );
    });

    test('非 Web 平台注册自定义音视频构建器', () {
      final builders = QuillEditorExtensions.getEmbedBuilders();
      expect(
        builders.any(
          (b) =>
              b.key == 'video' &&
              b.runtimeType.toString() == '_CustomVideoEmbedBuilder',
        ),
        isTrue,
      );
      expect(
        builders.any(
          (b) =>
              b.key == 'audio' &&
              b.runtimeType.toString() == '_CustomAudioEmbedBuilder',
        ),
        isTrue,
      );
    });

    test('enableEditorMenu 参数正确传递给 _OptimizedImageEmbedBuilder', () {
      final buildersWithMenu = QuillEditorExtensions.getEmbedBuilders(
        optimizedImages: true,
        enableEditorMenu: true,
      );
      final imageBuilderWithMenu = buildersWithMenu.firstWhere(
        (b) => b.key == 'image',
      );
      expect(
        imageBuilderWithMenu.runtimeType.toString(),
        '_OptimizedImageEmbedBuilder',
      );

      final buildersWithoutMenu = QuillEditorExtensions.getEmbedBuilders(
        optimizedImages: true,
        enableEditorMenu: false,
      );
      final imageBuilderWithoutMenu = buildersWithoutMenu.firstWhere(
        (b) => b.key == 'image',
      );
      expect(
        imageBuilderWithoutMenu.runtimeType.toString(),
        '_OptimizedImageEmbedBuilder',
      );
    });

    testWidgets('_CustomVideoEmbedBuilder 构建的组件外层包含 RepaintBoundary 进行重绘隔离',
        (tester) async {
      final builders = QuillEditorExtensions.getEmbedBuilders();
      final videoBuilder = builders.firstWhere((b) => b.key == 'video');

      final controller = quill.QuillController.basic();
      addTearDown(controller.dispose);
      final embedNode =
          quill.Embed(quill.BlockEmbed.video('https://example.com/test.mp4'));
      // ignore: invalid_use_of_internal_member
      final embedContext = quill.EmbedContext(
        controller: controller,
        node: embedNode,
        readOnly: false,
        inline: false,
        textStyle: const TextStyle(),
      );

      late Widget builtWidget;
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Builder(
              builder: (context) {
                builtWidget = videoBuilder.build(context, embedContext);
                return builtWidget;
              },
            ),
          ),
        ),
      );

      expect(builtWidget, isA<RepaintBoundary>());

      final videoFinder = find.byWidgetPredicate(
        (widget) =>
            widget is MediaPlayerWidget && widget.mediaType == MediaType.video,
      );
      expect(videoFinder, findsOneWidget);

      final videoRepaintBoundaryFinder = find.ancestor(
        of: videoFinder,
        matching: find.byType(RepaintBoundary),
      );
      expect(videoRepaintBoundaryFinder, findsWidgets);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 600));
    });

    testWidgets('_CustomAudioEmbedBuilder 构建的组件外层包含 RepaintBoundary 进行重绘隔离',
        (tester) async {
      final originalOnError = FlutterError.onError;
      FlutterError.onError = (details) {
        if (details.exceptionAsString().contains('A RenderFlex overflowed')) {
          return;
        }
        originalOnError?.call(details);
      };
      addTearDown(() {
        FlutterError.onError = originalOnError;
      });

      final builders = QuillEditorExtensions.getEmbedBuilders();
      final audioBuilder = builders.firstWhere((b) => b.key == 'audio');

      final controller = quill.QuillController.basic();
      addTearDown(controller.dispose);
      final embedNode = quill.Embed(
        quill.BlockEmbed('audio', 'https://example.com/test.mp3'),
      );
      // ignore: invalid_use_of_internal_member
      final embedContext = quill.EmbedContext(
        controller: controller,
        node: embedNode,
        readOnly: false,
        inline: false,
        textStyle: const TextStyle(),
      );

      late Widget builtWidget;
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Builder(
              builder: (context) {
                builtWidget = audioBuilder.build(context, embedContext);
                return builtWidget;
              },
            ),
          ),
        ),
      );

      expect(builtWidget, isA<RepaintBoundary>());

      final audioFinder = find.byWidgetPredicate(
        (widget) =>
            widget is MediaPlayerWidget && widget.mediaType == MediaType.audio,
      );
      expect(audioFinder, findsOneWidget);

      final audioRepaintBoundaryFinder = find.ancestor(
        of: audioFinder,
        matching: find.byType(RepaintBoundary),
      );
      expect(audioRepaintBoundaryFinder, findsWidgets);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 600));
    });

    testWidgets('QuillEditor 中嵌入音视频媒体卡片均具有 RepaintBoundary 绘制边界',
        (tester) async {
      final originalOnError = FlutterError.onError;
      FlutterError.onError = (details) {
        if (details.exceptionAsString().contains('A RenderFlex overflowed')) {
          return;
        }
        originalOnError?.call(details);
      };
      addTearDown(() {
        FlutterError.onError = originalOnError;
      });

      final doc = quill.Document();
      doc.insert(0, quill.BlockEmbed.video('https://example.com/test.mp4'));
      doc.insert(1, '\n');
      doc.insert(2, quill.BlockEmbed('audio', 'https://example.com/test.mp3'));
      doc.insert(3, '\n');

      final controller = quill.QuillController(
        document: doc,
        selection: const TextSelection.collapsed(offset: 0),
      );
      addTearDown(controller.dispose);

      final scrollController = ScrollController();
      addTearDown(scrollController.dispose);
      final focusNode = FocusNode();
      addTearDown(focusNode.dispose);

      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: quill.QuillEditor(
              controller: controller,
              scrollController: scrollController,
              focusNode: focusNode,
              config: quill.QuillEditorConfig(
                embedBuilders: QuillEditorExtensions.getEmbedBuilders(),
              ),
            ),
          ),
        ),
      );

      final videoFinder = find.byWidgetPredicate(
        (widget) =>
            widget is MediaPlayerWidget && widget.mediaType == MediaType.video,
      );
      expect(videoFinder, findsOneWidget);
      expect(
        find.ancestor(
          of: videoFinder,
          matching: find.byType(RepaintBoundary),
        ),
        findsWidgets,
      );

      final audioFinder = find.byWidgetPredicate(
        (widget) =>
            widget is MediaPlayerWidget && widget.mediaType == MediaType.audio,
      );
      expect(audioFinder, findsOneWidget);
      expect(
        find.ancestor(
          of: audioFinder,
          matching: find.byType(RepaintBoundary),
        ),
        findsWidgets,
      );

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 600));
    });
  });
}
