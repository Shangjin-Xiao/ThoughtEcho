import 'dart:typed_data';

import 'package:flutter/widgets.dart';

import 'optimized_image_loader_base.dart';
import 'optimized_image_loader_stub.dart'
    if (dart.library.io) 'optimized_image_loader_io.dart' as impl;

ImageProvider? createOptimizedImageProvider(
  String source, {
  int? cacheWidth,
  int? cacheHeight,
}) {
  return impl.createOptimizedImageProvider(
    source,
    cacheWidth: cacheWidth,
    cacheHeight: cacheHeight,
  );
}

/// 把逻辑显示尺寸换算成解码用的设备像素尺寸，见 [decodeDimensionFor]。
int? decodeSizeFor(double logicalSize, double pixelRatio) =>
    decodeDimensionFor(logicalSize, pixelRatio);

/// 由解码宽度推出总像素预算下的高度上限，见 [decodeHeightBudgetFor]。
int? decodeHeightBudget(int? decodeWidth) => decodeHeightBudgetFor(decodeWidth);

/// 全屏预览一个维度的解码上限，见 [previewDecodeDimensionFor]。
int? previewDecodeSizeFor(double logicalSize, double pixelRatio) =>
    previewDecodeDimensionFor(logicalSize, pixelRatio);

bool isInlineDataImage(String source) => isDataUrl(source);

Uint8List? decodeInlineImageBytes(String source) => tryDecodeDataUrl(source);
