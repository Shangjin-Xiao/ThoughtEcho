import 'package:flutter/widgets.dart';

import 'optimized_image_loader_base.dart';

ImageProvider? createOptimizedImageProvider(
  String source, {
  int? cacheWidth,
  int? cacheHeight,
}) {
  if (source.isEmpty) {
    return null;
  }

  ImageProvider provider;

  if (isDataUrl(source)) {
    final data = tryDecodeDataUrl(source);
    if (data == null) {
      return null;
    }
    provider = MemoryImage(data);
  } else {
    provider = NetworkImage(source);
  }

  return wrapWithDecodeLimit(provider, cacheWidth, cacheHeight);
}
