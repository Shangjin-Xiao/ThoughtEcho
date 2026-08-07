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
