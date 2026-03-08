part of '../database_service.dart';

/// DatabaseQuoteCrudOperations for DatabaseService.
extension DatabaseQuoteCrudOperations on DatabaseService {

  /// 修复：添加一条引用（笔记），增加数据验证和并发控制
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
            for (final tagId in quote.tagIds) {
              await txn.insert(
                  'quote_tags',
                  {
                    'quote_id': newQuoteId,
                    'tag_id': tagId,
                  },
                  conflictAlgorithm: ConflictAlgorithm.ignore);
            }
          }
        });

        logDebug('笔记已成功保存到数据库，ID: ${quoteWithId.id}');

        // 同步媒体文件引用
        await MediaReferenceService.syncQuoteMediaReferences(quoteWithId);

        // 优化：数据变更后清空缓存
        _clearAllCache();

        // 修复：避免直接操作_currentQuotes，使用刷新机制确保数据一致性
        _refreshQuotesStream();
        notifyListeners(); // 通知其他监听者（如Homepage的FAB）
      } catch (e) {
        logDebug('保存笔记到数据库时出错: $e');
        rethrow; // 重新抛出异常，让调用者处理
      }
    });
  }

  /// 刷新笔记流数据（公开方法）


  /// 根据ID获取单个笔记的完整信息
  Future<Quote?> getQuoteById(String id) async {
    if (kIsWeb) {
      try {
        return _memoryStore.firstWhere((q) => q.id == id);
      } catch (e) {
        return null;
      }
    }

    try {
      final db = await safeDatabase;

      // 使用 GROUP_CONCAT 获取关联标签
      final List<Map<String, dynamic>> maps = await db.rawQuery(
        '''
        SELECT q.*, GROUP_CONCAT(qt.tag_id) as tag_ids
        FROM quotes q
        LEFT JOIN quote_tags qt ON q.id = qt.quote_id
        WHERE q.id = ?
        GROUP BY q.id
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

  /// 获取笔记列表，支持标签、分类、搜索、天气和时间段筛选


  /// 获取所有笔记
  /// [excludeHiddenNotes] 是否排除隐藏笔记，默认为 true
  /// 注意：媒体引用迁移等需要访问全部数据的场景应传入 false
  Future<List<Quote>> getAllQuotes({bool excludeHiddenNotes = true}) async {
    if (kIsWeb) {
      var result = List<Quote>.from(_memoryStore);
      if (excludeHiddenNotes) {
        result = result.where((q) => !q.tagIds.contains(hiddenTagId)).toList();
      }
      return result;
    }

    try {
      final db = await safeDatabase;

      // 修复：使用 LEFT JOIN 获取笔记及其关联的标签
      // 这样可以正确获取每个笔记的 tagIds
      final String query = '''
        SELECT q.*, GROUP_CONCAT(qt.tag_id) as tag_ids
        FROM quotes q
        LEFT JOIN quote_tags qt ON q.id = qt.quote_id
        ${excludeHiddenNotes ? '''
        WHERE NOT EXISTS (
          SELECT 1 FROM quote_tags qt_hidden
          WHERE qt_hidden.quote_id = q.id
          AND qt_hidden.tag_id = ?
        )
        ''' : ''}
        GROUP BY q.id
      ''';

      final List<Map<String, dynamic>> maps = excludeHiddenNotes
          ? await db.rawQuery(query, [hiddenTagId])
          : await db.rawQuery(query);

      return maps.map((m) => Quote.fromJson(m)).toList();
    } catch (e) {
      logDebug('获取所有笔记失败: $e');
      return [];
    }
  }

  /// 获取笔记总数，用于分页


  /// 修复：删除指定的笔记，增加数据验证和错误处理
  Future<void> deleteQuote(String id) async {
    // 修复：添加参数验证
    if (id.isEmpty) {
      throw ArgumentError('笔记ID不能为空');
    }

    if (kIsWeb) {
      _memoryStore.removeWhere((quote) => quote.id == id);
      notifyListeners();
      _refreshQuotesStream();
      return;
    }

    return _executeWithLock('deleteQuote_$id', () async {
      try {
        final db = await safeDatabase;

        // 先检查笔记是否存在
        final existingQuote = await db.query(
          'quotes',
          where: 'id = ?',
          whereArgs: [id],
          limit: 1,
        );

        if (existingQuote.isEmpty) {
          logDebug('要删除的笔记不存在: $id');
          return; // 笔记不存在，直接返回
        }

        // 先获取笔记引用的媒体文件列表（来自引用表）
        final referencedFiles = await MediaReferenceService.getReferencedFiles(
          id,
        );

        // 同时从笔记内容本身提取媒体路径，避免引用表不同步导致遗漏
        final Set<String> mediaPathsToCheck = {...referencedFiles};
        try {
          final quoteRow = existingQuote.first;
          final quoteFromDb = Quote.fromJson(quoteRow);
          final extracted =
              await MediaReferenceService.extractMediaPathsFromQuote(
            quoteFromDb,
          );
          mediaPathsToCheck.addAll(extracted);
        } catch (e) {
          logDebug('从笔记内容提取媒体路径失败，继续使用引用表: $e');
        }

        await db.transaction((txn) async {
          // 由于设置了 ON DELETE CASCADE，quote_tags 表中的相关条目会自动删除
          await txn.delete('quotes', where: 'id = ?', whereArgs: [id]);
        });

        // 移除媒体文件引用（CASCADE会自动删除，但为了确保一致性）
        await MediaReferenceService.removeAllReferencesForQuote(id);

        // 使用轻量级检查机制清理孤儿媒体文件（合并来源：引用表 + 内容提取）
        // 注：removeAllReferencesForQuote 已经清理了引用表，这里只需查引用计数
        for (final storedPath in mediaPathsToCheck) {
          try {
            // storedPath 可能是相对路径（相对于应用文档目录）
            String absolutePath = storedPath;
            try {
              // 使用 path.isAbsolute 来判断是否为绝对路径，兼容 Windows/Linux/macOS
              if (!isAbsolute(absolutePath)) {
                // 简单判断相对路径
                final appDir = await getApplicationDocumentsDirectory();
                absolutePath = join(appDir.path, storedPath);
              }
            } catch (e) {
              logDebug('[DatabaseService] path resolution failed: $e');
            }

            // 使用轻量级检查（仅查引用表计数）
            final deleted =
                await MediaReferenceService.quickCheckAndDeleteIfOrphan(
              absolutePath,
            );
            if (deleted) {
              logDebug('已清理孤儿媒体文件: $absolutePath (原始记录: $storedPath)');
            }
          } catch (e) {
            logDebug('清理孤儿媒体文件失败: $storedPath, 错误: $e');
          }
        }

        // 清理缓存
        _clearAllCache();

        // 修复问题1：清理富文本控制器缓存
        QuoteContent.removeCacheForQuote(id);

        // 直接从内存中移除并通知
        _currentQuotes.removeWhere((quote) => quote.id == id);
        if (_quotesController != null && !_quotesController!.isClosed) {
          _quotesController!.add(List.from(_currentQuotes));
        }
        notifyListeners();

        logDebug('笔记删除完成，ID: $id');
      } catch (e) {
        logDebug('删除笔记时出错: $e');
        rethrow;
      }
    });
  }

  /// 根据内容搜索笔记（用于媒体引用校验等内部逻辑）


  /// 根据内容搜索笔记（用于媒体引用校验等内部逻辑）
  Future<List<Quote>> searchQuotesByContent(String query) async {
    if (kIsWeb) {
      return _memoryStore
          .where(
            (q) =>
                (q.content.contains(query)) ||
                (q.deltaContent != null && q.deltaContent!.contains(query)),
          )
          .toList();
    }

    final db = await safeDatabase;
    final List<Map<String, dynamic>> results = await db.query(
      'quotes',
      where: 'content LIKE ? OR delta_content LIKE ?',
      whereArgs: ['%$query%', '%$query%'],
    );

    return results.map((map) => Quote.fromJson(map)).toList();
  }

  /// 修复：更新笔记内容，增加数据验证和并发控制


  /// 修复：更新笔记内容，增加数据验证和并发控制
  Future<void> updateQuote(Quote quote) async {
    // 修复：添加数据验证
    if (quote.id == null || quote.id!.isEmpty) {
      throw ArgumentError('更新笔记时ID不能为空');
    }

    if (!quote.isValid) {
      throw ArgumentError('笔记数据无效，请检查内容、日期和其他字段');
    }

    if (kIsWeb) {
      final index = _memoryStore.indexWhere((q) => q.id == quote.id);
      if (index != -1) {
        _memoryStore[index] = quote;
        notifyListeners();
      }
      return;
    }

    return _executeWithLock('updateQuote_${quote.id}', () async {
      try {
        final db = await safeDatabase;
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
          await txn.update(
            'quotes',
            quoteMap,
            where: 'id = ?',
            whereArgs: [quote.id],
          );

          // 2. 删除旧的标签关联
          await txn.delete(
            'quote_tags',
            where: 'quote_id = ?',
            whereArgs: [quote.id],
          );

          /// 修复：插入新的标签关联，避免事务嵌套
          if (quote.tagIds.isNotEmpty) {
            for (final tagId in quote.tagIds) {
              await txn.insert(
                  'quote_tags',
                  {
                    'quote_id': quote.id!,
                    'tag_id': tagId,
                  },
                  conflictAlgorithm: ConflictAlgorithm.ignore);
            }
          }

          // 3. 同步媒体引用，确保与内容更新保持原子性
          await MediaReferenceService.syncQuoteMediaReferencesWithTransaction(
            txn,
            quote,
          );
        });

        logDebug('笔记已成功更新，ID: ${quote.id}');

        // 使用轻量级检查机制清理因内容变更而不再被引用的媒体文件
        for (final storedPath in oldReferencedFiles) {
          try {
            String absolutePath = storedPath;
            if (!absolutePath.startsWith('/') && !absolutePath.contains(':')) {
              final appDir = await getApplicationDocumentsDirectory();
              absolutePath = join(appDir.path, storedPath);
            }

            // 使用增强版的 quickCheckAndDeleteIfOrphan（包含内容二次校验）
            final deleted =
                await MediaReferenceService.quickCheckAndDeleteIfOrphan(
              absolutePath,
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
      } catch (e) {
        logDebug('更新笔记时出错: $e');
        rethrow; // 重新抛出异常，让调用者处理
      }
    });
  }

  /// 增加笔记的心形点击次数

}
