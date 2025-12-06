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
        AppLogger.w(
          '图片尺寸过大: ${width}x$height，可能导致内存问题',
          source: 'SvgToImageService',
        );
      }

      // 生成缓存键
      final cacheKey = useCache
          ? ImageCacheService.generateCacheKey(
              svgContent,
              width,
              height,
              format,
            )
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
      final normalizedSvg = _normalizeSvgForRendering(
        svgContent,
        width,
        height,
      );

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
        AppLogger.w(
          '批量转换第${i + 1}个SVG失败: $e',
          error: e,
          source: 'SvgToImageService',
        );
        // 添加错误图片
        final errorImage = await _generateErrorImage(
          width,
          height,
          format,
          e.toString(),
        );
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
    String svgContent,
    int width,
    int height,
  ) {
    String normalized = svgContent.trim();

    // 确保SVG有xmlns命名空间
    if (!normalized.contains('xmlns=')) {
      normalized = normalized.replaceFirst(
        '<svg',
        '<svg xmlns="http://www.w3.org/2000/svg"',
      );
    }

    final inferredSize = _inferSvgIntrinsicSize(normalized);

    AppLogger.d(
      'SVG内在尺寸: ${inferredSize.$1}x${inferredSize.$2}',
      source: 'SvgToImageService',
    );

    // 移除现有的width、height、viewBox属性（避免重复或无效值导致错位）
    normalized = normalized
        .replaceAll(RegExp(r'\s+width="[^"]*"'), '')
        .replaceAll(RegExp(r'\s+height="[^"]*"'), '')
        .replaceAll(RegExp(r'\s+viewBox="[^"]*"'), '')
        .replaceAll(RegExp(r'\s+preserveAspectRatio="[^"]*"'), '');

    // 统一设置标准属性：使用推断的viewBox，并显式设置width/height防止百分比导致裁剪
    normalized = normalized.replaceFirst(
      '<svg',
      '<svg viewBox="0 0 ${inferredSize.$1} ${inferredSize.$2}" width="${inferredSize.$1}" height="${inferredSize.$2}" preserveAspectRatio="xMidYMid meet"',
    );

    return normalized;
  }

  /// 推断SVG的内在尺寸，优先使用合法viewBox，其次使用数值width/height，
  /// 若为百分比或无效则从首个大矩形推断，最后回退到400x600。
  static (String, String) _inferSvgIntrinsicSize(String svgContent) {
    // 1) 优先使用合法的viewBox
    final viewBoxMatch = RegExp(r'viewBox="([^"]+)"').firstMatch(svgContent);
    if (viewBoxMatch != null) {
      final parts = viewBoxMatch.group(1)!.split(RegExp(r'[\s,]+'));
      if (parts.length == 4 && parts.every((p) => double.tryParse(p) != null)) {
        return (parts[2], parts[3]);
      }
    }

    // 2) 解析数值width/height（忽略百分比/空值）
    double? w = _parseNumericDimension(
      RegExp(r'width="([^"]+)"').firstMatch(svgContent)?.group(1),
    );
    double? h = _parseNumericDimension(
      RegExp(r'height="([^"]+)"').firstMatch(svgContent)?.group(1),
    );

    // 3) 如果根节点给的是百分比或0，尝试从第一个rect推断背景尺寸
    if (w == null || h == null) {
      final rectMatch = RegExp(r'<rect[^>]*width="([^"]+)"[^>]*height="([^"]+)"')
          .firstMatch(svgContent);
      if (rectMatch != null) {
        w = _parseNumericDimension(rectMatch.group(1)) ?? w;
        h = _parseNumericDimension(rectMatch.group(2)) ?? h;
      }
    }

    // 4) 仍然无效时使用默认值
    w ??= 400;
    h ??= 600;

    return (w.toString(), h.toString());
  }

  /// 仅接受数值维度，忽略百分比/空/非数字，避免 100% 导致视窗被错置。
  static double? _parseNumericDimension(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    if (raw.contains('%')) return null;
    final cleaned = raw.replaceAll(RegExp('[^0-9.\-]'), '');
    if (cleaned.isEmpty) return null;
    final parsed = double.tryParse(cleaned);
    if (parsed == null || parsed <= 0) return null;
    return parsed;
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
          source: 'SvgToImageService',
        );
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
        AppLogger.i(
          'Flutter真实渲染成功，图片大小: ${result.length} bytes',
          source: 'SvgToImageService',
        );
        return result;
      } catch (e) {
        AppLogger.w(
          'Flutter真实渲染失败，尝试备用方案: $e',
          error: e,
          source: 'SvgToImageService',
        );
      }
    } else {
      AppLogger.w(
        '缺少BuildContext，无法使用真实渲染，将使用备用方案',
        source: 'SvgToImageService',
      );
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
      AppLogger.w(
        'flutter_svg渲染失败，使用最终回退: $e',
        error: e,
        source: 'SvgToImageService',
      );
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
    Canvas canvas,
    String svgContent,
    int width,
    int height,
  ) async {
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
      final x1 = _parsePercentage(
        RegExp(r'x1="([^"]*)"').firstMatch(tag)?.group(1),
      );
      final y1 = _parsePercentage(
        RegExp(r'y1="([^"]*)"').firstMatch(tag)?.group(1),
      );
      final x2 = _parsePercentage(
        RegExp(r'x2="([^"]*)"').firstMatch(tag)?.group(1),
      );
      final y2 = _parsePercentage(
        RegExp(r'y2="([^"]*)"').firstMatch(tag)?.group(1),
      );

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

  /// 解析标签属性，兼容任意顺序及style内联写法
  static Map<String, String> _parseAttributes(String tag) {
    final attrs = <String, String>{};
    final attrRegex = RegExp(r'([a-zA-Z_:][\w:.-]*)\s*=\s*"([^"]*)"');
    for (final match in attrRegex.allMatches(tag)) {
      attrs[match.group(1)!] = match.group(2)!;
    }
    return attrs;
  }

  /// 从属性或style中提取填充色
  static String _extractFill(
    Map<String, String> attrs, {
    String defaultColor = '#000000',
  }) {
    String? fill = attrs['fill'];
    fill ??= _parseStyleValue(attrs['style'], 'fill');
    if (fill == null || fill.isEmpty) return defaultColor;
    return fill.trim();
  }

  /// 从属性或style中提取透明度
  static double _extractOpacity(
    Map<String, String> attrs, {
    String attributeKey = 'fill-opacity',
    double defaultOpacity = 1.0,
  }) {
    final raw = attrs[attributeKey] ?? _parseStyleValue(attrs['style'], attributeKey);
    final parsed = double.tryParse(raw ?? '');
    return parsed ?? defaultOpacity;
  }

  /// 从属性或style中提取数值字体大小
  static double _extractFontSize(
    Map<String, String> attrs, {
    double defaultSize = 14.0,
  }) {
    final raw = attrs['font-size'] ?? _parseStyleValue(attrs['style'], 'font-size');
    final cleaned = raw?.replaceAll(RegExp('[^0-9.\-]'), '');
    final parsed = double.tryParse(cleaned ?? '');
    return parsed ?? defaultSize;
  }

  /// 从style中解析键值
  static String? _parseStyleValue(String? style, String key) {
    if (style == null) return null;
    final regex = RegExp('$key\\s*:\\s*([^;]+)', caseSensitive: false);
    final match = regex.firstMatch(style);
    return match?.group(1)?.trim();
  }

  /// 将数值字符串转换为double，容忍%或px后缀
  static double _parseDimension(String? value) {
    if (value == null) return 0;
    final cleaned = value.replaceAll(RegExp('[^0-9.\-]'), '');
    return double.tryParse(cleaned) ?? 0;
  }

  /// 绘制背景矩形
  static void _drawBackgroundRect(
    Canvas canvas,
    String svgContent,
    int width,
    int height,
    Map<String, Gradient> gradients,
  ) {
    // 查找可能的背景矩形，兼容属性顺序与style写法
    final rectRegex = RegExp(r'<rect[^>]*>', caseSensitive: false);

    for (final match in rectRegex.allMatches(svgContent)) {
      final tag = match.group(0) ?? '';
      final attrs = _parseAttributes(tag);

      final w = _parseDimension(attrs['width']);
      final h = _parseDimension(attrs['height']);
      final rx = _parseDimension(attrs['rx']);
      final fill = _extractFill(attrs, defaultColor: '#ffffff');

      // 检查是否是全尺寸背景(留10%容差，避免因缩放丢失背景)
      if (w >= width * 0.8 && h >= height * 0.8) {
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
  static void _drawAllShapes(
    Canvas canvas,
    String svgContent,
    int width,
    int height,
    Map<String, Gradient> gradients,
  ) {
    // 绘制圆形（兼容style写法）
    final circleRegex = RegExp(r'<circle[^>]*>', caseSensitive: false);

    for (final match in circleRegex.allMatches(svgContent)) {
      try {
        final attrs = _parseAttributes(match.group(0) ?? '');
        final cx = _parseDimension(attrs['cx']);
        final cy = _parseDimension(attrs['cy']);
        final r = _parseDimension(attrs['r']);
        final fill = _extractFill(attrs, defaultColor: '#000000');
        final opacity = _extractOpacity(attrs, defaultOpacity: 1.0);

        final paint = Paint();
        if (fill.startsWith('url(#')) {
          final gradientId = fill.substring(5, fill.length - 1);
          final gradient = gradients[gradientId];
          if (gradient != null) {
            paint.shader = gradient.createShader(
              Rect.fromCircle(center: Offset(cx, cy), radius: r),
            );
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
    final rectRegex = RegExp(r'<rect[^>]*>', caseSensitive: false);

    for (final match in rectRegex.allMatches(svgContent)) {
      try {
        final tag = match.group(0) ?? '';
        final attrs = _parseAttributes(tag);

        final x = _parseDimension(attrs['x']);
        final y = _parseDimension(attrs['y']);
        final w = _parseDimension(attrs['width']);
        final h = _parseDimension(attrs['height']);
        final fill = _extractFill(attrs, defaultColor: '#000000');
        final opacity = _extractOpacity(attrs, defaultOpacity: 1.0);
        final rx = _parseDimension(attrs['rx']);

        // 跳过全屏背景矩形
        if (w >= width * 0.8 && h >= height * 0.8 && x <= 10 && y <= 10) {
          continue;
        }

        final rect = rx > 0
            ? RRect.fromRectAndRadius(
                Rect.fromLTWH(x, y, w, h),
                Radius.circular(rx),
              )
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
  static void _drawAllText(
    Canvas canvas,
    String svgContent,
    int width,
    int height,
  ) {
    final textRegex = RegExp(r'<text[^>]*>.*?<\/text>', dotAll: true, caseSensitive: false);

    for (final match in textRegex.allMatches(svgContent)) {
      try {
        final rawTag = match.group(0) ?? '';
        final attrs = _parseAttributes(rawTag);
        double x = _parseDimension(attrs['x']);
        final y = _parseDimension(attrs['y']);
        final anchor = attrs['text-anchor'] ?? _parseStyleValue(attrs['style'], 'text-anchor') ?? 'start';
        final fill = _extractFill(attrs, defaultColor: '#000000');
        final fontSize = _extractFontSize(attrs, defaultSize: 14.0);
        final opacity = _extractOpacity(attrs, defaultOpacity: 1.0);

        final contentMatch = RegExp(r'>\s*(.*?)\s*<\/text>', dotAll: true).firstMatch(rawTag);
        String text = contentMatch?.group(1) ?? '';

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
    canvas.drawRect(
      Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
      backgroundPaint,
    );

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
    Canvas canvas,
    int width,
    int height,
    String svgContent,
  ) {
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
    canvas.drawRect(
      Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
      backgroundPaint,
    );

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
      center + const Offset(-15, -15),
      center + const Offset(15, 15),
      xPaint,
    );
    canvas.drawLine(
      center + const Offset(15, -15),
      center + const Offset(-15, 15),
      xPaint,
    );

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
            style: const TextStyle(color: Color(0xFF666666), fontSize: 12),
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
