import 'dart:io';

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

  if (isDataUrl(source)) {
    final data = tryDecodeDataUrl(source);
    if (data == null) {
      return null;
    }
    return _wrapResize(MemoryImage(data), cacheWidth, cacheHeight);
  }

  final uri = Uri.tryParse(source);
  if (uri != null && uri.hasScheme) {
    if (uri.scheme == 'file') {
      final file = File.fromUri(uri);
      if (!file.existsSync()) {
        return null;
      }
      return _wrapResize(FileImage(file), cacheWidth, cacheHeight);
    }

    return _wrapResize(NetworkImage(source), cacheWidth, cacheHeight);
  }

  final file = File(source);
  if (!file.existsSync()) {
    return _wrapResize(NetworkImage(source), cacheWidth, cacheHeight);
  }

  return _wrapResize(FileImage(file), cacheWidth, cacheHeight);
}

ImageProvider _wrapResize(
  ImageProvider provider,
  int? cacheWidth,
  int? cacheHeight,
) {
  if (cacheWidth == null && cacheHeight == null) {
    return provider;
  }

  return ResizeImage(provider, width: cacheWidth, height: cacheHeight);
}
