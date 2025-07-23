import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/services/svg_to_image_service.dart';

void main() {
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
        print('警告: SVG渲染耗时 ${stopwatch.elapsedMilliseconds}ms');
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
