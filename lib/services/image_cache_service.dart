import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:thoughtecho/utils/app_logger.dart';

/// 图片缓存服务
class ImageCacheService {
  static final ImageCacheService _instance = ImageCacheService._internal();
  factory ImageCacheService() => _instance;
  ImageCacheService._internal();

  // 内存缓存
  final Map<String, Uint8List> _memoryCache = {};
  final Map<String, DateTime> _cacheTimestamps = {};

  // 缓存配置
  static const int maxCacheSize = 50; // 最大缓存数量
  static const Duration cacheExpiry = Duration(hours: 1); // 缓存过期时间
  static const int maxImageSize = 5 * 1024 * 1024; // 5MB 单个图片最大尺寸

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
      // 检查图片大小
      if (imageBytes.length > maxImageSize) {
        return;
      }

      // 清理过期缓存
      _cleanExpiredCache();

      // 如果缓存已满，移除最旧的条目
      if (_memoryCache.length >= maxCacheSize) {
        _removeOldestEntry();
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
    ui.ImageByteFormat format,
  ) {
    // 使用SVG内容的哈希值和参数生成唯一键
    final contentHash = svgContent.hashCode;
    return '${contentHash}_${width}x${height}_${format.name}';
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
        print('移除最旧缓存条目: $oldestKey');
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
      print('已清空所有图片缓存');
    }
  }

  /// 获取缓存统计信息
  Map<String, dynamic> getCacheStats() {
    final totalSize =
        _memoryCache.values.fold<int>(0, (sum, bytes) => sum + bytes.length);

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
    AppLogger.i('开始预热图片缓存: ${svgContents.length} 个SVG',
        source: 'ImageCacheService');

    for (int i = 0; i < svgContents.length && i < maxCacheSize; i++) {
      try {
        final key =
            generateCacheKey(svgContents[i], 400, 600, ui.ImageByteFormat.png);

        // 如果已经缓存，跳过
        if (_memoryCache.containsKey(key)) {
          continue;
        }

        // 这里可以添加预加载逻辑
        // 由于需要异步转换，暂时跳过实际预加载
      } catch (e) {
        AppLogger.e('预热缓存失败: $e', error: e, source: 'ImageCacheService');
      }
    }
  }

  /// 检查内存使用情况
  bool isMemoryUsageHigh() {
    final stats = getCacheStats();
    final totalSize = stats['totalSize'] as int;

    // 如果总缓存大小超过50MB，认为内存使用过高
    return totalSize > 50 * 1024 * 1024;
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

      AppLogger.i('智能清理缓存: 移除 ${keysToRemove.length} 个条目',
          source: 'ImageCacheService');
    }
  }
}
