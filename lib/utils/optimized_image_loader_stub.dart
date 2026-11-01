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

  final bytes = tryDecodeAnyImageBytes(source);
  if (bytes != null) {
    provider = MemoryImage(bytes);
  } else if (source.startsWith('assets/')) {
    provider = AssetImage(source);
  } else {
    provider = NetworkImage(source);
  }

  return wrapWithDecodeLimit(provider, cacheWidth, cacheHeight);
}
