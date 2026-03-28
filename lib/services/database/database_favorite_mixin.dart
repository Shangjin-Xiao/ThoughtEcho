part of '../database_service.dart';

/// Mixin providing favorite/heart operations for DatabaseService.
mixin _DatabaseFavoriteMixin on _DatabaseServiceBase {
  /// 增加笔记的心形点击次数
  @override
  Future<void> incrementFavoriteCount(String quoteId) async {
    if (quoteId.isEmpty) {
      throw ArgumentError('笔记ID不能为空');
    }

    if (kIsWeb) {
      final index = _memoryStore.indexWhere((q) => q.id == quoteId);
      if (index != -1) {
        if (_memoryStore[index].isDeleted) {
          throw StateError('已删除的笔记不能收藏');
        }
        final oldCount = _memoryStore[index].favoriteCount;
        _memoryStore[index] = _memoryStore[index].copyWith(
          favoriteCount: oldCount + 1,
        );
        logDebug(
          'Web平台收藏操作: quoteId=$quoteId, 旧值=$oldCount, 新值=${oldCount + 1}',
          source: 'IncrementFavorite',
        );

        // 同步更新当前流缓存并推送
        final curIndex = _currentQuotes.indexWhere((q) => q.id == quoteId);
        if (curIndex != -1) {
          _currentQuotes[curIndex] = _currentQuotes[curIndex].copyWith(
            favoriteCount: _currentQuotes[curIndex].favoriteCount + 1,
          );
          if (_quotesController != null && !_quotesController!.isClosed) {
            _quotesController!.add(List.from(_currentQuotes));
          }
        }
        notifyListeners();
      } else {
        logWarning(
          'Web平台收藏操作失败: 未找到quoteId=$quoteId',
          source: 'IncrementFavorite',
        );
      }
      return;
    }

    return _executeWithLock('incrementFavorite_$quoteId', () async {
      try {
        // 记录操作前的状态
        final index = _currentQuotes.indexWhere((q) => q.id == quoteId);
        final oldCount =
            index != -1 ? _currentQuotes[index].favoriteCount : null;
        logDebug(
          '收藏操作开始: quoteId=$quoteId, 内存旧值=$oldCount',
          source: 'IncrementFavorite',
        );

        final db = await safeDatabase;
        await db.transaction((txn) async {
          final existing = await txn.query(
            'quotes',
            columns: ['id', 'is_deleted'],
            where: 'id = ?',
            whereArgs: [quoteId],
            limit: 1,
          );

          if (existing.isEmpty) {
            throw StateError('笔记不存在，无法收藏');
          }

          final isDeletedValue = existing.first['is_deleted'];
          final isDeleted =
              (isDeletedValue is num && isDeletedValue.toInt() == 1) ||
                  (isDeletedValue is bool && isDeletedValue);
          if (isDeleted) {
            throw StateError('已删除的笔记不能收藏');
          }

          // 原子性地增加计数
          final updateCount = await txn.rawUpdate(
            'UPDATE quotes SET favorite_count = favorite_count + 1, last_modified = ? WHERE id = ?',
            [DateTime.now().toUtc().toIso8601String(), quoteId],
          );

          if (updateCount == 0) {
            logWarning(
              '收藏操作失败: 数据库中未找到quoteId=$quoteId',
              source: 'IncrementFavorite',
            );
          } else {
            // 查询更新后的值进行验证
            final result = await txn.rawQuery(
              'SELECT favorite_count FROM quotes WHERE id = ?',
              [quoteId],
            );
            final newCount = result.isNotEmpty
                ? (result.first['favorite_count'] as int?) ?? 0
                : 0;
            logInfo(
              '收藏操作成功: quoteId=$quoteId, 旧值=$oldCount, 数据库新值=$newCount',
              source: 'IncrementFavorite',
            );
          }
        });

        // 更新内存中的笔记列表
        if (index != -1) {
          _currentQuotes[index] = _currentQuotes[index].copyWith(
            favoriteCount: _currentQuotes[index].favoriteCount + 1,
          );
          logDebug(
            '内存缓存已更新: 新值=${_currentQuotes[index].favoriteCount}',
            source: 'IncrementFavorite',
          );
        }
        if (_quotesController != null && !_quotesController!.isClosed) {
          _quotesController!.add(List.from(_currentQuotes));
        }
        notifyListeners();
      } catch (e) {
        logError(
          '增加心形点击次数时出错: quoteId=$quoteId, error=$e',
          error: e,
          source: 'IncrementFavorite',
        );
        rethrow;
      }
    });
  }

  /// 重置心形点击次数为0（清除收藏）
  @override
  Future<void> resetFavoriteCount(String quoteId) async {
    if (quoteId.isEmpty) {
      throw ArgumentError('笔记ID不能为空');
    }

    if (kIsWeb) {
      final index = _memoryStore.indexWhere((q) => q.id == quoteId);
      if (index != -1) {
        if (_memoryStore[index].isDeleted) {
          throw StateError('已删除的笔记不能清除收藏');
        }
        _memoryStore[index] = _memoryStore[index].copyWith(favoriteCount: 0);
        logDebug('Web平台清除收藏: quoteId=$quoteId', source: 'ResetFavorite');
      }

      final curIndex = _currentQuotes.indexWhere((q) => q.id == quoteId);
      if (curIndex != -1) {
        _currentQuotes[curIndex] = _currentQuotes[curIndex].copyWith(
          favoriteCount: 0,
        );
      }

      if (_quotesController != null && !_quotesController!.isClosed) {
        _quotesController!.add(List.from(_currentQuotes));
      }
      notifyListeners();
      return;
    }

    return _executeWithLock('resetFavorite_$quoteId', () async {
      try {
        final index = _currentQuotes.indexWhere((q) => q.id == quoteId);
        final oldCount =
            index != -1 ? _currentQuotes[index].favoriteCount : null;
        logDebug(
          '清除收藏操作开始: quoteId=$quoteId, 内存旧值=$oldCount',
          source: 'ResetFavorite',
        );

        final db = await safeDatabase;
        await db.transaction((txn) async {
          final existing = await txn.query(
            'quotes',
            columns: ['id', 'is_deleted'],
            where: 'id = ?',
            whereArgs: [quoteId],
            limit: 1,
          );

          if (existing.isEmpty) {
            throw StateError('笔记不存在，无法清除收藏');
          }

          final isDeletedValue = existing.first['is_deleted'];
          final isDeleted =
              (isDeletedValue is num && isDeletedValue.toInt() == 1) ||
                  (isDeletedValue is bool && isDeletedValue);
          if (isDeleted) {
            throw StateError('已删除的笔记不能清除收藏');
          }

          final updateCount = await txn.rawUpdate(
            'UPDATE quotes SET favorite_count = 0, last_modified = ? WHERE id = ?',
            [DateTime.now().toUtc().toIso8601String(), quoteId],
          );

          if (updateCount == 0) {
            logWarning(
              '清除收藏失败: 数据库中未找到quoteId=$quoteId',
              source: 'ResetFavorite',
            );
          } else {
            logInfo(
              '清除收藏成功: quoteId=$quoteId, 旧值=$oldCount, 新值=0',
              source: 'ResetFavorite',
            );
          }
        });

        // 更新内存中的笔记列表
        if (index != -1) {
          _currentQuotes[index] = _currentQuotes[index].copyWith(
            favoriteCount: 0,
          );
          logDebug('内存缓存已更新: 新值=0', source: 'ResetFavorite');
        }
        if (_quotesController != null && !_quotesController!.isClosed) {
          _quotesController!.add(List.from(_currentQuotes));
        }
        notifyListeners();
      } catch (e) {
        logError(
          '清除收藏时出错: quoteId=$quoteId, error=$e',
          error: e,
          source: 'ResetFavorite',
        );
        rethrow;
      }
    });
  }

  /// 获取本周期内点心最多的笔记
  @override
  Future<List<Quote>> getMostFavoritedQuotesThisWeek({int limit = 5}) async {
    if (kIsWeb) {
      final now = DateTime.now();
      final weekStart = now.subtract(Duration(days: now.weekday - 1));
      final weekStartString = weekStart.toIso8601String().substring(0, 10);

      final filtered = _memoryStore
          .where(
            (q) =>
                q.date.compareTo(weekStartString) >= 0 &&
                q.favoriteCount > 0 &&
                !q.isDeleted,
          )
          .toList();
      filtered.sort((a, b) => b.favoriteCount.compareTo(a.favoriteCount));
      return filtered.take(limit).toList();
    }

    try {
      final db = await safeDatabase;
      final now = DateTime.now();
      final weekStart = now.subtract(Duration(days: now.weekday - 1));
      final weekStartString = weekStart.toIso8601String().substring(0, 10);

      final List<Map<String, dynamic>> results = await db.query(
        'quotes',
        where:
            'date >= ? AND favorite_count > 0 AND (is_deleted = 0 OR is_deleted IS NULL)',
        whereArgs: [weekStartString],
        orderBy: 'favorite_count DESC, date DESC',
        limit: limit,
      );

      return results.map((map) => Quote.fromJson(map)).toList();
    } catch (e) {
      logError('获取本周最受喜爱笔记时出错: $e', error: e, source: 'GetMostFavorited');
      return [];
    }
  }
}
