import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/gen_l10n/app_localizations.dart';
import 'package:thoughtecho/utils/delta_media_extractor.dart';
import 'package:thoughtecho/widgets/note_list/collapsed_media_thumbnail.dart';

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

void main() {
  late Directory tempDir;
  late String pngPath;

  setUpAll(() {
    tempDir = Directory.systemTemp.createTempSync('thumb_test');
    pngPath = '${tempDir.path}/tiny.png';
    File(pngPath).writeAsBytesSync(
      Uint8List.fromList(base64Decode(_tinyPngBase64)),
    );
  });

  tearDownAll(() {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  setUp(() {
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
      await Future<void>.delayed(const Duration(milliseconds: 300));
      await tester.pump();
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

  testWidgets('缩略图尺寸固定，占位与成图不改变布局', (tester) async {
    final media = _mediaWithImage();

    await tester.pumpWidget(_wrap(CollapsedMediaThumbnail(media: media)));
    await tester.pump();
    final sizeBeforeDecode = tester.getSize(
      find.byType(CollapsedMediaThumbnail),
    );

    await tester.pumpAndSettle();
    final sizeAfterDecode = tester.getSize(
      find.byType(CollapsedMediaThumbnail),
    );

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
