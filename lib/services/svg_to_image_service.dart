import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'image_cache_service.dart';

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
  }) async {
    try {
      // 生成缓存键
      final cacheKey = useCache
          ? ImageCacheService.generateCacheKey(
              svgContent, width, height, format)
          : null;

      // 尝试从缓存获取
      if (useCache && cacheKey != null) {
        final cachedImage = _cacheService.getCachedImage(cacheKey);
        if (cachedImage != null) {
          if (kDebugMode) {
            print('使用缓存图片: $cacheKey');
          }
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
      );

      // 缓存结果
      if (useCache && cacheKey != null) {
        _cacheService.cacheImage(cacheKey, imageBytes);
      }

      return imageBytes;
    } catch (e) {
      if (kDebugMode) {
        print('SVG转换失败: $e');
      }
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
  ) async {
    try {
      // 直接使用Canvas渲染SVG
      return await _renderSvgWithCanvas(
        svgContent,
        width,
        height,
        format,
        backgroundColor,
      );
    } catch (e) {
      if (kDebugMode) {
        print('SVG渲染失败，使用回退方案: $e');
      }
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
    int width,
    int height,
    ui.ImageByteFormat format,
    Color backgroundColor,
  ) async {
    // 创建画布
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);

    // 设置背景色
    final backgroundPaint = Paint()..color = backgroundColor;
    canvas.drawRect(Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()), backgroundPaint);

    // 尝试解析和绘制SVG内容
    await _drawSvgContent(canvas, svgContent, width, height);

    // 转换为图片
    final picture = recorder.endRecording();
    final image = await picture.toImage(width, height);
    final byteData = await image.toByteData(format: format);

    // 清理资源
    picture.dispose();

    return byteData!.buffer.asUint8List();
  }

  /// 绘制SVG内容（基础解析）
  static Future<void> _drawSvgContent(Canvas canvas, String svgContent, int width, int height) async {
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
    canvas.drawRect(Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()), backgroundPaint);

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
  static void _drawGradientBackground(Canvas canvas, String svgContent, int width, int height) {
    // 检查是否包含linearGradient
    if (svgContent.contains('linearGradient')) {
      // 简化的渐变解析
      final gradientPaint = Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF4F46E5), Color(0xFF7C3AED), Color(0xFFDB2777)],
        ).createShader(Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()));

      canvas.drawRect(Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()), gradientPaint);
    }
  }

  /// 绘制基本形状
  static void _drawBasicShapes(Canvas canvas, String svgContent, int width, int height) {
    // 解析并绘制圆形
    final circleRegex = RegExp(r'<circle[^>]*cx="([^"]*)"[^>]*cy="([^"]*)"[^>]*r="([^"]*)"[^>]*fill="([^"]*)"');
    final circleMatches = circleRegex.allMatches(svgContent);

    for (final match in circleMatches) {
      try {
        final cx = double.parse(match.group(1) ?? '0');
        final cy = double.parse(match.group(2) ?? '0');
        final r = double.parse(match.group(3) ?? '0');
        final fillColor = _parseColor(match.group(4) ?? '#000000');

        final paint = Paint()..color = fillColor;
        canvas.drawCircle(Offset(cx, cy), r, paint);
      } catch (e) {
        // 忽略解析错误
      }
    }

    // 解析并绘制矩形
    final rectRegex = RegExp(r'<rect[^>]*x="([^"]*)"[^>]*y="([^"]*)"[^>]*width="([^"]*)"[^>]*height="([^"]*)"[^>]*fill="([^"]*)"');
    final rectMatches = rectRegex.allMatches(svgContent);

    for (final match in rectMatches) {
      try {
        final x = double.parse(match.group(1) ?? '0');
        final y = double.parse(match.group(2) ?? '0');
        final w = double.parse(match.group(3) ?? '0');
        final h = double.parse(match.group(4) ?? '0');
        final fillColor = _parseColor(match.group(5) ?? '#000000');

        final paint = Paint()..color = fillColor;
        canvas.drawRect(Rect.fromLTWH(x, y, w, h), paint);
      } catch (e) {
        // 忽略解析错误
      }
    }
  }

  /// 绘制文本内容
  static void _drawTextContent(Canvas canvas, String svgContent, int width, int height) {
    // 解析并绘制文本
    final textRegex = RegExp(r'<text[^>]*x="([^"]*)"[^>]*y="([^"]*)"[^>]*[^>]*>([^<]*)</text>');
    final textMatches = textRegex.allMatches(svgContent);

    for (final match in textMatches) {
      try {
        final x = double.parse(match.group(1) ?? '0');
        final y = double.parse(match.group(2) ?? '0');
        final text = match.group(3) ?? '';

        final textPainter = TextPainter(
          text: TextSpan(
            text: text,
            style: const TextStyle(
              color: Colors.black,
              fontSize: 14,
            ),
          ),
          textDirection: ui.TextDirection.ltr,
        );

        textPainter.layout();
        textPainter.paint(canvas, Offset(x, y - textPainter.height));
      } catch (e) {
        // 忽略解析错误
      }
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
        case 'white': return Colors.white;
        case 'black': return Colors.black;
        case 'red': return Colors.red;
        case 'blue': return Colors.blue;
        case 'green': return Colors.green;
        default: return Colors.black;
      }
    } catch (e) {
      return Colors.black;
    }
  }

  /// 绘制占位符内容
  static void _drawPlaceholderContent(Canvas canvas, int width, int height, String svgContent) {
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
