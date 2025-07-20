import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:thoughtecho/services/svg_to_image_service.dart';
import 'package:thoughtecho/services/image_cache_service.dart';

void main() {
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

    test('缓存功能测试', () async {
      final cacheService = ImageCacheService();

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

    test('无效SVG处理', () async {
      const invalidSvg = '<invalid>not svg</invalid>';

      expect(
        () async => await SvgToImageService.convertSvgToImage(invalidSvg),
        throwsException,
      );
    });

    test('空SVG处理', () async {
      expect(
        () async => await SvgToImageService.convertSvgToImage(''),
        throwsException,
      );
    });

    test('缓存键生成', () {
      final key1 = ImageCacheService.generateCacheKey(
        testSvg,
        400,
        600,
        ui.ImageByteFormat.png,
      );

      final key2 = ImageCacheService.generateCacheKey(
        testSvg,
        400,
        600,
        ui.ImageByteFormat.png,
      );

      final key3 = ImageCacheService.generateCacheKey(
        testSvg,
        800,
        1200,
        ui.ImageByteFormat.png,
      );

      expect(key1, equals(key2));
      expect(key1, isNot(equals(key3)));
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
    late ImageCacheService cacheService;

    setUp(() {
      cacheService = ImageCacheService();
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

    test('大文件拒绝缓存', () {
      // 创建超过5MB的数据
      final largeData = Uint8List(6 * 1024 * 1024);

      cacheService.cacheImage('large_key', largeData);

      final cached = cacheService.getCachedImage('large_key');
      expect(cached, isNull);
    });
  });
}
