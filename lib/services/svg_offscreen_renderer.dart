import 'dart:async';
import 'package:flutter/foundation.dart';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:thoughtecho/utils/app_logger.dart';
import 'svg_to_image_service.dart';
import '../utils/bounded_svg_loader.dart';

/// 使用 Overlay + Offstage + RepaintBoundary 进行真实渲染，获取与预览一致的位图。
/// 需要传入当前应用中的 BuildContext（带 Overlay）。
class SvgOffscreenRenderer {
  SvgOffscreenRenderer._();
  static final SvgOffscreenRenderer instance = SvgOffscreenRenderer._();

  static const int _maxReadyFrames = 12;

  Future<Uint8List> renderSvgString(
    String svgContent, {
    required BuildContext context,
    required int width,
    required int height,
    double scaleFactor = 1.0,
    required Color background,
    ExportRenderMode mode = ExportRenderMode.contain,
    ui.ImageByteFormat format = ui.ImageByteFormat.png,
    Duration timeout = const Duration(seconds: 10),
    bool devicePixelRatioAware = false,
    double borderRadius = 0,
    BytesLoader? loaderOverride,
  }) async {
    if (width <= 0 || height <= 0) {
      throw ArgumentError('图片尺寸必须大于0');
    }

    // 检查context是否有效
    if (context is Element) {
      if (!context.mounted) {
        AppLogger.w(
          'BuildContext已失效（Element未mounted）',
          source: 'SvgOffscreenRenderer',
        );
        throw StateError('BuildContext已失效（未mounted），无法执行离屏渲染');
      }
    }

    // 使用rootOverlay=false，尝试获取最近的Overlay
    final overlayState = Overlay.maybeOf(context, rootOverlay: false) ??
        Overlay.maybeOf(context, rootOverlay: true);

    if (overlayState == null) {
      AppLogger.w(
        '未找到Overlay（rootOverlay=false和true都尝试过）',
        source: 'SvgOffscreenRenderer',
      );
      throw StateError('未找到 Overlay，无法执行离屏渲染');
    }

    // 检查overlay是否已mounted
    if (!overlayState.mounted) {
      AppLogger.w('Overlay未mounted', source: 'SvgOffscreenRenderer');
      throw StateError('Overlay未mounted，无法执行离屏渲染');
    }

    AppLogger.d('Overlay检查通过，准备离屏渲染', source: 'SvgOffscreenRenderer');

    // 在任何异步等待之前获取设备像素比，避免异步后再次访问 context 触发 lint
    final preComputedDevicePixelRatio = devicePixelRatioAware
        ? (MediaQuery.maybeOf(context)?.devicePixelRatio ?? 1.0)
        : 1.0;

    final boundaryKey = GlobalKey();
    final placeholderKey = GlobalKey();
    var isVectorReady = false;
    Object? svgLoadError;
    StackTrace? svgLoadStackTrace;

    AppLogger.d('SVG渲染目标尺寸: ${width}x$height', source: 'SvgOffscreenRenderer');

    final boxFit = _mapFit(mode);
    final loader = loaderOverride ?? BoundedSvgLoader(svgContent);
    final preloadFuture = loader.loadBytes(context);
    unawaited(preloadFuture.then((_) {}, onError: (_) {}));

    // 创建SVG widget，使用与预览完全一致的配置
    // 结合 placeholderKey、imageBuilder 与 errorBuilder，精确检测解码与绘制就绪态
    final svgWidget = SvgPicture(
      loader,
      width: width.toDouble(),
      height: height.toDouble(),
      fit: boxFit,
      allowDrawingOutsideViewBox: false,
      placeholderBuilder: (context) {
        isVectorReady = false;
        return Container(
          key: placeholderKey,
          color: background,
          width: width.toDouble(),
          height: height.toDouble(),
        );
      },
      imageBuilder: (context, child) {
        isVectorReady = true;
        return child;
      },
      errorBuilder: (context, error, stackTrace) {
        svgLoadError = error;
        svgLoadStackTrace = stackTrace;
        AppLogger.w(
          'SVG矢量图解码失败: $error',
          error: error,
          stackTrace: stackTrace,
          source: 'SvgOffscreenRenderer',
        );
        return const SizedBox.shrink();
      },
    );

    // 简化布局结构，移除复杂的FittedBox嵌套，直接使用Container包裹
    // 如果指定了圆角，则使用ClipRRect裁剪
    final Widget contentWidget = borderRadius > 0
        ? ClipRRect(
            borderRadius: BorderRadius.circular(borderRadius),
            child: svgWidget,
          )
        : svgWidget;

    final captureContent = Container(
      color: background,
      width: width.toDouble(),
      height: height.toDouble(),
      alignment: Alignment.center,
      child: contentWidget,
    );

    final mediaQueryData = MediaQuery.maybeOf(context);
    TextDirection resolvedTextDirection;
    try {
      resolvedTextDirection = Directionality.of(context);
    } catch (_) {
      resolvedTextDirection = TextDirection.ltr;
    }
    ThemeData? themeData;
    try {
      themeData = Theme.of(context);
    } catch (_) {
      themeData = null;
    }

    final repaintBoundary = RepaintBoundary(
      key: boundaryKey,
      child: captureContent,
    );

    final horizontalOffset = width.toDouble() + 200;
    final verticalOffset = height.toDouble() + 200;

    // 放到屏幕外，避免闪烁，同时保持渲染链路
    final entry = OverlayEntry(
      opaque: false,
      builder: (_) {
        Widget overlayChild = IgnorePointer(
          ignoring: true,
          child: Stack(
            clipBehavior: Clip.none,
            fit: StackFit.expand,
            children: [
              Positioned(
                left: -horizontalOffset,
                top: -verticalOffset,
                width: width.toDouble(),
                height: height.toDouble(),
                child: repaintBoundary,
              ),
            ],
          ),
        );

        if (themeData != null) {
          overlayChild = Theme(data: themeData, child: overlayChild);
        }

        overlayChild = Directionality(
          textDirection: resolvedTextDirection,
          child: overlayChild,
        );

        if (mediaQueryData != null) {
          overlayChild = MediaQuery(data: mediaQueryData, child: overlayChild);
        }

        return overlayChild;
      },
    );

    overlayState.insert(entry);

    var cleanedUp = false;
    void cleanup() {
      if (cleanedUp) return;
      cleanedUp = true;
      try {
        entry.remove();
        entry.dispose();
        final binding = WidgetsBinding.instance;
        if (binding.platformDispatcher.onDrawFrame == null &&
            binding.schedulerPhase == SchedulerPhase.idle &&
            binding.hasScheduledFrame) {
          binding.handleBeginFrame(null);
          binding.handleDrawFrame();
        }
      } catch (e) {
        AppLogger.w('清理OverlayEntry失败: $e', source: 'SvgOffscreenRenderer');
      }
    }

    try {
      final stopwatch = Stopwatch()..start();
      await preloadFuture.timeout(timeout);

      RenderRepaintBoundary? readyBoundary;
      var postDecodeFrames = 0;

      while (postDecodeFrames < _maxReadyFrames) {
        final remaining = timeout - stopwatch.elapsed;
        if (remaining <= Duration.zero) {
          throw TimeoutException('SVG离屏渲染等待帧就绪超时', timeout);
        }

        await _waitForNextFrame(remaining);

        if (svgLoadError != null) {
          Error.throwWithStackTrace(
            svgLoadError!,
            svgLoadStackTrace ?? StackTrace.current,
          );
        }

        // 若矢量图元仍在异步解码（占位子树仍挂载或图元尚未就绪），继续按壁钟超时等待而不消耗绘制稳定帧配额
        if (!isVectorReady || placeholderKey.currentContext != null) {
          final afterFrameRemaining = timeout - stopwatch.elapsed;
          if (afterFrameRemaining <= Duration.zero) {
            throw TimeoutException('SVG离屏渲染等待矢量解码超时', timeout);
          }
          final backoff = afterFrameRemaining < const Duration(milliseconds: 8)
              ? afterFrameRemaining
              : const Duration(milliseconds: 8);
          await Future<void>.delayed(backoff);
          continue;
        }

        postDecodeFrames++;
        final candidate = boundaryKey.currentContext?.findRenderObject()
            as RenderRepaintBoundary?;
        final isBoundaryReady = candidate != null &&
            candidate.attached &&
            candidate.hasSize &&
            !candidate.size.isEmpty &&
            (!kDebugMode ||
                (!candidate.debugNeedsLayout && !candidate.debugNeedsPaint));

        if (isBoundaryReady) {
          readyBoundary = candidate;
          break;
        }

        await Future<void>.delayed(Duration.zero);
      }

      if (svgLoadError != null) {
        Error.throwWithStackTrace(
          svgLoadError!,
          svgLoadStackTrace ?? StackTrace.current,
        );
      }

      final boundary = readyBoundary;
      if (boundary == null) {
        final lastCandidate = boundaryKey.currentContext?.findRenderObject()
            as RenderRepaintBoundary?;
        AppLogger.w(
          'SVG离屏渲染在 $_maxReadyFrames 帧内未就绪: '
          'boundary=${lastCandidate != null}, '
          'hasSize=${lastCandidate?.hasSize ?? false}, '
          'placeholderMounted=${placeholderKey.currentContext != null}',
          source: 'SvgOffscreenRenderer',
        );
        throw StateError('SVG离屏子树在最大等待帧数内未完成解码与绘制');
      }

      AppLogger.d(
        'RenderRepaintBoundary已就绪: ${boundary.size}',
        source: 'SvgOffscreenRenderer',
      );

      final effectivePixelRatio = SvgToImageService.resolveEffectivePixelRatio(
        width: width,
        height: height,
        scaleFactor: scaleFactor,
        devicePixelRatio: preComputedDevicePixelRatio,
        logSource: 'SvgOffscreenRenderer',
      );

      final image = await SvgToImageService.captureBoundaryImage(
        boundary,
        pixelRatio: effectivePixelRatio,
        timeout: timeout - stopwatch.elapsed,
      );
      final bytes = await SvgToImageService.exportUiImageBytes(
        image,
        format: format,
        onImageRead: cleanup,
      );

      AppLogger.d(
        'SVG离屏渲染成功: ${width}x$height, 像素比: ${effectivePixelRatio.toStringAsFixed(1)}, 大小: ${bytes.length} bytes',
        source: 'SvgOffscreenRenderer',
      );

      return bytes;
    } catch (e, st) {
      AppLogger.e(
        '离屏渲染失败: $e',
        error: e,
        stackTrace: st,
        source: 'SvgOffscreenRenderer',
      );
      rethrow;
    } finally {
      cleanup();
    }
  }

  Future<void> _waitForNextFrame(Duration timeout) async {
    final binding = WidgetsBinding.instance;
    binding.ensureVisualUpdate();
    final frameFuture = binding.endOfFrame;
    if (binding.platformDispatcher.onDrawFrame == null &&
        binding.schedulerPhase == SchedulerPhase.idle) {
      binding.handleBeginFrame(null);
      binding.handleDrawFrame();
    }
    await frameFuture.timeout(timeout);
  }

  BoxFit _mapFit(ExportRenderMode mode) {
    switch (mode) {
      case ExportRenderMode.contain:
        return BoxFit.contain;
      case ExportRenderMode.cover:
        return BoxFit.cover;
      case ExportRenderMode.stretch:
        return BoxFit.fill;
    }
  }
}
