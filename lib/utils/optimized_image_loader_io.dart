import 'dart:io';

import 'package:flutter/widgets.dart';

import 'optimized_image_loader_base.dart';
import 'safe_file_image.dart';

ImageProvider? createOptimizedImageProvider(
  String source, {
  int? cacheWidth,
  int? cacheHeight,
}) {
  if (source.isEmpty) {
    return null;
  }

  final bytes = tryDecodeAnyImageBytes(source);
  if (bytes != null) {
    return _wrapResize(MemoryImage(bytes), cacheWidth, cacheHeight);
  }

  if (source.startsWith('assets/')) {
    return _wrapResize(AssetImage(source), cacheWidth, cacheHeight);
  }

  final uri = Uri.tryParse(source);
  if (uri != null && uri.hasScheme) {
    if (uri.scheme == 'file') {
      final file = File.fromUri(uri);
      // 跳过同步 existsSync 检查，让 FileImage 自行处理不存在的情况
      // 避免在 build 过程中阻塞 UI 线程
      return _wrapResize(SafeFileImage(file), cacheWidth, cacheHeight);
    }

    return _wrapResize(NetworkImage(source), cacheWidth, cacheHeight);
  }

  final file = File(source);
  // 跳过同步 existsSync 检查，直接尝试加载
  // SafeFileImage 异步检查文件是否存在，缺失时抛出 MissingMediaFileException，
  // 由 errorBuilder 显示占位图，并按路径去重上报（见 MissingMediaFileReporter）
  return _wrapResize(SafeFileImage(file), cacheWidth, cacheHeight);
}

ImageProvider _wrapResize(
  ImageProvider provider,
  int? cacheWidth,
  int? cacheHeight,
) =>
    wrapWithDecodeLimit(provider, cacheWidth, cacheHeight);
