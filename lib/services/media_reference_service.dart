import 'dart:io';
import 'dart:convert';
import 'dart:math' as math;
import 'package:meta/meta.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';
import '../utils/app_logger.dart';
import '../models/quote_model.dart';
import 'database_service.dart';

part 'media_reference/media_reference_cleanup.dart';
part 'media_reference/media_reference_sync.dart';

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
  static Future<bool> addReference(
    String filePath,
    String quoteId, {
    String? cachedAppPath,
  }) async {
    try {
      final db = await database;

      // 标准化文件路径
      final normalizedPath = await _normalizeFilePath(
        filePath,
        cachedAppPath: cachedAppPath,
      );

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
  static Future<bool> removeReference(
    String filePath,
    String quoteId, {
    String? cachedAppPath,
  }) async {
    try {
      final db = await database;

      // 标准化文件路径
      final normalizedPath = await _normalizeFilePath(
        filePath,
        cachedAppPath: cachedAppPath,
      );

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
  static Future<int> getReferenceCount(
    String filePath, {
    String? cachedAppPath,
  }) async {
    try {
      final db = await database;

      // 标准化文件路径
      final normalizedPath = await _normalizeFilePath(
        filePath,
        cachedAppPath: cachedAppPath,
      );

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

  /// 批量获取多个笔记引用的媒体文件
  static Future<Map<String, List<String>>> getReferencedFilesBatch(
    Iterable<String> quoteIds,
  ) async {
    const int maxChunkSize = 900;
    final uniqueIds = quoteIds.where((id) => id.isNotEmpty).toSet().toList();
    if (uniqueIds.isEmpty) {
      return {};
    }

    try {
      final db = await database;
      final grouped = <String, List<String>>{};

      for (var start = 0; start < uniqueIds.length; start += maxChunkSize) {
        final end = math.min(start + maxChunkSize, uniqueIds.length);
        final chunk = uniqueIds.sublist(start, end);
        final placeholders = List.filled(chunk.length, '?').join(',');
        final result = await db.query(
          _tableName,
          columns: ['quote_id', 'file_path'],
          where: 'quote_id IN ($placeholders)',
          whereArgs: chunk,
        );

        for (final row in result) {
          final quoteId = row['quote_id'] as String?;
          final filePath = row['file_path'] as String?;
          if (quoteId == null || filePath == null) {
            continue;
          }
          grouped.putIfAbsent(quoteId, () => <String>[]).add(filePath);
        }
      }
      return grouped;
    } catch (e, stackTrace) {
      logError(
        '批量获取笔记引用的媒体文件失败: $e',
        error: e,
        stackTrace: stackTrace,
        source: 'MediaReferenceService',
      );
      rethrow;
    }
  }

  /// 检测孤儿文件（没有被任何笔记引用的文件）
  static Future<List<String>> detectOrphanFiles() async {
    return _detectOrphanFiles();
  }

  /// 清理孤儿文件
  static Future<int> cleanupOrphanFiles({bool dryRun = false}) async {
    return _cleanupOrphanFiles(dryRun: dryRun);
  }

  /// 轻量级检查单个文件是否仍被引用（双重校验：引用表 + 笔记内容）
  /// 返回 true 表示文件已被安全删除，false 表示文件仍被引用或删除失败
  static Future<bool> quickCheckAndDeleteIfOrphan(
    String filePath, {
    String? cachedAppPath,
  }) async {
    return _quickCheckAndDeleteIfOrphan(filePath, cachedAppPath: cachedAppPath);
  }

  /// 安全检查并清理单个媒体文件（使用快照机制，避免误删）
  /// 返回 true 表示文件已被安全删除，false 表示文件仍被引用或删除失败
  static Future<bool> safeCheckAndDeleteOrphan(
    String filePath, {
    String? cachedAppPath,
  }) async {
    return _safeCheckAndDeleteOrphan(filePath, cachedAppPath: cachedAppPath);
  }

  /// 提供给备份使用的引用快照（避免重复全量扫描）
  static Future<ReferenceSnapshot> buildReferenceSnapshotForBackup() async {
    return _buildReferenceSnapshotForBackup();
  }

  /// 备份/恢复使用的路径标准化（避免重复获取目录）
  static Future<String> normalizePathForBackup(
    String filePath, {
    required String appPath,
  }) async {
    return _normalizePathForBackup(filePath, appPath: appPath);
  }

  /// 备份/恢复使用的统一比较Key
  static String canonicalKeyForBackup(String value) {
    return _canonicalKeyForBackup(value);
  }

  /// 从笔记内容中提取媒体文件路径
  static Future<List<String>> extractMediaPathsFromQuote(
    Quote quote, {
    String? cachedAppPath,
  }) async {
    return _extractMediaPathsFromQuote(quote, cachedAppPath: cachedAppPath);
  }

  /// 同步笔记的媒体文件引用
  static Future<bool> syncQuoteMediaReferences(
    Quote quote, {
    String? cachedAppPath,
  }) async {
    return _syncQuoteMediaReferences(quote, cachedAppPath: cachedAppPath);
  }

  /// 同步笔记的媒体文件引用（事务内版本）
  static Future<bool> syncQuoteMediaReferencesWithTransaction(
    DatabaseExecutor txn,
    Quote quote,
  ) async {
    return _syncQuoteMediaReferencesWithTransaction(txn, quote);
  }

  /// 获取媒体引用统计信息
  static Future<Map<String, dynamic>> getMediaReferenceStats() async {
    return _getMediaReferenceStats();
  }

  /// 迁移现有笔记的媒体文件引用
  static Future<int> migrateExistingQuotes() async {
    return _migrateExistingQuotes();
  }
}
