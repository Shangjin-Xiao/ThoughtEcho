import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:thoughtecho/utils/app_logger.dart';
import 'svg_offscreen_renderer.dart';
import 'image_cache_service.dart';

/// 导出渲染模式
enum ExportRenderMode {
  contain, // 等比完整显示（可能留边）
  cover, // 等比填满（可能裁切）
  stretch, // 拉伸填满（可能变形）
}

/// SVG到图片转换服务
class SvgToImageService {
  static final ImageCacheService _cacheService = ImageCacheService();

  /// 将SVG字符串转换为图片字节数组
  static Future<Uint8List> convertSvgToImage(
    String svgContent, {
    int width = 400,
    int height = 600,
    ui.ImageByteFormat format = ui.ImageByteFormat.png,
    Color backgroundColor = Colors.white,
    bool maintainAspectRatio = true,
    bool useCache = true,
    double scaleFactor = 1.0,
    ExportRenderMode renderMode = ExportRenderMode.contain,
    BuildContext? context,
  }) async {
    try {
      // 验证输入参数
      if (width <= 0 || height <= 0) {
        throw ArgumentError('图片尺寸必须大于0');
      }

      if (width > 4000 || height > 4000) {
        logError('图片尺寸过大: ${width}x$height，可能导致内存问题',
            source: 'SvgToImageService');
      }

      // 生成缓存键
      final cacheKey = useCache
          ? ImageCacheService.generateCacheKey(
              svgContent, width, height, format)
          : null;

      // 尝试从缓存获取
      if (useCache && cacheKey != null) {
        final cachedImage = _cacheService.getCachedImage(cacheKey);
        if (cachedImage != null) {
          AppLogger.d('使用缓存图片: $cacheKey', source: 'SvgToImageService');
          return cachedImage;
        }
      }

      // 验证SVG内容
      _validateSvgContent(svgContent);

      // 检查内存使用情况
      if (useCache) {
        _cacheService.smartCleanup();
      }

      // 创建一个简化的SVG渲染器
      final imageBytes = await _renderSvgToBytes(
        svgContent,
        width,
        height,
        format,
        backgroundColor,
        maintainAspectRatio,
        scaleFactor,
        renderMode,
        context,
      );

      // 缓存结果
      if (useCache && cacheKey != null) {
        _cacheService.cacheImage(cacheKey, imageBytes);
      }

      return imageBytes;
    } catch (e) {
      AppLogger.e('SVG转换失败: $e', error: e, source: 'SvgToImageService');
      // 生成错误提示图片
      return await _generateErrorImage(width, height, format, e.toString());
    }
  }

  /// 批量转换SVG为图片
  static Future<List<Uint8List>> convertMultipleSvgsToImages(
    List<String> svgContents, {
    int width = 400,
    int height = 600,
    ui.ImageByteFormat format = ui.ImageByteFormat.png,
    Color backgroundColor = Colors.white,
    bool maintainAspectRatio = true,
    Function(int current, int total)? onProgress,
  }) async {
    final results = <Uint8List>[];

    for (int i = 0; i < svgContents.length; i++) {
      try {
        final imageBytes = await convertSvgToImage(
          svgContents[i],
          width: width,
          height: height,
          format: format,
          backgroundColor: backgroundColor,
          maintainAspectRatio: maintainAspectRatio,
        );
        results.add(imageBytes);

        onProgress?.call(i + 1, svgContents.length);
      } catch (e) {
        if (kDebugMode) {
          print('批量转换第${i + 1}个SVG失败: $e');
        }
        // 添加错误图片
        final errorImage =
            await _generateErrorImage(width, height, format, e.toString());
        results.add(errorImage);
      }
    }

    return results;
  }

  /// 验证SVG内容
  static void _validateSvgContent(String svgContent) {
    if (svgContent.trim().isEmpty) {
      throw Exception('SVG内容为空');
    }

    if (!svgContent.contains('<svg') || !svgContent.contains('</svg>')) {
      throw Exception('无效的SVG格式：缺少必要的SVG标签');
    }

    // 检查SVG内容长度
    if (svgContent.length > 1024 * 1024) {
      // 1MB限制
      throw Exception('SVG内容过大，超过1MB限制');
    }

    // 基本的安全检查
    final dangerousElements = ['<script', '<iframe', '<object', '<embed'];
    final lowerContent = svgContent.toLowerCase();
    for (final dangerous in dangerousElements) {
      if (lowerContent.contains(dangerous)) {
        throw Exception('SVG内容包含不安全的元素: $dangerous');
      }
    }
  }

  /// 渲染SVG为字节数组
  static Future<Uint8List> _renderSvgToBytes(
    String svgContent,
    int width,
    int height,
    ui.ImageByteFormat format,
    Color backgroundColor,
    bool maintainAspectRatio,
    double scaleFactor,
    ExportRenderMode renderMode,
    BuildContext? buildContext,
  ) async {
    try {
      // 直接使用Canvas渲染SVG
      return await _renderSvgWithCanvas(
        svgContent,
        width,
        height,
        format,
        backgroundColor,
        scaleFactor,
        renderMode,
        buildContext,
      );
    } catch (e) {
      AppLogger.w('SVG渲染失败，使用回退方案: $e', error: e, source: 'SvgToImageService');
      // 如果SVG渲染失败，使用回退方案
      return await _renderFallbackImage(
        svgContent,
        width,
        height,
        format,
        backgroundColor,
      );
    }
  }

  /// 使用Canvas渲染SVG（简化版本）
  static Future<Uint8List> _renderSvgWithCanvas(
    String svgContent,
    int targetWidth,
    int targetHeight,
    ui.ImageByteFormat format,
    Color backgroundColor,
    double scaleFactor,
    ExportRenderMode renderMode,
    BuildContext? buildContext,
  ) async {
    // 优先尝试离屏Flutter渲染（与预览一致）
    try {
      if (buildContext != null) {
        final bytes = await SvgOffscreenRenderer.instance.renderSvgString(
          svgContent,
          context: buildContext,
          width: targetWidth,
          height: targetHeight,
          scaleFactor: scaleFactor,
          background: backgroundColor,
          mode: renderMode,
        );
        return bytes;
      } else {
        throw StateError('缺少BuildContext，无法执行精准渲染');
      }
    } catch (e) {
      AppLogger.w('离屏真实渲染失败，使用简化回退: $e', error: e, source: 'SvgToImageService');
      return _legacySimplifiedRender(
        svgContent,
        targetWidth,
        targetHeight,
        format,
        backgroundColor,
      );
    }
  }

  /// 旧的简化渲染逻辑作为回退保留
  static Future<Uint8List> _legacySimplifiedRender(
    String svgContent,
    int width,
    int height,
    ui.ImageByteFormat format,
    Color backgroundColor,
  ) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final backgroundPaint = Paint()..color = backgroundColor;
    canvas.drawRect(Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
        backgroundPaint);
    await _drawSvgContent(canvas, svgContent, width, height);
    final picture = recorder.endRecording();
    final image = await picture.toImage(width, height);
    final byteData = await image.toByteData(format: format);
    picture.dispose();
    return byteData!.buffer.asUint8List();
  }

  /// 绘制SVG内容（基础解析）
  static Future<void> _drawSvgContent(
      Canvas canvas, String svgContent, int width, int height) async {
    // 简化的SVG解析和绘制
    // 这里实现基本的SVG元素绘制

    // 绘制背景渐变（如果存在）
    _drawGradientBackground(canvas, svgContent, width, height);

    // 绘制基本形状
    _drawBasicShapes(canvas, svgContent, width, height);

    // 绘制文本内容
    _drawTextContent(canvas, svgContent, width, height);
  }

  /// 渲染回退图片
  static Future<Uint8List> _renderFallbackImage(
    String svgContent,
    int width,
    int height,
    ui.ImageByteFormat format,
    Color backgroundColor,
  ) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);

    // 设置背景色
    final backgroundPaint = Paint()..color = backgroundColor;
    canvas.drawRect(Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
        backgroundPaint);

    // 绘制简化内容
    _drawPlaceholderContent(canvas, width, height, svgContent);

    // 转换为图片
    final picture = recorder.endRecording();
    final image = await picture.toImage(width, height);
    final byteData = await image.toByteData(format: format);

    picture.dispose();
    return byteData!.buffer.asUint8List();
  }

  /// 绘制渐变背景
  static void _drawGradientBackground(
      Canvas canvas, String svgContent, int width, int height) {
    // 检查是否包含linearGradient
    if (svgContent.contains('linearGradient')) {
      // 解析linearGradient定义
      final gradientColors = _parseLinearGradient(svgContent);

      final gradientPaint = Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: gradientColors.isNotEmpty
              ? gradientColors
              : [
                  const Color(0xFF4F46E5),
                  const Color(0xFF7C3AED),
                  const Color(0xFFDB2777)
                ],
        ).createShader(
            Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()));

      canvas.drawRect(Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
          gradientPaint);
    }
  }

  /// 解析SVG中的linearGradient定义
  static List<Color> _parseLinearGradient(String svgContent) {
    final colors = <Color>[];

    try {
      // 匹配linearGradient标签内容
      final gradientRegex =
          RegExp(r'<linearGradient[^>]*>(.*?)</linearGradient>', dotAll: true);
      final gradientMatch = gradientRegex.firstMatch(svgContent);

      if (gradientMatch != null) {
        final gradientContent = gradientMatch.group(1) ?? '';

        // 匹配stop元素
        final stopRegex = RegExp(
            r'<stop[^>]*stop-color="([^"]*)"[^>]*(?:stop-opacity="([^"]*)")?');
        final stopMatches = stopRegex.allMatches(gradientContent);

        for (final stopMatch in stopMatches) {
          final stopColor = _parseColor(stopMatch.group(1) ?? '#000000');
          final stopOpacity =
              double.tryParse(stopMatch.group(2) ?? '1.0') ?? 1.0;
          colors.add(stopColor.withValues(alpha: stopOpacity));
        }
      }
    } catch (e) {
      logError('解析linearGradient失败: $e', error: e, source: 'SvgToImageService');
    }

    return colors;
  }

  /// 绘制基本形状
  static void _drawBasicShapes(
      Canvas canvas, String svgContent, int width, int height) {
    // 解析并绘制圆形
    final circleRegex = RegExp(
        r'<circle[^>]*cx="([^"]*)"[^>]*cy="([^"]*)"[^>]*r="([^"]*)"[^>]*fill="([^"]*)"(?:[^>]*fill-opacity="([^"]*)")?');
    final circleMatches = circleRegex.allMatches(svgContent);

    for (final match in circleMatches) {
      try {
        final cx = double.parse(match.group(1) ?? '0');
        final cy = double.parse(match.group(2) ?? '0');
        final r = double.parse(match.group(3) ?? '0');
        final fillColor = _parseColor(match.group(4) ?? '#000000');
        final fillOpacity = double.tryParse(match.group(5) ?? '1.0') ?? 1.0;

        final paint = Paint()..color = fillColor.withValues(alpha: fillOpacity);
        canvas.drawCircle(Offset(cx, cy), r, paint);
      } catch (e) {
        logError('解析圆形元素失败: $e', error: e, source: 'SvgToImageService');
      }
    }

    // 解析并绘制矩形
    final rectRegex = RegExp(
        r'<rect[^>]*x="([^"]*)"[^>]*y="([^"]*)"[^>]*width="([^"]*)"[^>]*height="([^"]*)"[^>]*fill="([^"]*)"(?:[^>]*fill-opacity="([^"]*)")?(?:[^>]*rx="([^"]*)")?(?:[^>]*ry="([^"]*)")?');
    final rectMatches = rectRegex.allMatches(svgContent);

    for (final match in rectMatches) {
      try {
        final x = double.parse(match.group(1) ?? '0');
        final y = double.parse(match.group(2) ?? '0');
        final w = double.parse(match.group(3) ?? '0');
        final h = double.parse(match.group(4) ?? '0');
        final fillColor = _parseColor(match.group(5) ?? '#000000');
        final fillOpacity = double.tryParse(match.group(6) ?? '1.0') ?? 1.0;
        final rx = double.tryParse(match.group(7) ?? '0') ?? 0;
        final ry = double.tryParse(match.group(8) ?? '0') ?? 0;

        final paint = Paint()..color = fillColor.withValues(alpha: fillOpacity);

        if (rx > 0 || ry > 0) {
          // 绘制圆角矩形，正确处理不同的rx和ry值
          final rect = Rect.fromLTWH(x, y, w, h);
          final radiusX = rx > 0 ? rx : 0.0;
          final radiusY = ry > 0 ? ry : 0.0;

          if (radiusX == radiusY) {
            // 统一圆角
            final rrect =
                RRect.fromRectAndRadius(rect, Radius.circular(radiusX));
            canvas.drawRRect(rrect, paint);
          } else {
            // 不同的rx和ry值，使用椭圆圆角
            final rrect = RRect.fromRectAndCorners(
              rect,
              topLeft: Radius.elliptical(radiusX, radiusY),
              topRight: Radius.elliptical(radiusX, radiusY),
              bottomLeft: Radius.elliptical(radiusX, radiusY),
              bottomRight: Radius.elliptical(radiusX, radiusY),
            );
            canvas.drawRRect(rrect, paint);
          }
        } else {
          // 绘制普通矩形
          canvas.drawRect(Rect.fromLTWH(x, y, w, h), paint);
        }
      } catch (e) {
        logError('解析矩形元素失败: $e', error: e, source: 'SvgToImageService');
      }
    }
  }

  /// 绘制文本内容
  static void _drawTextContent(
      Canvas canvas, String svgContent, int width, int height) {
    // 使用更强大的文本元素解析，支持嵌套标签
    final textElements = _extractTextElements(svgContent);

    for (final textElement in textElements) {
      try {
        final fullTextElement = textElement['element'] as String;
        final textContent = textElement['content'] as String;

        if (textContent.trim().isEmpty) continue;

        // 解析文本属性
        final attributes = _parseTextAttributes(fullTextElement);

        final textStyle = TextStyle(
          color: attributes['fill'] != null
              ? _parseColor(attributes['fill']!)
              : Colors.black,
          fontSize: attributes['font-size'] != null
              ? _parseFontSize(attributes['font-size']!)
              : 14.0,
          fontWeight: attributes['font-weight'] != null
              ? _parseFontWeight(attributes['font-weight']!)
              : FontWeight.normal,
          fontStyle: attributes['font-style'] == 'italic'
              ? FontStyle.italic
              : FontStyle.normal,
        );

        final textPainter = TextPainter(
          text: TextSpan(
            text: textContent.trim(),
            style: textStyle,
          ),
          textDirection: ui.TextDirection.ltr,
          textAlign: attributes['text-anchor'] == 'middle'
              ? TextAlign.center
              : attributes['text-anchor'] == 'end'
                  ? TextAlign.right
                  : TextAlign.left,
        );

        textPainter.layout();

        // 计算绘制位置
        double x = attributes['x'] != null
            ? double.tryParse(attributes['x']!) ?? 0
            : 0;
        double y = attributes['y'] != null
            ? double.tryParse(attributes['y']!) ?? 0
            : 0;

        // 处理text-anchor对齐
        if (attributes['text-anchor'] == 'middle') {
          x -= textPainter.width / 2;
        } else if (attributes['text-anchor'] == 'end') {
          x -= textPainter.width;
        }

        // SVG的y坐标是基线位置，需要调整到顶部
        y -= textPainter.height * 0.8; // 近似基线调整

        textPainter.paint(canvas, Offset(x, y));
      } catch (e) {
        if (kDebugMode) {
          print('解析文本元素失败: $e');
        }
      }
    }
  }

  /// 提取文本元素，支持嵌套标签如<tspan>
  static List<Map<String, String>> _extractTextElements(String svgContent) {
    final textElements = <Map<String, String>>[];

    // 使用更强大的正则表达式来匹配text元素，包括嵌套内容
    final textRegex =
        RegExp(r'<text[^>]*>(.*?)</text>', multiLine: true, dotAll: true);
    final textMatches = textRegex.allMatches(svgContent);

    for (final match in textMatches) {
      final fullElement = match.group(0) ?? '';
      final innerContent = match.group(1) ?? '';

      // 提取所有文本内容，包括嵌套的tspan等标签
      final textContent = _extractAllTextContent(innerContent);

      if (textContent.trim().isNotEmpty) {
        textElements.add({
          'element': fullElement,
          'content': textContent,
        });
      }
    }

    return textElements;
  }

  /// 提取所有文本内容，包括嵌套标签内的文本
  static String _extractAllTextContent(String content) {
    // 移除所有HTML/XML标签，保留文本内容
    String textContent = content;

    // 处理常见的XML实体
    final entities = {
      '&lt;': '<',
      '&gt;': '>',
      '&amp;': '&',
      '&quot;': '"',
      '&apos;': "'",
      '&#39;': "'",
    };

    for (final entry in entities.entries) {
      textContent = textContent.replaceAll(entry.key, entry.value);
    }

    // 移除所有标签，保留文本内容
    textContent = textContent.replaceAll(RegExp(r'<[^>]*>'), '');

    // 清理多余的空白字符
    textContent = textContent.replaceAll(RegExp(r'\s+'), ' ').trim();

    return textContent;
  }

  /// 解析文本属性
  static Map<String, String> _parseTextAttributes(String textElement) {
    final attributes = <String, String>{};

    // 解析各种属性
    final attributePatterns = {
      'x': RegExp(r'x="([^"]*)"'),
      'y': RegExp(r'y="([^"]*)"'),
      'fill': RegExp(r'fill="([^"]*)"'),
      'font-size': RegExp(r'font-size="([^"]*)"'),
      'font-weight': RegExp(r'font-weight="([^"]*)"'),
      'font-style': RegExp(r'font-style="([^"]*)"'),
      'text-anchor': RegExp(r'text-anchor="([^"]*)"'),
      'font-family': RegExp(r'font-family="([^"]*)"'),
    };

    for (final entry in attributePatterns.entries) {
      final match = entry.value.firstMatch(textElement);
      if (match != null) {
        attributes[entry.key] = match.group(1) ?? '';
      }
    }

    return attributes;
  }

  /// 解析字体大小，支持不同单位
  static double _parseFontSize(String fontSizeStr) {
    try {
      final trimmed = fontSizeStr.trim().toLowerCase();

      // 处理纯数字（默认为px）
      final numericMatch = RegExp(r'^(\d+(?:\.\d+)?)$').firstMatch(trimmed);
      if (numericMatch != null) {
        return double.tryParse(numericMatch.group(1)!) ?? 14.0;
      }

      // 处理带单位的值
      final unitMatch =
          RegExp(r'^(\d+(?:\.\d+)?)(px|pt|em|rem|%)?$').firstMatch(trimmed);
      if (unitMatch != null) {
        final value = double.tryParse(unitMatch.group(1)!) ?? 14.0;
        final unit = unitMatch.group(2) ?? 'px';

        switch (unit) {
          case 'px':
            return value;
          case 'pt':
            // 1pt = 1.333px (approximately)
            return value * 1.333;
          case 'em':
            // 1em = 16px (default browser font size)
            return value * 16.0;
          case 'rem':
            // 1rem = 16px (root em, same as em for our purposes)
            return value * 16.0;
          case '%':
            // 100% = 16px (default), so 1% = 0.16px
            return value * 0.16;
          default:
            return value;
        }
      }

      // 如果无法解析，返回默认值
      return 14.0;
    } catch (e) {
      return 14.0;
    }
  }

  /// 解析字体粗细
  static FontWeight _parseFontWeight(String fontWeightStr) {
    switch (fontWeightStr.toLowerCase()) {
      case 'bold':
      case '700':
      case '800':
      case '900':
        return FontWeight.bold;
      case '500':
      case '600':
        return FontWeight.w600;
      case 'normal':
      case '400':
      default:
        return FontWeight.normal;
    }
  }

  /// 解析颜色
  static Color _parseColor(String colorString) {
    try {
      if (colorString.startsWith('#')) {
        final hex = colorString.substring(1);
        if (hex.length == 6) {
          return Color(int.parse('FF$hex', radix: 16));
        } else if (hex.length == 8) {
          return Color(int.parse(hex, radix: 16));
        }
      }
      // 简单的颜色名称映射
      switch (colorString.toLowerCase()) {
        case 'white':
          return Colors.white;
        case 'black':
          return Colors.black;
        case 'red':
          return Colors.red;
        case 'blue':
          return Colors.blue;
        case 'green':
          return Colors.green;
        default:
          return Colors.black;
      }
    } catch (e) {
      return Colors.black;
    }
  }

  /// 绘制占位符内容
  static void _drawPlaceholderContent(
      Canvas canvas, int width, int height, String svgContent) {
    // 绘制边框
    final borderPaint = Paint()
      ..color = Colors.grey[300]!
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawRect(
      Rect.fromLTWH(10, 10, width - 20.0, height - 20.0),
      borderPaint,
    );

    // 绘制SVG图标
    final iconPaint = Paint()..color = Colors.grey[600]!;
    final center = Offset(width / 2, height / 3);
    canvas.drawCircle(center, 40, iconPaint);

    // 绘制文本
    final textPainter = TextPainter(
      text: const TextSpan(
        text: 'SVG卡片\n(基础渲染)',
        style: TextStyle(
          color: Colors.black87,
          fontSize: 16,
          fontWeight: FontWeight.w500,
        ),
      ),
      textDirection: ui.TextDirection.ltr,
      textAlign: TextAlign.center,
    );

    textPainter.layout(maxWidth: width - 40.0);
    textPainter.paint(
      canvas,
      Offset((width - textPainter.width) / 2, height * 0.6),
    );
  }

  /// 生成错误提示图片
  static Future<Uint8List> _generateErrorImage(
    int width,
    int height,
    ui.ImageByteFormat format,
    String errorMessage,
  ) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);

    // 绘制红色背景
    final backgroundPaint = Paint()..color = const Color(0xFFFFEBEE);
    canvas.drawRect(Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
        backgroundPaint);

    // 绘制边框
    final borderPaint = Paint()
      ..color = const Color(0xFFE57373)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawRect(
      Rect.fromLTWH(10, 10, width - 20.0, height - 20.0),
      borderPaint,
    );

    // 绘制错误图标
    final iconPaint = Paint()..color = const Color(0xFFD32F2F);
    canvas.drawCircle(Offset(width / 2, height / 3), 30, iconPaint);

    // 绘制X符号
    final xPaint = Paint()
      ..color = Colors.white
      ..strokeWidth = 4
      ..style = PaintingStyle.stroke;
    final center = Offset(width / 2, height / 3);
    canvas.drawLine(
        center + const Offset(-15, -15), center + const Offset(15, 15), xPaint);
    canvas.drawLine(
        center + const Offset(15, -15), center + const Offset(-15, 15), xPaint);

    // 绘制错误文本
    final textPainter = TextPainter(
      text: TextSpan(
        children: [
          const TextSpan(
            text: '图片生成失败\n\n',
            style: TextStyle(
              color: Color(0xFFD32F2F),
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          TextSpan(
            text: errorMessage.length > 100
                ? '${errorMessage.substring(0, 100)}...'
                : errorMessage,
            style: const TextStyle(
              color: Color(0xFF666666),
              fontSize: 12,
            ),
          ),
        ],
      ),
      textDirection: ui.TextDirection.ltr,
      textAlign: TextAlign.center,
    );

    textPainter.layout(maxWidth: width - 40.0);
    textPainter.paint(
      canvas,
      Offset((width - textPainter.width) / 2, height / 2),
    );

    // 转换为图片
    final picture = recorder.endRecording();
    final image = await picture.toImage(width, height);
    final byteData = await image.toByteData(format: format);

    picture.dispose();

    return byteData!.buffer.asUint8List();
  }
}
