import 'dart:io';

import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../models/merge_report.dart';
import '../utils/app_logger.dart';
import '../utils/lww_utils.dart';
import 'large_file_manager.dart';

class DatabaseBackupService {
  final Uuid _uuid;

  DatabaseBackupService({Uuid? uuid}) : _uuid = uuid ?? const Uuid();

  /// 将所有笔记和分类数据导出为Map对象
  Future<Map<String, dynamic>> exportDataAsMap(Database db) async {
    try {
      final dbVersion = await db.getVersion();

      // 查询所有分类数据
      final categories = await db.query('categories');

      // ⚡ Bolt: 使用标量子查询优化标签聚合查询，避免 LEFT JOIN + GROUP BY 的整表聚合性能开销
      final quotesWithTags = await db.rawQuery('''
        SELECT q.*, (SELECT GROUP_CONCAT(tag_id) FROM quote_tags WHERE quote_id = q.id) as tag_ids
        FROM quotes q
        ORDER BY q.date DESC
      ''');

      // 构建与旧版exportAllData兼容的JSON结构
      final tombstones = await db.query('quote_tombstones');
      return {
        'metadata': {
          'app': '心迹',
          'version': dbVersion,
          'exportTime': DateTime.now().toIso8601String(),
        },
        'categories': categories,
        'quotes': quotesWithTags,
        'tombstones': tombstones,
      };
    } catch (e) {
      logDebug('数据导出为Map时失败: $e');
      rethrow;
    }
  }

  /// 导出全部数据到 JSON 格式
  ///
  /// [customPath] - 可选的自定义保存路径。如果提供，将保存到指定路径；否则保存到应用文档目录
  /// 返回保存的文件路径
  Future<String> exportAllData(Database db, {String? customPath}) async {
    try {
      // 修复 P1-2: 避免直接构建巨大的 JSON 字符串并 writeAsString 导致 OOM
      // 1. 调用新方法获取 Map 数据（在内存中构建 Map）
      final jsonData = await exportDataAsMap(db);

      String filePath;
      if (customPath != null) {
        filePath = customPath;
      } else {
        final dir = await getApplicationDocumentsDirectory();
        final fileName = '心迹_${DateTime.now().millisecondsSinceEpoch}.json';
        filePath = join(dir.path, fileName);
      }

      // 2. 使用流式写入将 Map 数据转换为文件（大幅降低内存峰值占用）
      // 修复：替换 file.writeAsString(jsonStr)，并传入 File 对象
      logDebug('开始流式导出大文件到: $filePath');
      await LargeFileManager.encodeJsonToFileStreaming(
        jsonData,
        File(filePath),
      );

      return filePath;
    } catch (e) {
      logError('数据导出失败', error: e, source: 'exportAllData');
      rethrow;
    }
  }

  /// 从Map对象导入数据
  Future<void> importDataFromMap(
    Database db,
    Map<String, dynamic> data, {
    bool clearExisting = true,
  }) async {
    try {
      // 验证数据格式
      if (!data.containsKey('categories') || !data.containsKey('quotes')) {
        throw Exception('备份数据格式无效，缺少 "categories" 或 "quotes" 键');
      }

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
        final categories = data['categories'] as List;
        final categoryBatch = txn.batch();

        for (final c in categories) {
          final categoryData = Map<String, dynamic>.from(
            c as Map<String, dynamic>,
          );

          // 修复：处理旧版分类数据字段名兼容性
          final categoryFieldMappings = {
            'isDefault': 'is_default',
            'iconName': 'icon_name',
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

          // 添加到batch
          categoryBatch.insert(
            'categories',
            categoryData,
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }

        // 批量提交分类（性能提升5-10倍）
        try {
          await categoryBatch.commit(noResult: true);
          logDebug('批量插入${categories.length}个分类成功');
        } catch (e) {
          logError('批量插入分类失败，降级为逐条插入: $e', error: e, source: 'BackupRestore');
          // 降级：逐条插入
          for (final c in categories) {
            final categoryData = Map<String, dynamic>.from(
              c as Map<String, dynamic>,
            );
            final categoryFieldMappings = {
              'isDefault': 'is_default',
              'iconName': 'icon_name',
            };
            for (final mapping in categoryFieldMappings.entries) {
              if (categoryData.containsKey(mapping.key)) {
                categoryData[mapping.value] = categoryData[mapping.key];
                categoryData.remove(mapping.key);
              }
            }
            categoryData['id'] ??= _uuid.v4();
            categoryData['name'] ??= '未命名分类';
            categoryData['is_default'] ??= 0;

            try {
              await txn.insert(
                'categories',
                categoryData,
                conflictAlgorithm: ConflictAlgorithm.replace,
              );
            } catch (e2) {
              logDebug('插入单个分类失败: ${categoryData['id']}');
            }
          }
        }

        // 恢复笔记数据（优化：使用batch批量插入）
        final quotes = data['quotes'] as List;
        final quoteBatch = txn.batch();
        final tagRelations = <Map<String, String>>[];

        for (final q in quotes) {
          final quoteData = Map<String, dynamic>.from(
            q as Map<String, dynamic>,
          );

          // 修复：处理旧版笔记数据字段名兼容性
          String? tagIdsString;

          // 处理tag_ids字段的各种可能格式
          if (quoteData.containsKey('tag_ids')) {
            tagIdsString = quoteData['tag_ids'] as String?;
            quoteData.remove('tag_ids');
          } else if (quoteData.containsKey('taglds')) {
            // 处理错误的字段名 taglds -> tag_ids
            tagIdsString = quoteData['taglds'] as String?;
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

          // 收集标签信息（稍后批量插入）
          if (tagIdsString != null && tagIdsString.isNotEmpty) {
            final quoteId = quoteData['id'] as String;
            final tagIds =
                tagIdsString.split(',').where((id) => id.trim().isNotEmpty);
            for (final tagId in tagIds) {
              tagRelations.add({'quote_id': quoteId, 'tag_id': tagId.trim()});
            }
          }

          // 添加到batch
          quoteBatch.insert(
            'quotes',
            quoteData,
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }

        // 批量提交笔记数据（性能提升5-10倍）
        try {
          await quoteBatch.commit(noResult: true);
          logDebug('批量插入${quotes.length}条笔记成功');
        } catch (e) {
          logError('批量插入笔记失败，降级为逐条插入: $e', error: e, source: 'BackupRestore');
          // 降级：逐条插入
          for (final q in quotes) {
            final quoteData = Map<String, dynamic>.from(
              q as Map<String, dynamic>,
            );

            String? tagIdsString;
            if (quoteData.containsKey('tag_ids')) {
              tagIdsString = quoteData['tag_ids'] as String?;
              quoteData.remove('tag_ids');
            } else if (quoteData.containsKey('taglds')) {
              tagIdsString = quoteData['taglds'] as String?;
              quoteData.remove('taglds');
            }

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

            quoteData['id'] ??= _uuid.v4();
            quoteData['content'] ??= '';
            quoteData['date'] ??= DateTime.now().toIso8601String();
            quoteData['is_deleted'] =
                _parseDeletedFlag(quoteData['is_deleted']);
            quoteData['deleted_at'] = quoteData['deleted_at']?.toString();

            try {
              await txn.insert(
                'quotes',
                quoteData,
                conflictAlgorithm: ConflictAlgorithm.replace,
              );

              // 插入成功后，处理标签关联
              if (tagIdsString != null && tagIdsString.isNotEmpty) {
                final quoteId = quoteData['id'] as String;
                final tagIds =
                    tagIdsString.split(',').where((id) => id.trim().isNotEmpty);
                for (final tagId in tagIds) {
                  try {
                    await txn.insert(
                        'quote_tags',
                        {
                          'quote_id': quoteId,
                          'tag_id': tagId.trim(),
                        },
                        conflictAlgorithm: ConflictAlgorithm.ignore);
                  } catch (e3) {
                    logDebug('插入标签关联失败: $e3');
                  }
                }
              }
            } catch (e2) {
              logDebug('插入单条笔记失败: ${quoteData['id']}');
            }
          }
        }

        // 批量插入标签关联（性能提升显著）
        if (tagRelations.isNotEmpty) {
          final tagBatch = txn.batch();
          for (final relation in tagRelations) {
            tagBatch.insert(
              'quote_tags',
              relation,
              conflictAlgorithm: ConflictAlgorithm.ignore,
            );
          }

          try {
            await tagBatch.commit(noResult: true);
            logDebug('批量插入${tagRelations.length}条标签关联成功');
          } catch (e) {
            logError('批量插入标签关联失败: $e', error: e, source: 'BackupRestore');
            // 降级：逐条插入
            for (final relation in tagRelations) {
              try {
                await txn.insert(
                  'quote_tags',
                  relation,
                  conflictAlgorithm: ConflictAlgorithm.ignore,
                );
              } catch (e2) {
                logDebug('插入单条标签关联失败: ${relation['quote_id']}');
              }
            }
          }
        }

        final tombstones = data['tombstones'];
        if (tombstones is List) {
          final tombstoneBatch = txn.batch();
          for (final row in tombstones) {
            if (row is! Map<String, dynamic>) {
              continue;
            }
            final quoteId = row['quote_id']?.toString();
            final deletedAt = row['deleted_at']?.toString();
            if (quoteId == null || quoteId.isEmpty || deletedAt == null) {
              continue;
            }
            tombstoneBatch.insert(
              'quote_tombstones',
              {
                'quote_id': quoteId,
                'deleted_at': deletedAt,
                'device_id': row['device_id']?.toString(),
              },
              conflictAlgorithm: ConflictAlgorithm.replace,
            );
          }
          await tombstoneBatch.commit(noResult: true);
        }
      });
    } catch (e) {
      logDebug('从Map导入数据失败: $e');
      rethrow;
    }
  }

  /// 从 JSON 文件导入数据
  ///
  /// [filePath] - 导入文件的路径
  /// [clearExisting] - 是否清空现有数据，默认为 true
  Future<void> importData(
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
      await importDataFromMap(db, data, clearExisting: clearExisting);
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

      // --- 修改处 ---
      // 验证基本结构，应与 exportAllData 导出的结构一致
      final requiredKeys = {'metadata', 'categories', 'quotes'};
      if (!requiredKeys.every((key) => data.containsKey(key))) {
        // 提供更详细的错误信息，指出缺少哪些键
        final missingKeys = requiredKeys.difference(data.keys.toSet());
        throw Exception(
          '备份文件格式无效，缺少必要的顶层数据结构 (需要: metadata, categories, quotes; 缺少: ${missingKeys.join(', ')})',
        );
      }
      // --- 修改结束 ---

      // 可选：进一步验证内部结构，例如 metadata 是否包含 version
      if (data['metadata'] is! Map ||
          !(data['metadata'] as Map).containsKey('version')) {
        logDebug('警告：备份文件元数据 (metadata) 格式不正确或缺少版本信息');
        // 可以选择是否在这里抛出异常，取决于是否强制要求版本信息
      }

      // 可选：检查 categories 和 quotes 是否为列表类型
      if (data['categories'] is! List) {
        throw Exception('备份文件中的 \'categories\' 必须是一个列表');
      }
      if (data['quotes'] is! List) {
        throw Exception('备份文件中的 \'quotes\' 必须是一个列表');
      }

      // 检查至少需要有quotes或categories (可选，空备份也可能有效)
      final quotes = data['quotes'] as List?;
      final categories = data['categories'] as List?;

      if ((quotes == null || quotes.isEmpty) &&
          (categories == null || categories.isEmpty)) {
        logDebug('警告：备份文件不包含任何分类或笔记数据');
        // 空备份也是有效的，但可以记录警告
      }

      logDebug('备份文件验证通过: $filePath');
      return true; // 如果所有检查都通过，返回 true
    } catch (e) {
      logDebug('验证备份文件失败: $e');
      // 重新抛出更具体的错误信息给上层调用者
      // 保留原始异常类型，以便上层可以根据需要区分处理
      // 例如: throw FormatException('备份文件JSON格式错误');
      // 或: throw FileSystemException('无法读取备份文件', filePath);
      // 这里统一抛出 Exception，包含原始错误信息
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

    try {
      // 验证数据格式
      if (!data.containsKey('categories') || !data.containsKey('quotes')) {
        reportBuilder.addError('备份数据格式无效，缺少 "categories" 或 "quotes" 键');
        return reportBuilder.build();
      }

      await db.transaction((txn) async {
        await _mergeCategories(
          txn,
          data['categories'] as List,
          reportBuilder,
          categoryIdRemap,
        );
        await _mergeQuotes(
          txn,
          data['quotes'] as List,
          reportBuilder,
          categoryIdRemap,
        );

        final tombstones = data['tombstones'];
        if (tombstones is List) {
          await _applyTombstones(txn, tombstones, reportBuilder);
        }
      });

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

    for (final c in categories) {
      try {
        final categoryData = Map<String, dynamic>.from(
          c as Map<String, dynamic>,
        );

        // 标准化字段名
        const categoryFieldMappings = {
          'isDefault': 'is_default',
          'iconName': 'icon_name',
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
        categoryData['last_modified'] ??= DateTime.now().toIso8601String();

        // 1. 优先按ID匹配
        if (idToRow.containsKey(remoteId)) {
          final existing = idToRow[remoteId]!;
          final decision = LWWDecisionMaker.makeDecision(
            localTimestamp: existing['last_modified'] as String?,
            remoteTimestamp: categoryData['last_modified'] as String?,
          );
          if (decision.shouldUseRemote) {
            await txn.update(
              'categories',
              categoryData,
              where: 'id = ?',
              whereArgs: [remoteId],
            );
            reportBuilder.addUpdatedCategory();
            // 更新缓存
            idToRow[remoteId] = categoryData;
            nameLowerToRow[remoteName.toLowerCase()] = categoryData;
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
            // 仅更新可变字段（名称相同无需变更）
            final updateMap = Map<String, dynamic>.from(existing)
              ..addAll({
                'icon_name': categoryData['icon_name'],
                'is_default': categoryData['is_default'],
                'last_modified': categoryData['last_modified'],
              });
            await txn.update(
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
        await txn.insert('categories', categoryData);
        idToRow[remoteId] = categoryData;
        nameLowerToRow[nameKey] = categoryData;
        categoryIdRemap[remoteId] = remoteId;
        reportBuilder.addInsertedCategory();
      } catch (e) {
        reportBuilder.addError('处理分类失败: $e');
      }
    }
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

        final localTombstone = await txn.query(
          'quote_tombstones',
          where: 'quote_id = ?',
          whereArgs: [quoteId],
          limit: 1,
        );
        if (localTombstone.isNotEmpty) {
          final tombstoneAt = localTombstone.first['deleted_at']?.toString();
          final quoteLastModified = quoteData['last_modified']?.toString();

          // Only compare timestamps if both are present and non-empty
          if (tombstoneAt != null && tombstoneAt.isNotEmpty &&
              quoteLastModified != null && quoteLastModified.isNotEmpty) {
            if (_compareIsoTime(quoteLastModified, tombstoneAt) <= 0) {
              reportBuilder.addSkippedQuote();
              continue;
            }
          } else if (tombstoneAt == null || tombstoneAt.isEmpty) {
            // Invalid tombstone without timestamp - remove it
            await txn.delete(
              'quote_tombstones',
              where: 'quote_id = ?',
              whereArgs: [quoteId],
            );
          } else if (quoteLastModified == null || quoteLastModified.isEmpty) {
            // Quote has no timestamp but tombstone does - skip the quote
            reportBuilder.addSkippedQuote();
            continue;
          }

          // If tombstone is older or invalid, delete it
          if (tombstoneAt != null && tombstoneAt.isNotEmpty &&
              quoteLastModified != null && quoteLastModified.isNotEmpty &&
              _compareIsoTime(quoteLastModified, tombstoneAt) > 0) {
            await txn.delete(
              'quote_tombstones',
              where: 'quote_id = ?',
              whereArgs: [quoteId],
            );
          }
        }

        // 查询本地是否存在该笔记
        final existingRows = await txn.query(
          'quotes',
          where: 'id = ?',
          whereArgs: [quoteId],
        );

        bool inserted = false;
        if (existingRows.isEmpty) {
          await txn.insert('quotes', quoteData);
          reportBuilder.addInsertedQuote();
          inserted = true;
        } else {
          final existingQuote = existingRows.first;
          final decision = LWWDecisionMaker.makeDecision(
            localTimestamp: existingQuote['last_modified'] as String?,
            remoteTimestamp: quoteData['last_modified'] as String?,
            localContent: existingQuote['content'] as String?,
            remoteContent: quoteData['content'] as String?,
            checkContentSimilarity: true,
          );
          if (decision.shouldUseRemote) {
            await txn.update(
              'quotes',
              quoteData,
              where: 'id = ?',
              whereArgs: [quoteId],
            );
            reportBuilder.addUpdatedQuote();
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
            await txn.delete(
              'quote_tags',
              where: 'quote_id = ?',
              whereArgs: [quoteId],
            );
          }
          final batch = txn.batch();
          for (final tagId in remappedTagIds) {
            batch.insert(
                'quote_tags',
                {
                  'quote_id': quoteId,
                  'tag_id': tagId,
                },
                conflictAlgorithm: ConflictAlgorithm.ignore);
          }
          await batch.commit(noResult: true);
        }
      } catch (e) {
        reportBuilder.addError('处理笔记失败: $e');
      }
    }
  }

  Future<void> _applyTombstones(
    Transaction txn,
    List tombstones,
    MergeReportBuilder reportBuilder,
  ) async {
    for (final item in tombstones) {
      try {
        if (item is! Map<String, dynamic>) {
          continue;
        }

        final quoteId = item['quote_id']?.toString();
        final incomingDeletedAt = item['deleted_at']?.toString();
        if (quoteId == null || quoteId.isEmpty || incomingDeletedAt == null) {
          continue;
        }

        final normalizedIncoming =
            LWWUtils.normalizeTimestamp(incomingDeletedAt);

        final localTombstones = await txn.query(
          'quote_tombstones',
          where: 'quote_id = ?',
          whereArgs: [quoteId],
          limit: 1,
        );
        if (localTombstones.isNotEmpty) {
          final localDeletedAt =
              localTombstones.first['deleted_at']?.toString();
          if (_compareIsoTime(localDeletedAt, normalizedIncoming) >= 0) {
            continue;
          }
        }

        final quoteRows = await txn.query(
          'quotes',
          columns: ['last_modified'],
          where: 'id = ?',
          whereArgs: [quoteId],
          limit: 1,
        );

        if (quoteRows.isNotEmpty) {
          final quoteLastModified =
              quoteRows.first['last_modified']?.toString();
          if (_compareIsoTime(normalizedIncoming, quoteLastModified) >= 0) {
            await txn.delete(
              'quotes',
              where: 'id = ?',
              whereArgs: [quoteId],
            );
            reportBuilder.addDeletedQuote();
          } else {
            continue;
          }
        }

        await txn.insert(
          'quote_tombstones',
          {
            'quote_id': quoteId,
            'deleted_at': normalizedIncoming,
            'device_id': item['device_id']?.toString(),
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      } catch (e) {
        reportBuilder.addError('处理 tombstone 失败: $e');
      }
    }
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
    return DateTime.parse(leftTs).compareTo(DateTime.parse(rightTs));
  }
}
