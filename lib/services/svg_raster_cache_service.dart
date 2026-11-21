import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:thoughtecho/utils/app_logger.dart';

/// SVG 光栅化结果的字节缓存。
///
/// **和 Flutter 的图片缓存没有任何关系**——它不碰
/// `PaintingBinding.instance.imageCache`，只缓存 [SvgToImageService] 把 SVG 渲染成
/// PNG/位图后的字节，键覆盖 SVG 内容指纹、目标宽高、缩放比、渲染模式、背景色、圆角与编码格式。
///
/// 旧名字叫 `ImageCacheService`，排查记录页图片反复重解码时很容易先翻到这里，
/// 白绕一圈——真正管解码结果淘汰的是 `PaintingBinding.instance.imageCache`，
/// 上限在 `main.dart` 的 `_configureImageCache` 里设定。
class SvgRasterCacheService {
  static final SvgRasterCacheService _instance =
      SvgRasterCacheService._internal();
  factory SvgRasterCacheService() => _instance;
  SvgRasterCacheService._internal();

  // 内存缓存
  final Map<String, Uint8List> _memoryCache = {};
  final Map<String, DateTime> _cacheTimestamps = {};

  // 缓存配置
  static const int maxCacheSize = 20; // 最大缓存条目数
  static const Duration cacheExpiry = Duration(hours: 1); // 缓存过期时间
  static const int maxImageSize = 12 * 1024 * 1024; // 12 MiB 单张图片上限（容纳纸纹高清卡片）
  static const int maxTotalCacheBytes = 50 * 1024 * 1024; // 50 MiB 总缓存字节预算

  int get _totalCachedBytes => _memoryCache.values.fold<int>(
        0,
        (sum, bytes) => sum + bytes.length,
      );

  /// 获取缓存的图片
  Uint8List? getCachedImage(String key) {
    try {
      // 检查缓存是否存在
      if (!_memoryCache.containsKey(key)) {
        return null;
      }

      // 检查缓存是否过期
      final timestamp = _cacheTimestamps[key];
      if (timestamp == null ||
          DateTime.now().difference(timestamp) > cacheExpiry) {
        _removeCacheEntry(key);
        return null;
      }

      // 缓存命中

      return _memoryCache[key];
    } catch (e) {
      return null;
    }
  }

  /// 缓存图片
  void cacheImage(String key, Uint8List imageBytes) {
    try {
      // 检查单张图片大小上限
      if (imageBytes.length > maxImageSize) {
        AppLogger.d(
          '跳过缓存超限图片: key=$key, size=${imageBytes.length} bytes (上限 $maxImageSize bytes)',
          source: 'SvgRasterCacheService',
        );
        return;
      }

      // 清理过期缓存
      _cleanExpiredCache();

      // 若同一键已存在，先移除旧值以准确核算容量
      if (_memoryCache.containsKey(key)) {
        _removeCacheEntry(key);
      }

      // 按条目上限与 50 MiB 总字节预算淘汰最旧条目
      while (_memoryCache.isNotEmpty &&
          (_memoryCache.length >= maxCacheSize ||
              _totalCachedBytes + imageBytes.length > maxTotalCacheBytes)) {
        _removeOldestEntry();
      }

      if (imageBytes.length > maxTotalCacheBytes) {
        AppLogger.d(
          '跳过缓存超出总预算图片: key=$key, size=${imageBytes.length} bytes',
          source: 'SvgRasterCacheService',
        );
        return;
      }

      // 添加到缓存
      _memoryCache[key] = imageBytes;
      _cacheTimestamps[key] = DateTime.now();
    } catch (e) {
      // 缓存失败，忽略错误
    }
  }

  /// 生成缓存键
  static String generateCacheKey(
    String svgContent,
    int width,
    int height,
    ui.ImageByteFormat format, {
    double scaleFactor = 1.0,
    String renderMode = 'contain',
    ui.Color backgroundColor = const ui.Color(0x00000000),
    double borderRadius = 0.0,
  }) {
    final contentHash = svgContent.hashCode;
    final contentLength = svgContent.length;
    final normalizedScale =
        (scaleFactor.isFinite && scaleFactor > 0) ? scaleFactor : 1.0;
    final normalizedRadius =
        (borderRadius.isFinite && borderRadius > 0) ? borderRadius : 0.0;
    final bgArgb = backgroundColor.toARGB32().toRadixString(16).padLeft(8, '0');
    return '${contentHash}_${contentLength}_${width}x${height}_${format.name}'
        '_s${normalizedScale}_m${renderMode}_bg${bgArgb}_r$normalizedRadius';
  }

  /// 清理过期缓存
  void _cleanExpiredCache() {
    final now = DateTime.now();
    final expiredKeys = <String>[];

    for (final entry in _cacheTimestamps.entries) {
      if (now.difference(entry.value) > cacheExpiry) {
        expiredKeys.add(entry.key);
      }
    }

    for (final key in expiredKeys) {
      _removeCacheEntry(key);
    }
  }

  /// 移除最旧的缓存条目
  void _removeOldestEntry() {
    if (_cacheTimestamps.isEmpty) return;

    String? oldestKey;
    DateTime? oldestTime;

    for (final entry in _cacheTimestamps.entries) {
      if (oldestTime == null || entry.value.isBefore(oldestTime)) {
        oldestTime = entry.value;
        oldestKey = entry.key;
      }
    }

    if (oldestKey != null) {
      _removeCacheEntry(oldestKey);
      if (kDebugMode) {
        AppLogger.d('移除最旧缓存条目: $oldestKey', source: 'SvgRasterCacheService');
      }
    }
  }

  /// 移除缓存条目
  void _removeCacheEntry(String key) {
    _memoryCache.remove(key);
    _cacheTimestamps.remove(key);
  }

  /// 清空所有缓存
  void clearCache() {
    _memoryCache.clear();
    _cacheTimestamps.clear();
    if (kDebugMode) {
      AppLogger.d('已清空所有图片缓存', source: 'SvgRasterCacheService');
    }
  }

  /// 获取缓存统计信息
  Map<String, dynamic> getCacheStats() {
    final totalSize = _memoryCache.values.fold<int>(
      0,
      (sum, bytes) => sum + bytes.length,
    );

    return {
      'count': _memoryCache.length,
      'totalSize': totalSize,
      'maxSize': maxCacheSize,
      'averageSize':
          _memoryCache.isNotEmpty ? totalSize / _memoryCache.length : 0,
    };
  }

  /// 预热缓存（可选）
  Future<void> preloadImages(List<String> svgContents) async {
    AppLogger.i(
      '开始预热图片缓存: ${svgContents.length} 个SVG',
      source: 'SvgRasterCacheService',
    );

    for (int i = 0; i < svgContents.length && i < maxCacheSize; i++) {
      try {
        final key = generateCacheKey(
          svgContents[i],
          400,
          600,
          ui.ImageByteFormat.png,
        );

        // 如果已经缓存，跳过
        if (_memoryCache.containsKey(key)) {
          continue;
        }

        // 这里可以添加预加载逻辑
        // 由于需要异步转换，暂时跳过实际预加载
      } catch (e) {
        AppLogger.e('预热缓存失败: $e', error: e, source: 'SvgRasterCacheService');
      }
    }
  }

  /// 检查内存使用情况
  bool isMemoryUsageHigh() {
    final stats = getCacheStats();
    final totalSize = stats['totalSize'] as int;

    // 如果总缓存大小超过预算上限，认为内存使用过高
    return totalSize > maxTotalCacheBytes;
  }

  /// 智能清理缓存
  void smartCleanup() {
    if (isMemoryUsageHigh()) {
      // 清理一半的缓存
      final targetSize = _memoryCache.length ~/ 2;
      final keysToRemove = <String>[];

      // 按时间戳排序，移除最旧的
      final sortedEntries = _cacheTimestamps.entries.toList()
        ..sort((a, b) => a.value.compareTo(b.value));

      for (int i = 0; i < targetSize && i < sortedEntries.length; i++) {
        keysToRemove.add(sortedEntries[i].key);
      }

      for (final key in keysToRemove) {
        _removeCacheEntry(key);
      }

      AppLogger.i(
        '智能清理缓存: 移除 ${keysToRemove.length} 个条目',
        source: 'SvgRasterCacheService',
      );
    }
  }
}
