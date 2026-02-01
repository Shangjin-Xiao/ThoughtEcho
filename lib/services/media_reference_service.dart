import 'dart:io';
import 'dart:convert';
import 'package:meta/meta.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';
import '../utils/app_logger.dart';
import '../models/quote_model.dart';
import 'database_service.dart';

/// 媒体文件引用管理服务
///
/// 负责管理媒体文件的引用关系，包括：
/// - 添加和移除媒体文件引用
/// - 计算引用计数
/// - 检测和清理孤儿文件
/// - 提供垃圾回收机制
class MediaReferenceService {
  static const String _tableName = 'media_references';
  static Database? _database;

  /// 设置测试用的数据库实例
  @visibleForTesting
  static void setDatabaseForTesting(Database db) {
    _database = db;
  }

  /// 获取数据库实例
  static Future<Database> get database async {
    if (_database != null) return _database!;

    final databaseService = DatabaseService();
    _database = databaseService.database;
    return _database!;
  }

  /// 初始化媒体引用表
  static Future<void> initializeTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $_tableName (
        id TEXT PRIMARY KEY,
        file_path TEXT NOT NULL,
        quote_id TEXT NOT NULL,
        created_at TEXT NOT NULL,
        FOREIGN KEY (quote_id) REFERENCES quotes (id) ON DELETE CASCADE,
        UNIQUE(file_path, quote_id)
      )
    ''');

    // 创建索引以提高查询性能
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_media_references_file_path 
      ON $_tableName (file_path)
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_media_references_quote_id 
      ON $_tableName (quote_id)
    ''');

    logDebug('媒体引用表初始化完成');
  }

  /// 添加媒体文件引用
  static Future<bool> addReference(String filePath, String quoteId) async {
    try {
      final db = await database;

      // 标准化文件路径
      final normalizedPath = await _normalizeFilePath(filePath);

      await db.insert(
        _tableName,
        {
          'id': const Uuid().v4(),
          'file_path': normalizedPath,
          'quote_id': quoteId,
          'created_at': DateTime.now().toIso8601String(),
        },
        conflictAlgorithm: ConflictAlgorithm.ignore, // 忽略重复引用
      );

      logDebug('添加媒体文件引用: $normalizedPath -> $quoteId');
      return true;
    } catch (e) {
      logDebug('添加媒体文件引用失败: $e');
      return false;
    }
  }

  /// 移除媒体文件引用
  static Future<bool> removeReference(String filePath, String quoteId) async {
    try {
      final db = await database;

      // 标准化文件路径
      final normalizedPath = await _normalizeFilePath(filePath);

      final result = await db.delete(
        _tableName,
        where: 'file_path = ? AND quote_id = ?',
        whereArgs: [normalizedPath, quoteId],
      );

      logDebug('移除媒体文件引用: $normalizedPath -> $quoteId (删除了 $result 条记录)');
      return result > 0;
    } catch (e) {
      logDebug('移除媒体文件引用失败: $e');
      return false;
    }
  }

  /// 移除笔记的所有媒体文件引用
  static Future<int> removeAllReferencesForQuote(String quoteId) async {
    try {
      final db = await database;

      final result = await db.delete(
        _tableName,
        where: 'quote_id = ?',
        whereArgs: [quoteId],
      );

      logDebug('移除笔记的所有媒体文件引用: $quoteId (删除了 $result 条记录)');
      return result;
    } catch (e) {
      logDebug('移除笔记媒体文件引用失败: $e');
      return 0;
    }
  }

  /// 获取媒体文件的引用计数
  static Future<int> getReferenceCount(String filePath) async {
    try {
      final db = await database;

      // 标准化文件路径
      final normalizedPath = await _normalizeFilePath(filePath);

      final result = await db.rawQuery(
        'SELECT COUNT(*) as count FROM $_tableName WHERE file_path = ?',
        [normalizedPath],
      );

      final count = result.first['count'] as int;
      return count;
    } catch (e) {
      logDebug('获取媒体文件引用计数失败: $e');
      return 0;
    }
  }

  /// 获取笔记引用的所有媒体文件
  static Future<List<String>> getReferencedFiles(String quoteId) async {
    try {
      final db = await database;

      final result = await db.query(
        _tableName,
        columns: ['file_path'],
        where: 'quote_id = ?',
        whereArgs: [quoteId],
      );

      return result.map((row) => row['file_path'] as String).toList();
    } catch (e) {
      logDebug('获取笔记引用的媒体文件失败: $e');
      return [];
    }
  }

  /// 检测孤儿文件（没有被任何笔记引用的文件）
  static Future<List<String>> detectOrphanFiles() async {
    try {
      final plan = await _planOrphanCleanupStreamed();
      logDebug(
        '检测到 ${plan.candidates.length} 个孤儿文件，待修复引用 ${plan.missingReferencePairs} 条',
      );
      return plan.candidates.map((c) => c.absolutePath).toList();
    } catch (e) {
      logDebug('检测孤儿文件失败: $e');
      return [];
    }
  }

  /// 清理孤儿文件
  static Future<int> cleanupOrphanFiles({bool dryRun = false}) async {
    try {
      final plan = await _planOrphanCleanupStreamed();

      if (plan.missingReferencePairs > 0) {
        if (dryRun) {
          logDebug('检测到 ${plan.missingReferencePairs} 条缺失的引用记录，实际执行时将自动修复');
        } else {
          final healed = await _healMissingReferences(
            plan.missingReferenceIndex,
          );
          if (healed > 0) {
            logDebug('已自动修复 $healed 条缺失的媒体引用记录');
          }
        }
      }

      if (plan.candidates.isEmpty) {
        logDebug('${dryRun ? '模拟' : '实际'}清理完成：未发现孤儿文件');
        return 0;
      }

      int cleanedCount = 0;

      if (dryRun) {
        for (final candidate in plan.candidates) {
          logDebug('(模拟) 将删除孤儿文件: ${candidate.absolutePath}');
        }
        cleanedCount = plan.candidates.length;
      } else {
        for (final candidate in plan.candidates) {
          try {
            final file = File(candidate.absolutePath);
            if (await file.exists()) {
              await file.delete();
              cleanedCount++;
              logDebug('已删除孤儿文件: ${candidate.absolutePath}');
            }
          } catch (e) {
            logDebug('删除孤儿文件失败: ${candidate.absolutePath}, 错误: $e');
          }
        }
      }

      logDebug('${dryRun ? '模拟' : '实际'}清理完成，共处理 $cleanedCount 个孤儿文件');
      return cleanedCount;
    } catch (e) {
      logDebug('清理孤儿文件失败: $e');
      return 0;
    }
  }

  // ignore: unused_element
  static Future<_CleanupPlan> _planOrphanCleanup() async {
    final snapshot = await _buildReferenceSnapshot();
    final allMediaFiles = await _getAllMediaFiles();

    final candidates = <_OrphanCandidate>[];
    final missingReferences = <String, Map<String, Set<String>>>{};

    for (final filePath in allMediaFiles) {
      final normalizedPath = await _normalizeFilePath(filePath);
      final canonicalKey = _canonicalComparisonKey(normalizedPath);

      final storedVariants = snapshot.storedIndex[canonicalKey];
      final quoteVariants = snapshot.quoteIndex[canonicalKey];

      final hasStoredRefs = storedVariants != null &&
          storedVariants.values.any((refs) => refs.isNotEmpty);
      final hasQuoteRefs = quoteVariants != null &&
          quoteVariants.values.any((refs) => refs.isNotEmpty);

      if (hasQuoteRefs) {
        final variants = quoteVariants;
        if (!hasStoredRefs) {
          missingReferences[canonicalKey] = variants.map(
            (variantPath, ids) => MapEntry(variantPath, Set<String>.from(ids)),
          );
        }
        continue;
      }

      if (hasStoredRefs) {
        continue;
      }

      candidates.add(
        _OrphanCandidate(
          absolutePath: filePath,
          normalizedPath: normalizedPath,
          canonicalKey: canonicalKey,
        ),
      );
    }

    return _CleanupPlan(
      candidates: candidates,
      missingReferenceIndex: missingReferences,
    );
  }

  /// 迭代式构建清理计划，避免一次性加载所有笔记
  static Future<_CleanupPlan> _planOrphanCleanupStreamed() async {
    final storedIndex = await _fetchStoredReferenceIndex();
    final quoteIndex = await _collectQuoteReferenceIndexStreamed();
    final snapshot =
        _ReferenceSnapshot(storedIndex: storedIndex, quoteIndex: quoteIndex);
    final allMediaFiles = await _getAllMediaFiles();
    final candidates = <_OrphanCandidate>[];
    final missingReferences = <String, Map<String, Set<String>>>{};

    for (final filePath in allMediaFiles) {
      final normalizedPath = await _normalizeFilePath(filePath);
      final canonicalKey = _canonicalComparisonKey(normalizedPath);

      final storedVariants = snapshot.storedIndex[canonicalKey];
      final quoteVariants = snapshot.quoteIndex[canonicalKey];

      final hasStoredRefs = storedVariants != null &&
          storedVariants.values.any((refs) => refs.isNotEmpty);
      final hasQuoteRefs = quoteVariants != null &&
          quoteVariants.values.any((refs) => refs.isNotEmpty);

      if (hasQuoteRefs) {
        final variants = quoteVariants;
        if (!hasStoredRefs) {
          missingReferences[canonicalKey] = variants.map(
            (variantPath, ids) => MapEntry(variantPath, Set<String>.from(ids)),
          );
        }
        continue;
      }

      if (hasStoredRefs) {
        continue;
      }

      candidates.add(
        _OrphanCandidate(
          absolutePath: filePath,
          normalizedPath: normalizedPath,
          canonicalKey: canonicalKey,
        ),
      );
    }

    return _CleanupPlan(
      candidates: candidates,
      missingReferenceIndex: missingReferences,
    );
  }

  /// 提供给备份使用的引用快照（避免重复全量扫描）
  static Future<_ReferenceSnapshot> buildReferenceSnapshotForBackup() async {
    return _buildReferenceSnapshot();
  }

  /// 备份/恢复使用的路径标准化（避免重复获取目录）
  static Future<String> normalizePathForBackup(
    String filePath, {
    required String appPath,
  }) async {
    try {
      if (filePath.isEmpty) {
        return filePath;
      }

      var sanitized = filePath.trim();

      if (sanitized.startsWith('file://')) {
        final uri = Uri.tryParse(sanitized);
        if (uri != null && uri.scheme == 'file') {
          sanitized = uri.toFilePath();
        }
      }

      sanitized = path.normalize(sanitized);

      if (sanitized.startsWith(appPath)) {
        return path.normalize(path.relative(sanitized, from: appPath));
      }

      return sanitized;
    } catch (_) {
      return filePath;
    }
  }

  /// 备份/恢复使用的统一比较Key
  static String canonicalKeyForBackup(String value) {
    return _canonicalComparisonKey(value);
  }

  static Future<_ReferenceSnapshot> _buildReferenceSnapshot() async {
    final storedIndex = await _fetchStoredReferenceIndex();
    final quoteIndex = await _collectQuoteReferenceIndex();
    return _ReferenceSnapshot(storedIndex: storedIndex, quoteIndex: quoteIndex);
  }

  static Future<Map<String, Map<String, Set<String>>>>
      _fetchStoredReferenceIndex() async {
    final db = await database;
    final rows = await db.query(_tableName, columns: ['file_path', 'quote_id']);

    final index = <String, Map<String, Set<String>>>{};

    for (final row in rows) {
      final filePath = row['file_path'] as String?;
      final quoteId = row['quote_id'] as String?;
      if (filePath == null || quoteId == null || quoteId.isEmpty) {
        continue;
      }

      final variantPath = path.normalize(filePath);
      final key = _canonicalComparisonKey(variantPath);

      final variants = index.putIfAbsent(key, () => <String, Set<String>>{});
      final quoteSet = variants.putIfAbsent(variantPath, () => <String>{});
      quoteSet.add(quoteId);
    }

    return index;
  }

  static Future<Map<String, Map<String, Set<String>>>>
      _collectQuoteReferenceIndex() async {
    final databaseService = DatabaseService();
    // 媒体引用索引需要包含所有笔记（包括隐藏笔记）
    final quotes =
        await databaseService.getAllQuotes(excludeHiddenNotes: false);

    final index = <String, Map<String, Set<String>>>{};

    for (final quote in quotes) {
      final quoteId = quote.id;
      if (quoteId == null || quoteId.isEmpty) {
        continue;
      }

      final mediaPaths = await extractMediaPathsFromQuote(quote);

      for (final mediaPath in mediaPaths) {
        final variantPath = path.normalize(mediaPath);
        final key = _canonicalComparisonKey(variantPath);

        final variants = index.putIfAbsent(key, () => <String, Set<String>>{});
        final quoteSet = variants.putIfAbsent(variantPath, () => <String>{});
        quoteSet.add(quoteId);
      }
    }

    return index;
  }

  /// 流式收集引用索引，避免一次性加载全部笔记
  static Future<Map<String, Map<String, Set<String>>>>
      _collectQuoteReferenceIndexStreamed() async {
    final databaseService = DatabaseService();
    final index = <String, Map<String, Set<String>>>{};
    const int pageSize = 200;
    var offset = 0;

    while (true) {
      final quotes = await databaseService.getUserQuotes(
        offset: offset,
        limit: pageSize,
        excludeHiddenNotes: false,
      );
      if (quotes.isEmpty) break;

      for (final quote in quotes) {
        final quoteId = quote.id;
        if (quoteId == null || quoteId.isEmpty) {
          continue;
        }

        final mediaPaths = await extractMediaPathsFromQuote(quote);

        for (final mediaPath in mediaPaths) {
          final variantPath = path.normalize(mediaPath);
          final key = _canonicalComparisonKey(variantPath);

          final variants =
              index.putIfAbsent(key, () => <String, Set<String>>{});
          final quoteSet = variants.putIfAbsent(variantPath, () => <String>{});
          quoteSet.add(quoteId);
        }
      }

      offset += quotes.length;
      if (quotes.length < pageSize) break;
    }

    return index;
  }

  static Future<int> _healMissingReferences(
    Map<String, Map<String, Set<String>>> missingIndex,
  ) async {
    int healed = 0;

    try {
      final db = await database;
      final batch = db.batch();

      // 获取应用目录路径缓存，避免循环中多次获取
      final appDir = await getApplicationDocumentsDirectory();
      final appPath = path.normalize(appDir.path);

      int batchCount = 0;

      for (final variants in missingIndex.values) {
        for (final entry in variants.entries) {
          final filePath = entry.key;

          // 使用缓存的 appPath 进行标准化
          final normalizedPath = await _normalizeFilePath(
            filePath,
            cachedAppPath: appPath,
          );

          for (final quoteId in entry.value) {
            batch.insert(
              _tableName,
              {
                'id': const Uuid().v4(),
                'file_path': normalizedPath,
                'quote_id': quoteId,
                'created_at': DateTime.now().toIso8601String(),
              },
              conflictAlgorithm: ConflictAlgorithm.ignore, // 忽略重复引用
            );
            batchCount++;
          }
        }
      }

      if (batchCount > 0) {
        await batch.commit(noResult: true);
        healed = batchCount;
        logDebug('批量修复完成，共处理 $healed 条引用');
      }
    } catch (e) {
      logDebug('批量修复媒体引用失败: $e');
    }

    return healed;
  }

  static String _canonicalComparisonKey(String value) {
    if (value.isEmpty) {
      return value;
    }

    var key = value.trim();
    key = key.replaceAll('\\', '/');

    while (key.contains('//')) {
      key = key.replaceAll('//', '/');
    }

    if (key.startsWith('./')) {
      key = key.substring(2);
    }

    return key;
  }

  /// 轻量级检查单个文件是否仍被引用（双重校验：引用表 + 笔记内容）
  /// 返回 true 表示文件已被安全删除，false 表示文件仍被引用或删除失败
  static Future<bool> quickCheckAndDeleteIfOrphan(String filePath) async {
    try {
      final normalizedPath = await _normalizeFilePath(filePath);

      // 1. 优先查引用表（高性能）
      final refCount = await getReferenceCount(normalizedPath);
      if (refCount > 0) {
        return false; // 仍被引用，不删除
      }

      // 2. 二次确认：即使引用表说没有，也从笔记内容中全文搜索一次（防止引用表损坏/不同步导致的误删）
      // 注意：这步对于数据安全至关重要
      final dbService = DatabaseService();
      final quotesWithFile =
          await dbService.searchQuotesByContent(normalizedPath);

      if (quotesWithFile.isNotEmpty) {
        logDebug(
            '警告：文件 $filePath 在引用表中无记录，但在 ${quotesWithFile.length} 条笔记内容中发现引用。正在自动修复引用表并跳过删除。');
        // 自动修复逻辑：重建引用记录
        for (final quote in quotesWithFile) {
          if (quote.id != null) {
            await addReference(normalizedPath, quote.id!);
          }
        }
        return false;
      }

      // 引用计数为0且内容中未搜到，执行删除
      final file = File(filePath);
      if (await file.exists()) {
        await file.delete();
        logDebug('已删除无引用文件: $filePath');
        return true;
      }

      return false;
    } catch (e) {
      logDebug('检查并删除文件失败: $filePath, 错误: $e');
      return false;
    }
  }

  /// 安全检查并清理单个媒体文件（使用快照机制，避免误删）
  /// 返回 true 表示文件已被安全删除，false 表示文件仍被引用或删除失败
  static Future<bool> safeCheckAndDeleteOrphan(String filePath) async {
    try {
      final snapshot = await _buildReferenceSnapshot();
      final normalizedPath = await _normalizeFilePath(filePath);
      final canonicalKey = _canonicalComparisonKey(normalizedPath);

      final storedVariants = snapshot.storedIndex[canonicalKey];
      final quoteVariants = snapshot.quoteIndex[canonicalKey];

      final hasStoredRefs = storedVariants != null &&
          storedVariants.values.any((refs) => refs.isNotEmpty);
      final hasQuoteRefs = quoteVariants != null &&
          quoteVariants.values.any((refs) => refs.isNotEmpty);

      // 如果在笔记内容中找到引用，先尝试修复缺失的引用记录
      if (hasQuoteRefs) {
        final variants = quoteVariants;
        if (!hasStoredRefs) {
          logDebug('检测到文件 $filePath 在笔记中有引用但缺失引用记录，尝试修复...');
          for (final entry in variants.entries) {
            final variantPath = entry.key;
            for (final quoteId in entry.value) {
              await addReference(variantPath, quoteId);
            }
          }
          logDebug('已修复文件 $filePath 的引用记录');
        }
        // 文件仍被引用，不删除
        return false;
      }

      // 如果在引用表中有记录，不删除
      if (hasStoredRefs) {
        return false;
      }

      // 确认是孤儿文件，执行删除
      final file = File(filePath);
      if (await file.exists()) {
        await file.delete();
        logDebug('安全删除孤儿文件: $filePath');
        return true;
      }

      return false;
    } catch (e) {
      logDebug('安全检查并删除文件失败: $filePath, 错误: $e');
      return false;
    }
  }

  /// 从笔记内容中提取媒体文件路径
  static Future<List<String>> extractMediaPathsFromQuote(Quote quote) async {
    final mediaPaths = <String>[];

    try {
      // 如果有富文本内容，从Delta中提取
      if (quote.deltaContent != null && quote.deltaContent!.isNotEmpty) {
        final deltaJson = jsonDecode(quote.deltaContent!);
        if (deltaJson is List) {
          for (final op in deltaJson) {
            if (op is Map && op.containsKey('insert')) {
              final insert = op['insert'];
              if (insert is Map) {
                // 检查图片
                if (insert.containsKey('image')) {
                  final imagePath = insert['image'] as String?;
                  if (imagePath != null) {
                    final normalizedPath = await _normalizeFilePath(imagePath);
                    mediaPaths.add(normalizedPath);
                  }
                }

                // 检查视频
                if (insert.containsKey('video')) {
                  final videoPath = insert['video'] as String?;
                  if (videoPath != null) {
                    final normalizedPath = await _normalizeFilePath(videoPath);
                    mediaPaths.add(normalizedPath);
                  }
                }

                // 检查自定义嵌入（如音频）
                if (insert.containsKey('custom')) {
                  final custom = insert['custom'];
                  if (custom is Map && custom.containsKey('audio')) {
                    final audioPath = custom['audio'] as String?;
                    if (audioPath != null) {
                      final normalizedPath = await _normalizeFilePath(
                        audioPath,
                      );
                      mediaPaths.add(normalizedPath);
                    }
                  }
                }
              }
            }
          }
        }
      }
    } catch (e) {
      logDebug('从笔记内容提取媒体文件路径失败: $e');
    }

    return mediaPaths.toSet().toList(); // 去重
  }

  /// 同步笔记的媒体文件引用
  static Future<bool> syncQuoteMediaReferences(Quote quote) async {
    try {
      final quoteId = quote.id;
      if (quoteId == null) {
        logDebug('笔记ID为空，跳过媒体引用同步');
        return false;
      }

      // 先移除该笔记的所有现有引用
      await removeAllReferencesForQuote(quoteId);

      // 从笔记内容中提取媒体文件路径
      final mediaPaths = await extractMediaPathsFromQuote(quote);

      // 添加新的引用
      for (final mediaPath in mediaPaths) {
        await addReference(mediaPath, quoteId);
      }

      logDebug('同步笔记媒体文件引用完成: $quoteId, 共 ${mediaPaths.length} 个文件');
      return true;
    } catch (e) {
      logDebug('同步笔记媒体文件引用失败: $e');
      return false;
    }
  }

  /// 同步笔记的媒体文件引用（事务内版本）
  static Future<bool> syncQuoteMediaReferencesWithTransaction(
    DatabaseExecutor txn,
    Quote quote,
  ) async {
    try {
      final quoteId = quote.id;
      if (quoteId == null) {
        logDebug('笔记ID为空，跳过媒体引用同步');
        return false;
      }

      // 先移除该笔记的所有现有引用
      await txn.delete(
        _tableName,
        where: 'quote_id = ?',
        whereArgs: [quoteId],
      );

      // 从笔记内容中提取媒体文件路径
      final mediaPaths = await extractMediaPathsFromQuote(quote);

      // 添加新的引用
      for (final mediaPath in mediaPaths) {
        final normalizedPath = await _normalizeFilePath(mediaPath);
        await txn.insert(
          _tableName,
          {
            'id': const Uuid().v4(),
            'file_path': normalizedPath,
            'quote_id': quoteId,
            'created_at': DateTime.now().toIso8601String(),
          },
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
      }

      logDebug('同步笔记媒体文件引用完成: $quoteId, 共 ${mediaPaths.length} 个文件');
      return true;
    } catch (e) {
      logDebug('同步笔记媒体文件引用失败: $e');
      return false;
    }
  }

  /// 获取所有媒体文件路径
  static Future<List<String>> _getAllMediaFiles() async {
    final mediaFiles = <String>[];

    try {
      final appDir = await getApplicationDocumentsDirectory();
      final mediaDir = Directory(path.join(appDir.path, 'media'));

      if (!await mediaDir.exists()) {
        return mediaFiles;
      }

      await for (final entity in mediaDir.list(recursive: true)) {
        if (entity is File) {
          mediaFiles.add(entity.path);
        }
      }
    } catch (e) {
      logDebug('获取所有媒体文件失败: $e');
    }

    return mediaFiles;
  }

  /// 标准化文件路径（转换为相对路径）
  static Future<String> _normalizeFilePath(
    String filePath, {
    String? cachedAppPath,
  }) async {
    try {
      if (filePath.isEmpty) {
        return filePath;
      }

      var sanitized = filePath.trim();

      if (sanitized.startsWith('file://')) {
        final uri = Uri.tryParse(sanitized);
        if (uri != null && uri.scheme == 'file') {
          sanitized = uri.toFilePath();
        }
      }

      sanitized = path.normalize(sanitized);

      final appPath = cachedAppPath ??
          path.normalize((await getApplicationDocumentsDirectory()).path);

      if (sanitized.startsWith(appPath)) {
        return path.normalize(path.relative(sanitized, from: appPath));
      }

      return sanitized;
    } catch (_) {
      return filePath;
    }
  }

  /// 获取媒体引用统计信息
  static Future<Map<String, dynamic>> getMediaReferenceStats() async {
    try {
      final db = await database;

      // 总引用数
      final totalRefsResult = await db.rawQuery(
        'SELECT COUNT(*) as count FROM $_tableName',
      );
      final totalRefs = totalRefsResult.first['count'] as int;

      // 被引用的文件数
      final referencedFilesResult = await db.rawQuery(
        'SELECT COUNT(DISTINCT file_path) as count FROM $_tableName',
      );
      final referencedFiles = referencedFilesResult.first['count'] as int;

      // 总媒体文件数
      final allMediaFiles = await _getAllMediaFiles();
      final totalFiles = allMediaFiles.length;

      // 孤儿文件数
      final orphanFiles = totalFiles - referencedFiles;

      return {
        'totalReferences': totalRefs,
        'referencedFiles': referencedFiles,
        'totalFiles': totalFiles,
        'orphanFiles': orphanFiles,
      };
    } catch (e) {
      logDebug('获取媒体引用统计信息失败: $e');
      return {
        'totalReferences': 0,
        'referencedFiles': 0,
        'totalFiles': 0,
        'orphanFiles': 0,
      };
    }
  }

  /// 迁移现有笔记的媒体文件引用
  static Future<int> migrateExistingQuotes() async {
    try {
      logDebug('开始迁移现有笔记的媒体文件引用...');

      final databaseService = DatabaseService();
      // 媒体引用迁移需要处理所有笔记（包括隐藏笔记）
      // 修复：使用分页加载以避免内存溢出
      int migratedCount = 0;
      const int pageSize = 200;
      var offset = 0;

      while (true) {
        final quotes = await databaseService.getUserQuotes(
          offset: offset,
          limit: pageSize,
          excludeHiddenNotes: false,
        );
        if (quotes.isEmpty) break;

        for (final quote in quotes) {
          final success = await syncQuoteMediaReferences(quote);
          if (success) {
            migratedCount++;
          }
        }

        offset += quotes.length;
        if (quotes.length < pageSize) break;

        // 让出事件循环，避免长时间阻塞UI
        await Future.delayed(const Duration(milliseconds: 0));
      }

      logDebug('迁移完成，共处理 $migratedCount 个笔记');
      return migratedCount;
    } catch (e) {
      logDebug('迁移现有笔记媒体文件引用失败: $e');
      return 0;
    }
  }
}

class _ReferenceSnapshot {
  final Map<String, Map<String, Set<String>>> storedIndex;
  final Map<String, Map<String, Set<String>>> quoteIndex;

  const _ReferenceSnapshot({
    required this.storedIndex,
    required this.quoteIndex,
  });
}

class _CleanupPlan {
  final List<_OrphanCandidate> candidates;
  final Map<String, Map<String, Set<String>>> missingReferenceIndex;

  const _CleanupPlan({
    required this.candidates,
    required this.missingReferenceIndex,
  });

  int get missingReferencePairs {
    var total = 0;
    for (final variants in missingReferenceIndex.values) {
      for (final ids in variants.values) {
        total += ids.length;
      }
    }
    return total;
  }
}

class _OrphanCandidate {
  final String absolutePath;
  final String normalizedPath;
  final String canonicalKey;

  const _OrphanCandidate({
    required this.absolutePath,
    required this.normalizedPath,
    required this.canonicalKey,
  });
}
