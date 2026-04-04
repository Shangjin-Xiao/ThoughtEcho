part of '../database_service.dart';

/// Mixin providing cache management operations for DatabaseService.
mixin _DatabaseCacheMixin on _DatabaseServiceBase {
  /// 优化：定期清理过期缓存，而不是每次查询都清理
  /// 兼容性说明：这个变更不影响外部API，只是内部优化
  @override
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
    _filterCache.cleanExpired();
    _countCache.cleanExpired();
    logDebug('缓存清理完成');
  }

  /// 优化：清空所有缓存（在数据变更时调用）
  @override
  void _clearAllCache() {
    _filterCache.clear();
    _countCache.clear();
  }
}
