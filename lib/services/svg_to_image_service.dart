import 'dart:async';
import 'dart:isolate';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_svg/flutter_svg.dart' as flutter_svg;
import 'package:image/image.dart' as img;
import 'package:thoughtecho/utils/app_logger.dart';
import 'svg_offscreen_renderer.dart';
import 'svg_raster_cache_service.dart';
import '../utils/bounded_svg_loader.dart';

TransferableTypedData _encodeRgbaToPngTransferable(
  TransferableTypedData transferableRgba,
  int width,
  int height,
) {
  final rgbaBytes = transferableRgba.materialize().asUint8List();
  SvgToImageService.unpremultiplyRgbaInPlace(rgbaBytes);

  final decodedImage = img.Image.fromBytes(
    width: width,
    height: height,
    bytes: rgbaBytes.buffer,
    bytesOffset: rgbaBytes.offsetInBytes,
    numChannels: 4,
    order: img.ChannelOrder.rgba,
  );
  final pngBytes = img.encodePng(
    decodedImage,
    filter: img.PngFilter.sub,
    level: 6,
  );
  return TransferableTypedData.fromList([pngBytes]);
}

/// 导出渲染模式
enum ExportRenderMode {
  contain, // 等比完整显示（可能留边）
  cover, // 等比填满（可能裁切）
  stretch, // 拉伸填满（可能变形）
}

/// SVG到图片转换服务
class SvgToImageService {
  static final SvgRasterCacheService _cacheService = SvgRasterCacheService();
  static final Map<String, Future<Uint8List>> _inFlightRenders = {};

  /// 导出最大像素比上限
  static const double maxExportPixelRatio = 4.0;

  /// 导出物理边长上限（与 AICardGenerationService.saveCardAsImage 安全上限一致）
  static const double maxExportPhysicalDimension = 4000.0;

  @visibleForTesting
  static int debugRenderCount = 0;

  @visibleForTesting
  static void resetDebugRenderCount() {
    debugRenderCount = 0;
  }

  @visibleForTesting
  static int get debugInFlightCount => _inFlightRenders.length;

  // 预编译正则表达式以提升性能
  static final RegExp _numericRegex = RegExp('[^0-9.-]');
  static final RegExp _linearGradientRegex = RegExp(
      r'<linearGradient[^>]*>.*?<\/linearGradient>',
      dotAll: true,
      caseSensitive: false);
  static final RegExp _radialGradientRegex = RegExp(
      r'<radialGradient[^>]*>.*?<\/radialGradient>',
      dotAll: true,
      caseSensitive: false);
  static final RegExp _linearGradientStartRegex =
      RegExp(r'<linearGradient[^>]*>', caseSensitive: false);
  static final RegExp _radialGradientStartRegex =
      RegExp(r'<radialGradient[^>]*>', caseSensitive: false);
  static final RegExp _x1Regex = RegExp(r'x1="([^"]*)"');
  static final RegExp _y1Regex = RegExp(r'y1="([^"]*)"');
  static final RegExp _x2Regex = RegExp(r'x2="([^"]*)"');
  static final RegExp _y2Regex = RegExp(r'y2="([^"]*)"');
  static final RegExp _stopWithAttrsRegex = RegExp(
    r'<stop[^>]*offset="([^"]*)"[^>]*(?:stop-color="([^"]*)"|style="[^"]*stop-color:\s*([^;"\s]+))[^>]*(?:stop-opacity="([^"]*)"|style="[^"]*stop-opacity:\s*([^;"\s]+))?',
    caseSensitive: false,
  );
  static final RegExp _rgbaRegex = RegExp(r'^rgba?\(([^)]+)\)$');
  static final RegExp _idRegex = RegExp(r'id="([^"]+)"');

  // 缓存样式的RegExp，避免动态生成时的编译开销
  static final Map<String, RegExp> _styleRegexCache = {};

  /// 规范化导出像素比：先校验 safeScale，按需乘以设备像素比，并受最大像素比与物理边长安全上限约束
  static double resolveEffectivePixelRatio({
    required int width,
    required int height,
    required double scaleFactor,
    double devicePixelRatio = 1.0,
    String logSource = 'SvgToImageService',
  }) {
    final safeScale =
        (scaleFactor.isFinite && scaleFactor > 0) ? scaleFactor : 1.0;
    final safeDpr = (devicePixelRatio.isFinite && devicePixelRatio > 0)
        ? devicePixelRatio
        : 1.0;
    double effectivePixelRatio = safeScale * safeDpr;

    if (effectivePixelRatio > maxExportPixelRatio) {
      AppLogger.w(
        '像素比过高(${effectivePixelRatio.toStringAsFixed(1)})，限制为$maxExportPixelRatio',
        source: logSource,
      );
      effectivePixelRatio = maxExportPixelRatio;
    }

    final maxLogicalSide =
        width > height ? width.toDouble() : height.toDouble();
    if (maxLogicalSide > 0 &&
        maxLogicalSide * effectivePixelRatio > maxExportPhysicalDimension) {
      final cappedRatio = maxExportPhysicalDimension / maxLogicalSide;
      AppLogger.w(
        '导出物理尺寸超限(${(maxLogicalSide * effectivePixelRatio).round()}px)，限制像素比为${cappedRatio.toStringAsFixed(2)}',
        source: logSource,
      );
      effectivePixelRatio = cappedRatio;
    }

    return effectivePixelRatio;
  }

  /// 将 dart:ui ImageByteFormat.rawRgba 预乘 Alpha 像素原地还原为直通 Alpha（Straight Alpha）
  @visibleForTesting
  static void unpremultiplyRgbaInPlace(Uint8List rgbaBytes) {
    final length = rgbaBytes.length & ~3;
    for (var i = 0; i < length; i += 4) {
      final a = rgbaBytes[i + 3];
      if (a == 255) {
        continue;
      }
      if (a == 0) {
        rgbaBytes[i] = 0;
        rgbaBytes[i + 1] = 0;
        rgbaBytes[i + 2] = 0;
        continue;
      }
      final halfA = a >> 1;
      final r = (rgbaBytes[i] * 255 + halfA) ~/ a;
      final g = (rgbaBytes[i + 1] * 255 + halfA) ~/ a;
      final b = (rgbaBytes[i + 2] * 255 + halfA) ~/ a;
      rgbaBytes[i] = r > 255 ? 255 : r;
      rgbaBytes[i + 1] = g > 255 ? 255 : g;
      rgbaBytes[i + 2] = b > 255 ? 255 : b;
    }
  }

  /// 在指定超时内截取 [RenderRepaintBoundary]，若发生超时则在底层截图稍后完成时自动释放 [ui.Image]
  static Future<ui.Image> captureBoundaryImage(
    RenderRepaintBoundary boundary, {
    required double pixelRatio,
    required Duration timeout,
  }) async {
    if (timeout <= Duration.zero) {
      throw TimeoutException('SVG离屏渲染截图超时', timeout);
    }
    final imageFuture = boundary.toImage(pixelRatio: pixelRatio);
    var timedOut = false;
    unawaited(
      imageFuture.then((lateImage) {
        if (timedOut) {
          lateImage.dispose();
        }
      }, onError: (_) {}),
    );
    try {
      return await imageFuture.timeout(timeout);
    } on TimeoutException {
      timedOut = true;
      rethrow;
    }
  }

  /// 统一从 [ui.Image] 导出编码字节：
  /// - 非 PNG 格式直接调用 [ui.Image.toByteData]；
  /// - PNG 格式仅在主线程读取未压缩 [ui.ImageByteFormat.rawRgba] 并在 `finally` 中立即释放
  ///   GPU 纹理与 [onImageRead] 资源，随后零拷贝移交后台 Isolate 执行反预乘、滤波与 zlib 压缩。
  static Future<Uint8List> exportUiImageBytes(
    ui.Image image, {
    ui.ImageByteFormat format = ui.ImageByteFormat.png,
    VoidCallback? onImageRead,
  }) async {
    if (format != ui.ImageByteFormat.png) {
      try {
        final byteData = await image.toByteData(format: format);
        if (byteData == null) {
          throw StateError('无法获取图片字节数据');
        }
        return byteData.buffer.asUint8List(
          byteData.offsetInBytes,
          byteData.lengthInBytes,
        );
      } finally {
        image.dispose();
        onImageRead?.call();
      }
    }

    final int imageWidth = image.width;
    final int imageHeight = image.height;
    final TransferableTypedData transferableRgba;
    try {
      final rawByteData = await image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      );
      if (rawByteData == null) {
        throw StateError('无法获取图片原始RGBA字节数据');
      }
      final rawView = rawByteData.buffer.asUint8List(
        rawByteData.offsetInBytes,
        rawByteData.lengthInBytes,
      );
      transferableRgba = TransferableTypedData.fromList([rawView]);
    } finally {
      image.dispose();
      onImageRead?.call();
    }

    final encodedTransferable = await Isolate.run(
      () => _encodeRgbaToPngTransferable(
        transferableRgba,
        imageWidth,
        imageHeight,
      ),
    );
    return encodedTransferable.materialize().asUint8List();
  }

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
    Duration timeout = const Duration(seconds: 10),
    @visibleForTesting flutter_svg.BytesLoader? loaderOverride,
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

      // 生成完整参数缓存键
      final cacheKey = useCache
          ? SvgRasterCacheService.generateCacheKey(
              svgContent,
              width,
              height,
              format,
              scaleFactor: scaleFactor,
              renderMode: renderMode.name,
              backgroundColor: backgroundColor,
              borderRadius: borderRadius,
            )
          : null;

      // 尝试从缓存获取
      if (useCache && cacheKey != null) {
        final cachedImage = _cacheService.getCachedImage(cacheKey);
        if (cachedImage != null) {
          AppLogger.d('使用缓存图片: $cacheKey', source: 'SvgToImageService');
          return cachedImage;
        }

        final inFlight = _inFlightRenders[cacheKey];
        if (inFlight != null) {
          AppLogger.d('复用在飞SVG渲染任务: $cacheKey', source: 'SvgToImageService');
          return await inFlight;
        }
      }

      // 验证SVG内容
      _validateSvgContent(svgContent);

      // 检查内存使用情况
      if (useCache) {
        _cacheService.smartCleanup();
      }

      Future<Uint8List> runRenderPipeline() async {
        // 关键修复：始终使用原始 SVG，不做任何标准化处理
        // 这样保证保存时的渲染与预览完全一致
        // flutter_svg 已能正确处理各种 SVG 格式（包括 rgb()/rgba()/style 等）
        final renderResult = await _renderSvgToBytes(
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
          timeout,
          loaderOverride,
        );

        // 仅在真实渲染成功（非超时/降级占位兜底图）时写入缓存，防止慢解码超时把残缺图片固化到缓存
        if (useCache && cacheKey != null && renderResult.cacheable) {
          _cacheService.cacheImage(cacheKey, renderResult.bytes);
        }
        return renderResult.bytes;
      }

      if (useCache && cacheKey != null) {
        late final Future<Uint8List> renderFuture;
        renderFuture = runRenderPipeline().whenComplete(() {
          if (identical(_inFlightRenders[cacheKey], renderFuture)) {
            _inFlightRenders.remove(cacheKey);
          }
        });
        _inFlightRenders[cacheKey] = renderFuture;
        return await renderFuture;
      }

      return await runRenderPipeline();
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

  /// 渲染SVG为字节数组，并标记结果是否可安全写入光栅化缓存
  static Future<({Uint8List bytes, bool cacheable})> _renderSvgToBytes(
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
    Duration timeout,
    flutter_svg.BytesLoader? loaderOverride,
  ) async {
    debugRenderCount++;
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
          timeout: timeout,
          devicePixelRatioAware: false,
          borderRadius: borderRadius,
          loaderOverride: loaderOverride,
        );
        AppLogger.i(
          'Flutter真实渲染成功，图片大小: ${result.length} bytes',
          source: 'SvgToImageService',
        );
        return (bytes: result, cacheable: true);
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
      final bytes = await _renderWithFlutterSvg(
        svgContent,
        width,
        height,
        format,
        backgroundColor,
        scaleFactor,
        renderMode,
        borderRadius,
        timeout: timeout,
        loaderOverride: loaderOverride,
      );
      return (bytes: bytes, cacheable: true);
    } catch (e) {
      AppLogger.w(
        'flutter_svg渲染失败，使用最终回退: $e',
        error: e,
        source: 'SvgToImageService',
      );
      // 最终回退方案（降级占位图不可写入缓存，以便后续重试恢复真实卡片）
      final fallbackBytes = await _renderFallbackImage(
        svgContent,
        width,
        height,
        format,
        backgroundColor,
      );
      return (bytes: fallbackBytes, cacheable: false);
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
    double borderRadius, {
    Duration timeout = const Duration(seconds: 10),
    flutter_svg.BytesLoader? loaderOverride,
  }) async {
    AppLogger.d(
      '使用flutter_svg Drawable 渲染（无BuildContext）: ${width}x$height, 缩放: $scaleFactor, 模式: $renderMode',
      source: 'SvgToImageService',
    );

    final effectiveScale = resolveEffectivePixelRatio(
      width: width,
      height: height,
      scaleFactor: scaleFactor,
      logSource: 'SvgToImageService',
    );

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

    final stopwatch = Stopwatch()..start();
    final loader = loaderOverride ?? BoundedSvgLoader(svgContent);
    await loader.loadBytes(null).timeout(timeout);

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
    RenderObjectToWidgetElement<RenderBox>? mountedElement;
    var resourcesDisposed = false;
    void disposeOffscreenTree() {
      if (resourcesDisposed) return;
      resourcesDisposed = true;
      final elementToUnmount = mountedElement;
      mountedElement = null;
      if (elementToUnmount != null) {
        try {
          RenderObjectToWidgetAdapter<RenderBox>(
            container: repaintBoundary,
          ).attachToRenderTree(buildOwner, elementToUnmount);
          buildOwner.finalizeTree();
        } catch (_) {}
      }
      focusManager.dispose();
    }

    try {
      var isVectorReady = false;
      Object? svgLoadError;
      StackTrace? svgLoadStackTrace;

      Widget content = flutter_svg.SvgPicture(
        loader,
        width: outputSize.width,
        height: outputSize.height,
        fit: fit,
        allowDrawingOutsideViewBox: false,
        placeholderBuilder: (_) {
          isVectorReady = false;
          return SizedBox(
            width: outputSize.width,
            height: outputSize.height,
          );
        },
        imageBuilder: (_, child) {
          isVectorReady = true;
          return child;
        },
        errorBuilder: (_, error, stackTrace) {
          svgLoadError = error;
          svgLoadStackTrace = stackTrace;
          return const SizedBox.shrink();
        },
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
          child: ColoredBox(color: backgroundColor, child: content),
        ),
      );

      final element = RenderObjectToWidgetAdapter<RenderBox>(
        container: repaintBoundary,
        child: rootWidget,
      ).attachToRenderTree(buildOwner);
      mountedElement = element;

      void flushPipeline() {
        buildOwner.buildScope(element);
        buildOwner.finalizeTree();
        pipelineOwner.flushLayout();
        pipelineOwner.flushCompositingBits();
        pipelineOwner.flushPaint();
      }

      flushPipeline();

      // 在壁钟超时范围内等待矢量解码完成并挂载真实图元子树，绝不提前截取空白占位图
      var pollCount = 0;
      while (!isVectorReady && svgLoadError == null) {
        final remaining = timeout - stopwatch.elapsed;
        if (remaining <= Duration.zero) {
          break;
        }
        final stepDelay = pollCount < 4
            ? Duration.zero
            : (remaining < const Duration(milliseconds: 8)
                ? remaining
                : const Duration(milliseconds: 8));
        pollCount++;
        await Future<void>.delayed(stepDelay);
        flushPipeline();
      }

      if (svgLoadError != null) {
        Error.throwWithStackTrace(
          svgLoadError!,
          svgLoadStackTrace ?? StackTrace.current,
        );
      }

      if (!isVectorReady) {
        throw TimeoutException('SVG无Context离屏解码超时，矢量图元尚未就绪', timeout);
      }

      repaintBoundary.markNeedsPaint();
      flushPipeline();

      // 通过 pixelRatio 控制最终清晰度，并在主线程读取完原始 RGBA 后立即交由后台 Isolate 编码 PNG
      final image = await captureBoundaryImage(
        repaintBoundary,
        pixelRatio: effectiveScale,
        timeout: timeout - stopwatch.elapsed,
      );
      return await exportUiImageBytes(
        image,
        format: format,
        onImageRead: disposeOffscreenTree,
      );
    } finally {
      disposeOffscreenTree();
    }
  }

  /// 改进的SVG内容绘制

  /// 解析所有渐变定义
  // ignore: unused_element
  static Map<String, Gradient> _parseAllGradients(String svgContent) {
    final gradients = <String, Gradient>{};

    // 解析 linearGradient
    for (final match in _linearGradientRegex.allMatches(svgContent)) {
      final tag = match.group(0) ?? '';
      // 使用 RegExp 匹配以开始标签作为作用域
      final startTagMatch = _linearGradientStartRegex.firstMatch(tag);
      final idMatch = _idRegex.firstMatch(startTagMatch?.group(0) ?? '');
      final id = idMatch?.group(1) ?? '';
      final content = match.group(0) ??
          ''; // Since we changed regex, but actually dotAll matches entire tag in _linearGradientRegex

      if (id.isEmpty) continue;

      // 解析渐变方向
      final x1 = _parsePercentage(
        _x1Regex.firstMatch(tag)?.group(1),
      );
      final y1 = _parsePercentage(
        _y1Regex.firstMatch(tag)?.group(1),
      );
      final x2 = _parsePercentage(
        _x2Regex.firstMatch(tag)?.group(1),
      );
      final y2 = _parsePercentage(
        _y2Regex.firstMatch(tag)?.group(1),
      );

      // 解析颜色停靠点
      final stops = <double>[];
      final colors = <Color>[];

      for (final stopMatch in _stopWithAttrsRegex.allMatches(content)) {
        final offset = _parsePercentage(stopMatch.group(1));
        final colorStr = stopMatch.group(2) ?? stopMatch.group(3) ?? '#000000';
        final opacityStr = stopMatch.group(4) ?? stopMatch.group(5);

        stops.add(offset);
        Color color = _parseColor(colorStr);
        if (opacityStr != null) {
          final opacity = double.tryParse(opacityStr) ?? 1.0;
          color = _applyOpacityMultiplier(color, opacity);
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
    for (final match in _radialGradientRegex.allMatches(svgContent)) {
      final tag = match.group(0) ?? '';
      // 使用 RegExp 匹配以开始标签作为作用域
      final startTagMatch = _radialGradientStartRegex.firstMatch(tag);
      final idMatch = _idRegex.firstMatch(startTagMatch?.group(0) ?? '');
      final id = idMatch?.group(1) ?? '';
      final content = match.group(0) ?? '';

      if (id.isEmpty) continue;

      final stops = <double>[];
      final colors = <Color>[];

      for (final stopMatch in _stopWithAttrsRegex.allMatches(content)) {
        final offset = _parsePercentage(stopMatch.group(1));
        final colorStr = stopMatch.group(2) ?? stopMatch.group(3) ?? '#000000';
        final opacityStr = stopMatch.group(4) ?? stopMatch.group(5);

        stops.add(offset);
        Color color = _parseColor(colorStr);
        if (opacityStr != null) {
          final opacity = double.tryParse(opacityStr) ?? 1.0;
          color = _applyOpacityMultiplier(color, opacity);
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
  // ignore: unused_element
  static double _parsePercentage(String? value) {
    if (value == null) return 0.0;
    final trimmed = value.trim().replaceAll('%', '');
    return (double.tryParse(trimmed) ?? 0.0) / 100.0;
  }

  /// 从属性或style中提取填充色
  // ignore: unused_element
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
  // ignore: unused_element
  static double _extractOpacity(
    Map<String, String> attrs, {
    String attributeKey = 'fill-opacity',
    double defaultOpacity = 1.0,
  }) {
    final raw =
        attrs[attributeKey] ?? _parseStyleValue(attrs['style'], attributeKey);
    final parsed = double.tryParse(raw ?? '');
    return parsed ?? defaultOpacity;
  }

  /// 从属性或style中提取数值字体大小
  // ignore: unused_element
  static double _extractFontSize(
    Map<String, String> attrs, {
    double defaultSize = 14.0,
  }) {
    final raw =
        attrs['font-size'] ?? _parseStyleValue(attrs['style'], 'font-size');
    final cleaned = raw?.replaceAll(_numericRegex, '');
    final parsed = double.tryParse(cleaned ?? '');
    return parsed ?? defaultSize;
  }

  /// 从style中解析键值
  // ignore: unused_element
  static String? _parseStyleValue(String? style, String key) {
    if (style == null) return null;

    RegExp regex = _styleRegexCache[key] ??=
        RegExp('$key\\s*:\\s*([^;]+)', caseSensitive: false);
    final match = regex.firstMatch(style);
    return match?.group(1)?.trim();
  }

  /// 将数值字符串转换为double，容忍%或px后缀
  // ignore: unused_element
  static double _parseDimension(String? value) {
    if (value == null) return 0;
    final cleaned = value.replaceAll(_numericRegex, '');
    return double.tryParse(cleaned) ?? 0;
  }

  /// 渲染回退图片
  // ignore: unused_element
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
  // ignore: unused_element
  static Color _parseColor(String colorString) {
    final raw = colorString.trim();
    if (raw.isEmpty) return Colors.black;

    final lower = raw.toLowerCase();

    // 常见无填充/透明写法
    if (lower == 'none' || lower == 'transparent') {
      return Colors.transparent;
    }

    // rgb()/rgba()
    // 兼容：rgb(255,0,0) / rgb(100%,0%,0%) / rgba(255,0,0,0.5)
    final rgbaMatch = _rgbaRegex.firstMatch(lower);
    if (rgbaMatch != null) {
      final parts = rgbaMatch.group(1)!.split(',').map((e) => e.trim());
      final list = parts.toList(growable: false);
      if (list.length >= 3) {
        int parseChannel(String v) {
          if (v.endsWith('%')) {
            final p = double.tryParse(v.replaceAll('%', '')) ?? 0;
            return (p.clamp(0, 100) * 2.55).round();
          }
          final n = double.tryParse(v) ?? 0;
          return n.round().clamp(0, 255);
        }

        double parseAlpha(String v) {
          if (v.endsWith('%')) {
            final p = double.tryParse(v.replaceAll('%', '')) ?? 100;
            return (p / 100.0).clamp(0.0, 1.0);
          }
          final n = double.tryParse(v);
          if (n == null) return 1.0;
          if (n <= 1.0) return n.clamp(0.0, 1.0);
          // 容忍 0-255 的 alpha
          if (n <= 255.0) return (n / 255.0).clamp(0.0, 1.0);
          return 1.0;
        }

        final r = parseChannel(list[0]);
        final g = parseChannel(list[1]);
        final b = parseChannel(list[2]);
        final a = list.length >= 4 ? parseAlpha(list[3]) : 1.0;
        return Color.fromRGBO(r, g, b, a);
      }
    }

    // 十六进制：#RGB/#RGBA/#RRGGBB/#RRGGBBAA
    if (lower.startsWith('#')) {
      final hex = lower.substring(1);

      try {
        if (hex.length == 3) {
          final rrggbb =
              '${hex[0]}${hex[0]}${hex[1]}${hex[1]}${hex[2]}${hex[2]}';
          return Color(int.parse('ff$rrggbb', radix: 16));
        }
        if (hex.length == 4) {
          final rrggbb =
              '${hex[0]}${hex[0]}${hex[1]}${hex[1]}${hex[2]}${hex[2]}';
          final aa = '${hex[3]}${hex[3]}';
          return Color(int.parse('$aa$rrggbb', radix: 16));
        }
        if (hex.length == 6) {
          return Color(int.parse('ff$hex', radix: 16));
        }
        if (hex.length == 8) {
          // CSS/SVG 更常见的是 #RRGGBBAA，这里转换成 Flutter 的 #AARRGGBB
          final rrggbb = hex.substring(0, 6);
          final aa = hex.substring(6, 8);
          return Color(int.parse('$aa$rrggbb', radix: 16));
        }
      } catch (_) {
        // fallthrough
      }
    }

    // 简单的颜色名称映射（按需扩展）
    switch (lower) {
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
      case 'gray':
      case 'grey':
        return Colors.grey;
      default:
        return Colors.black;
    }
  }

  /// 将外部 opacity（如 fill-opacity/stop-opacity）与颜色本身 alpha 合并（乘法），而不是直接覆盖。
  // ignore: unused_element
  static Color _applyOpacityMultiplier(Color color, double opacity) {
    final safeOpacity = opacity.isFinite ? opacity.clamp(0.0, 1.0) : 1.0;
    final base = color.a;
    final combined = (base * safeOpacity).clamp(0.0, 1.0);
    return color.withValues(alpha: combined);
  }

  /// 绘制占位符内容
  // ignore: unused_element
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
