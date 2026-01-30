import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_svg/flutter_svg.dart' as flutter_svg;
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
    Color backgroundColor = Colors.transparent,
    bool maintainAspectRatio = true,
    bool useCache = true,
    double scaleFactor = 1.0,
    ExportRenderMode renderMode = ExportRenderMode.contain,
    BuildContext? context,
    double borderRadius = 0,
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

      // 关键修复：始终使用原始 SVG，不做任何标准化处理
      // 这样保证保存时的渲染与预览完全一致
      // flutter_svg 已能正确处理各种 SVG 格式（包括 rgb()/rgba()/style 等）
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
        borderRadius,
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
    Color backgroundColor = Colors.transparent,
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
    double borderRadius,
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
          borderRadius: borderRadius,
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
        borderRadius,
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

  /// 备用方案：使用 flutter_svg 的 Drawable 解析，保留渐变/滤镜/阴影；失败再落手写兜底。
  static Future<Uint8List> _renderWithFlutterSvg(
    String svgContent,
    int width,
    int height,
    ui.ImageByteFormat format,
    Color backgroundColor,
    double scaleFactor,
    ExportRenderMode renderMode,
    double borderRadius,
  ) async {
    AppLogger.d(
      '使用flutter_svg Drawable 渲染（无BuildContext）: ${width}x$height, 缩放: $scaleFactor, 模式: $renderMode',
      source: 'SvgToImageService',
    );

    final safeScale =
        scaleFactor.isFinite && scaleFactor > 0 ? scaleFactor : 1.0;

    final outputSize = Size(width.toDouble(), height.toDouble());
    final fit = switch (renderMode) {
      ExportRenderMode.contain => BoxFit.contain,
      ExportRenderMode.cover => BoxFit.cover,
      ExportRenderMode.stretch => BoxFit.fill,
    };

    // 确保绑定初始化（在单元测试/后台调用中尤为重要）。
    final binding = WidgetsFlutterBinding.ensureInitialized();
    final views = binding.platformDispatcher.views;
    if (views.isEmpty) {
      throw StateError('无可用 FlutterView，无法进行离屏渲染');
    }
    final flutterView = views.first;

    final repaintBoundary = RenderRepaintBoundary();

    // 通过 RenderView + PipelineOwner 驱动一次 layout/paint。
    final renderView = RenderView(
      view: flutterView,
      configuration: ViewConfiguration(
        logicalConstraints: BoxConstraints.tight(outputSize),
        physicalConstraints: BoxConstraints.tight(outputSize),
        devicePixelRatio: 1.0,
      ),
      child: RenderPositionedBox(
        alignment: Alignment.center,
        child: repaintBoundary,
      ),
    );

    final pipelineOwner = PipelineOwner();
    pipelineOwner.rootNode = renderView;
    renderView.prepareInitialFrame();

    final focusManager = FocusManager();
    final buildOwner = BuildOwner(focusManager: focusManager);

    Widget content = flutter_svg.SvgPicture.string(
      svgContent,
      width: outputSize.width,
      height: outputSize.height,
      fit: fit,
      allowDrawingOutsideViewBox: false,
    );

    // 如果指定了圆角，则使用ClipRRect裁剪内容
    if (borderRadius > 0) {
      content = ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius),
        child: content,
      );
    }

    final rootWidget = Directionality(
      textDirection: ui.TextDirection.ltr,
      child: SizedBox(
        width: outputSize.width,
        height: outputSize.height,
        child: ColoredBox(
          color: backgroundColor,
          child: content,
        ),
      ),
    );

    final element = RenderObjectToWidgetAdapter<RenderBox>(
      container: repaintBoundary,
      child: rootWidget,
    ).attachToRenderTree(buildOwner);

    // build -> layout -> paint
    buildOwner.buildScope(element);
    buildOwner.finalizeTree();
    pipelineOwner.flushLayout();
    pipelineOwner.flushCompositingBits();
    pipelineOwner.flushPaint();

    // 通过 pixelRatio 控制最终清晰度
    final image = await repaintBoundary.toImage(pixelRatio: safeScale);
    final byteData = await image.toByteData(format: format);
    image.dispose();

    focusManager.dispose();

    if (byteData == null) {
      throw StateError('无法生成图片字节数据');
    }
    return byteData.buffer.asUint8List();
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
