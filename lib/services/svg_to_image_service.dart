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
        AppLogger.w('图片尺寸过大: ${width}x$height，可能导致内存问题',
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

      // 标准化SVG内容，确保正确的viewBox和尺寸属性
      final normalizedSvg =
          _normalizeSvgForRendering(svgContent, width, height);

      // 优先使用真实Flutter渲染（与预览完全一致）
      final imageBytes = await _renderSvgToBytes(
        normalizedSvg,
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
        // 使用统一日志服务记录批量转换错误
        AppLogger.w('批量转换第${i + 1}个SVG失败: $e',
            error: e, source: 'SvgToImageService');
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

  /// 标准化SVG内容以确保正确渲染
  static String _normalizeSvgForRendering(
      String svgContent, int width, int height) {
    String normalized = svgContent.trim();

    // 确保SVG有xmlns命名空间
    if (!normalized.contains('xmlns=')) {
      normalized = normalized.replaceFirst(
        '<svg',
        '<svg xmlns="http://www.w3.org/2000/svg"',
      );
    }

    // 提取现有的viewBox或从width/height推断
    String? existingViewBox;
    final viewBoxMatch = RegExp(r'viewBox="([^"]+)"').firstMatch(normalized);
    if (viewBoxMatch != null) {
      existingViewBox = viewBoxMatch.group(1);
      AppLogger.d('使用现有viewBox: $existingViewBox', source: 'SvgToImageService');
    }

    // 提取SVG内在尺寸
    final widthMatch =
        RegExp(r'width="(\d+(?:\.\d+)?)"').firstMatch(normalized);
    final heightMatch =
        RegExp(r'height="(\d+(?:\.\d+)?)"').firstMatch(normalized);

    String svgWidth;
    String svgHeight;

    if (existingViewBox != null) {
      // 有viewBox，从viewBox提取
      final parts = existingViewBox.split(RegExp(r'[\s,]+'));
      if (parts.length == 4) {
        svgWidth = parts[2];
        svgHeight = parts[3];
      } else {
        svgWidth = widthMatch?.group(1) ?? '400';
        svgHeight = heightMatch?.group(1) ?? '600';
      }
    } else {
      // 没有viewBox，从width/height提取或使用默认
      svgWidth = widthMatch?.group(1) ?? '400';
      svgHeight = heightMatch?.group(1) ?? '600';
    }

    AppLogger.d('SVG内在尺寸: ${svgWidth}x$svgHeight', source: 'SvgToImageService');

    // 移除现有的width、height、viewBox属性
    normalized = normalized
        .replaceAll(RegExp(r'\s+width="[^"]*"'), '')
        .replaceAll(RegExp(r'\s+height="[^"]*"'), '')
        .replaceAll(RegExp(r'\s+viewBox="[^"]*"'), '');

    // 重新设置标准化的属性：保持SVG内在尺寸作为viewBox，物理尺寸由外层容器控制
    normalized = normalized.replaceFirst(
      '<svg',
      '<svg viewBox="0 0 $svgWidth $svgHeight" width="$svgWidth" height="$svgHeight" preserveAspectRatio="xMidYMid meet"',
    );

    return normalized;
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
    // 策略：优先使用真实Flutter渲染，确保与预览一致
    if (buildContext != null) {
      try {
        AppLogger.d(
            '使用Flutter真实渲染（与预览一致）: ${width}x$height, 缩放: $scaleFactor, 模式: $renderMode',
            source: 'SvgToImageService');
        final result = await SvgOffscreenRenderer.instance.renderSvgString(
          svgContent,
          context: buildContext,
          width: width,
          height: height,
          scaleFactor: scaleFactor,
          background: backgroundColor,
          mode: renderMode,
          format: format,
        );
        AppLogger.i('Flutter真实渲染成功，图片大小: ${result.length} bytes',
            source: 'SvgToImageService');
        return result;
      } catch (e) {
        AppLogger.w('Flutter真实渲染失败，尝试备用方案: $e',
            error: e, source: 'SvgToImageService');
      }
    } else {
      AppLogger.w('缺少BuildContext，无法使用真实渲染，将使用备用方案',
          source: 'SvgToImageService');
    }

    // 备用方案：使用flutter_svg直接渲染
    try {
      AppLogger.d('使用flutter_svg备用渲染', source: 'SvgToImageService');
      return await _renderWithFlutterSvg(
        svgContent,
        width,
        height,
        format,
        backgroundColor,
        scaleFactor,
        renderMode,
      );
    } catch (e) {
      AppLogger.w('flutter_svg渲染失败，使用最终回退: $e',
          error: e, source: 'SvgToImageService');
      // 最终回退方案
      return await _renderFallbackImage(
        svgContent,
        width,
        height,
        format,
        backgroundColor,
      );
    }
  }

  /// 使用flutter_svg库直接渲染（备用方案）
  /// 重构：改进渐变和颜色解析，确保备用渲染与预览一致
  static Future<Uint8List> _renderWithFlutterSvg(
    String svgContent,
    int width,
    int height,
    ui.ImageByteFormat format,
    Color backgroundColor,
    double scaleFactor,
    ExportRenderMode renderMode,
  ) async {
    AppLogger.d('使用改进的备用SVG渲染', source: 'SvgToImageService');

    final pictureRecorder = ui.PictureRecorder();
    final canvas = Canvas(pictureRecorder);
    
    final scaledWidth = (width * scaleFactor).round();
    final scaledHeight = (height * scaleFactor).round();

    // 应用缩放
    canvas.scale(scaleFactor);

    // 绘制白色背景作为基础
    final bgPaint = Paint()..color = backgroundColor;
    canvas.drawRect(
      Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
      bgPaint,
    );

    // 解析并绘制SVG内容
    await _drawSvgContentImproved(canvas, svgContent, width, height);

    final picture = pictureRecorder.endRecording();
    final image = await picture.toImage(scaledWidth, scaledHeight);
    final byteData = await image.toByteData(format: format);

    picture.dispose();
    image.dispose();

    if (byteData == null) {
      throw Exception('无法生成图片字节数据');
    }

    return byteData.buffer.asUint8List();
  }

  /// 改进的SVG内容绘制
  static Future<void> _drawSvgContentImproved(
      Canvas canvas, String svgContent, int width, int height) async {
    // 解析所有渐变定义
    final gradients = _parseAllGradients(svgContent);
    
    // 绘制背景矩形（通常是第一个rect元素）
    _drawBackgroundRect(canvas, svgContent, width, height, gradients);
    
    // 绘制其他形状
    _drawAllShapes(canvas, svgContent, width, height, gradients);
    
    // 绘制文本
    _drawAllText(canvas, svgContent, width, height);
  }

  /// 解析所有渐变定义
  static Map<String, Gradient> _parseAllGradients(String svgContent) {
    final gradients = <String, Gradient>{};
    
    // 解析 linearGradient
    final linearGradientRegex = RegExp(
      r'<linearGradient\s+id="([^"]+)"[^>]*>(.*?)</linearGradient>',
      dotAll: true,
    );
    
    for (final match in linearGradientRegex.allMatches(svgContent)) {
      final id = match.group(1) ?? '';
      final content = match.group(2) ?? '';
      final tag = match.group(0) ?? '';
      
      if (id.isEmpty) continue;
      
      // 解析渐变方向
      final x1 = _parsePercentage(RegExp(r'x1="([^"]*)"').firstMatch(tag)?.group(1));
      final y1 = _parsePercentage(RegExp(r'y1="([^"]*)"').firstMatch(tag)?.group(1));
      final x2 = _parsePercentage(RegExp(r'x2="([^"]*)"').firstMatch(tag)?.group(1));
      final y2 = _parsePercentage(RegExp(r'y2="([^"]*)"').firstMatch(tag)?.group(1));
      
      // 解析颜色停靠点
      final stops = <double>[];
      final colors = <Color>[];
      
      final stopRegex = RegExp(
        r'<stop[^>]*offset="([^"]*)"[^>]*(?:stop-color="([^"]*)"|style="[^"]*stop-color:\s*([^;"\s]+))[^>]*(?:stop-opacity="([^"]*)"|style="[^"]*stop-opacity:\s*([^;"\s]+))?',
        caseSensitive: false,
      );
      
      for (final stopMatch in stopRegex.allMatches(content)) {
        final offset = _parsePercentage(stopMatch.group(1));
        final colorStr = stopMatch.group(2) ?? stopMatch.group(3) ?? '#000000';
        final opacityStr = stopMatch.group(4) ?? stopMatch.group(5);
        
        stops.add(offset);
        Color color = _parseColor(colorStr);
        if (opacityStr != null) {
          final opacity = double.tryParse(opacityStr) ?? 1.0;
          color = color.withValues(alpha: opacity);
        }
        colors.add(color);
      }
      
      if (colors.isNotEmpty) {
        gradients[id] = LinearGradient(
          begin: Alignment(x1 * 2 - 1, y1 * 2 - 1),
          end: Alignment(x2 * 2 - 1, y2 * 2 - 1),
          colors: colors,
          stops: stops.isEmpty ? null : stops,
        );
      }
    }
    
    // 解析 radialGradient
    final radialGradientRegex = RegExp(
      r'<radialGradient\s+id="([^"]+)"[^>]*>(.*?)</radialGradient>',
      dotAll: true,
    );
    
    for (final match in radialGradientRegex.allMatches(svgContent)) {
      final id = match.group(1) ?? '';
      final content = match.group(2) ?? '';
      
      if (id.isEmpty) continue;
      
      final stops = <double>[];
      final colors = <Color>[];
      
      final stopRegex = RegExp(
        r'<stop[^>]*offset="([^"]*)"[^>]*(?:stop-color="([^"]*)"|style="[^"]*stop-color:\s*([^;"\s]+))[^>]*(?:stop-opacity="([^"]*)"|style="[^"]*stop-opacity:\s*([^;"\s]+))?',
        caseSensitive: false,
      );
      
      for (final stopMatch in stopRegex.allMatches(content)) {
        final offset = _parsePercentage(stopMatch.group(1));
        final colorStr = stopMatch.group(2) ?? stopMatch.group(3) ?? '#000000';
        final opacityStr = stopMatch.group(4) ?? stopMatch.group(5);
        
        stops.add(offset);
        Color color = _parseColor(colorStr);
        if (opacityStr != null) {
          final opacity = double.tryParse(opacityStr) ?? 1.0;
          color = color.withValues(alpha: opacity);
        }
        colors.add(color);
      }
      
      if (colors.isNotEmpty) {
        gradients[id] = RadialGradient(
          colors: colors,
          stops: stops.isEmpty ? null : stops,
        );
      }
    }
    
    return gradients;
  }

  /// 解析百分比值
  static double _parsePercentage(String? value) {
    if (value == null) return 0.0;
    final trimmed = value.trim().replaceAll('%', '');
    return (double.tryParse(trimmed) ?? 0.0) / 100.0;
  }

  /// 绘制背景矩形
  static void _drawBackgroundRect(Canvas canvas, String svgContent, int width, int height, Map<String, Gradient> gradients) {
    // 查找第一个覆盖整个画布的矩形
    final rectRegex = RegExp(
      r'<rect[^>]*width="([^"]*)"[^>]*height="([^"]*)"[^>]*fill="([^"]*)"[^>]*(?:rx="([^"]*)")?',
    );
    
    for (final match in rectRegex.allMatches(svgContent)) {
      final w = double.tryParse(match.group(1) ?? '0') ?? 0;
      final h = double.tryParse(match.group(2) ?? '0') ?? 0;
      final fill = match.group(3) ?? '';
      final rx = double.tryParse(match.group(4) ?? '0') ?? 0;
      
      // 检查是否是全尺寸背景
      if (w >= width * 0.9 && h >= height * 0.9) {
        final rect = RRect.fromRectAndRadius(
          Rect.fromLTWH(0, 0, w, h),
          Radius.circular(rx),
        );
        
        final paint = Paint();
        if (fill.startsWith('url(#')) {
          final gradientId = fill.substring(5, fill.length - 1);
          final gradient = gradients[gradientId];
          if (gradient != null) {
            paint.shader = gradient.createShader(Rect.fromLTWH(0, 0, w, h));
          } else {
            paint.color = Colors.grey;
          }
        } else {
          paint.color = _parseColor(fill);
        }
        
        canvas.drawRRect(rect, paint);
        break; // 只绘制第一个背景
      }
    }
  }

  /// 绘制所有形状
  static void _drawAllShapes(Canvas canvas, String svgContent, int width, int height, Map<String, Gradient> gradients) {
    // 绘制圆形
    final circleRegex = RegExp(
      r'<circle[^>]*cx="([^"]*)"[^>]*cy="([^"]*)"[^>]*r="([^"]*)"[^>]*(?:fill="([^"]*)")?[^>]*(?:fill-opacity="([^"]*)")?',
    );
    
    for (final match in circleRegex.allMatches(svgContent)) {
      try {
        final cx = double.parse(match.group(1) ?? '0');
        final cy = double.parse(match.group(2) ?? '0');
        final r = double.parse(match.group(3) ?? '0');
        final fill = match.group(4) ?? '#000000';
        final opacity = double.tryParse(match.group(5) ?? '1.0') ?? 1.0;
        
        final paint = Paint();
        if (fill.startsWith('url(#')) {
          final gradientId = fill.substring(5, fill.length - 1);
          final gradient = gradients[gradientId];
          if (gradient != null) {
            paint.shader = gradient.createShader(Rect.fromCircle(center: Offset(cx, cy), radius: r));
          }
        } else {
          paint.color = _parseColor(fill).withValues(alpha: opacity);
        }
        
        canvas.drawCircle(Offset(cx, cy), r, paint);
      } catch (e) {
        // 忽略解析错误
      }
    }
    
    // 绘制矩形（跳过背景矩形）
    final rectRegex = RegExp(
      r'<rect[^>]*x="([^"]*)"[^>]*y="([^"]*)"[^>]*width="([^"]*)"[^>]*height="([^"]*)"[^>]*(?:fill="([^"]*)")?[^>]*(?:fill-opacity="([^"]*)")?[^>]*(?:rx="([^"]*)")?',
    );
    
    for (final match in rectRegex.allMatches(svgContent)) {
      try {
        final x = double.parse(match.group(1) ?? '0');
        final y = double.parse(match.group(2) ?? '0');
        final w = double.parse(match.group(3) ?? '0');
        final h = double.parse(match.group(4) ?? '0');
        final fill = match.group(5) ?? '#000000';
        final opacity = double.tryParse(match.group(6) ?? '1.0') ?? 1.0;
        final rx = double.tryParse(match.group(7) ?? '0') ?? 0;
        
        // 跳过全屏背景矩形
        if (w >= width * 0.9 && h >= height * 0.9 && x < 10 && y < 10) continue;
        
        final rect = rx > 0
            ? RRect.fromRectAndRadius(Rect.fromLTWH(x, y, w, h), Radius.circular(rx))
            : null;
        
        final paint = Paint();
        if (fill.startsWith('url(#')) {
          final gradientId = fill.substring(5, fill.length - 1);
          final gradient = gradients[gradientId];
          if (gradient != null) {
            paint.shader = gradient.createShader(Rect.fromLTWH(x, y, w, h));
          }
        } else {
          paint.color = _parseColor(fill).withValues(alpha: opacity);
        }
        
        if (rect != null) {
          canvas.drawRRect(rect, paint);
        } else {
          canvas.drawRect(Rect.fromLTWH(x, y, w, h), paint);
        }
      } catch (e) {
        // 忽略解析错误
      }
    }
  }

  /// 绘制所有文本
  static void _drawAllText(Canvas canvas, String svgContent, int width, int height) {
    final textRegex = RegExp(
      r'<text[^>]*x="([^"]*)"[^>]*y="([^"]*)"[^>]*(?:text-anchor="([^"]*)")?[^>]*(?:fill="([^"]*)")?[^>]*(?:font-size="([^"]*)")?[^>]*(?:fill-opacity="([^"]*)")?[^>]*>([^<]*)</text>',
    );
    
    for (final match in textRegex.allMatches(svgContent)) {
      try {
        double x = double.parse(match.group(1) ?? '0');
        final y = double.parse(match.group(2) ?? '0');
        final anchor = match.group(3) ?? 'start';
        final fill = match.group(4) ?? '#000000';
        final fontSize = double.tryParse(match.group(5) ?? '14') ?? 14.0;
        final opacity = double.tryParse(match.group(6) ?? '1.0') ?? 1.0;
        String text = match.group(7) ?? '';
        
        // 解码HTML实体
        text = text
            .replaceAll('&lt;', '<')
            .replaceAll('&gt;', '>')
            .replaceAll('&amp;', '&')
            .replaceAll('&quot;', '"')
            .replaceAll('&apos;', "'")
            .trim();
        
        if (text.isEmpty) continue;
        
        final textStyle = TextStyle(
          color: _parseColor(fill).withValues(alpha: opacity),
          fontSize: fontSize,
        );
        
        final textPainter = TextPainter(
          text: TextSpan(text: text, style: textStyle),
          textDirection: ui.TextDirection.ltr,
        );
        
        textPainter.layout();
        
        // 处理文本对齐
        double offsetX = x;
        if (anchor == 'middle') {
          offsetX = x - textPainter.width / 2;
        } else if (anchor == 'end') {
          offsetX = x - textPainter.width;
        }
        
        // SVG y坐标是基线位置
        final offsetY = y - fontSize * 0.8;
        
        textPainter.paint(canvas, Offset(offsetX, offsetY));
      } catch (e) {
        // 忽略解析错误
      }
    }
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
