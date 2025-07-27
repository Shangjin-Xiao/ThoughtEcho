import 'dart:io';
import 'dart:convert';
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
      final orphanFiles = <String>[];

      // 获取所有媒体文件
      final allMediaFiles = await _getAllMediaFiles();

      // 检查每个文件的引用计数
      for (final filePath in allMediaFiles) {
        final count = await getReferenceCount(filePath);
        if (count == 0) {
          orphanFiles.add(filePath);
        }
      }

      logDebug('检测到 ${orphanFiles.length} 个孤儿文件');
      return orphanFiles;
    } catch (e) {
      logDebug('检测孤儿文件失败: $e');
      return [];
    }
  }

  /// 清理孤儿文件
  static Future<int> cleanupOrphanFiles({bool dryRun = false}) async {
    try {
      final orphanFiles = await detectOrphanFiles();
      int cleanedCount = 0;

      for (final filePath in orphanFiles) {
        try {
          if (dryRun) {
            logDebug('(模拟) 将删除孤儿文件: $filePath');
            cleanedCount++;
          } else {
            final file = File(filePath);
            if (await file.exists()) {
              await file.delete();
              logDebug('已删除孤儿文件: $filePath');
              cleanedCount++;
            }
          }
        } catch (e) {
          logDebug('删除孤儿文件失败: $filePath, 错误: $e');
        }
      }

      logDebug('${dryRun ? '模拟' : '实际'}清理完成，共处理 $cleanedCount 个孤儿文件');
      return cleanedCount;
    } catch (e) {
      logDebug('清理孤儿文件失败: $e');
      return 0;
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
                      final normalizedPath =
                          await _normalizeFilePath(audioPath);
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
  static Future<String> _normalizeFilePath(String filePath) async {
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final appPath = appDir.path;

      if (filePath.startsWith(appPath)) {
        return path.relative(filePath, from: appPath);
      }

      return filePath;
    } catch (e) {
      return filePath;
    }
  }

  /// 获取媒体引用统计信息
  static Future<Map<String, dynamic>> getMediaReferenceStats() async {
    try {
      final db = await database;

      // 总引用数
      final totalRefsResult =
          await db.rawQuery('SELECT COUNT(*) as count FROM $_tableName');
      final totalRefs = totalRefsResult.first['count'] as int;

      // 被引用的文件数
      final referencedFilesResult = await db.rawQuery(
          'SELECT COUNT(DISTINCT file_path) as count FROM $_tableName');
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
      final quotes = await databaseService.getAllQuotes();

      int migratedCount = 0;

      for (final quote in quotes) {
        final success = await syncQuoteMediaReferences(quote);
        if (success) {
          migratedCount++;
        }
      }

      logDebug('迁移完成，共处理 $migratedCount 个笔记');
      return migratedCount;
    } catch (e) {
      logDebug('迁移现有笔记媒体文件引用失败: $e');
      return 0;
    }
  }
}
