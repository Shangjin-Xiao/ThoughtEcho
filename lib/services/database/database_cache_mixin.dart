part of '../database_service.dart';

/// Mixin providing cache management operations for DatabaseService.
mixin _DatabaseCacheMixin on ChangeNotifier {
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

  /// 优化：生成更可靠的缓存键，避免冲突
  String _generateCacheKey({
    List<String>? tagIds,
    String? categoryId,
    String? searchQuery,
    String orderBy = 'date DESC',
    List<String>? selectedWeathers,
    List<String>? selectedDayPeriods,
  }) {
    // 使用更安全的分隔符避免冲突
    final tagKey = tagIds?.join('|') ?? 'NULL';
    final categoryKey = categoryId ?? 'NULL';
    final searchKey = searchQuery ?? 'NULL';
    final weatherKey = selectedWeathers?.join('|') ?? 'NULL';
    final dayPeriodKey = selectedDayPeriods?.join('|') ?? 'NULL';

    // 使用不同的分隔符确保唯一性
    return '$tagKey@@$categoryKey@@$searchKey@@$orderBy@@$weatherKey@@$dayPeriodKey';
  }

  /// 修复：从缓存中获取数据，更新LRU访问时间
  List<Quote>? _getFromCache(String cacheKey, int offset, int limit) {
    final cachedData = _filterCache[cacheKey];
    if (cachedData == null || cachedData.isEmpty) {
      return null;
    }

    // 更新LRU访问时间和缓存命中统计
    _cacheAccessTimes[cacheKey] = DateTime.now();
    _healthService.recordCacheHit();

    // 优化：改进边界检查逻辑
    if (offset >= cachedData.length) {
      // 如果偏移量超过缓存数据长度，返回空列表而不是null
      return [];
    }

    final end = (offset + limit).clamp(0, cachedData.length);
    final result = cachedData.sublist(offset, end);

    logDebug('从缓存获取数据: offset=$offset, limit=$limit, 实际返回=${result.length}条');
    return result;
  }

  /// 修复：更智能的LRU缓存管理
  void _addToCache(String cacheKey, List<Quote> quotes, int offset) {
    final now = DateTime.now();

    if (!_filterCache.containsKey(cacheKey)) {
      // 如果缓存已满，使用真正的LRU策略移除最久未访问的条目
      if (_filterCache.length >= _maxCacheEntries) {
        _evictLRUCache();
      }
      _filterCache[cacheKey] = [];
    }

    // 更新缓存时间戳
    _cacheTimestamps[cacheKey] = now;
    _cacheAccessTimes[cacheKey] = now;

    // 如果是第一页，则清空缓存重新开始
    if (offset == 0) {
      _filterCache[cacheKey] = List.from(quotes);
      logDebug('缓存第一页数据，共 ${quotes.length} 条');
    } else {
      // 否则追加到现有缓存
      _filterCache[cacheKey]!.addAll(quotes);
      logDebug(
        '追加缓存数据，新增 ${quotes.length} 条，总计 ${_filterCache[cacheKey]!.length} 条',
      );
    }
  }

  /// 修复：实现真正的LRU缓存淘汰策略
  void _evictLRUCache() {
    if (_cacheAccessTimes.isEmpty) return;

    // 找到最久未访问的缓存条目
    String? lruKey;
    DateTime? oldestAccess;

    for (final entry in _cacheAccessTimes.entries) {
      if (oldestAccess == null || entry.value.isBefore(oldestAccess)) {
        oldestAccess = entry.value;
        lruKey = entry.key;
      }
    }

    if (lruKey != null) {
      _filterCache.remove(lruKey);
      _cacheTimestamps.remove(lruKey);
      _cacheAccessTimes.remove(lruKey);
      logDebug('LRU缓存淘汰，移除缓存条目: $lruKey');
    }
  }

}
