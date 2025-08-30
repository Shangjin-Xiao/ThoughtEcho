import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter/rendering.dart';
import 'package:thoughtecho/utils/app_logger.dart';
import 'svg_to_image_service.dart';

// 内在尺寸解析结果（顶层私有类）
class _SvgIntrinsicSize {
  final double? width;
  final double? height;
  const _SvgIntrinsicSize({this.width, this.height});
}

/// 使用 Overlay + Offstage + RepaintBoundary 进行真实渲染，获取与预览一致的位图。
/// 需要传入当前应用中的 BuildContext（带 Overlay）。
class SvgOffscreenRenderer {
  SvgOffscreenRenderer._();
  static final SvgOffscreenRenderer instance = SvgOffscreenRenderer._();

  _SvgIntrinsicSize _parseSvgIntrinsicSize(String svg) {
    try {
      // 匹配 <svg ... width="123" height="456" ...>
      final tagMatch =
          RegExp(r'<svg[^>]*>', caseSensitive: false).firstMatch(svg);
      if (tagMatch == null) return const _SvgIntrinsicSize();
      final tag = tagMatch.group(0)!;
      double? parseLength(String? v) {
        if (v == null) return null;
        v = v.trim();
        // 去除常见单位 px
        v = v.replaceAll(RegExp(r'px', caseSensitive: false), '');
        return double.tryParse(v);
      }

      String? attr(String name) {
        final m =
            RegExp('$name="([^"]+)"', caseSensitive: false).firstMatch(tag);
        return m?.group(1);
      }

      final w = parseLength(attr('width'));
      final h = parseLength(attr('height'));
      // 如果没有 width/height，尝试 viewBox 推导
      if (w == null || h == null) {
        final vb = attr('viewBox');
        if (vb != null) {
          final parts = vb.split(RegExp(r'[ ,]+'));
          if (parts.length == 4) {
            final vbW = double.tryParse(parts[2]);
            final vbH = double.tryParse(parts[3]);
            return _SvgIntrinsicSize(width: w ?? vbW, height: h ?? vbH);
          }
        }
      }
      return _SvgIntrinsicSize(width: w, height: h);
    } catch (_) {
      return const _SvgIntrinsicSize();
    }
  }

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
    final overlayState = Overlay.maybeOf(context, rootOverlay: true);
    if (overlayState == null) {
      throw StateError('未找到 Overlay，无法执行离屏渲染');
    }

    // 在任何异步等待之前获取设备像素比，避免异步后再次访问 context 触发 lint
    final preComputedDevicePixelRatio = devicePixelRatioAware
        ? (MediaQuery.maybeOf(context)?.devicePixelRatio ?? 1.0)
        : 1.0;

    final boundaryKey = GlobalKey();
    // 解析SVG内在尺寸（若有），用于更精确的缩放与裁剪
    final intrinsic = _parseSvgIntrinsicSize(svgContent);
    final intrinsicWidth = intrinsic.width ?? width.toDouble();
    final intrinsicHeight = intrinsic.height ?? height.toDouble();

    final boxFit = _mapFit(mode);
    // Svg widget (与预览保持一致)
    final svgWidget = SvgPicture.string(
      svgContent,
      allowDrawingOutsideViewBox: true,
      fit: boxFit,
      width: intrinsicWidth,
      height: intrinsicHeight,
    );

    // 使用与预览类似的结构：背景 -> Center/Alignment -> Svg
    Widget child = Container(
      color: background,
      width: width.toDouble(),
      height: height.toDouble(),
      alignment: Alignment.center,
      child: FittedBox(
        fit: boxFit,
        clipBehavior: Clip.hardEdge,
        child: SizedBox(
          width: intrinsicWidth,
          height: intrinsicHeight,
          child: svgWidget,
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
      // 根据设备像素比提升导出清晰度，同时限制最大像素比，防止内存暴涨
      double effectivePixelRatio = scaleFactor * preComputedDevicePixelRatio;
      // 限制最大像素比（4.0 已足够大部分需求）
      if (effectivePixelRatio > 4.0) effectivePixelRatio = 4.0;
      final image = await boundary.toImage(pixelRatio: effectivePixelRatio);
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
