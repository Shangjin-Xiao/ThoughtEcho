import 'dart:typed_data';

import 'package:flutter/widgets.dart';

/// 按解码上限包装 provider。
///
/// 同时给了宽高时必须用 [ResizeImagePolicy.fit]（等比缩放到框内），
/// `ResizeImage` 默认的 `exact` 会把图拉成给定的宽高、直接变形。
/// 只给一个维度时另一维本就按比例推算，沿用默认策略即可。
ImageProvider wrapWithDecodeLimit(
  ImageProvider provider,
  int? cacheWidth,
  int? cacheHeight,
) {
  if (cacheWidth == null && cacheHeight == null) {
    return provider;
  }

  return ResizeImage(
    provider,
    width: cacheWidth,
    height: cacheHeight,
    policy: (cacheWidth != null && cacheHeight != null)
        ? ResizeImagePolicy.fit
        : ResizeImagePolicy.exact,
  );
}

/// 解码尺寸的下限与上限（设备像素）。
///
/// 下限避免极窄容器把图解成马赛克；上限避免超大图把单张解码撑爆。
const int minDecodeDimension = 160;
const int maxDecodeDimension = 2048;

/// 把「逻辑显示尺寸 × 像素比」换算成解码用的设备像素尺寸。
///
/// 尺寸非法（0、负数、NaN、无穷）时返回 null，表示不设解码上限、按原图解。
int? decodeDimensionFor(double logicalSize, double pixelRatio) {
  if (!logicalSize.isFinite || logicalSize <= 0) {
    return null;
  }

  final double devicePixels = logicalSize * pixelRatio;
  if (!devicePixels.isFinite || devicePixels <= 0) {
    return null;
  }

  if (devicePixels < minDecodeDimension) return minDecodeDimension;
  if (devicePixels > maxDecodeDimension) return maxDecodeDimension;
  return devicePixels.round();
}

bool isDataUrl(String source) => source.startsWith('data:');

Uint8List? tryDecodeDataUrl(String source) {
  if (!isDataUrl(source)) {
    return null;
  }

  try {
    final uri = Uri.parse(source);
    if (!uri.isScheme('data')) {
      return null;
    }

    final data = uri.data;
    if (data == null) {
      return null;
    }

    return data.contentAsBytes();
  } catch (_) {
    return null;
  }
}
