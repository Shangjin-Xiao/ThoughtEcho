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
  }) async {
    final overlayState = Overlay.maybeOf(context, rootOverlay: true);
    if (overlayState == null) {
      throw StateError('未找到 Overlay，无法执行离屏渲染');
    }

    final boundaryKey = GlobalKey();
    // 使用 Overlay + RepaintBoundary 捕获

    final boxFit = _mapFit(mode);
    // Svg widget
    final svgWidget = SvgPicture.string(
      svgContent,
      allowDrawingOutsideViewBox: true,
      fit: boxFit,
    );

    Widget child = SizedBox(
      width: width.toDouble(),
      height: height.toDouble(),
      child: DecoratedBox(
        decoration: BoxDecoration(color: background),
        child: FittedBox(
          fit: boxFit,
          clipBehavior: Clip.hardEdge,
          child: SizedBox(
            width: width.toDouble(),
            height: height.toDouble(),
            child: svgWidget,
          ),
        ),
      ),
    );

    child = RepaintBoundary(key: boundaryKey, child: child);

    // 放到屏幕外（或用 Offstage）
    final entry = OverlayEntry(
      opaque: false,
      builder: (_) => Offstage(
        offstage: true,
        child: Center(child: child),
      ),
    );

    overlayState.insert(entry);

    void cleanup() {
      try {
        entry.remove();
      } catch (_) {}
    }

    // 等待两帧，确保解析 + 布局 + 绘制完成
    await _pumpFrames(count: 2);
    try {
      final boundary = boundaryKey.currentContext?.findRenderObject()
          as RenderRepaintBoundary?;
      if (boundary == null) {
        throw StateError('未获取到 RenderRepaintBoundary');
      }
      final image = await boundary.toImage(pixelRatio: scaleFactor);
      final byteData = await image.toByteData(format: format);
      if (byteData == null) {
        throw StateError('无法获取图片字节');
      }
      cleanup();
      return byteData.buffer.asUint8List();
    } catch (e, st) {
      cleanup();
      AppLogger.e('离屏渲染失败: $e',
          error: e, stackTrace: st, source: 'SvgOffscreenRenderer');
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
