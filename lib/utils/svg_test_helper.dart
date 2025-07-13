import 'package:flutter/foundation.dart';

/// SVG测试辅助工具
class SVGTestHelper {
  /// 生成测试用的简单SVG
  static String generateTestSVG({
    String content = '这是一个测试卡片',
    String title = 'SVG测试',
  }) {
    return '''
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 400 600">
  <defs>
    <linearGradient id="testBg" x1="0%" y1="0%" x2="100%" y2="100%">
      <stop offset="0%" style="stop-color:#4facfe;stop-opacity:1" />
      <stop offset="100%" style="stop-color:#00f2fe;stop-opacity:1" />
    </linearGradient>
  </defs>
  
  <!-- 背景 -->
  <rect width="400" height="600" fill="url(#testBg)" rx="20"/>
  
  <!-- 标题 -->
  <text x="200" y="100" text-anchor="middle" fill="white" font-family="Arial, sans-serif" font-size="24" font-weight="bold">
    $title
  </text>
  
  <!-- 内容区域 -->
  <rect x="40" y="140" width="320" height="300" fill="rgba(255,255,255,0.95)" rx="15"/>
  
  <!-- 内容文字 -->
  <text x="200" y="200" text-anchor="middle" fill="#333" font-family="Arial, sans-serif" font-size="16">
    $content
  </text>
  
  <!-- 装饰元素 -->
  <circle cx="80" cy="500" r="20" fill="rgba(255,255,255,0.3)"/>
  <circle cx="320" cy="520" r="15" fill="rgba(255,255,255,0.3)"/>
  
  <!-- 底部信息 -->
  <text x="200" y="550" text-anchor="middle" fill="white" font-family="Arial, sans-serif" font-size="12">
    ThoughtEcho - SVG测试
  </text>
</svg>
''';
  }

  /// 验证SVG内容是否有效
  static bool validateSVG(String svgContent) {
    if (svgContent.trim().isEmpty) {
      if (kDebugMode) print('SVG验证失败: 内容为空');
      return false;
    }

    if (!svgContent.contains('<svg')) {
      if (kDebugMode) print('SVG验证失败: 缺少<svg>标签');
      return false;
    }

    if (!svgContent.contains('</svg>')) {
      if (kDebugMode) print('SVG验证失败: 缺少</svg>结束标签');
      return false;
    }

    if (!svgContent.contains('xmlns="http://www.w3.org/2000/svg"')) {
      if (kDebugMode) print('SVG验证警告: 缺少xmlns命名空间');
    }

    if (!svgContent.contains('viewBox')) {
      if (kDebugMode) print('SVG验证警告: 缺少viewBox属性');
    }

    return true;
  }

  /// 清理和修复SVG内容
  static String cleanAndFixSVG(String svgContent) {
    String cleaned = svgContent.trim();

    // 移除markdown标记
    cleaned =
        cleaned
            .replaceAll('```svg', '')
            .replaceAll('```xml', '')
            .replaceAll('```', '')
            .replaceAll('`', '')
            .trim();

    // 确保有xmlns
    if (!cleaned.contains('xmlns="http://www.w3.org/2000/svg"')) {
      cleaned = cleaned.replaceFirst(
        '<svg',
        '<svg xmlns="http://www.w3.org/2000/svg"',
      );
    }

    // 确保有viewBox
    if (!cleaned.contains('viewBox') &&
        !cleaned.contains('width=') &&
        !cleaned.contains('height=')) {
      cleaned = cleaned.replaceFirst('<svg', '<svg viewBox="0 0 400 600"');
    }

    return cleaned;
  }

  /// 生成多种测试SVG样式
  static List<String> generateTestSVGs() {
    return [
      generateTestSVG(content: '简单测试卡片', title: '基础测试'),
      generateGradientTestSVG(),
      generateTextTestSVG(),
      generateShapeTestSVG(),
    ];
  }

  /// 生成渐变测试SVG
  static String generateGradientTestSVG() {
    return '''
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 400 600">
  <defs>
    <radialGradient id="radialBg" cx="50%" cy="50%" r="50%">
      <stop offset="0%" style="stop-color:#ff9a9e;stop-opacity:1" />
      <stop offset="100%" style="stop-color:#fecfef;stop-opacity:1" />
    </radialGradient>
  </defs>
  
  <rect width="400" height="600" fill="url(#radialBg)" rx="20"/>
  <text x="200" y="300" text-anchor="middle" fill="#333" font-family="Arial, sans-serif" font-size="20">
    渐变测试
  </text>
</svg>
''';
  }

  /// 生成文字测试SVG
  static String generateTextTestSVG() {
    return '''
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 400 600">
  <rect width="400" height="600" fill="#f8f9fa" rx="20"/>
  <text x="200" y="100" text-anchor="middle" fill="#333" font-family="Arial, sans-serif" font-size="18" font-weight="bold">
    文字渲染测试
  </text>
  <text x="200" y="200" text-anchor="middle" fill="#666" font-family="Arial, sans-serif" font-size="14">
    这是一段测试文字
  </text>
  <text x="200" y="300" text-anchor="middle" fill="#999" font-family="Arial, sans-serif" font-size="12">
    Text Rendering Test
  </text>
</svg>
''';
  }

  /// 生成形状测试SVG
  static String generateShapeTestSVG() {
    return '''
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 400 600">
  <rect width="400" height="600" fill="#e3f2fd" rx="20"/>
  <circle cx="200" cy="150" r="50" fill="#2196f3"/>
  <rect x="150" y="250" width="100" height="100" fill="#4caf50" rx="10"/>
  <polygon points="200,400 150,500 250,500" fill="#ff9800"/>
  <text x="200" y="550" text-anchor="middle" fill="#333" font-family="Arial, sans-serif" font-size="16">
    形状测试
  </text>
</svg>
''';
  }
}
