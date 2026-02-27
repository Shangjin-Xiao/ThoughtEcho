import 'dart:typed_data';

import 'package:flutter/widgets.dart';

import 'optimized_image_loader_base.dart';
import 'optimized_image_loader_stub.dart'
    if (dart.library.io) 'optimized_image_loader_io.dart'
    as impl;

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

bool isInlineDataImage(String source) => isDataUrl(source);

Uint8List? decodeInlineImageBytes(String source) => tryDecodeDataUrl(source);
