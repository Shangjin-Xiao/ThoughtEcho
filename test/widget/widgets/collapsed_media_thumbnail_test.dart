import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/gen_l10n/app_localizations.dart';
import 'package:thoughtecho/utils/delta_media_extractor.dart';
import 'package:thoughtecho/widgets/note_list/collapsed_media_thumbnail.dart';

import '../../test_harness.dart';

/// 1×1 的合法 PNG。测试把它写进临时文件，走 FileImage——和真实笔记一致。
const String _tinyPngBase64 =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk'
    'YPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==';

const String _tinyPngDataUrl = 'data:image/png;base64,$_tinyPngBase64';

DeltaMediaSummary _mediaWithImage([String source = _tinyPngDataUrl]) {
  return parseDeltaMedia(jsonEncode([
    {
      'insert': {'image': source},
    },
    {'insert': '\n'},
  ]));
}

Widget _wrap(Widget child) {
  return MaterialApp(
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
    ],
    supportedLocales: AppLocalizations.supportedLocales,
    locale: const Locale('zh'),
    home: Scaffold(body: Center(child: child)),
  );
}

/// 有界地等真实解码**成功**：占位图标消失、且没有落到失败占位。
///
/// 不用固定时长的 `Future.delayed`（CI 上是不稳定来源），也不用 `pumpAndSettle`
/// ——真实解码走 dart:ui 的异步 codec，不随假时钟推进，`pumpAndSettle` 只会在
/// 占位态上空转。必须包在 `tester.runAsync` 里调用。
///
/// 必须同时检查 broken-image：解码失败时 `image_outlined` 同样会消失（换成
/// `broken_image_outlined`），只等它消失的话失败会被当成成功放过去。
Future<void> _pumpUntilDecoded(WidgetTester tester) async {
  for (var i = 0; i < 100; i++) {
    if (find.byIcon(Icons.broken_image_outlined).evaluate().isNotEmpty) {
      fail('图片解码失败，落到了 broken-image 占位');
    }
    if (find.byIcon(Icons.image_outlined).evaluate().isEmpty) return;
    await Future<void>.delayed(const Duration(milliseconds: 10));
    await tester.pump();
  }
  fail('图片在 1s 内没有完成解码');
}

/// 有界地等失败占位出现，用于错误路径的用例。
Future<void> _pumpUntilFailed(WidgetTester tester) async {
  for (var i = 0; i < 100; i++) {
    if (find.byIcon(Icons.broken_image_outlined).evaluate().isNotEmpty) return;
    await Future<void>.delayed(const Duration(milliseconds: 10));
    await tester.pump();
  }
  fail('图片在 1s 内没有落到失败占位');
}

void main() {
  late String pngPath;
  late String tempDirPath;

  setUpAll(() async {
    // 平台插件和文件系统一律走 test_harness 的 mock 目录，
    // 不碰真实用户目录（test/AGENTS.md）。
    final tempDir = await TestHarness.createTempDirectory('collapsed_thumb');
    tempDirPath = tempDir.path;
    pngPath = '${tempDir.path}/tiny.png';
    File(pngPath).writeAsBytesSync(
      Uint8List.fromList(base64Decode(_tinyPngBase64)),
    );
  });

  setUp(() {
    // 每条用例都从冷缓存开始。这不是"覆盖组件的缓存复用行为"——恰恰相反，
    // 下面那条命中测试是**自己**先把图预热进缓存再断言命中的，
    // 不清就会依赖用例执行顺序，命中断言也就失去意义。
    imageCache.clear();
    imageCache.clearLiveImages();
  });

  testWidgets('缓存命中时首帧直接画出图片，不经过占位', (tester) async {
    // 用真实文件而不是 data: URL：真实笔记里图片就是文件路径，走 FileImage，
    // 缓存键按路径字符串比较，重新挂载时能稳定命中。
    //
    // data: URL 走的是 MemoryImage，而 MemoryImage 的 `==` 比的是字节数组**身份**，
    // 每次 createOptimizedImageProvider 都会重新 decode 出一个新的 Uint8List，
    // 键对不上、必然重解——那是 data: URL 这条路自带的性质，不是本组件的行为。
    final media = _mediaWithImage(pngPath);

    // 第一次挂载：冷加载。真实解码走 dart:ui 的异步 codec，不随 pump 的帧循环推进，
    // 必须放在 runAsync 里才会真的跑完并落进 imageCache。
    await tester.runAsync(() async {
      await tester.pumpWidget(_wrap(CollapsedMediaThumbnail(media: media)));
      await tester.pump();
      await _pumpUntilDecoded(tester);
    });

    expect(imageCache.currentSize, greaterThan(0));
    expect(find.byIcon(Icons.image_outlined), findsNothing);

    // 卸载再挂载，复现「滑出 cacheExtent 后又滑回来」。
    await tester.pumpWidget(_wrap(const SizedBox.shrink()));
    await tester.pump();

    await tester.pumpWidget(_wrap(CollapsedMediaThumbnail(media: media)));
    // 只 pump 一帧、不 settle、也不进 runAsync：解码结果还在 imageCache 里，
    // ScrollAwareImageProvider 必须同步解析完，占位一帧都不该出现。
    // 这条断言就是「滑回来又变灰」的回归防线——历史上的 _shouldLoad 门控会在这里
    // 插入一帧占位再加 80~120ms 的 Timer，即便像素其实一直在缓存里。
    await tester.pump();
    expect(find.byIcon(Icons.image_outlined), findsNothing);
    expect(find.byType(Image), findsOneWidget);
  });

  testWidgets('多媒体时显示剩余数量角标', (tester) async {
    final media = parseDeltaMedia(jsonEncode([
      {
        'insert': {'image': _tinyPngDataUrl},
      },
      {
        'insert': {'image': _tinyPngDataUrl},
      },
      {
        'insert': {'video': 'v.mp4'},
      },
      {'insert': '\n'},
    ]));

    await tester.pumpWidget(_wrap(CollapsedMediaThumbnail(media: media)));
    await tester.pump();

    expect(find.text('+2'), findsOneWidget);
  });

  testWidgets('单张图片不显示角标', (tester) async {
    await tester.pumpWidget(
      _wrap(CollapsedMediaThumbnail(media: _mediaWithImage())),
    );
    await tester.pump();

    expect(find.textContaining('+'), findsNothing);
  });

  testWidgets('加载失败时读屏播报的是「图片加载失败」而不是「查看图片」', (tester) async {
    // 必须在测试体内 dispose：addTearDown 跑在 flutter_test 的
    // "SemanticsHandle 是否已释放" 校验之后，会被判成泄漏。
    //
    // 而且必须走 finally：任何一条断言先抛错时若跳过 dispose，flutter_test 会改报
    // 「SemanticsHandle 未释放」，把真正的失败原因盖掉。
    final handle = tester.ensureSemantics();
    try {
      // 不存在的文件 → FileImage 读取失败 → errorBuilder。
      final media = _mediaWithImage('$tempDirPath/does_not_exist.png');

      await tester.runAsync(() async {
        await tester.pumpWidget(_wrap(CollapsedMediaThumbnail(media: media)));
        await tester.pump();
        await _pumpUntilFailed(tester);
      });
      await tester.pump();

      expect(find.bySemanticsLabel('图片加载失败'), findsOneWidget);
      expect(find.bySemanticsLabel('查看图片'), findsNothing);
    } finally {
      handle.dispose();
    }
  });

  testWidgets('旧图的失败回调不会把换上来的新图钉在失败态', (tester) async {
    // 竞态：errorBuilder 的 postFrame 回调是异步的，期间 source 已经换成好图。
    // 回调必须确认失败的还是当前这张，否则新缩略图会永久停在 broken-image。
    final broken = _mediaWithImage('$tempDirPath/does_not_exist.png');
    final good = _mediaWithImage(pngPath);

    await tester.runAsync(() async {
      await tester.pumpWidget(_wrap(CollapsedMediaThumbnail(media: broken)));
      await tester.pump();
      // 不等失败落地，立刻换成好图——让旧图的失败回调在换源之后才触发。
      await tester.pumpWidget(_wrap(CollapsedMediaThumbnail(media: good)));
      await tester.pump();
      await _pumpUntilDecoded(tester);
    });

    expect(find.byIcon(Icons.broken_image_outlined), findsNothing);
    expect(find.byType(Image), findsOneWidget);
  });

  testWidgets('source 非法时不反复解析，且渲染失败占位', (tester) async {
    // 空 source 会让 createOptimizedImageProvider 返回 null。
    // 记忆化条件不带 `_provider != null`，所以 null 结果也会被缓存住，
    // 重建不会每帧重新解析一次来源。
    const media = DeltaMediaSummary(
      firstImageSource: '',
      imageCount: 1,
      videoCount: 0,
      audioCount: 0,
    );

    await tester.pumpWidget(_wrap(const CollapsedMediaThumbnail(media: media)));
    await tester.pump();
    await tester.pumpWidget(_wrap(const CollapsedMediaThumbnail(media: media)));
    await tester.pump();

    expect(find.byIcon(Icons.broken_image_outlined), findsOneWidget);
    expect(find.byType(Image), findsNothing);
  });

  testWidgets('只有视频时显示视频图标而不是图片', (tester) async {
    final media = parseDeltaMedia(jsonEncode([
      {
        'insert': {'video': 'v.mp4'},
      },
      {'insert': '\n'},
    ]));

    await tester.pumpWidget(_wrap(CollapsedMediaThumbnail(media: media)));
    await tester.pump();

    expect(find.byIcon(Icons.videocam_outlined), findsOneWidget);
    expect(find.byType(Image), findsNothing);
  });

  group('尺寸分档', () {
    test('取不超过正文高度的最大档', () {
      expect(
        CollapsedMediaThumbnail.sizeForContentHeight(0),
        CollapsedMediaThumbnail.compactSize,
      );
      // 一两行正文：比最小档还矮也停在最小档，再小就看不清是什么照片了。
      expect(
        CollapsedMediaThumbnail.sizeForContentHeight(24),
        CollapsedMediaThumbnail.compactSize,
      );
      expect(
        CollapsedMediaThumbnail.sizeForContentHeight(
          CollapsedMediaThumbnail.defaultSize - 0.5,
        ),
        CollapsedMediaThumbnail.compactSize,
      );
      // 边界取等号：正好够一档就用那一档，图和正文齐平。
      expect(
        CollapsedMediaThumbnail.sizeForContentHeight(
          CollapsedMediaThumbnail.defaultSize,
        ),
        CollapsedMediaThumbnail.defaultSize,
      );
      expect(
        CollapsedMediaThumbnail.sizeForContentHeight(
          CollapsedMediaThumbnail.tallNoteSize,
        ),
        CollapsedMediaThumbnail.tallNoteSize,
      );
      // 正文排满折叠盒（160）也不再往上走：上限就是最大档。
      expect(
        CollapsedMediaThumbnail.sizeForContentHeight(160),
        CollapsedMediaThumbnail.tallNoteSize,
      );
    });

    test('档位递增，且挑出来的档永远不高于正文（最小档除外）', () {
      // 这两条不变量是「图不比字高」的全部依据：档位乱序或多出一个大于
      // 160 的档，都会让长笔记的图重新撑出卡片。
      for (var i = 1; i < CollapsedMediaThumbnail.sizeLadder.length; i++) {
        expect(
          CollapsedMediaThumbnail.sizeLadder[i],
          greaterThan(CollapsedMediaThumbnail.sizeLadder[i - 1]),
        );
      }
      for (var height = CollapsedMediaThumbnail.compactSize;
          height <= 200;
          height += 4) {
        expect(
          CollapsedMediaThumbnail.sizeForContentHeight(height),
          lessThanOrEqualTo(height),
        );
      }
    });
  });

  testWidgets('缩略图尺寸固定，占位与成图不改变布局', (tester) async {
    final media = _mediaWithImage(pngPath);

    late Size sizeBeforeDecode;
    late Size sizeAfterDecode;

    await tester.runAsync(() async {
      await tester.pumpWidget(_wrap(CollapsedMediaThumbnail(media: media)));
      await tester.pump();
      // 断言此刻确实还在占位态，否则下面的"前后尺寸一致"是废话。
      expect(find.byIcon(Icons.image_outlined), findsOneWidget);
      sizeBeforeDecode = tester.getSize(find.byType(CollapsedMediaThumbnail));

      await _pumpUntilDecoded(tester);
      sizeAfterDecode = tester.getSize(find.byType(CollapsedMediaThumbnail));
    });

    expect(find.byIcon(Icons.image_outlined), findsNothing);
    expect(sizeBeforeDecode, sizeAfterDecode);
    expect(
      sizeAfterDecode,
      const Size(
        CollapsedMediaThumbnail.defaultSize,
        CollapsedMediaThumbnail.defaultSize,
      ),
    );
  });
}
