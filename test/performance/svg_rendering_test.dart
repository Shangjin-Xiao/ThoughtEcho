import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:thoughtecho/constants/card_templates.dart';
import 'package:thoughtecho/models/generated_card.dart';
import 'package:thoughtecho/services/svg_offscreen_renderer.dart';
import 'package:thoughtecho/services/svg_raster_cache_service.dart';
import 'package:thoughtecho/services/svg_to_image_service.dart';
import 'package:thoughtecho/utils/bounded_svg_loader.dart';

class _DelayedOffscreenSvgLoader extends BytesLoader {
  const _DelayedOffscreenSvgLoader(this.svgContent, this.delay);

  final String svgContent;
  final Duration delay;

  @override
  Future<ByteData> loadBytes(BuildContext? context) async {
    await Future<void>.delayed(delay);
    return BoundedSvgLoader(svgContent).loadBytes(context);
  }

  @override
  Object cacheKey(BuildContext? context) => Object.hash(svgContent, delay);
}

void main() {
  setUpAll(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('SVG渲染功能测试', () {
    const testSvg = '''
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 400 600">
  <defs>
    <linearGradient id="bg" x1="0%" y1="0%" x2="100%" y2="100%">
      <stop offset="0%" style="stop-color:#4f46e5;stop-opacity:1" />
      <stop offset="100%" style="stop-color:#7c3aed;stop-opacity:1" />
    </linearGradient>
  </defs>
  <rect width="400" height="600" fill="url(#bg)" rx="24"/>
  <circle cx="200" cy="150" r="40" fill="#ffffff" fill-opacity="0.9"/>
  <rect x="50" y="250" width="300" height="200" fill="#ffffff" fill-opacity="0.95" rx="16"/>
  <text x="200" y="350" text-anchor="middle" fill="#333333" font-size="16">测试SVG内容</text>
  <text x="200" y="550" text-anchor="middle" fill="#ffffff" font-size="12">心迹</text>
</svg>
''';

    test('基本SVG渲染功能', () async {
      final imageBytes = await SvgToImageService.convertSvgToImage(
        testSvg,
        width: 400,
        height: 600,
      );

      expect(imageBytes, isNotNull);
      expect(imageBytes.length, greaterThan(0));
      expect(imageBytes, isA<Uint8List>());
    });

    testWidgets('离屏渲染保持对齐且无异常', (tester) async {
      const svgContent = '''
    <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 400 600">
      <rect width="400" height="600" fill="#ffffff"/>
      <rect x="40" y="60" width="320" height="480" fill="#f5f5f5" rx="24"/>
      <text x="200" y="150" text-anchor="middle" font-size="28" fill="#333">离屏渲染</text>
      <text x="200" y="210" text-anchor="middle" font-size="16" fill="#666">确保布局和导出一致</text>
    </svg>
    ''';

      late BuildContext overlayContext;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                overlayContext = context;
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
      );

      await tester.pump();

      final bytes = await tester.runAsync(() async {
        return SvgOffscreenRenderer.instance.renderSvgString(
          svgContent,
          context: overlayContext,
          width: 400,
          height: 600,
          background: Colors.white,
          mode: ExportRenderMode.contain,
        );
      });

      expect(bytes, isNotNull);
      final nonNullBytes = bytes!;
      expect(nonNullBytes, isA<Uint8List>());
      expect(nonNullBytes.length, greaterThan(0));
    });

    testWidgets(
      '高分屏 devicePixelRatio=3.0 下 800x1200 scaleFactor=2.0 精确输出 1600x2400 且无 300ms 固定睡眠',
      (tester) async {
        const cardSvg = '''
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 400 600">
  <rect width="400" height="600" fill="#1e293b"/>
  <rect x="32" y="48" width="336" height="504" rx="20" fill="#f8fafc"/>
  <text x="200" y="300" text-anchor="middle" font-size="24" fill="#0f172a">固定物理分辨率</text>
</svg>
''';

        late BuildContext overlayContext;

        await tester.pumpWidget(
          MaterialApp(
            builder: (context, child) => MediaQuery(
              data: const MediaQueryData(
                size: Size(400, 800),
                devicePixelRatio: 3.0,
              ),
              child: child!,
            ),
            home: Scaffold(
              body: Column(
                children: [
                  // 模拟预览弹窗已渲染卡片并预热 BoundedSvgLoader 内存缓存
                  SizedBox(
                    width: 200,
                    height: 300,
                    child: SvgPicture(BoundedSvgLoader(cardSvg)),
                  ),
                  Builder(
                    builder: (context) {
                      overlayContext = context;
                      return const SizedBox.shrink();
                    },
                  ),
                ],
              ),
            ),
          ),
        );
        await tester.pump();

        // 1. 验证小尺寸导出无需 300ms 固定睡眠
        final fastWatch = Stopwatch()..start();
        final smallBytes = await tester.runAsync(() async {
          // 预热一次后台编码后再测纯帧就绪等待开销
          await SvgOffscreenRenderer.instance.renderSvgString(
            cardSvg,
            context: overlayContext,
            width: 80,
            height: 120,
            scaleFactor: 1.0,
            background: Colors.transparent,
          );
          fastWatch.reset();
          return SvgOffscreenRenderer.instance.renderSvgString(
            cardSvg,
            context: overlayContext,
            width: 80,
            height: 120,
            scaleFactor: 1.0,
            background: Colors.transparent,
          );
        });
        fastWatch.stop();
        expect(smallBytes, isNotNull);
        expect(fastWatch.elapsedMilliseconds, lessThan(280));

        // 2. 验证 800x1200 + scaleFactor=2.0 精确输出 1600x2400（而非二次叠乘后的 3200x4800）
        final hdBytes = await tester.runAsync(() async {
          return SvgOffscreenRenderer.instance.renderSvgString(
            cardSvg,
            context: overlayContext,
            width: 800,
            height: 1200,
            scaleFactor: 2.0,
            background: Colors.transparent,
            mode: ExportRenderMode.contain,
          );
        });

        expect(hdBytes, isNotNull);
        final decoded = await tester.runAsync(
          () async => img.decodePng(hdBytes!),
        );
        expect(decoded, isNotNull);
        expect(decoded!.width, equals(1600));
        expect(decoded.height, equals(2400));
      },
    );

    testWidgets(
      '离屏导出透明背景配圆角保留四角透明与反预乘抗锯齿，且复杂模板先分享后保存零重算',
      (tester) async {
        late BuildContext overlayContext;

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) {
                  overlayContext = context;
                  return const SizedBox.shrink();
                },
              ),
            ),
          ),
        );
        await tester.pump();

        // 1. 验证离屏路径下透明背景 + 圆角裁剪四角 alpha == 0 且边缘无预乘暗边
        const whiteCardSvg = '''
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 200 200">
  <rect width="200" height="200" fill="#ffffff"/>
</svg>
''';
        final roundedBytes = await tester.runAsync(() async {
          return SvgOffscreenRenderer.instance.renderSvgString(
            whiteCardSvg,
            context: overlayContext,
            width: 200,
            height: 200,
            scaleFactor: 1.0,
            background: Colors.transparent,
            borderRadius: 40,
          );
        });
        final roundedDecoded = await tester.runAsync(
          () async => img.decodePng(roundedBytes!),
        );
        expect(roundedDecoded, isNotNull);
        expect(roundedDecoded!.getPixel(0, 0).a.toInt(), equals(0));
        expect(roundedDecoded.getPixel(199, 0).a.toInt(), equals(0));
        expect(roundedDecoded.getPixel(0, 199).a.toInt(), equals(0));
        expect(roundedDecoded.getPixel(199, 199).a.toInt(), equals(0));

        var edgePixelsChecked = 0;
        for (var y = 0; y < 45; y++) {
          for (var x = 0; x < 45; x++) {
            final p = roundedDecoded.getPixel(x, y);
            final a = p.a.toInt();
            if (a >= 32 && a <= 224) {
              edgePixelsChecked++;
              expect(p.r.toInt(), greaterThanOrEqualTo(245));
              expect(p.g.toInt(), greaterThanOrEqualTo(245));
              expect(p.b.toInt(), greaterThanOrEqualTo(245));
            }
          }
        }
        expect(edgePixelsChecked, greaterThan(0));

        // 2. 验证复杂模板（sotaModern 与 classicSerif）离屏导出及同卡先分享后保存零重复渲染
        SvgRasterCacheService().clearCache();
        SvgToImageService.resetDebugRenderCount();

        final sotaCard = GeneratedCard(
          id: 'sota-card-1',
          noteId: 'note-sota',
          originalContent: '弥散渐变模板离屏导出与二次保存缓存命中验证。',
          svgContent: CardTemplates.sotaModernTemplate(
            content: '弥散渐变模板离屏导出与二次保存缓存命中验证。',
            author: '测试作者',
            date: '2026-11-20',
            location: '示例省·示例市',
          ),
          type: CardType.sotaModern,
          createdAt: DateTime(2026, 11, 20),
        );

        final serifCard = GeneratedCard(
          id: 'serif-card-1',
          noteId: 'note-serif',
          originalContent: '经典衬线纸纹模板离屏导出与二次保存缓存命中验证。',
          svgContent: CardTemplates.classicSerifTemplate(
            content: '经典衬线纸纹模板离屏导出与二次保存缓存命中验证。',
            author: '测试作者',
            date: '2026-11-20',
          ),
          type: CardType.classicSerif,
          createdAt: DateTime(2026, 11, 20),
        );

        final exportResults = await tester.runAsync(() async {
          final shareSota = await sotaCard.toImageBytes(
            width: 800,
            height: 1200,
            scaleFactor: 2.0,
            renderMode: ExportRenderMode.contain,
            context: overlayContext,
          );
          final saveSota = await sotaCard.toImageBytes(
            width: 800,
            height: 1200,
            scaleFactor: 2.0,
            renderMode: ExportRenderMode.contain,
            context: overlayContext,
          );
          final shareSerif = await serifCard.toImageBytes(
            width: 800,
            height: 1200,
            scaleFactor: 2.0,
            renderMode: ExportRenderMode.contain,
            context: overlayContext,
          );
          final saveSerif = await serifCard.toImageBytes(
            width: 800,
            height: 1200,
            scaleFactor: 2.0,
            renderMode: ExportRenderMode.contain,
            context: overlayContext,
          );
          return [shareSota, saveSota, shareSerif, saveSerif];
        });

        expect(exportResults, isNotNull);
        // 两张卡片各执行先分享后保存共 4 次调用，实际渲染编码仅应发生 2 次
        expect(SvgToImageService.debugRenderCount, equals(2));
        expect(exportResults![0], same(exportResults[1]));
        expect(exportResults[2], same(exportResults[3]));

        final decodedSota = await tester.runAsync(
          () async => img.decodePng(exportResults[0]),
        );
        final decodedSerif = await tester.runAsync(
          () async => img.decodePng(exportResults[2]),
        );
        expect(decodedSota!.width, equals(1600));
        expect(decodedSota.height, equals(2400));
        expect(decodedSerif!.width, equals(1600));
        expect(decodedSerif.height, equals(2400));
        // GeneratedCard.toImageBytes 默认四角透明圆角裁剪
        expect(decodedSota.getPixel(0, 0).a.toInt(), equals(0));
        expect(decodedSerif.getPixel(0, 0).a.toInt(), equals(0));
      },
    );

    testWidgets(
      '离屏导出遇到慢速冷解码仍等待真实像素落盘，且超时抛错不截取空白占位',
      (tester) async {
        late BuildContext overlayContext;

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) {
                  overlayContext = context;
                  return const SizedBox.shrink();
                },
              ),
            ),
          ),
        );
        await tester.pump();

        const emeraldCardSvg = '''
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 120 120">
  <rect width="120" height="120" fill="#10b981"/>
</svg>
''';
        const slowLoader = _DelayedOffscreenSvgLoader(
          emeraldCardSvg,
          Duration(milliseconds: 150),
        );

        // 1. 超时短于解码耗时应抛出 TimeoutException，而非返回空白图
        Object? caughtError;
        await tester.runAsync(() async {
          try {
            await SvgOffscreenRenderer.instance.renderSvgString(
              emeraldCardSvg,
              context: overlayContext,
              width: 120,
              height: 120,
              background: Colors.transparent,
              timeout: const Duration(milliseconds: 25),
              loaderOverride: slowLoader,
            );
          } catch (e) {
            caughtError = e;
          }
        });
        expect(caughtError, isA<TimeoutException>());

        // 2. 充足超时内应等待慢解码完成并截取真实绿色像素
        final renderedBytes = await tester.runAsync(() async {
          return SvgOffscreenRenderer.instance.renderSvgString(
            emeraldCardSvg,
            context: overlayContext,
            width: 120,
            height: 120,
            background: Colors.transparent,
            timeout: const Duration(seconds: 2),
            loaderOverride: slowLoader,
          );
        });

        expect(renderedBytes, isNotNull);
        final decoded = await tester.runAsync(
          () async => img.decodePng(renderedBytes!),
        );
        expect(decoded, isNotNull);
        final center = decoded!.getPixel(60, 60);
        expect(center.a.toInt(), equals(255));
        expect(center.g.toInt(), greaterThan(150));
        expect(center.r.toInt(), lessThan(60));
      },
    );

    test('不同尺寸渲染', () async {
      final imageBytes = await SvgToImageService.convertSvgToImage(
        testSvg,
        width: 800,
        height: 1200,
      );

      expect(imageBytes, isNotNull);
      expect(imageBytes.length, greaterThan(0));
    });

    test('PNG格式输出', () async {
      final imageBytes = await SvgToImageService.convertSvgToImage(
        testSvg,
        width: 400,
        height: 600,
        format: ui.ImageByteFormat.png,
      );

      expect(imageBytes, isNotNull);
      expect(imageBytes.length, greaterThan(0));
      // PNG文件头检查
      expect(imageBytes[0], equals(0x89));
      expect(imageBytes[1], equals(0x50));
      expect(imageBytes[2], equals(0x4E));
      expect(imageBytes[3], equals(0x47));
    });

    test('无效SVG处理', () async {
      const invalidSvg = '<invalid>not svg</invalid>';

      final imageBytes = await SvgToImageService.convertSvgToImage(invalidSvg);

      // 应该返回错误图片而不是抛出异常
      expect(imageBytes, isNotNull);
      expect(imageBytes.length, greaterThan(0));
    });

    test('空SVG处理', () async {
      final imageBytes = await SvgToImageService.convertSvgToImage('');

      // 应该返回错误图片
      expect(imageBytes, isNotNull);
      expect(imageBytes.length, greaterThan(0));
    });

    test('复杂SVG渲染', () async {
      const complexSvg = '''
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 400 600">
  <defs>
    <linearGradient id="grad1" x1="0%" y1="0%" x2="100%" y2="100%">
      <stop offset="0%" style="stop-color:#ff6b6b;stop-opacity:1" />
      <stop offset="50%" style="stop-color:#4ecdc4;stop-opacity:1" />
      <stop offset="100%" style="stop-color:#45b7d1;stop-opacity:1" />
    </linearGradient>
  </defs>
  <rect width="400" height="600" fill="url(#grad1)" rx="20"/>
  <circle cx="100" cy="100" r="30" fill="#ffffff" fill-opacity="0.8"/>
  <circle cx="300" cy="500" r="25" fill="#ffffff" fill-opacity="0.6"/>
  <rect x="50" y="200" width="300" height="250" fill="#ffffff" fill-opacity="0.95" rx="15"/>
  <text x="200" y="250" text-anchor="middle" fill="#333" font-size="18">复杂SVG测试</text>
  <text x="200" y="300" text-anchor="middle" fill="#666" font-size="14">包含多个元素</text>
  <text x="200" y="350" text-anchor="middle" fill="#666" font-size="14">渐变背景</text>
  <text x="200" y="400" text-anchor="middle" fill="#666" font-size="14">多个图形</text>
</svg>
''';

      final imageBytes = await SvgToImageService.convertSvgToImage(
        complexSvg,
        width: 400,
        height: 600,
      );

      expect(imageBytes, isNotNull);
      expect(imageBytes.length, greaterThan(0));
    });

    test('性能测试', () async {
      final stopwatch = Stopwatch()..start();

      final imageBytes = await SvgToImageService.convertSvgToImage(
        testSvg,
        width: 400,
        height: 600,
      );

      stopwatch.stop();

      expect(imageBytes, isNotNull);
      expect(imageBytes.length, greaterThan(0));

      // 渲染时间应该在合理范围内（小于5秒）
      expect(stopwatch.elapsedMilliseconds, lessThan(5000));

      if (stopwatch.elapsedMilliseconds > 1000) {
        // Warning: SVG渲染耗时 ${stopwatch.elapsedMilliseconds}ms
      }
    });

    test('内存使用测试', () async {
      // 连续渲染多个SVG，检查内存是否正确释放
      for (int i = 0; i < 5; i++) {
        final imageBytes = await SvgToImageService.convertSvgToImage(
          testSvg,
          width: 400,
          height: 600,
        );

        expect(imageBytes, isNotNull);
        expect(imageBytes.length, greaterThan(0));
      }

      // 如果没有内存泄漏，测试应该正常完成
    });
  });
}
