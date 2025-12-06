import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter/rendering.dart';
import 'package:thoughtecho/utils/app_logger.dart';
import 'svg_to_image_service.dart';

/// 使用 Overlay + Offstage + RepaintBoundary 进行真实渲染，获取与预览一致的位图。
/// 需要传入当前应用中的 BuildContext（带 Overlay）。
class SvgOffscreenRenderer {
  SvgOffscreenRenderer._();
  static final SvgOffscreenRenderer instance = SvgOffscreenRenderer._();

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
    bool devicePixelRatioAware = true,
  }) async {
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
    var overlayState = Overlay.maybeOf(context, rootOverlay: false) ??
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

    AppLogger.d('SVG渲染目标尺寸: ${width}x$height', source: 'SvgOffscreenRenderer');

    final boxFit = _mapFit(mode);

    // 创建SVG widget，使用与预览完全一致的配置
    // 直接设置width和height，让SvgPicture处理缩放，与SvgCardWidget保持一致
    final svgWidget = SvgPicture.string(
      svgContent,
      width: width.toDouble(),
      height: height.toDouble(),
      fit: boxFit,
      allowDrawingOutsideViewBox: false,
      placeholderBuilder: (context) => Container(
        color: background,
        width: width.toDouble(),
        height: height.toDouble(),
      ),
    );

    // 简化布局结构，移除复杂的FittedBox嵌套，直接使用Container包裹
    final captureContent = Container(
      color: background,
      width: width.toDouble(),
      height: height.toDouble(),
      alignment: Alignment.center,
      child: svgWidget,
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

    void cleanup() {
      try {
        entry.remove();
        entry.dispose();
      } catch (e) {
        AppLogger.w('清理OverlayEntry失败: $e', source: 'SvgOffscreenRenderer');
      }
    }

    try {
      // 等待多帧，确保SVG完全解析和渲染
      // SVG解析通常需要2-3帧：布局 -> 解析 -> 绘制
      // 增加到8帧，并添加额外延迟确保复杂SVG完全渲染
      await _pumpFrames(count: 8);

      // 额外延迟确保渲染管线完成
      await Future.delayed(const Duration(milliseconds: 300));

      final boundary = boundaryKey.currentContext?.findRenderObject()
          as RenderRepaintBoundary?;
      if (boundary == null) {
        throw StateError('未获取到 RenderRepaintBoundary，SVG可能未完成渲染');
      }

      // 验证boundary已经完成布局
      if (!boundary.hasSize || boundary.size.isEmpty) {
        AppLogger.w(
          'RenderRepaintBoundary尺寸异常: ${boundary.hasSize ? boundary.size : "无尺寸"}',
          source: 'SvgOffscreenRenderer',
        );
        throw StateError('RenderRepaintBoundary尺寸异常，SVG可能未完成布局');
      }

      AppLogger.d(
        'RenderRepaintBoundary已就绪: ${boundary.size}',
        source: 'SvgOffscreenRenderer',
      );

      // 根据设备像素比提升导出清晰度，同时限制最大像素比，防止内存暴涨
      double effectivePixelRatio = scaleFactor * preComputedDevicePixelRatio;
      // 限制最大像素比（4.0 已足够大部分需求，避免OOM）
      if (effectivePixelRatio > 4.0) {
        AppLogger.w(
          '像素比过高(${effectivePixelRatio.toStringAsFixed(1)})，限制为4.0',
          source: 'SvgOffscreenRenderer',
        );
        effectivePixelRatio = 4.0;
      }

      final image = await boundary.toImage(pixelRatio: effectivePixelRatio);
      final byteData = await image.toByteData(format: format);
      if (byteData == null) {
        throw StateError('无法获取图片字节数据');
      }

      final bytes = byteData.buffer.asUint8List();

      // 清理资源
      image.dispose();
      cleanup();

      AppLogger.d(
        'SVG离屏渲染成功: ${width}x$height, 像素比: ${effectivePixelRatio.toStringAsFixed(1)}, 大小: ${bytes.length} bytes',
        source: 'SvgOffscreenRenderer',
      );

      return bytes;
    } catch (e, st) {
      cleanup();
      AppLogger.e(
        '离屏渲染失败: $e',
        error: e,
        stackTrace: st,
        source: 'SvgOffscreenRenderer',
      );
      rethrow;
    }
  }

  Future<void> _pumpFrames({int count = 1}) async {
    for (var i = 0; i < count; i++) {
      final c = Completer<void>();
      WidgetsBinding.instance.addPostFrameCallback((_) => c.complete());
      await Future.delayed(Duration.zero);
      await c.future;
    }
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
