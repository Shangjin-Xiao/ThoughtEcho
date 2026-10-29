import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:vector_graphics_codec/vector_graphics_codec.dart';

/// Checks compiled pattern allocations before vector_graphics can rasterize them.
///
/// Inspecting compiled commands accounts for resolved percentages, inferred
/// dimensions and repeated references without duplicating SVG parsing rules.
class BoundedSvgLoader extends SvgLoader<void> {
  const BoundedSvgLoader(this.svgContent);

  final String svgContent;

  @override
  String provideSvg(void message) => svgContent;

  @override
  Future<ByteData> loadBytes(BuildContext? context) {
    return super.loadBytes(context).then((data) {
      try {
        const codec = VectorGraphicsCodec();
        final budget = _PatternBudget();
        DecodeResponse? response;
        do {
          // Decoding pauses after image definitions; inspect all commands.
          response = codec.decode(data, budget, response: response);
        } while (!response.complete);
        return data;
      } catch (error, stackTrace) {
        // Preserve synchronous cache hits while delivering failures as Futures.
        return Future<ByteData>.error(error, stackTrace);
      }
    });
  }

  // Keep bounded loads in their own cache namespace, with content-based reuse.
  @override
  int get hashCode => Object.hash(BoundedSvgLoader, svgContent);

  @override
  bool operator ==(Object other) =>
      other is BoundedSvgLoader && other.svgContent == svgContent;
}

class _PatternBudget implements VectorGraphicsCodecListener {
  static const int _maxDimensionPixels = 2048;
  static const int _maxPatternPixels = 1024 * 1024;
  static const int _maxTotalPatternPixels = 4 * _maxPatternPixels;

  int _totalPixels = 0;

  @override
  void onPatternStart(int patternId, double x, double y, double width,
      double height, Float64List transform) {
    if (!width.isFinite ||
        !height.isFinite ||
        width <= 0 ||
        height <= 0 ||
        width > _maxDimensionPixels ||
        height > _maxDimensionPixels) {
      throw const FormatException('SVG pattern dimensions exceed safe limits');
    }

    // Match Picture.toImageSync's rounding in the pinned vector_graphics loader.
    final pixelWidth = width.round();
    final pixelHeight = height.round();
    final pixels = pixelWidth * pixelHeight;
    _totalPixels += pixels;
    if (pixelWidth == 0 ||
        pixelHeight == 0 ||
        pixels > _maxPatternPixels ||
        _totalPixels > _maxTotalPatternPixels) {
      throw const FormatException('SVG pattern pixel budget exceeded');
    }
  }

  // All other codec callbacks are void drawing operations. This inspection
  // deliberately records no pictures, decodes no images and performs no drawing.
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
