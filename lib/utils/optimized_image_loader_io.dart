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
      // 跳过同步 existsSync 检查，让 FileImage 自行处理不存在的情况
      // 避免在 build 过程中阻塞 UI 线程
      return _wrapResize(FileImage(file), cacheWidth, cacheHeight);
    }

    return _wrapResize(NetworkImage(source), cacheWidth, cacheHeight);
  }

  final file = File(source);
  // 跳过同步 existsSync 检查，直接尝试加载
  // FileImage 内部会异步处理文件不存在的错误，由 errorBuilder 捕获
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
