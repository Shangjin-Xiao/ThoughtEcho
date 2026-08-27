import 'dart:io';

import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../models/import_cleanup_stats.dart';
import '../models/merge_report.dart';
import '../models/quote_model.dart';
import '../utils/app_logger.dart';
import '../utils/lww_utils.dart';
import '../utils/quill_delta_builder.dart';
import 'media_reference_service.dart';
import 'large_file_manager.dart';

class DatabaseBackupService {
  final Uuid _uuid;

  DatabaseBackupService({Uuid? uuid}) : _uuid = uuid ?? const Uuid();

  /// 从Map对象导入数据，返回本次入库前被清洗/跳过的统计。
  Future<ImportCleanupStats> importDataFromMap(
    Database db,
    Map<String, dynamic> data, {
    bool clearExisting = true,
  }) async {
    try {
      final actualData = (data.containsKey('notes') && data['notes'] is Map)
          ? Map<String, dynamic>.from(data['notes'] as Map)
          : data;

      // 验证数据格式
      if (!actualData.containsKey('categories') ||
          !actualData.containsKey('quotes')) {
        throw Exception('备份数据格式无效，缺少 "categories" 或 "quotes" 键');
      }

      // 计数在事务外声明：入库前清洗了什么要能报给调用方，最终由还原页展示。
      //
      // 只累计**数量** + 固定长度的日志预览。一份上万条的坏备份如果每条都留一个
      // 字符串，光是这些详情就能顶出一片内存，最后还要 join 成一个巨大的日志行。
      var sanitizedFieldCount = 0;
      var skippedEmptyQuoteCount = 0;
      final sanitizedPreview = <String>[];
      final skippedPreview = <String>[];

      // 开始事务
      await db.transaction((txn) async {
        if (clearExisting) {
          logDebug('清空现有数据并导入新数据');
          await txn.delete('quote_tags'); // 先删除关联表
          await txn.delete('quote_tombstones');
          await txn.delete('categories');
          await txn.delete('quotes');
        }

        // 恢复分类数据（优化：使用batch批量插入）
        final categories = actualData['categories'] as List;
        final categoryBatch = txn.batch();
        final processedCategories = <Map<String, dynamic>>[];

        for (final c in categories) {
          final categoryData = Map<String, dynamic>.from(
            c as Map<String, dynamic>,
          );

          // 修复：处理旧版分类数据字段名兼容性
          final categoryFieldMappings = {
            'isDefault': 'is_default',
            'iconName': 'icon_name',
            'icon': 'icon_name',
          };

          for (final mapping in categoryFieldMappings.entries) {
            if (categoryData.containsKey(mapping.key)) {
              categoryData[mapping.value] = categoryData[mapping.key];
              categoryData.remove(mapping.key);
            }
          }

          // 确保必要字段存在
          categoryData['id'] ??= _uuid.v4();
          categoryData['name'] ??= '未命名分类';
          categoryData['is_default'] ??= 0;

          // 白名单过滤：去除本地 schema 不认识的字段，防止恶意备份字段影响 SQL 结构
          final filteredCategoryData =
              _filterKnownCategoryColumns(categoryData);

          // 添加到batch
          processedCategories.add(filteredCategoryData);
          categoryBatch.insert(
            'categories',
            filteredCategoryData,
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }

        // 批量提交分类（性能提升5-10倍）
        try {
          await categoryBatch.commit(noResult: true);
          logDebug('批量插入${categories.length}个分类成功');
        } catch (e) {
          logError('批量插入分类失败，降级为逐条插入: $e', error: e, source: 'BackupRestore');
          final fallbackBatch = txn.batch();
          for (final filteredCategoryData in processedCategories) {
            fallbackBatch.insert(
              'categories',
              filteredCategoryData,
              conflictAlgorithm: ConflictAlgorithm.replace,
            );
          }
          try {
            await fallbackBatch.commit(noResult: true);
          } catch (e2) {
            logDebug('降级批量插入分类再次失败: $e2');
            rethrow;
          }
        }

        // 恢复笔记数据（优化：使用batch批量插入）
        final quotes = actualData['quotes'] as List;
        final quoteBatch = txn.batch();
        final tagRelations = <Map<String, String>>[];
        final processedQuotes = <Map<String, dynamic>>[];

        for (final q in quotes) {
          final quoteData = Map<String, dynamic>.from(
            q as Map<String, dynamic>,
          );

          // 修复：处理旧版笔记数据字段名兼容性
          List<String> parsedTagIds = [];

          // 处理tag_ids字段的各种可能格式（逗号分隔字符串或数组）
          if (quoteData.containsKey('tag_ids')) {
            final raw = quoteData['tag_ids'];
            if (raw is String) {
              parsedTagIds = raw
                  .split(',')
                  .map((e) => e.trim())
                  .where((e) => e.isNotEmpty)
                  .toSet()
                  .toList();
            } else if (raw is List) {
              parsedTagIds = raw
                  .map((e) => e.toString().trim())
                  .where((e) => e.isNotEmpty)
                  .toSet()
                  .toList();
            }
            quoteData.remove('tag_ids');
          } else if (quoteData.containsKey('taglds')) {
            // 处理错误的字段名 taglds -> tag_ids
            final raw = quoteData['taglds'];
            if (raw is String) {
              parsedTagIds = raw
                  .split(',')
                  .map((e) => e.trim())
                  .where((e) => e.isNotEmpty)
                  .toSet()
                  .toList();
            } else if (raw is List) {
              parsedTagIds = raw
                  .map((e) => e.toString().trim())
                  .where((e) => e.isNotEmpty)
                  .toSet()
                  .toList();
            }
            quoteData.remove('taglds');
          }

          // 修复：处理字段名不匹配问题
          final fieldMappings = {
            // 旧字段名 -> 新字段名
            'sourceAuthor': 'source_author',
            'sourceWork': 'source_work',
            'categoryld': 'category_id', // 修复 categoryld -> category_id
            'categoryId': 'category_id',
            'aiAnalysis': 'ai_analysis',
            'colorHex': 'color_hex',
            'editSource': 'edit_source',
            'deltaContent': 'delta_content',
            'dayPeriod': 'day_period',
            'favoriteCount': 'favorite_count',
            'lastModified': 'last_modified',
            'isDeleted': 'is_deleted',
            'deletedAt': 'deleted_at',
          };

          // 应用字段名映射
          for (final mapping in fieldMappings.entries) {
            if (quoteData.containsKey(mapping.key)) {
              quoteData[mapping.value] = quoteData[mapping.key];
              quoteData.remove(mapping.key);
            }
          }

          // 确保必要字段存在
          quoteData['id'] ??= _uuid.v4();
          quoteData['content'] ??= '';
          quoteData['date'] ??= DateTime.now().toIso8601String();
          quoteData['is_deleted'] = _parseDeletedFlag(quoteData['is_deleted']);
          quoteData['deleted_at'] = quoteData['deleted_at']?.toString();

          // 修复：回填缺失的 deleted_at，确保软删除记录能被 autoCleanupExpiredTrash 清理
          if ((quoteData['is_deleted'] as int) == 1 &&
              (quoteData['deleted_at'] == null ||
                  (quoteData['deleted_at'] as String).isEmpty)) {
            final lastModified = quoteData['last_modified']?.toString();
            quoteData['deleted_at'] =
                (lastModified != null && lastModified.isNotEmpty)
                    ? lastModified
                    : DateTime.now().toUtc().toIso8601String();
          }

          // 值域收敛：外来数据里应用词汇表之外的值必须在入库前处理掉，否则这条
          // 笔记要么存不回去、要么连整页都读不出来（见 [_sanitizeQuoteValues]）。
          final replaced = _sanitizeQuoteValues(quoteData);
          // 计的是**字段数**而不是笔记数：同一条笔记的 sentiment、color_hex、date
          // 可能一起被清洗，报成 1 会瞒掉另外两处。合并路径用的也是 replaced.length。
          sanitizedFieldCount += replaced.length;
          final detail = _describeSanitized(quoteData['id'], replaced);
          if (detail != null && sanitizedPreview.length < _logPreviewLimit) {
            sanitizedPreview.add(detail);
          }

          final recoveredContent = _recoverContent(quoteData);
          if (recoveredContent.isEmpty) {
            // 正文为空的行读出来就会抛异常，连累整页笔记加载失败，不能入库。
            skippedEmptyQuoteCount++;
            if (skippedPreview.length < _logPreviewLimit) {
              skippedPreview.add(_logSafeValue(quoteData['id']));
            }
            continue;
          }
          quoteData['content'] = recoveredContent;

          // 收集标签信息（稍后批量插入）
          if (parsedTagIds.isNotEmpty) {
            final quoteId = quoteData['id'] as String;
            for (final tagId in parsedTagIds) {
              tagRelations.add({'quote_id': quoteId, 'tag_id': tagId});
            }
          }

          // 白名单过滤：去除本地 schema 不认识的字段，防止恶意备份字段影响 SQL 结构
          final filteredQuoteData = _filterKnownQuoteColumns(quoteData);

          // 添加到batch
          processedQuotes.add(filteredQuoteData);
          quoteBatch.insert(
            'quotes',
            filteredQuoteData,
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }

        _logSanitizedValues(
          sanitizedPreview,
          total: sanitizedFieldCount,
          source: 'BackupRestore',
        );
        if (skippedEmptyQuoteCount > 0) {
          logWarning(
            '导入时跳过 $skippedEmptyQuoteCount 条正文为空的笔记: '
            '${_previewLine(skippedPreview, skippedEmptyQuoteCount)}',
            source: 'BackupRestore',
          );
        }

        // 批量提交笔记数据（性能提升5-10倍）
        try {
          await quoteBatch.commit(noResult: true);
          logDebug('批量插入${processedQuotes.length}条笔记成功');
        } catch (e) {
          logError('批量插入笔记失败，降级为逐条插入: $e', error: e, source: 'BackupRestore');
          final fallbackQuoteBatch = txn.batch();
          for (final filteredQuoteData in processedQuotes) {
            fallbackQuoteBatch.insert(
              'quotes',
              filteredQuoteData,
              conflictAlgorithm: ConflictAlgorithm.replace,
            );
          }
          try {
            await fallbackQuoteBatch.commit(noResult: true);
          } catch (e2) {
            logDebug('降级批量插入笔记再次失败: $e2');
            rethrow;
          }
        }

        // 批量插入标签关联（性能提升显著）
        if (tagRelations.isNotEmpty) {
          final tagBatch = txn.batch();
          const int chunkSize = 400;
          for (int i = 0; i < tagRelations.length; i += chunkSize) {
            final end = (i + chunkSize < tagRelations.length)
                ? i + chunkSize
                : tagRelations.length;
            final chunk = tagRelations.sublist(i, end);
            if (chunk.length == 1) {
              tagBatch.insert(
                'quote_tags',
                chunk.first,
                conflictAlgorithm: ConflictAlgorithm.ignore,
              );
            } else {
              final valuePlaceholders =
                  List.filled(chunk.length, '(?, ?)').join(', ');
              final args = <Object?>[];
              for (final relation in chunk) {
                args.addAll([relation['quote_id'], relation['tag_id']]);
              }
              tagBatch.rawInsert(
                'INSERT OR IGNORE INTO quote_tags (quote_id, tag_id) VALUES $valuePlaceholders',
                args,
              );
            }
          }

          try {
            await tagBatch.commit(noResult: true);
            logDebug('批量插入${tagRelations.length}条标签关联成功');
          } catch (e) {
            logError('批量插入标签关联失败: $e', error: e, source: 'BackupRestore');
            final fallbackTagBatch = txn.batch();
            for (final relation in tagRelations) {
              fallbackTagBatch.insert(
                'quote_tags',
                relation,
                conflictAlgorithm: ConflictAlgorithm.ignore,
              );
            }
            try {
              await fallbackTagBatch.commit(noResult: true);
            } catch (e2) {
              logDebug('降级批量插入标签关联再次失败: $e2');
              rethrow;
            }
          }
        }

        final tombstones = data['tombstones'];
        if (tombstones is List) {
          final affectedQuoteIds = <String>{};

          final existingTombstoneRows = await txn.query('quote_tombstones');
          final Map<String, String> localTombstoneMap = {
            for (final r in existingTombstoneRows)
              if (r['quote_id'] != null)
                r['quote_id'] as String: r['deleted_at']?.toString() ?? '',
          };

          final tombstoneBatch = txn.batch();
          final tombstoneRows = <Map<String, dynamic>>[];
          for (final row in tombstones) {
            if (row is! Map<String, dynamic>) {
              continue;
            }
            final quoteId = row['quote_id']?.toString();
            final deletedAt = row['deleted_at']?.toString();
            if (quoteId == null ||
                quoteId.isEmpty ||
                deletedAt == null ||
                deletedAt.isEmpty ||
                !LWWUtils.isValidTimestamp(deletedAt)) {
              continue;
            }
            final normalizedDeletedAt = LWWUtils.normalizeTimestamp(deletedAt);

            final localDeletedAt = localTombstoneMap[quoteId];
            if (localDeletedAt != null &&
                localDeletedAt.isNotEmpty &&
                _compareIsoTime(localDeletedAt, normalizedDeletedAt) >= 0) {
              continue;
            }

            final tombstoneData = {
              'quote_id': quoteId,
              'deleted_at': normalizedDeletedAt,
              'device_id': row['device_id']?.toString(),
            };
            tombstoneRows.add(tombstoneData);
            affectedQuoteIds.add(quoteId);
            localTombstoneMap[quoteId] = normalizedDeletedAt;
            tombstoneBatch.insert(
              'quote_tombstones',
              tombstoneData,
              conflictAlgorithm: ConflictAlgorithm.replace,
            );
          }
          try {
            await tombstoneBatch.commit(noResult: true);
          } catch (e) {
            logDebug('tombstones批量提交失败，回退到严格批量插入: $e');
            final fallbackTombstoneBatch = txn.batch();
            for (final tombstoneData in tombstoneRows) {
              fallbackTombstoneBatch.insert(
                'quote_tombstones',
                tombstoneData,
                conflictAlgorithm: ConflictAlgorithm.replace,
              );
            }
            try {
              await fallbackTombstoneBatch.commit(noResult: true);
            } catch (e2) {
              logDebug('降级批量插入 tombstone 再次失败: $e2');
              rethrow;
            }
          }

          if (!clearExisting && affectedQuoteIds.isNotEmpty) {
            final quoteIdList = affectedQuoteIds.toList();
            const int batchSize = 500;
            final List<String> quotesToDelete = [];

            for (int i = 0; i < quoteIdList.length; i += batchSize) {
              final end = (i + batchSize < quoteIdList.length)
                  ? i + batchSize
                  : quoteIdList.length;
              final batchIds = quoteIdList.sublist(i, end);
              final placeholders = List.filled(batchIds.length, '?').join(',');

              final quoteRows = await txn.query(
                'quotes',
                columns: ['id', 'last_modified'],
                where: 'id IN ($placeholders)',
                whereArgs: batchIds,
              );

              for (final row in quoteRows) {
                final quoteId = row['id'] as String;
                final localLastModified = row['last_modified']?.toString();
                final tombstoneDeletedAt = localTombstoneMap[quoteId];

                if (tombstoneDeletedAt == null || tombstoneDeletedAt.isEmpty) {
                  continue;
                }

                if (localLastModified == null ||
                    localLastModified.isEmpty ||
                    _compareIsoTime(tombstoneDeletedAt, localLastModified) >=
                        0) {
                  quotesToDelete.add(quoteId);
                }
              }
            }

            if (quotesToDelete.isNotEmpty) {
              for (int i = 0; i < quotesToDelete.length; i += batchSize) {
                final end = (i + batchSize < quotesToDelete.length)
                    ? i + batchSize
                    : quotesToDelete.length;
                final batchIds = quotesToDelete.sublist(i, end);
                final placeholders = List.filled(
                  batchIds.length,
                  '?',
                ).join(',');
                await txn.delete(
                  'quotes',
                  where: 'id IN ($placeholders)',
                  whereArgs: batchIds,
                );
              }
            }
          }
        }
      });

      return ImportCleanupStats(
        sanitizedFields: sanitizedFieldCount,
        skippedEmptyQuotes: skippedEmptyQuoteCount,
      );
    } catch (e) {
      logDebug('从Map导入数据失败: $e');
      rethrow;
    }
  }

  /// 从 JSON 文件导入数据
  ///
  /// [filePath] - 导入文件的路径
  /// [clearExisting] - 是否清空现有数据，默认为 true
  Future<ImportCleanupStats> importData(
    Database db,
    String filePath, {
    bool clearExisting = true,
  }) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) {
        throw Exception('备份文件不存在: $filePath');
      }
      // 使用流式JSON解析避免大文件OOM
      final data = await LargeFileManager.decodeJsonFromFileStreaming(file);

      // 调用新的核心导入逻辑
      return await importDataFromMap(db, data, clearExisting: clearExisting);
    } catch (e) {
      logDebug('数据导入失败: $e');
      rethrow;
    }
  }

  /// 检查是否可以导出数据（检测数据库是否可访问）
  Future<bool> checkCanExport(Database? db) async {
    try {
      // 尝试执行简单查询以验证数据库可访问
      if (db == null) {
        logDebug('数据库未初始化');
        return false;
      }

      // 修正：将'quote'改为正确的表名'quotes'
      await db.query('quotes', limit: 1);
      return true;
    } catch (e) {
      logDebug('数据库访问检查失败: $e');
      return false;
    }
  }

  /// 验证备份文件是否有效
  Future<bool> validateBackupFile(String filePath) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) {
        throw Exception('文件不存在: $filePath');
      }

      // 使用流式JSON解析避免大文件OOM
      final data = await LargeFileManager.decodeJsonFromFileStreaming(file);

      // 支持两种顶层结构：
      // 1. 标准结构：顶层包含 "notes" 对象，内部包含 "categories" 和/或 "quotes"
      // 2. 扁平/旧版结构：顶层直接包含 "categories" 和/或 "quotes"（可选包含 "metadata"）
      final Map<String, dynamic> notesData;
      if (data.containsKey('notes') && data['notes'] is Map) {
        notesData = Map<String, dynamic>.from(data['notes'] as Map);
      } else if (data.containsKey('categories') || data.containsKey('quotes')) {
        notesData = data;
      } else {
        throw Exception(
          '备份文件格式无效，缺少必要的笔记数据结构 (需要包含 "notes" 对象或 "categories"/"quotes" 列表)',
        );
      }

      // 验证内部结构
      if (notesData.containsKey('categories') &&
          notesData['categories'] is! List) {
        throw Exception('备份文件中的 "categories" 必须是一个列表');
      }
      if (notesData.containsKey('quotes') && notesData['quotes'] is! List) {
        throw Exception('备份文件中的 "quotes" 必须是一个列表');
      }

      // 检查至少需要有 quotes 或 categories (空备份也允许但需键存在)
      if (!notesData.containsKey('categories') &&
          !notesData.containsKey('quotes')) {
        throw Exception('备份文件缺少 "categories" 或 "quotes" 数据');
      }

      final quotes = notesData['quotes'] as List?;
      final categories = notesData['categories'] as List?;

      if ((quotes == null || quotes.isEmpty) &&
          (categories == null || categories.isEmpty)) {
        logDebug('警告：备份文件不包含任何分类或笔记数据');
      }

      logDebug('备份文件验证通过: $filePath');
      return true;
    } catch (e) {
      logDebug('验证备份文件失败: $e');
      throw Exception('无法验证备份文件： $e');
    }
  }

  ///
  /// 使用时间戳比较来决定是否覆盖本地数据
  /// [data] - 远程数据Map
  /// [sourceDevice] - 源设备标识符（可选）
  /// 返回 [MergeReport] 包含合并统计信息
  Future<MergeReport> importDataWithLWWMerge(
    Database db,
    Map<String, dynamic> data, {
    String? sourceDevice,
  }) async {
    final reportBuilder = MergeReportBuilder(sourceDevice: sourceDevice);
    // 分类ID重映射：用于处理不同设备上相同名称分类(标签)导致的ID不一致与重复问题
    final Map<String, String> categoryIdRemap = {}; // remoteId -> localId
    final mediaCleanupCandidates = <String>{};

    try {
      final actualData = (data.containsKey('notes') && data['notes'] is Map)
          ? Map<String, dynamic>.from(data['notes'] as Map)
          : data;

      // 验证数据格式
      if (!actualData.containsKey('categories') ||
          !actualData.containsKey('quotes')) {
        reportBuilder.addError('备份数据格式无效，缺少 "categories" 或 "quotes" 键');
        return reportBuilder.build();
      }

      await db.transaction((txn) async {
        await _mergeCategories(
          txn,
          actualData['categories'] as List,
          reportBuilder,
          categoryIdRemap,
        );
        await _mergeQuotes(
          txn,
          actualData['quotes'] as List,
          reportBuilder,
          categoryIdRemap,
        );

        final tombstones = actualData['tombstones'];
        if (tombstones is List) {
          await _applyTombstones(
            txn,
            tombstones,
            reportBuilder,
            mediaCleanupCandidates,
          );
        }
      });

      if (mediaCleanupCandidates.isNotEmpty) {
        final appDir = await getApplicationDocumentsDirectory();
        final appPath = normalize(appDir.path);
        final candidatePaths = <String>[];
        for (final mediaPath in mediaCleanupCandidates) {
          final candidatePath = normalize(
            isAbsolute(mediaPath) ? mediaPath : join(appPath, mediaPath),
          );
          if (candidatePath != appPath &&
              !candidatePath.startsWith(
                '$appPath${Platform.pathSeparator}',
              )) {
            continue;
          }
          candidatePaths.add(candidatePath);
        }

        try {
          await MediaReferenceService.quickCheckAndDeleteOrphans(
            candidatePaths,
            cachedAppPath: appPath,
          );
        } catch (cleanupErr) {
          reportBuilder.addError('清理墓碑删除后媒体文件失败: $cleanupErr');
        }
      }

      logInfo('LWW合并完成: ${reportBuilder.build().summary}');
    } catch (e) {
      reportBuilder.addError('合并过程发生错误: $e');
      logError('LWW合并失败: $e', error: e, source: 'DatabaseService');
    }

    return reportBuilder.build();
  }

  /// 合并分类数据（LWW策略）
  Future<void> _mergeCategories(
    Transaction txn,
    List categories,
    MergeReportBuilder reportBuilder,
    Map<String, String> categoryIdRemap,
  ) async {
    // 预先加载本地分类，建立名称(小写)->行、ID->行映射，便于避免 O(n^2) 查询
    final existingCategoryRows = await txn.query('categories');
    final Map<String, Map<String, dynamic>> idToRow = {
      for (final row in existingCategoryRows) (row['id'] as String): row,
    };
    final Map<String, Map<String, dynamic>> nameLowerToRow = {
      for (final row in existingCategoryRows)
        (row['name'] as String).toLowerCase(): row,
    };

    final batch = txn.batch();

    for (final c in categories) {
      try {
        final categoryData = Map<String, dynamic>.from(
          c as Map<String, dynamic>,
        );

        // 标准化字段名
        const categoryFieldMappings = {
          'isDefault': 'is_default',
          'iconName': 'icon_name',
          'icon': 'icon_name',
        };
        for (final mapping in categoryFieldMappings.entries) {
          if (categoryData.containsKey(mapping.key)) {
            categoryData[mapping.value] = categoryData[mapping.key];
            categoryData.remove(mapping.key);
          }
        }

        final remoteId = (categoryData['id'] as String?) ?? _uuid.v4();
        categoryData['id'] = remoteId; // 统一
        final remoteName = (categoryData['name'] as String?) ?? '未命名分类';
        categoryData['name'] = remoteName;
        categoryData['is_default'] ??= 0;
        // last_modified 参与 LWW 比较，必须统一为 UTC；对端旧版本可能携带本地时区裸时间戳
        final rawLastModified = categoryData['last_modified']?.toString();
        categoryData['last_modified'] =
            (rawLastModified == null || rawLastModified.isEmpty)
                ? DateTime.now().toUtc().toIso8601String()
                : LWWUtils.normalizeTimestamp(rawLastModified);

        // 过滤未知列名，防止对端版本较新时携带本地 schema 不认识的字段导致 SQLite 报错
        final filteredCategoryData = _filterKnownCategoryColumns(categoryData);

        // 1. 优先按ID匹配
        if (idToRow.containsKey(remoteId)) {
          final existing = idToRow[remoteId]!;
          final decision = LWWDecisionMaker.makeDecision(
            localTimestamp: existing['last_modified'] as String?,
            remoteTimestamp: categoryData['last_modified'] as String?,
          );
          if (decision.shouldUseRemote) {
            batch.update(
              'categories',
              filteredCategoryData,
              where: 'id = ?',
              whereArgs: [remoteId],
            );
            reportBuilder.addUpdatedCategory();
            // 更新缓存
            idToRow[remoteId] = filteredCategoryData;
            nameLowerToRow[remoteName.toLowerCase()] = filteredCategoryData;
          } else {
            reportBuilder.addSkippedCategory();
          }
          categoryIdRemap[remoteId] = remoteId; // identity
          continue;
        }

        // 2. 按名称(小写)匹配，处理不同设备相同名称但不同ID的情况 -> 复用本地ID，建立重映射
        final nameKey = remoteName.toLowerCase();
        if (nameLowerToRow.containsKey(nameKey)) {
          final existing = nameLowerToRow[nameKey]!;
          final existingId = existing['id'] as String;
          final decision = LWWDecisionMaker.makeDecision(
            localTimestamp: existing['last_modified'] as String?,
            remoteTimestamp: categoryData['last_modified'] as String?,
          );
          if (decision.shouldUseRemote) {
            // 仅更新可变字段（名称相同无需变更）；updateMap 的来源是本地行，字段已合规，
            // 追加的三个字段均在白名单内，无需再次过滤
            final updateMap = Map<String, dynamic>.from(existing)
              ..addAll({
                'icon_name': filteredCategoryData['icon_name'],
                'is_default': filteredCategoryData['is_default'],
                'last_modified': filteredCategoryData['last_modified'],
              });
            batch.update(
              'categories',
              updateMap,
              where: 'id = ?',
              whereArgs: [existingId],
            );
            idToRow[existingId] = updateMap;
            nameLowerToRow[nameKey] = updateMap;
            reportBuilder.addUpdatedCategory();
          } else {
            reportBuilder.addSkippedCategory();
          }
          categoryIdRemap[remoteId] = existingId;
          continue;
        }

        // 3. 新分类，直接插入
        batch.insert('categories', filteredCategoryData);
        idToRow[remoteId] = filteredCategoryData;
        nameLowerToRow[nameKey] = filteredCategoryData;
        categoryIdRemap[remoteId] = remoteId;
        reportBuilder.addInsertedCategory();
      } catch (e) {
        reportBuilder.addError('处理分类失败: $e');
      }
    }

    await batch.commit(noResult: true);
  }

  /// categories 表中本地 schema 已知的列名白名单。
  /// 导入/同步时过滤掉此列表之外的字段，防止恶意备份字段影响 SQL 结构。
  static const Set<String> _knownCategoryColumns = {
    'id',
    'name',
    'is_default',
    'icon_name',
    'last_modified',
  };

  /// quotes 表中本地 schema 已知的列名白名单。
  /// 同步时若远端数据包含此列表之外的字段（对端版本更新），
  /// 将静默忽略未知字段以保持向前兼容，而非抛出 SQLite 错误。
  static const Set<String> _knownQuoteColumns = {
    'id',
    'content',
    'date',
    'source',
    'source_author',
    'source_work',
    'ai_analysis',
    'sentiment',
    'keywords',
    'summary',
    'category_id',
    'color_hex',
    'location',
    'latitude',
    'longitude',
    'poi_name',
    'weather',
    'temperature',
    'edit_source',
    'delta_content',
    'day_period',
    'last_modified',
    'weather_backup',
    'day_period_backup',
    'sentiment_backup',
    'favorite_count',
    'is_deleted',
    'deleted_at',
  };

  /// 过滤掉 categoryData 中本地 schema 不认识的字段。
  Map<String, dynamic> _filterKnownCategoryColumns(
    Map<String, dynamic> categoryData,
  ) {
    final unknown = categoryData.keys
        .where((k) => !_knownCategoryColumns.contains(k))
        .toList();
    if (unknown.isEmpty) return categoryData;
    logDebug(
      '导入时忽略 categories 中未知字段: $unknown',
      source: 'DatabaseBackupService',
    );
    return Map.fromEntries(
      categoryData.entries.where((e) => _knownCategoryColumns.contains(e.key)),
    );
  }

  /// 把一行外来笔记数据收敛到本地模型认得的值域，返回被清洗的字段个数。
  ///
  /// 导入侧原来只过滤不认识的**列**（[_filterKnownQuoteColumns]），从不看**值**。
  /// 于是外来数据里的越界值原样落库，而读和写对值域的要求并不一致，后果分两档：
  ///
  /// - `sentiment` 这种「读不查、写才查」的：笔记显示正常，一保存就被
  ///   [Quote.validationError] 拦下，变成只能看不能改的砖；
  /// - `date` / `content` 这种读就要查的：[Quote.fromJson] 直接抛异常，而
  ///   `database_query_mixin` 的反序列化没有逐行兜底，**整页笔记加载失败**。
  ///
  /// 所以洗在这里——数据进门这一次，洗完由调用方把计数报给用户（[MergeReport]
  /// 的 `sanitizedFields`）。读的时候不洗：那等于把库里的雷永远藏着。
  /// 返回「字段名 → 被替换掉的原值」，空 Map 表示这一行原样通过。
  static Map<String, Object?> _sanitizeQuoteValues(
    Map<String, dynamic> quoteData,
  ) {
    final replaced = <String, Object?>{};

    final rawSentiment = quoteData['sentiment'];
    if (rawSentiment != null) {
      final normalized = Quote.normalizeSentiment(rawSentiment);
      if (normalized != rawSentiment) {
        quoteData['sentiment'] = normalized;
        replaced['sentiment'] = rawSentiment;
      }
    }

    final rawColor = quoteData['color_hex'];
    if (rawColor != null) {
      final normalized = _normalizeColorHex(rawColor);
      if (normalized != rawColor) {
        quoteData['color_hex'] = normalized;
        replaced['color_hex'] = rawColor;
      }
    }

    final rawDate = quoteData['date']?.toString();
    if (rawDate == null || !Quote.isValidDate(rawDate)) {
      final lastModified = quoteData['last_modified']?.toString();
      quoteData['date'] =
          (lastModified != null && Quote.isValidDate(lastModified))
              ? lastModified
              : DateTime.now().toIso8601String();
      replaced['date'] = rawDate;
    }

    return replaced;
  }

  /// 把被替换掉的原值写进日志，让「清洗」这件事在导入之后还查得到。
  ///
  /// [preview] 是已经限量攒下的样本，[total] 是真实总数——两者分开，才能既报准
  /// 数量又不为此保留 O(n) 个字符串。
  ///
  /// 收敛是不可逆写入，源文件还在用户手里、同步时对端也还留着自己那份，但库内
  /// 得有个能追溯的落点。只记字段名和这三个字段的原值（都不是笔记内容），并且
  /// 限量，免得一份上万条的备份把日志刷爆。
  static void _logSanitizedValues(
    List<String> preview, {
    required int total,
    required String source,
  }) {
    if (total == 0) return;
    logWarning(
      '导入时忽略了 $total 处无法识别的字段值（非本应用产生的数据）：'
      '${_previewLine(preview, total)}',
      source: source,
    );
  }

  /// 预览行：只展示已经攒下的那几条，剩下的报数量。
  static String _previewLine(List<String> preview, int total) {
    final omitted = total - preview.length;
    final shown = preview.join('; ');
    return omitted > 0 ? '$shown …另有 $omitted 处' : shown;
  }

  /// 日志预览最多留几条。攒下的字符串数量必须有上限，否则一份很大的坏备份会把
  /// 详情本身变成内存压力。
  static const int _logPreviewLimit = 20;

  /// 把一行的清洗结果拼成可读的一条记录。
  ///
  /// 原值来自导入文件，长度和内容都不受本应用控制，所以进日志前要裁短并去掉控制
  /// 字符——否则一个超长或带换行的字段值就能把日志刷乱。
  static String? _describeSanitized(
    Object? quoteId,
    Map<String, Object?> replaced,
  ) {
    if (replaced.isEmpty) return null;
    final fields = replaced.entries
        .map((e) => '${e.key}=${_logSafeValue(e.value)}')
        .join(', ');
    return '${_logSafeValue(quoteId)}($fields)';
  }

  /// 单个外来值的日志安全形式：去控制字符 + 限长。
  static String _logSafeValue(Object? value) {
    const maxLength = 32;
    final cleaned =
        (value?.toString() ?? 'null').replaceAll(_controlChars, ' ').trim();
    return cleaned.length > maxLength
        ? '${cleaned.substring(0, maxLength)}…'
        : cleaned;
  }

  static final RegExp _controlChars = RegExp(r'[\x00-\x1F\x7F]');

  /// 收敛颜色值到 `#RRGGBB`，认不出来返回 null。
  ///
  /// 认 `RRGGBB`（缺 `#`）、`0xRRGGBB` 和 `#RGB` 缩写。**带 alpha 的 8 位一律丢弃**：
  /// `#RRGGBBAA` 和 `#AARRGGBB` 从字面上分不出来，猜错会把颜色改成另一个颜色，
  /// 比不上色更糟。
  static String? _normalizeColorHex(Object? raw) {
    var text = raw?.toString().trim() ?? '';
    if (text.isEmpty) return null;
    if (text.startsWith('0x') || text.startsWith('0X')) {
      text = text.substring(2);
    }
    if (!text.startsWith('#')) {
      text = '#$text';
    }
    if (RegExp(r'^#[0-9A-Fa-f]{3}$').hasMatch(text)) {
      text = '#${text[1]}${text[1]}${text[2]}${text[2]}${text[3]}${text[3]}';
    }
    return Quote.isValidColorHex(text) ? text : null;
  }

  /// 笔记正文为空时补一次：`content` 空字符串会让 [Quote.fromJson] 抛异常，
  /// 而那条异常会带着整页查询一起失败。能从 Delta 里捞回正文就捞，捞不回来的
  /// 交给调用方决定（当前是不导入这一条并记进报告）。
  static String _recoverContent(Map<String, dynamic> quoteData) {
    final content = quoteData['content']?.toString() ?? '';
    if (content.trim().isNotEmpty) return content;
    return DeltaBuilder.extractTextFromDelta(
      quoteData['delta_content']?.toString(),
    ).trim();
  }

  /// 过滤掉 quoteData 中本地 schema 不认识的字段，
  /// 记录被忽略的字段名（debug 级别，不含字段值）。
  Map<String, dynamic> _filterKnownQuoteColumns(
    Map<String, dynamic> quoteData,
  ) {
    final unknown =
        quoteData.keys.where((k) => !_knownQuoteColumns.contains(k)).toList();
    if (unknown.isEmpty) return quoteData;
    logDebug(
      '同步时忽略本地 schema 未知的字段（对端版本可能更新）: $unknown',
      source: 'DatabaseBackupService',
    );
    return Map.fromEntries(
      quoteData.entries.where((e) => _knownQuoteColumns.contains(e.key)),
    );
  }

  /// 合并笔记数据（LWW策略）
  Future<void> _mergeQuotes(
    Transaction txn,
    List quotes,
    MergeReportBuilder reportBuilder,
    Map<String, String> categoryIdRemap,
  ) async {
    // 预加载当前事务中有效的分类ID集合，用于过滤无效的远程标签引用，防止外键错误
    final existingCategoryIdRows = await txn.query(
      'categories',
      columns: ['id'],
    );
    final Set<String> validCategoryIds = existingCategoryIdRows
        .map((r) => r['id'] as String)
        .whereType<String>()
        .toSet();

    // ⚡ Bolt: 预加载本地笔记元数据，避免循环中的 N 次查询
    final existingQuoteRows = await txn.query(
      'quotes',
      columns: ['id', 'last_modified', 'content'],
    );
    final Map<String, Map<String, dynamic>> idToQuote = {
      for (final row in existingQuoteRows) (row['id'] as String): row,
    };

    // ⚡ Bolt: 预加载本地墓碑数据，避免循环中 N 次查询
    final existingTombstoneRows = await txn.query('quote_tombstones');
    final Map<String, Map<String, dynamic>> localTombstoneMap = {
      for (final row in existingTombstoneRows) (row['quote_id'] as String): row,
    };

    final batch = txn.batch();
    // 同上：只留固定长度的日志预览，总数走 reportBuilder。
    var sanitizedFieldCount = 0;
    final sanitizedPreview = <String>[];

    for (final q in quotes) {
      try {
        final quoteData = Map<String, dynamic>.from(q as Map<String, dynamic>);

        // 标准化字段名
        final fieldMappings = {
          'sourceAuthor': 'source_author',
          'sourceWork': 'source_work',
          'categoryld': 'category_id',
          'categoryId': 'category_id',
          'aiAnalysis': 'ai_analysis',
          'colorHex': 'color_hex',
          'editSource': 'edit_source',
          'deltaContent': 'delta_content',
          'dayPeriod': 'day_period',
          'favoriteCount': 'favorite_count',
          'lastModified': 'last_modified',
          'isDeleted': 'is_deleted',
          'deletedAt': 'deleted_at',
        };

        for (final mapping in fieldMappings.entries) {
          if (quoteData.containsKey(mapping.key)) {
            quoteData[mapping.value] = quoteData[mapping.key];
            quoteData.remove(mapping.key);
          }
        }

        // 提取并解析 tag_ids (字符串或列表)，稍后写入 quote_tags
        List<String> parsedTagIds = [];
        if (quoteData.containsKey('tag_ids')) {
          final raw = quoteData['tag_ids'];
          if (raw is String) {
            if (raw.isNotEmpty) {
              parsedTagIds = raw
                  .split(',')
                  .map((e) => e.trim())
                  .where((e) => e.isNotEmpty)
                  .toSet()
                  .toList();
            }
          } else if (raw is List) {
            parsedTagIds = raw
                .map((e) => e.toString().trim())
                .where((e) => e.isNotEmpty)
                .toSet()
                .toList();
          }
          quoteData.remove('tag_ids'); // 不存储在 quotes 表
        }

        // 重映射 category_id （如果存在）
        final originalCategoryId = quoteData['category_id'] as String?;
        if (originalCategoryId != null &&
            categoryIdRemap.containsKey(originalCategoryId)) {
          quoteData['category_id'] = categoryIdRemap[originalCategoryId];
        }

        // 重映射标签ID并去重
        final remappedTagIds = <String>{};
        for (final tid in parsedTagIds) {
          final mapped = categoryIdRemap[tid] ?? tid; // 若未重映射则保持原ID
          if (validCategoryIds.contains(mapped)) {
            remappedTagIds.add(mapped);
          }
        }

        // 确保必要字段存在
        final quoteId = quoteData['id'] ??= _uuid.v4();
        quoteData['content'] ??= '';
        quoteData['date'] ??= DateTime.now().toIso8601String();
        quoteData['last_modified'] ??=
            (quoteData['date'] as String? ?? DateTime.now().toIso8601String());
        quoteData['is_deleted'] = _parseDeletedFlag(quoteData['is_deleted']);
        quoteData['deleted_at'] = quoteData['deleted_at']?.toString();

        // 值域收敛。同步（局域网 / WebDAV）和「合并导入」共用这一段，所以对端版本
        // 比本机新、写了本机词汇表里还没有的值时，这里只收敛不拒收——整份拒收会
        // 让两台设备直接同步不了，代价远大于丢一个可选字段。
        final replaced = _sanitizeQuoteValues(quoteData);
        if (replaced.isNotEmpty) {
          reportBuilder.addSanitizedField(replaced.length);
          sanitizedFieldCount += replaced.length;
          final detail = _describeSanitized(quoteId, replaced);
          if (detail != null && sanitizedPreview.length < _logPreviewLimit) {
            sanitizedPreview.add(detail);
          }
        }

        final recoveredContent = _recoverContent(quoteData);
        if (recoveredContent.isEmpty) {
          // 正文为空的行读出来就会抛异常，连累整页笔记加载失败，不能入库。
          reportBuilder.addError('跳过正文为空的笔记: ${_logSafeValue(quoteId)}');
          reportBuilder.addSkippedEmptyQuote();
          continue;
        }
        quoteData['content'] = recoveredContent;

        final localTombstone = localTombstoneMap[quoteId];
        if (localTombstone != null) {
          final tombstoneAt = localTombstone['deleted_at']?.toString();
          final quoteLastModified = quoteData['last_modified']?.toString();

          // Defensive check: tombstone must have a valid timestamp to block import
          // If remote quote lacks last_modified, keep the tombstone decision.
          if (tombstoneAt == null || tombstoneAt.isEmpty) {
            // Invalid tombstone without timestamp - remove it and allow import
            batch.delete(
              'quote_tombstones',
              where: 'quote_id = ?',
              whereArgs: [quoteId],
            );
            localTombstoneMap.remove(quoteId);
          } else if (quoteLastModified == null || quoteLastModified.isEmpty) {
            // Missing remote timestamp must not revive a permanently deleted quote.
            reportBuilder.addSkippedQuote();
            continue;
          } else if (_compareIsoTime(quoteLastModified, tombstoneAt) <= 0) {
            // Tombstone is newer or equal - skip the quote
            reportBuilder.addSkippedQuote();
            continue;
          } else {
            // Quote is newer - delete the tombstone and allow import
            batch.delete(
              'quote_tombstones',
              where: 'quote_id = ?',
              whereArgs: [quoteId],
            );
            localTombstoneMap.remove(quoteId);
          }
        }

        // 过滤掉远端数据中本地 schema 不认识的字段，保持向前兼容
        final filteredData = _filterKnownQuoteColumns(quoteData);

        // ⚡ Bolt: 使用预加载的 map 进行匹配，避免重复查询
        bool inserted = false;
        if (!idToQuote.containsKey(quoteId)) {
          batch.insert('quotes', filteredData);
          reportBuilder.addInsertedQuote();
          inserted = true;
          // ⚡ Bolt: 更新本地缓存以处理输入数据中的重复项
          idToQuote[quoteId] = filteredData;
        } else {
          final existingQuote = idToQuote[quoteId]!;
          final decision = LWWDecisionMaker.makeDecision(
            localTimestamp: existingQuote['last_modified'] as String?,
            remoteTimestamp: quoteData['last_modified'] as String?,
            localContent: existingQuote['content'] as String?,
            remoteContent: quoteData['content'] as String?,
            checkContentSimilarity: true,
          );
          if (decision.shouldUseRemote) {
            batch.update(
              'quotes',
              filteredData,
              where: 'id = ?',
              whereArgs: [quoteId],
            );
            reportBuilder.addUpdatedQuote();
            // ⚡ Bolt: 更新本地缓存以处理输入数据中的重复项
            idToQuote[quoteId] = filteredData;
          } else if (decision.hasConflict) {
            reportBuilder.addSameTimestampDiffQuote();
          } else {
            reportBuilder.addSkippedQuote();
          }
        }

        // 写入标签关联 (插入或更新场景都需要同步), 仅当存在标签
        if (remappedTagIds.isNotEmpty) {
          // 如果是更新，先清理旧关联
          if (!inserted) {
            batch.delete(
              'quote_tags',
              where: 'quote_id = ?',
              whereArgs: [quoteId],
            );
          }
          final tagIdList = remappedTagIds.toList();
          const int chunkSize = 400;
          for (int i = 0; i < tagIdList.length; i += chunkSize) {
            final end = (i + chunkSize < tagIdList.length)
                ? i + chunkSize
                : tagIdList.length;
            final chunk = tagIdList.sublist(i, end);
            if (chunk.length == 1) {
              batch.insert(
                'quote_tags',
                {
                  'quote_id': quoteId,
                  'tag_id': chunk.first,
                },
                conflictAlgorithm: ConflictAlgorithm.ignore,
              );
            } else {
              final valuePlaceholders =
                  List.filled(chunk.length, '(?, ?)').join(', ');
              final args = <Object?>[];
              for (final tagId in chunk) {
                args.addAll([quoteId, tagId]);
              }
              batch.rawInsert(
                'INSERT OR IGNORE INTO quote_tags (quote_id, tag_id) VALUES $valuePlaceholders',
                args,
              );
            }
          }
        }
      } catch (e) {
        reportBuilder.addError('处理笔记失败: $e');
      }
    }

    _logSanitizedValues(
      sanitizedPreview,
      total: sanitizedFieldCount,
      source: 'BackupRestore',
    );

    await batch.commit(noResult: true);
  }

  Future<void> _applyTombstones(
    Transaction txn,
    List tombstones,
    MergeReportBuilder reportBuilder,
    Set<String> mediaCleanupCandidates,
  ) async {
    // ⚡ Bolt: 预加载本地墓碑数据，避免循环中 N 次查询
    final existingTombstoneRows = await txn.query('quote_tombstones');
    final Map<String, Map<String, dynamic>> localTombstoneMap = {
      for (final row in existingTombstoneRows) (row['quote_id'] as String): row,
    };

    // ⚡ Bolt: 提取有效的 quote_id 进行批量查询，避免 N+1
    final validQuoteIds = <String>[];
    for (final item in tombstones) {
      if (item is! Map<String, dynamic>) continue;
      final quoteId = item['quote_id']?.toString();
      final incomingDeletedAt = item['deleted_at']?.toString();
      if (quoteId != null &&
          quoteId.isNotEmpty &&
          incomingDeletedAt != null &&
          incomingDeletedAt.isNotEmpty &&
          LWWUtils.isValidTimestamp(incomingDeletedAt)) {
        validQuoteIds.add(quoteId);
      }
    }

    final Map<String, Map<String, dynamic>> existingQuotesMap = {};
    final Map<String, List<String>> existingMediaRefsMap = {};

    if (validQuoteIds.isNotEmpty) {
      final queryBatch = txn.batch();
      const int batchSize = 500;
      for (int i = 0; i < validQuoteIds.length; i += batchSize) {
        final end = (i + batchSize < validQuoteIds.length)
            ? i + batchSize
            : validQuoteIds.length;
        final batchIds = validQuoteIds.sublist(i, end);
        final placeholders = List.filled(batchIds.length, '?').join(',');

        queryBatch.query(
          'quotes',
          columns: ['id', 'last_modified', 'delta_content', 'content'],
          where: 'id IN ($placeholders)',
          whereArgs: batchIds,
        );
        queryBatch.query(
          'media_references',
          columns: ['quote_id', 'file_path'],
          where: 'quote_id IN ($placeholders)',
          whereArgs: batchIds,
        );
      }

      final queryResults = await queryBatch.commit();
      // queryResults contains results for quotes and media_references alternately
      for (int i = 0; i < queryResults.length; i += 2) {
        final quotesResult = queryResults[i] as List<Object?>;
        final refsResult = queryResults[i + 1] as List<Object?>;

        for (final rowObj in quotesResult) {
          final row = rowObj as Map<String, dynamic>;
          final id = row['id'] as String;
          existingQuotesMap[id] = row;
        }

        for (final rowObj in refsResult) {
          final row = rowObj as Map<String, dynamic>;
          final qId = row['quote_id'] as String;
          final fp = row['file_path']?.toString();
          if (fp != null && fp.isNotEmpty) {
            existingMediaRefsMap.putIfAbsent(qId, () => []).add(fp);
          }
        }
      }
    }

    final batch = txn.batch();

    for (final item in tombstones) {
      try {
        if (item is! Map<String, dynamic>) {
          continue;
        }

        final quoteId = item['quote_id']?.toString();
        final incomingDeletedAt = item['deleted_at']?.toString();
        if (quoteId == null ||
            quoteId.isEmpty ||
            incomingDeletedAt == null ||
            incomingDeletedAt.isEmpty ||
            !LWWUtils.isValidTimestamp(incomingDeletedAt)) {
          continue;
        }

        final normalizedIncoming = LWWUtils.normalizeTimestamp(
          incomingDeletedAt,
        );

        final localTombstone = localTombstoneMap[quoteId];
        if (localTombstone != null) {
          final localDeletedAt = localTombstone['deleted_at']?.toString() ?? '';
          if (_compareIsoTime(localDeletedAt, normalizedIncoming) >= 0) {
            continue;
          }
        }

        final quoteRow = existingQuotesMap[quoteId];

        if (quoteRow != null) {
          final quoteDeltaContent = quoteRow['delta_content']?.toString();
          final quoteContent = quoteRow['content']?.toString() ?? '';

          final tempQuote = Quote(
            content: quoteContent,
            date: DateTime.now().toIso8601String(),
            deltaContent: quoteDeltaContent,
          );
          final extracted =
              await MediaReferenceService.extractMediaPathsFromQuote(tempQuote);
          mediaCleanupCandidates.addAll(extracted);

          final refs = existingMediaRefsMap[quoteId];
          if (refs != null) {
            mediaCleanupCandidates.addAll(refs);
          }

          final quoteLastModified = quoteRow['last_modified']?.toString();
          if (quoteLastModified == null || quoteLastModified.isEmpty) {
            batch.delete('quotes', where: 'id = ?', whereArgs: [quoteId]);
            reportBuilder.addDeletedByTombstone();
          } else if (_compareIsoTime(normalizedIncoming, quoteLastModified) >=
              0) {
            batch.delete('quotes', where: 'id = ?', whereArgs: [quoteId]);
            reportBuilder.addDeletedByTombstone();
          } else {
            continue;
          }
        }

        batch.insert(
            'quote_tombstones',
            {
              'quote_id': quoteId,
              'deleted_at': normalizedIncoming,
              'device_id': item['device_id']?.toString(),
            },
            conflictAlgorithm: ConflictAlgorithm.replace);

        localTombstoneMap[quoteId] = {
          'quote_id': quoteId,
          'deleted_at': normalizedIncoming,
        };
      } catch (e) {
        reportBuilder.addError('处理 tombstone 失败: $e');
      }
    }

    await batch.commit(noResult: true);
  }

  int _parseDeletedFlag(dynamic value) {
    if (value == null) {
      return 0;
    }
    if (value is bool) {
      return value ? 1 : 0;
    }
    if (value is num) {
      return value.toInt() == 0 ? 0 : 1;
    }
    final parsed = int.tryParse(value.toString());
    if (parsed != null) {
      return parsed == 0 ? 0 : 1;
    }
    final text = value.toString().trim().toLowerCase();
    return text == 'true' ? 1 : 0;
  }

  int _compareIsoTime(String? left, String? right) {
    final leftTs = LWWUtils.normalizeTimestamp(left);
    final rightTs = LWWUtils.normalizeTimestamp(right);
    try {
      return DateTime.parse(leftTs).compareTo(DateTime.parse(rightTs));
    } on FormatException {
      // 回退到Unix纪元时间进行比较
      final leftDt = DateTime.tryParse(leftTs) ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
      final rightDt = DateTime.tryParse(rightTs) ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
      return leftDt.compareTo(rightDt);
    }
  }
}
