part of '../database_service.dart';

/// Mixin providing quote CRUD operations for DatabaseService.
mixin _DatabaseQuoteCrudMixin on _DatabaseServiceBase {
  /// 修复：添加一条引用（笔记），增加数据验证和并发控制
  @override
  Future<void> addQuote(Quote quote) async {
    // 修复：添加数据验证
    if (!quote.isValid) {
      throw ArgumentError('笔记数据无效，请检查内容、日期和其他字段');
    }

    if (kIsWeb) {
      _memoryStore.add(quote);
      notifyListeners();
      return;
    }

    return _executeWithLock('addQuote_${quote.id ?? 'new'}', () async {
      try {
        final db = await safeDatabase;
        final newQuoteId = quote.id ?? _uuid.v4();
        final quoteWithId =
            quote.id == null ? quote.copyWith(id: newQuoteId) : quote;

        await db.transaction((txn) async {
          final quoteMap = quoteWithId.toJson();
          quoteMap['id'] = newQuoteId;

          // 自动设置 last_modified 时间戳
          final now = DateTime.now().toUtc().toIso8601String();
          if (quoteMap['last_modified'] == null ||
              quoteMap['last_modified'].toString().isEmpty) {
            quoteMap['last_modified'] = now;
          }

          // 自动补全 day_period 字段
          if (quoteMap['date'] != null) {
            final dt = DateTime.tryParse(quoteMap['date']);
            if (dt != null) {
              final hour = dt.hour;
              String dayPeriodKey;
              if (hour >= 5 && hour < 8) {
                dayPeriodKey = 'dawn';
              } else if (hour >= 8 && hour < 12) {
                dayPeriodKey = 'morning';
              } else if (hour >= 12 && hour < 17) {
                dayPeriodKey = 'afternoon';
              } else if (hour >= 17 && hour < 20) {
                dayPeriodKey = 'dusk';
              } else if (hour >= 20 && hour < 23) {
                dayPeriodKey = 'evening';
              } else {
                dayPeriodKey = 'midnight';
              }
              quoteMap['day_period'] = dayPeriodKey;
            }
          }

          // 插入笔记
          await txn.insert(
            'quotes',
            quoteMap,
            conflictAlgorithm: ConflictAlgorithm.replace,
          );

          // 修复：插入标签关联，避免事务嵌套
          if (quote.tagIds.isNotEmpty) {
            // ⚡ Bolt: 使用 batch 优化批量插入标签，解决 N+1 性能问题
            final batch = txn.batch();
            for (final tagId in quote.tagIds) {
              batch.insert(
                  'quote_tags',
                  {
                    'quote_id': newQuoteId,
                    'tag_id': tagId,
                  },
                  conflictAlgorithm: ConflictAlgorithm.ignore);
            }
            await batch.commit(noResult: true);
          }
        });

        logDebug('笔记已成功保存到数据库，ID: ${quoteWithId.id}');

        // 同步媒体文件引用
        await MediaReferenceService.syncQuoteMediaReferences(quoteWithId);

        // 优化：数据变更后清空缓存
        clearAllCacheForParts();

        // 修复：避免直接操作_currentQuotes，使用刷新机制确保数据一致性
        refreshQuotesStreamForParts();
        notifyListeners(); // 通知其他监听者（如Homepage的FAB）
      } catch (e) {
        logDebug('保存笔记到数据库时出错: $e');
        rethrow; // 重新抛出异常，让调用者处理
      }
    });
  }

  /// 根据ID获取单个笔记的完整信息
  @override
  Future<Quote?> getQuoteById(
    String id, {
    bool includeDeleted = false,
  }) async {
    if (kIsWeb) {
      try {
        return _memoryStore.firstWhere(
          (q) => q.id == id && (includeDeleted || !q.isDeleted),
        );
      } catch (e) {
        return null;
      }
    }

    try {
      final db = await safeDatabase;

      // ⚡ Bolt: 使用标量子查询优化标签聚合查询，解决因 LEFT JOIN + GROUP BY 导致的性能问题
      final List<Map<String, dynamic>> maps = await db.rawQuery(
        '''
        SELECT q.*, (SELECT GROUP_CONCAT(tag_id) FROM quote_tags WHERE quote_id = q.id) as tag_ids
        FROM quotes q
        WHERE q.id = ?
          ${includeDeleted ? '' : 'AND (q.is_deleted = 0 OR q.is_deleted IS NULL)'}
      ''',
        [id],
      );

      if (maps.isEmpty) {
        return null;
      }

      return Quote.fromJson(maps.first);
    } catch (e) {
      logDebug('获取指定ID笔记失败: $e');
      return null;
    }
  }

  /// 获取所有笔记
  @override
  Future<List<Quote>> getAllQuotes({
    bool excludeHiddenNotes = true,
    bool includeDeleted = false,
  }) async {
    if (kIsWeb) {
      var result = List<Quote>.from(_memoryStore);
      if (!includeDeleted) {
        result = result.where((q) => !q.isDeleted).toList();
      }
      if (excludeHiddenNotes) {
        result = result
            .where((q) => !q.tagIds.contains(_DatabaseServiceBase.hiddenTagId))
            .toList();
      }
      return result;
    }

    try {
      final db = await safeDatabase;

      final conditions = <String>[];
      final args = <Object?>[];

      if (excludeHiddenNotes) {
        conditions.add('''
          NOT EXISTS (
            SELECT 1 FROM quote_tags qt_hidden
            WHERE qt_hidden.quote_id = q.id
            AND qt_hidden.tag_id = ?
          )
        ''');
        args.add(_DatabaseServiceBase.hiddenTagId);
      }

      if (!includeDeleted) {
        conditions.add('(q.is_deleted = 0 OR q.is_deleted IS NULL)');
      }

      final whereClause =
          conditions.isNotEmpty ? 'WHERE ${conditions.join(' AND ')}' : '';

      // ⚡ Bolt: 使用标量子查询优化获取笔记及其关联的标签
      final String query = '''
        SELECT q.*, (SELECT GROUP_CONCAT(tag_id) FROM quote_tags WHERE quote_id = q.id) as tag_ids
        FROM quotes q
        $whereClause
      ''';

      final List<Map<String, dynamic>> maps =
          await db.rawQuery(query, args.whereType<Object>().toList());

      return maps.map((m) => Quote.fromJson(m)).toList();
    } catch (e) {
      logDebug('获取所有笔记失败: $e');
      return [];
    }
  }

  /// 修复：删除指定的笔记，增加数据验证和错误处理
  @override
  Future<void> deleteQuote(String id) async {
    // 修复：添加参数验证
    if (id.isEmpty) {
      throw ArgumentError('笔记ID不能为空');
    }

    if (kIsWeb) {
      final index = _memoryStore.indexWhere((quote) => quote.id == id);
      if (index != -1 && !_memoryStore[index].isDeleted) {
        final now = DateTime.now().toUtc().toIso8601String();
        _memoryStore[index] = _memoryStore[index].copyWith(
          isDeleted: true,
          deletedAt: now,
          lastModified: now,
        );
      }
      clearAllCacheForParts();
      QuoteContent.removeCacheForQuote(id);
      refreshQuotesStreamForParts();
      notifyListeners();
      return;
    }

    return _executeWithLock('deleteQuote_$id', () async {
      try {
        final db = await safeDatabase;

        final now = DateTime.now().toUtc().toIso8601String();
        final updatedCount = await db.rawUpdate(
          'UPDATE quotes SET is_deleted = 1, deleted_at = ?, last_modified = ? '
          'WHERE id = ? AND (is_deleted = 0 OR is_deleted IS NULL)',
          [now, now, id],
        );

        if (updatedCount == 0) {
          logDebug('要删除的笔记不存在或已在回收站: $id');
          return;
        }

        // 清理缓存
        clearAllCacheForParts();

        // 修复问题1：清理富文本控制器缓存
        QuoteContent.removeCacheForQuote(id);

        refreshQuotesStreamForParts();
        notifyListeners();

        logDebug('笔记已移入回收站，ID: $id');
      } catch (e, stack) {
        UnifiedLogService.instance
            .error('删除笔记时出错', error: e, stackTrace: stack);
        rethrow;
      }
    });
  }

  /// 根据内容搜索笔记（用于媒体引用校验等内部逻辑）
  @override
  Future<List<Quote>> searchQuotesByContent(
    String query, {
    bool includeDeleted = false,
  }) async {
    if (kIsWeb) {
      var result = _memoryStore
          .where(
            (q) =>
                (q.content.contains(query)) ||
                (q.deltaContent != null && q.deltaContent!.contains(query)),
          )
          .toList();
      if (!includeDeleted) {
        result = result.where((q) => !q.isDeleted).toList();
      }
      return result;
    }

    final db = await safeDatabase;
    final where = includeDeleted
        ? 'content LIKE ? OR delta_content LIKE ?'
        : '(content LIKE ? OR delta_content LIKE ?) '
            'AND (is_deleted = 0 OR is_deleted IS NULL)';
    final List<Map<String, dynamic>> results = await db.query(
      'quotes',
      where: where,
      whereArgs: ['%$query%', '%$query%'],
    );

    return results.map((map) => Quote.fromJson(map)).toList();
  }

  /// 修复：更新笔记内容，增加数据验证和并发控制
  @override
  Future<QuoteUpdateResult> updateQuote(Quote quote) async {
    // 修复：添加数据验证
    if (quote.id == null || quote.id!.isEmpty) {
      throw ArgumentError('更新笔记时ID不能为空');
    }

    if (!quote.isValid) {
      throw ArgumentError('笔记数据无效，请检查内容、日期和其他字段');
    }

    if (kIsWeb) {
      final index = _memoryStore.indexWhere((q) => q.id == quote.id);
      if (index == -1) {
        return QuoteUpdateResult.notFound;
      }
      if (_memoryStore[index].isDeleted) {
        logWarning(
          '忽略对已删除笔记的更新请求: ${quote.id}',
          source: 'DatabaseService',
        );
        return QuoteUpdateResult.skippedDeleted;
      }
      _memoryStore[index] = quote;
      notifyListeners();
      return QuoteUpdateResult.updated;
    }

    return _executeWithLock('updateQuote_${quote.id}', () async {
      try {
        final db = await safeDatabase;
        var updateResult = QuoteUpdateResult.updated;

        // 在更新前记录旧的媒体引用，用于更新后判断是否需要清理文件
        final List<String> oldReferencedFiles =
            await MediaReferenceService.getReferencedFiles(quote.id!);
        await db.transaction((txn) async {
          final quoteMap = quote.toJson();

          // 更新时总是刷新 last_modified 时间戳
          final now = DateTime.now().toUtc().toIso8601String();
          quoteMap['last_modified'] = now;

          // 自动补全 day_period 字段
          if (quoteMap['date'] != null) {
            final dt = DateTime.tryParse(quoteMap['date']);
            if (dt != null) {
              final hour = dt.hour;
              String dayPeriodKey;
              if (hour >= 5 && hour < 8) {
                dayPeriodKey = 'dawn';
              } else if (hour >= 8 && hour < 12) {
                dayPeriodKey = 'morning';
              } else if (hour >= 12 && hour < 17) {
                dayPeriodKey = 'afternoon';
              } else if (hour >= 17 && hour < 20) {
                dayPeriodKey = 'dusk';
              } else if (hour >= 20 && hour < 23) {
                dayPeriodKey = 'evening';
              } else {
                dayPeriodKey = 'midnight';
              }
              quoteMap['day_period'] = dayPeriodKey;
            }
          }

          // 1. 更新笔记本身
          final updatedRows = await txn.update(
            'quotes',
            quoteMap,
            where: 'id = ? AND (is_deleted = 0 OR is_deleted IS NULL)',
            whereArgs: [quote.id],
          );
          if (updatedRows == 0) {
            final existingRows = await txn.query(
              'quotes',
              columns: ['id', 'is_deleted'],
              where: 'id = ?',
              whereArgs: [quote.id],
              limit: 1,
            );
            if (existingRows.isEmpty) {
              updateResult = QuoteUpdateResult.notFound;
              return;
            }
            final rawDeletedValue = existingRows.first['is_deleted'];
            final isDeleted = rawDeletedValue == true ||
                rawDeletedValue == 1 ||
                rawDeletedValue == '1';
            if (isDeleted) {
              logWarning(
                '忽略对已删除笔记的更新请求: ${quote.id}',
                source: 'DatabaseService',
              );
              updateResult = QuoteUpdateResult.skippedDeleted;
              return;
            }
            throw StateError('笔记状态异常，无法更新');
          }

          // 2. 删除旧的标签关联
          await txn.delete(
            'quote_tags',
            where: 'quote_id = ?',
            whereArgs: [quote.id],
          );

          /// 修复：插入新的标签关联，避免事务嵌套
          if (quote.tagIds.isNotEmpty) {
            // ⚡ Bolt: 使用 batch 优化批量插入标签，解决 N+1 性能问题
            final batch = txn.batch();
            for (final tagId in quote.tagIds) {
              batch.insert(
                  'quote_tags',
                  {
                    'quote_id': quote.id!,
                    'tag_id': tagId,
                  },
                  conflictAlgorithm: ConflictAlgorithm.ignore);
            }
            await batch.commit(noResult: true);
          }

          // 3. 同步媒体引用，确保与内容更新保持原子性
          await MediaReferenceService.syncQuoteMediaReferencesWithTransaction(
            txn,
            quote,
          );
        });

        if (updateResult != QuoteUpdateResult.updated) {
          return updateResult;
        }

        logDebug('笔记已成功更新，ID: ${quote.id}');

        // 使用轻量级检查机制清理因内容变更而不再被引用的媒体文件
        // ⚡ Bolt: Fetch appPath once to avoid N+1 platform channel calls in the loop below
        final appDir = await getApplicationDocumentsDirectory();
        final appPath = normalize(appDir.path);

        for (final storedPath in oldReferencedFiles) {
          try {
            String absolutePath = storedPath;
            if (!absolutePath.startsWith('/') && !absolutePath.contains(':')) {
              absolutePath = join(appPath, storedPath);
            }

            // 使用增强版的 quickCheckAndDeleteIfOrphan（包含内容二次校验）
            final deleted =
                await MediaReferenceService.quickCheckAndDeleteIfOrphan(
              absolutePath,
              cachedAppPath: appPath,
            );
            if (deleted) {
              logDebug('已清理无引用媒体文件: $absolutePath');
            }
          } catch (e) {
            logDebug('清理无引用媒体文件失败: $storedPath, 错误: $e');
          }
        }

        // 更新内存中的笔记列表
        final index = _currentQuotes.indexWhere((q) => q.id == quote.id);
        if (index != -1) {
          _currentQuotes[index] = quote;
        }

        // 修复问题1：更新笔记后清理旧缓存，确保显示最新内容
        QuoteContent.removeCacheForQuote(quote.id!);

        if (_quotesController != null && !_quotesController!.isClosed) {
          _quotesController!.add(List.from(_currentQuotes));
        }
        notifyListeners(); // 通知其他监听者
        return QuoteUpdateResult.updated;
      } catch (e, stack) {
        UnifiedLogService.instance
            .error('更新笔记时出错', error: e, stackTrace: stack);
        rethrow; // 重新抛出异常，让调用者处理
      }
    });
  }
}
