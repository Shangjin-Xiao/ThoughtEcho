part of '../database_service.dart';

/// Mixin providing cache management operations for DatabaseService.
mixin _DatabaseCacheMixin on _DatabaseServiceBase {
  /// 优化：定期清理过期缓存，而不是每次查询都清理
  /// 兼容性说明：这个变更不影响外部API，只是内部优化
  void _scheduleCacheCleanup() {
    // 如果距离上次清理不到1分钟，跳过
    if (DateTime.now().difference(_lastCacheCleanup).inMinutes < 1) {
      return;
    }

    _cacheCleanupTimer?.cancel();
    _cacheCleanupTimer = Timer(const Duration(seconds: 30), () {
      _cleanExpiredCache();
      _lastCacheCleanup = DateTime.now();
    });
  }

  /// 优化：检查并清理过期缓存
  void _cleanExpiredCache() {
    final now = DateTime.now();
    final expiredKeys = <String>[];
    final expiredCountKeys = <String>[];

    // 清理查询缓存
    for (final entry in _cacheTimestamps.entries) {
      if (now.difference(entry.value) > _cacheExpiration) {
        expiredKeys.add(entry.key);
      }
    }

    for (final key in expiredKeys) {
      _filterCache.remove(key);
      _cacheTimestamps.remove(key);
      _cacheAccessTimes.remove(key); // 同时清理访问时间
    }

    // 清理计数缓存
    for (final entry in _countCacheTimestamps.entries) {
      if (now.difference(entry.value) > _cacheExpiration) {
        expiredCountKeys.add(entry.key);
      }
    }

    for (final key in expiredCountKeys) {
      _countCache.remove(key);
      _countCacheTimestamps.remove(key);
    }

    logDebug(
      '缓存清理完成，移除 ${expiredKeys.length} 个查询缓存和 ${expiredCountKeys.length} 个计数缓存',
    );
  }

  /// 优化：清空所有缓存（在数据变更时调用）
  void _clearAllCache() {
    _filterCache.clear();
    _cacheTimestamps.clear();
    _countCache.clear();
    _countCacheTimestamps.clear();
  }
}
