import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/services/svg_to_image_service.dart';

void main() {
  group('SVG文本渲染修复测试', () {
    test('基本文本渲染', () async {
      const testSvg = '''
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 400 600">
  <rect width="400" height="600" fill="#ffffff"/>
  <text x="200" y="100" text-anchor="middle" fill="#333333" font-size="16">基本文本测试</text>
  <text x="50" y="200" fill="#666666" font-size="14">左对齐文本</text>
  <text x="350" y="300" text-anchor="end" fill="#999999" font-size="12">右对齐文本</text>
</svg>
''';

      final imageBytes = await SvgToImageService.convertSvgToImage(
        testSvg,
        width: 400,
        height: 600,
      );

      expect(imageBytes, isNotNull);
      expect(imageBytes.length, greaterThan(0));
      // Test output: 基本文本渲染图片大小: ${imageBytes.length} bytes
    });

    test('复杂字体属性文本', () async {
      const testSvg = '''
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 400 600">
  <rect width="400" height="600" fill="#f8f9fa"/>
  <text x="200" y="80" text-anchor="middle" fill="#212529" font-size="18" font-weight="bold">粗体标题</text>
  <text x="200" y="120" text-anchor="middle" fill="#495057" font-size="14" font-style="italic">斜体副标题</text>
  <text x="200" y="160" text-anchor="middle" fill="#6c757d" font-size="12" font-family="system-ui, Arial, sans-serif">系统字体文本</text>
  <text x="50" y="220" fill="#007bff" font-size="16" font-weight="500">中等粗细蓝色文本</text>
  <text x="50" y="260" fill="#28a745" font-size="14">绿色普通文本</text>
  <text x="50" y="300" fill="#dc3545" font-size="12" font-weight="700">红色粗体小文本</text>
</svg>
''';

      final imageBytes = await SvgToImageService.convertSvgToImage(
        testSvg,
        width: 400,
        height: 600,
      );

      expect(imageBytes, isNotNull);
      expect(imageBytes.length, greaterThan(0));
      // Test output: 复杂字体属性文本图片大小: ${imageBytes.length} bytes
    });

    test('中文文本渲染', () async {
      const testSvg = '''
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 400 600">
  <defs>
    <linearGradient id="bg" x1="0%" y1="0%" x2="100%" y2="100%">
      <stop offset="0%" style="stop-color:#4f46e5;stop-opacity:1" />
      <stop offset="100%" style="stop-color:#7c3aed;stop-opacity:1" />
    </linearGradient>
  </defs>
  <rect width="400" height="600" fill="url(#bg)"/>
  <text x="200" y="100" text-anchor="middle" fill="#ffffff" font-size="20" font-weight="bold">心迹</text>
  <text x="200" y="200" text-anchor="middle" fill="#ffffff" font-size="16">今天学习了Flutter的状态管理</text>
  <text x="200" y="240" text-anchor="middle" fill="#ffffff" font-size="14">发现Provider模式非常实用</text>
  <text x="200" y="280" text-anchor="middle" fill="#ffffff" font-size="14">可以有效地管理应用状态</text>
  <text x="200" y="500" text-anchor="middle" fill="#ffffff" font-size="12" font-style="italic">2024年1月15日</text>
</svg>
''';

      final imageBytes = await SvgToImageService.convertSvgToImage(
        testSvg,
        width: 400,
        height: 600,
      );

      expect(imageBytes, isNotNull);
      expect(imageBytes.length, greaterThan(0));
      // Test output: 中文文本渲染图片大小: ${imageBytes.length} bytes
    });

    test('实际卡片模板文本渲染', () async {
      // 使用实际的卡片模板SVG
      const cardSvg = '''
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 400 600">
  <defs>
    <linearGradient id="knowledgeBg" x1="0%" y1="0%" x2="100%" y2="100%">
      <stop offset="0%" style="stop-color:#3B82F6;stop-opacity:1" />
      <stop offset="50%" style="stop-color:#1E40AF;stop-opacity:1" />
      <stop offset="100%" style="stop-color:#6366F1;stop-opacity:1" />
    </linearGradient>
  </defs>
  
  <!-- 背景 -->
  <rect width="400" height="600" fill="url(#knowledgeBg)" rx="24"/>
  
  <!-- 装饰圆形 -->
  <circle cx="80" cy="80" r="40" fill="#ffffff" fill-opacity="0.15"/>
  <circle cx="320" cy="520" r="30" fill="#ffffff" fill-opacity="0.1"/>
  
  <!-- 内容区域 -->
  <rect x="32" y="150" width="336" height="300" fill="#ffffff" fill-opacity="0.95" rx="20"/>
  
  <!-- 主要内容 -->
  <text x="200" y="200" text-anchor="middle" fill="#1f2937" font-family="system-ui, -apple-system, sans-serif" font-size="16" font-weight="500">
    今天学习了Flutter的状态管理，
  </text>
  <text x="200" y="230" text-anchor="middle" fill="#1f2937" font-family="system-ui, -apple-system, sans-serif" font-size="16" font-weight="500">
    发现Provider模式非常实用，
  </text>
  <text x="200" y="260" text-anchor="middle" fill="#1f2937" font-family="system-ui, -apple-system, sans-serif" font-size="16" font-weight="500">
    可以有效地管理应用状态。
  </text>
  
  <!-- 底部信息 -->
  <rect x="32" y="500" width="336" height="50" fill="#ffffff" fill-opacity="0.15" rx="20"/>
  <text x="200" y="530" text-anchor="middle" fill="#ffffff" font-family="system-ui, -apple-system, sans-serif" font-size="12" fill-opacity="0.9">
    2024年1月15日 · 心迹
  </text>
</svg>
''';

      final imageBytes = await SvgToImageService.convertSvgToImage(
        cardSvg,
        width: 400,
        height: 600,
      );

      expect(imageBytes, isNotNull);
      expect(imageBytes.length, greaterThan(0));
      // Test output: 实际卡片模板文本渲染图片大小: ${imageBytes.length} bytes
    });

    test('特殊字符和符号文本', () async {
      const testSvg = '''
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 400 600">
  <rect width="400" height="600" fill="#ffffff"/>
  <text x="200" y="100" text-anchor="middle" fill="#333333" font-size="16">特殊字符测试：@#\$%^&*()</text>
  <text x="200" y="150" text-anchor="middle" fill="#333333" font-size="16">数字测试：1234567890</text>
  <text x="200" y="200" text-anchor="middle" fill="#333333" font-size="16">符号测试：！？。，；：""''</text>
  <text x="200" y="250" text-anchor="middle" fill="#333333" font-size="16">英文测试：Hello World!</text>
  <text x="200" y="300" text-anchor="middle" fill="#333333" font-size="16">混合测试：Hello 世界 123!</text>
</svg>
''';

      final imageBytes = await SvgToImageService.convertSvgToImage(
        testSvg,
        width: 400,
        height: 600,
      );

      expect(imageBytes, isNotNull);
      expect(imageBytes.length, greaterThan(0));
      // Test output: 特殊字符文本渲染图片大小: ${imageBytes.length} bytes
    });

    test('长文本处理', () async {
      const testSvg = '''
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 400 600">
  <rect width="400" height="600" fill="#f8f9fa"/>
  <text x="200" y="80" text-anchor="middle" fill="#212529" font-size="18" font-weight="bold">长文本测试</text>
  <text x="50" y="150" fill="#495057" font-size="14">这是一段很长的文本内容，用来测试SVG文本渲染器是否能够正确处理长文本。</text>
  <text x="50" y="200" fill="#495057" font-size="14">虽然SVG不支持自动换行，但我们的渲染器应该能够正确显示这些文本。</text>
  <text x="50" y="250" fill="#495057" font-size="14">这段文本包含了中文、English、数字123和特殊符号！@#\$%</text>
</svg>
''';

      final imageBytes = await SvgToImageService.convertSvgToImage(
        testSvg,
        width: 400,
        height: 600,
      );

      expect(imageBytes, isNotNull);
      expect(imageBytes.length, greaterThan(0));
      // Test output: 长文本处理图片大小: ${imageBytes.length} bytes
    });

    test('错误文本属性处理', () async {
      const testSvg = '''
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 400 600">
  <rect width="400" height="600" fill="#ffffff"/>
  <text x="invalid" y="100" text-anchor="middle" fill="#333333" font-size="16">无效x坐标</text>
  <text x="200" y="invalid" text-anchor="middle" fill="#333333" font-size="16">无效y坐标</text>
  <text x="200" y="200" text-anchor="middle" fill="invalid" font-size="16">无效颜色</text>
  <text x="200" y="250" text-anchor="middle" fill="#333333" font-size="invalid">无效字体大小</text>
  <text x="200" y="300" text-anchor="middle" fill="#333333" font-size="16" font-weight="invalid">无效字体粗细</text>
</svg>
''';

      // 即使有无效属性，也应该能够渲染而不抛出异常
      final imageBytes = await SvgToImageService.convertSvgToImage(
        testSvg,
        width: 400,
        height: 600,
      );

      expect(imageBytes, isNotNull);
      expect(imageBytes.length, greaterThan(0));
      // Test output: 错误文本属性处理图片大小: ${imageBytes.length} bytes
    });
  });
}
