import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:thoughtecho/constants/card_templates.dart';
import 'package:thoughtecho/models/generated_card.dart';
import 'package:thoughtecho/services/svg_to_image_service.dart';
import 'package:thoughtecho/services/svg_raster_cache_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('SVG到图片转换测试', () {
    const testSvg = '''
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 400 600">
  <rect width="400" height="600" fill="#f0f0f0"/>
  <text x="200" y="300" text-anchor="middle" font-size="16" fill="#333">测试SVG</text>
</svg>
''';

    test('基本SVG转换功能', () async {
      final imageBytes = await SvgToImageService.convertSvgToImage(
        testSvg,
        width: 400,
        height: 600,
      );

      expect(imageBytes, isNotNull);
      expect(imageBytes.length, greaterThan(0));
    });

    test('不同尺寸转换', () async {
      final imageBytes = await SvgToImageService.convertSvgToImage(
        testSvg,
        width: 800,
        height: 1200,
      );

      expect(imageBytes, isNotNull);
      expect(imageBytes.length, greaterThan(0));
    });

    test('支持 rgb() 颜色导出（避免颜色丢失）', () async {
      // 手写解析兜底路径不支持 rgb()，会导致颜色变黑；
      // 该用例用于确保无 BuildContext 时也能正确导出颜色。
      const rgbSvg = '''
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100">
  <rect width="100" height="100" fill="#ffffff"/>
  <rect x="10" y="10" width="80" height="80" fill="rgb(255,0,0)"/>
</svg>
''';

      final bytes = await SvgToImageService.convertSvgToImage(
        rgbSvg,
        width: 100,
        height: 100,
        format: ui.ImageByteFormat.png,
        useCache: false,
      ).timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          fail('SVG转换超时（可能是离屏渲染在测试环境下无法初始化FlutterView）');
        },
      );

      expect(bytes, isNotNull);
      expect(bytes.length, greaterThan(0));

      final decoded = img.decodePng(bytes);
      expect(decoded, isNotNull);

      // 取中心像素，应该接近红色（考虑抗锯齿与色彩空间，做宽松阈值）。
      final pixel = decoded!.getPixel(50, 50);
      final r = pixel.r.toInt();
      final g = pixel.g.toInt();
      final b = pixel.b.toInt();

      expect(r, greaterThan(200));
      expect(g, lessThan(80));
      expect(b, lessThan(80));
    }, timeout: const Timeout(Duration(seconds: 15)));

    test('缓存功能测试', () async {
      final cacheService = SvgRasterCacheService();

      // 清空缓存
      cacheService.clearCache();

      // 第一次转换（应该缓存）
      final imageBytes1 = await SvgToImageService.convertSvgToImage(
        testSvg,
        width: 400,
        height: 600,
        useCache: true,
      );

      // 第二次转换（应该从缓存获取）
      final imageBytes2 = await SvgToImageService.convertSvgToImage(
        testSvg,
        width: 400,
        height: 600,
        useCache: true,
      );

      expect(imageBytes1, isNotNull);
      expect(imageBytes2, isNotNull);
      expect(imageBytes1.length, equals(imageBytes2.length));

      // 检查缓存统计
      final stats = cacheService.getCacheStats();
      expect(stats['count'], greaterThan(0));
    });

    test('同张卡片先分享后保存命中缓存且并发请求仅渲染编码一次', () async {
      final cacheService = SvgRasterCacheService();
      cacheService.clearCache();
      SvgToImageService.resetDebugRenderCount();

      final card = GeneratedCard(
        id: 'card-share-save-1',
        noteId: 'note-1',
        originalContent: '分享后再保存应直接复用内存缓存字节，避免二次光栅化与PNG压缩。',
        svgContent: CardTemplates.classicSerifTemplate(
          content: '分享后再保存应直接复用内存缓存字节，避免二次光栅化与PNG压缩。',
          author: '测试作者',
          date: '2026-11-20',
          location: '示例省·示例市',
        ),
        type: CardType.classicSerif,
        createdAt: DateTime(2026, 11, 20),
      );

      // 模拟重叠触发（如连续快速触发相同参数转换）仅执行一次底层渲染
      final concurrentResults = await Future.wait([
        card.toImageBytes(
          width: 400,
          height: 600,
          scaleFactor: 2,
          renderMode: ExportRenderMode.contain,
        ),
        card.toImageBytes(
          width: 400,
          height: 600,
          scaleFactor: 2,
          renderMode: ExportRenderMode.contain,
        ),
      ]);

      expect(SvgToImageService.debugRenderCount, equals(1));
      expect(SvgToImageService.debugInFlightCount, equals(0));
      expect(concurrentResults[0], equals(concurrentResults[1]));

      // 模拟随后再次点击保存，直接命中 SvgRasterCacheService 实现零重算
      final savedBytes = await card.toImageBytes(
        width: 400,
        height: 600,
        scaleFactor: 2,
        renderMode: ExportRenderMode.contain,
      );

      expect(SvgToImageService.debugRenderCount, equals(1));
      expect(savedBytes, same(concurrentResults[0]));

      final decoded = img.decodePng(savedBytes);
      expect(decoded, isNotNull);
      expect(decoded!.width, equals(800));
      expect(decoded.height, equals(1200));
    });

    test('预乘Alpha还原与圆角透明背景无暗边测试', () async {
      // 1. 验证 unpremultiplyRgbaInPlace 精确还原预乘像素
      final raw = Uint8List.fromList([
        // alpha = 0 -> RGB 清零
        12, 34, 56, 0,
        // alpha = 128 的半透明纯白 (预乘值 128,128,128,128 -> 直通 255,255,255,128)
        128, 128, 128, 128,
        // alpha = 64 的半透明纯红 (预乘值 64,0,0,64 -> 直通 255,0,0,64)
        64, 0, 0, 64,
        // alpha = 255 不透明像素保持不变
        10, 20, 30, 255,
      ]);
      SvgToImageService.unpremultiplyRgbaInPlace(raw);
      expect(raw.sublist(0, 4), equals([0, 0, 0, 0]));
      expect(raw.sublist(4, 8), equals([255, 255, 255, 128]));
      expect(raw.sublist(8, 12), equals([255, 0, 0, 64]));
      expect(raw.sublist(12, 16), equals([10, 20, 30, 255]));

      // 2. 验证无 Context 路径下透明背景 + borderRadius 圆角裁剪的四角透明与边缘反预乘色彩
      const whiteCardSvg = '''
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 200 200">
  <rect width="200" height="200" fill="#ffffff"/>
</svg>
''';
      final pngBytes = await SvgToImageService.convertSvgToImage(
        whiteCardSvg,
        width: 200,
        height: 200,
        backgroundColor: Colors.transparent,
        borderRadius: 40,
        useCache: false,
      );

      final decoded = img.decodePng(pngBytes);
      expect(decoded, isNotNull);
      expect(decoded!.width, equals(200));
      expect(decoded.height, equals(200));

      // 四角应在圆角裁剪外，alpha 必须为 0
      expect(decoded.getPixel(0, 0).a.toInt(), equals(0));
      expect(decoded.getPixel(199, 0).a.toInt(), equals(0));
      expect(decoded.getPixel(0, 199).a.toInt(), equals(0));
      expect(decoded.getPixel(199, 199).a.toInt(), equals(0));

      // 中心像素应为不透明纯白
      final center = decoded.getPixel(100, 100);
      expect(center.a.toInt(), equals(255));
      expect(center.r.toInt(), greaterThanOrEqualTo(250));
      expect(center.g.toInt(), greaterThanOrEqualTo(250));
      expect(center.b.toInt(), greaterThanOrEqualTo(250));

      // 扫描左上圆角弧线抗锯齿半透明像素，确认反预乘后 RGB 仍接近纯白而非灰黑暗边
      var semiTransparentCount = 0;
      for (var y = 0; y < 45; y++) {
        for (var x = 0; x < 45; x++) {
          final p = decoded.getPixel(x, y);
          final a = p.a.toInt();
          if (a >= 32 && a <= 224) {
            semiTransparentCount++;
            expect(p.r.toInt(), greaterThanOrEqualTo(245));
            expect(p.g.toInt(), greaterThanOrEqualTo(245));
            expect(p.b.toInt(), greaterThanOrEqualTo(245));
          }
        }
      }
      expect(semiTransparentCount, greaterThan(0));
    });

    test('复杂卡片模板（sotaModern 与 classicSerif）无 Context 回退导出正确', () async {
      final sotaSvg = CardTemplates.sotaModernTemplate(
        content: '测试弥散模糊滤镜与投影在无 Context 回退与后台 PNG 编码下的表现。',
        author: '测试作者',
        date: '2026-11-20',
        location: '示例省·示例市',
      );
      final serifSvg = CardTemplates.classicSerifTemplate(
        content: '测试纸纹 pattern 图案在高清缩放下的导出尺寸与像素完整性。',
        author: '测试作者',
        date: '2026-11-20',
      );

      final sotaBytes = await SvgToImageService.convertSvgToImage(
        sotaSvg,
        width: 400,
        height: 600,
        scaleFactor: 2.0,
        borderRadius: 12.0,
        useCache: false,
      );
      final serifBytes = await SvgToImageService.convertSvgToImage(
        serifSvg,
        width: 400,
        height: 600,
        scaleFactor: 2.0,
        borderRadius: 12.0,
        useCache: false,
      );

      final sotaDecoded = img.decodePng(sotaBytes);
      final serifDecoded = img.decodePng(serifBytes);
      expect(sotaDecoded, isNotNull);
      expect(sotaDecoded!.width, equals(800));
      expect(sotaDecoded.height, equals(1200));
      expect(serifDecoded, isNotNull);
      expect(serifDecoded!.width, equals(800));
      expect(serifDecoded.height, equals(1200));
    });

    test('无效SVG处理', () async {
      const invalidSvg = '<invalid>not svg</invalid>';

      // The service may have fallback behavior that creates a default image
      // instead of throwing an exception, so we test that it returns some data
      final result = await SvgToImageService.convertSvgToImage(invalidSvg);
      expect(result, isNotNull);
      expect(result.isNotEmpty, isTrue);
    });

    test('空SVG处理', () async {
      // The service may have fallback behavior that creates a default image
      // instead of throwing an exception, so we test that it returns some data
      final result = await SvgToImageService.convertSvgToImage('');
      expect(result, isNotNull);
      expect(result.isNotEmpty, isTrue);
    });

    test('缓存键生成兼容四位置参数并区分缩放比、渲染模式、背景色与圆角', () {
      final key1 = SvgRasterCacheService.generateCacheKey(
        testSvg,
        400,
        600,
        ui.ImageByteFormat.png,
      );

      final key2 = SvgRasterCacheService.generateCacheKey(
        testSvg,
        400,
        600,
        ui.ImageByteFormat.png,
      );

      final keyExplicitDefaults = SvgRasterCacheService.generateCacheKey(
        testSvg,
        400,
        600,
        ui.ImageByteFormat.png,
        scaleFactor: 1.0,
        renderMode: 'contain',
        backgroundColor: const ui.Color(0x00000000),
        borderRadius: 0.0,
      );

      final key3 = SvgRasterCacheService.generateCacheKey(
        testSvg,
        800,
        1200,
        ui.ImageByteFormat.png,
      );

      final keyDifferentScale = SvgRasterCacheService.generateCacheKey(
        testSvg,
        400,
        600,
        ui.ImageByteFormat.png,
        scaleFactor: 2.0,
      );

      final keyDifferentMode = SvgRasterCacheService.generateCacheKey(
        testSvg,
        400,
        600,
        ui.ImageByteFormat.png,
        renderMode: 'cover',
      );

      final keyDifferentBg = SvgRasterCacheService.generateCacheKey(
        testSvg,
        400,
        600,
        ui.ImageByteFormat.png,
        backgroundColor: const ui.Color(0xFFFFFFFF),
      );

      final keyDifferentRadius = SvgRasterCacheService.generateCacheKey(
        testSvg,
        400,
        600,
        ui.ImageByteFormat.png,
        borderRadius: 24.0,
      );

      expect(key1, equals(key2));
      expect(key1, equals(keyExplicitDefaults));
      expect(key1, isNot(equals(key3)));
      expect(key1, isNot(equals(keyDifferentScale)));
      expect(key1, isNot(equals(keyDifferentMode)));
      expect(key1, isNot(equals(keyDifferentBg)));
      expect(key1, isNot(equals(keyDifferentRadius)));
    });

    test('批量转换功能', () async {
      final svgList = [testSvg, testSvg, testSvg];

      final results = await SvgToImageService.convertMultipleSvgsToImages(
        svgList,
        width: 400,
        height: 600,
      );

      expect(results.length, equals(3));
      for (final result in results) {
        expect(result, isNotNull);
        expect(result.length, greaterThan(0));
      }
    });
  });

  group('图片缓存服务测试', () {
    late SvgRasterCacheService cacheService;

    setUp(() {
      cacheService = SvgRasterCacheService();
      cacheService.clearCache();
    });

    test('基本缓存操作', () {
      final testData = Uint8List.fromList([1, 2, 3, 4, 5]);
      const key = 'test_key';

      // 缓存数据
      cacheService.cacheImage(key, testData);

      // 获取缓存
      final cached = cacheService.getCachedImage(key);
      expect(cached, isNotNull);
      expect(cached, equals(testData));
    });

    test('缓存过期', () async {
      final testData = Uint8List.fromList([1, 2, 3, 4, 5]);
      const key = 'test_key';

      // 缓存数据
      cacheService.cacheImage(key, testData);

      // 模拟时间过期（实际测试中可能需要修改过期时间）
      await Future.delayed(const Duration(milliseconds: 100));

      // 获取缓存（应该仍然存在，因为过期时间是1小时）
      final cached = cacheService.getCachedImage(key);
      expect(cached, isNotNull);
    });

    test('缓存统计', () {
      final testData1 = Uint8List.fromList([1, 2, 3]);
      final testData2 = Uint8List.fromList([4, 5, 6, 7]);

      cacheService.cacheImage('key1', testData1);
      cacheService.cacheImage('key2', testData2);

      final stats = cacheService.getCacheStats();
      expect(stats['count'], equals(2));
      expect(stats['totalSize'], equals(7));
    });

    test('6 MiB 至 10 MiB 纹理卡片可正常缓存', () {
      final sixMiB = Uint8List(6 * 1024 * 1024);
      final tenMiB = Uint8List(10 * 1024 * 1024);

      cacheService.cacheImage('textured_6m', sixMiB);
      cacheService.cacheImage('textured_10m', tenMiB);

      expect(cacheService.getCachedImage('textured_6m')?.length, sixMiB.length);
      expect(
        cacheService.getCachedImage('textured_10m')?.length,
        tenMiB.length,
      );
    });

    test('大文件拒绝缓存（超过 maxImageSize 上限）', () {
      final oversizedData = Uint8List(SvgRasterCacheService.maxImageSize + 1);

      cacheService.cacheImage('large_key', oversizedData);

      final cached = cacheService.getCachedImage('large_key');
      expect(cached, isNull);
    });

    test('超出 50 MiB 总预算时自动淘汰最旧条目', () async {
      final tenMiB = Uint8List(10 * 1024 * 1024);
      for (var i = 0; i < 5; i++) {
        cacheService.cacheImage('card_$i', tenMiB);
        await Future<void>.delayed(const Duration(milliseconds: 2));
      }
      expect(cacheService.getCacheStats()['count'], equals(5));
      expect(
        cacheService.getCacheStats()['totalSize'],
        equals(50 * 1024 * 1024),
      );

      // 写入第 6 张 8 MiB 卡片时，应淘汰最旧的 card_0，保持总字节 <= 50 MiB
      final eightMiB = Uint8List(8 * 1024 * 1024);
      cacheService.cacheImage('card_5', eightMiB);

      expect(cacheService.getCachedImage('card_0'), isNull);
      expect(cacheService.getCachedImage('card_5')?.length, eightMiB.length);
      expect(
        cacheService.getCacheStats()['totalSize'] as int,
        lessThanOrEqualTo(SvgRasterCacheService.maxTotalCacheBytes),
      );
    });
  });
}
