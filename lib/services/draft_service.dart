import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../utils/app_logger.dart';
import '../utils/mmkv_ffi_fix.dart' show kDraftsSqliteMigratedKey;
import 'app_preferences_service.dart';

/// 笔记草稿持久化服务（基于独立本地 SQLite `drafts.db`）
///
/// 草稿属于高频变更、体量较大的本地临时编辑态，不进入 KV 存储、备份或设备同步。
/// 首次访问时会自动将历史遗留 KV 键（`draft_*`）幂等迁移至 `drafts.db` 并清理旧键。
class DraftService {
  static final DraftService _instance = DraftService._internal();
  factory DraftService() => _instance;
  DraftService._internal();

  static const String _databaseFileName = 'drafts.db';
  static const String _tableName = 'note_drafts';
  static const int _schemaVersion = 1;

  Database? _database;
  String? _testDatabasePath;
  Future<void> _dbLock = Future<void>.value();

  Future<T> _withDbLock<T>(Future<T> Function() action) {
    final result = Completer<T>();
    Zone.root.run(() {
      final completer = Completer<void>();
      final previous = _dbLock;
      _dbLock = completer.future;
      previous.then((_) => action()).then(
        (value) {
          if (!result.isCompleted) {
            result.complete(value);
          }
        },
        onError: (Object error, StackTrace stackTrace) {
          if (!result.isCompleted) {
            result.completeError(error, stackTrace);
          }
        },
      ).whenComplete(() {
        if (!completer.isCompleted) {
          completer.complete();
        }
      });
    });
    return result.future;
  }

  String _normalizeId(String id) {
    return id.replaceAll(RegExp(r'[^\w\-]'), '_');
  }

  /// 仅供测试注入自定义数据库路径（如 `inMemoryDatabasePath` 或临时文件路径）。
  @visibleForTesting
  void configureForTesting({String? databasePath}) {
    _testDatabasePath = databasePath;
  }

  /// 仅供测试关闭数据库连接并重置内部状态。
  @visibleForTesting
  Future<void> resetForTesting() {
    return _withDbLock(() async {
      final db = _database;
      _database = null;
      _testDatabasePath = null;
      if (db != null && db.isOpen) {
        try {
          await db.close();
        } catch (e) {
          logDebug('DraftService resetForTesting 关闭数据库失败: $e');
        }
      }
    });
  }

  Future<String> _resolveDatabasePath() async {
    final customPath = _testDatabasePath;
    if (customPath != null && customPath.isNotEmpty) {
      return customPath;
    }
    final documentsDir = await getApplicationDocumentsDirectory();
    return p.join(documentsDir.path, _databaseFileName);
  }

  Future<Database> _openDatabase() async {
    final existing = _database;
    if (existing != null && existing.isOpen) {
      return existing;
    }

    if (!kIsWeb &&
        (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
      if (databaseFactory != databaseFactoryFfi) {
        sqfliteFfiInit();
        databaseFactory = databaseFactoryFfi;
      }
    }

    final dbPath = await _resolveDatabasePath();
    if (dbPath != inMemoryDatabasePath) {
      final dir = Directory(p.dirname(dbPath));
      if (!dir.existsSync()) {
        dir.createSync(recursive: true);
      }
    }

    final db = await databaseFactory.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(
        version: _schemaVersion,
        onCreate: (db, version) async => _ensureSchema(db),
        onOpen: (db) async => _ensureSchema(db),
      ),
    );
    _database = db;
    return db;
  }

  static Future<void> _ensureSchema(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $_tableName (
        id TEXT PRIMARY KEY,
        has_body_text INTEGER NOT NULL DEFAULT 0,
        has_user_content INTEGER NOT NULL DEFAULT 1,
        updated_at_ms INTEGER,
        payload_json TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_note_drafts_latest
      ON $_tableName (has_body_text, has_user_content, updated_at_ms DESC)
    ''');
  }

  Future<Database> _ensureDatabaseAndMigrated() async {
    final db = await _openDatabase();
    await _migrateLegacyKvDraftsIfNeeded(db);
    return db;
  }

  Future<void> _migrateLegacyKvDraftsIfNeeded(Database db) async {
    try {
      final prefs = AppPreferencesService();
      await prefs.init();
      if (prefs.getBool(kDraftsSqliteMigratedKey) == true) {
        return;
      }

      final legacyKeys = prefs
          .getAllKeys()
          .where((k) => k.startsWith('draft_'))
          .toList(growable: false);

      if (legacyKeys.isNotEmpty) {
        final rowsToInsert = <Map<String, Object?>>[];
        for (final key in legacyKeys) {
          final raw = prefs.getString(key);
          final data = _parseDraftData(raw);
          if (data == null) continue;
          final normalizedId = _normalizeId(key.substring(6));
          if (normalizedId.isEmpty) continue;
          rowsToInsert.add(_buildRow(normalizedId, data));
        }

        if (rowsToInsert.isNotEmpty) {
          await db.transaction((txn) async {
            final batch = txn.batch();
            for (final row in rowsToInsert) {
              batch.insert(
                _tableName,
                row,
                conflictAlgorithm: ConflictAlgorithm.ignore,
              );
            }
            await batch.commit(noResult: true);
          });
        }

        for (final key in legacyKeys) {
          await prefs.remove(key);
        }
        logDebug('DraftService 已迁移并清理 ${legacyKeys.length} 个历史 KV 草稿键');
      }

      await prefs.setBool(kDraftsSqliteMigratedKey, true);
    } catch (e, stackTrace) {
      logError(
        '迁移历史 KV 草稿失败（保留现有 SQLite 草稿并稍后重试）',
        error: e,
        stackTrace: stackTrace,
        source: 'DraftService',
      );
    }
  }

  Map<String, Object?> _buildRow(String id, Map<String, dynamic> data) {
    final plainText = data['plainText'];
    final hasBodyText =
        plainText is String && plainText.trim().isNotEmpty ? 1 : 0;

    final rawHasUserContent = data['hasUserContent'];
    final hasUserContent =
        (rawHasUserContent is bool ? rawHasUserContent : true) ? 1 : 0;

    int? updatedAtMs;
    if (data.containsKey('timestamp')) {
      final tsStr = data['timestamp']?.toString();
      if (tsStr != null) {
        updatedAtMs = DateTime.tryParse(tsStr)?.millisecondsSinceEpoch;
      }
    }

    return {
      'id': id,
      'has_body_text': hasBodyText,
      'has_user_content': hasUserContent,
      'updated_at_ms': updatedAtMs,
      'payload_json': jsonEncode(data),
    };
  }

  Map<String, dynamic>? _parseDraftData(dynamic stored) {
    if (stored == null) return null;
    if (stored is Map<String, dynamic>) return stored;
    if (stored is Map) {
      return stored.map((k, v) => MapEntry(k.toString(), v));
    }
    if (stored is String) {
      try {
        final decoded = jsonDecode(stored);
        if (decoded is Map) {
          return decoded.map((k, v) => MapEntry(k.toString(), v));
        }
      } catch (e) {
        logDebug('解析草稿 JSON 失败: $e');
      }
    }
    return null;
  }

  /// 保存草稿
  Future<void> saveDraft(String id, Map<String, dynamic> data) {
    return _withDbLock(() async {
      try {
        final db = await _ensureDatabaseAndMigrated();
        final normalizedId = _normalizeId(id);
        await db.insert(
          _tableName,
          _buildRow(normalizedId, data),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
        logDebug('草稿已保存: $id (SQLite)');
      } catch (e, stackTrace) {
        logError(
          '保存草稿失败: $id',
          error: e,
          stackTrace: stackTrace,
          source: 'DraftService',
        );
      }
    });
  }

  /// 读取草稿
  Future<Map<String, dynamic>?> getDraft(String id) {
    return _withDbLock(() async {
      try {
        final db = await _ensureDatabaseAndMigrated();
        final normalizedId = _normalizeId(id);
        final rows = await db.query(
          _tableName,
          columns: ['payload_json'],
          where: 'id = ?',
          whereArgs: [normalizedId],
          limit: 1,
        );
        if (rows.isEmpty) return null;
        return _parseDraftData(rows.first['payload_json']);
      } catch (e, stackTrace) {
        logError(
          '读取草稿失败: $id',
          error: e,
          stackTrace: stackTrace,
          source: 'DraftService',
        );
        return null;
      }
    });
  }

  /// 删除草稿
  Future<void> deleteDraft(String id) {
    return _withDbLock(() async {
      try {
        final db = await _ensureDatabaseAndMigrated();
        final normalizedId = _normalizeId(id);
        await db.delete(
          _tableName,
          where: 'id = ?',
          whereArgs: [normalizedId],
        );
        logDebug('草稿已删除: $id (SQLite)');
      } catch (e, stackTrace) {
        logError(
          '删除草稿失败: $id',
          error: e,
          stackTrace: stackTrace,
          source: 'DraftService',
        );
      }
    });
  }

  /// 删除所有草稿
  Future<void> deleteAllDrafts() {
    return _withDbLock(() async {
      try {
        final db = await _ensureDatabaseAndMigrated();
        await db.delete(_tableName);
        logDebug('所有草稿已删除 (SQLite)');
      } catch (e, stackTrace) {
        logError(
          '删除所有草稿失败',
          error: e,
          stackTrace: stackTrace,
          source: 'DraftService',
        );
      }
    });
  }

  /// 检查是否存在草稿
  Future<bool> hasDraft(String id) {
    return _withDbLock(() async {
      try {
        final db = await _ensureDatabaseAndMigrated();
        final normalizedId = _normalizeId(id);
        final rows = await db.query(
          _tableName,
          columns: ['id'],
          where: 'id = ? AND length(payload_json) > 0',
          whereArgs: [normalizedId],
          limit: 1,
        );
        return rows.isNotEmpty;
      } catch (e, stackTrace) {
        logError(
          '检查草稿是否存在失败: $id',
          error: e,
          stackTrace: stackTrace,
          source: 'DraftService',
        );
        return false;
      }
    });
  }

  /// 获取所有已保存的草稿 ID 列表
  Future<List<String>> getAllDraftIds() {
    return _withDbLock(() async {
      try {
        final db = await _ensureDatabaseAndMigrated();
        final rows = await db.query(
          _tableName,
          columns: ['id'],
          orderBy: 'updated_at_ms DESC, rowid DESC',
        );
        return rows
            .map((r) => r['id']?.toString() ?? '')
            .where((id) => id.isNotEmpty)
            .toList(growable: false);
      } catch (e, stackTrace) {
        logError(
          '获取所有草稿 ID 失败',
          error: e,
          stackTrace: stackTrace,
          source: 'DraftService',
        );
        return const <String>[];
      }
    });
  }

  /// 获取最新的草稿信息（用于启动恢复）
  Future<Map<String, dynamic>?> getLatestDraft() {
    return _withDbLock(() async {
      try {
        final db = await _ensureDatabaseAndMigrated();
        final rows = await db.query(
          _tableName,
          columns: ['id', 'payload_json'],
          where:
              'has_body_text = 1 AND has_user_content = 1 AND updated_at_ms IS NOT NULL',
          orderBy: 'updated_at_ms DESC, rowid DESC',
          limit: 1,
        );
        if (rows.isEmpty) return null;

        final row = rows.first;
        final id = row['id']?.toString();
        final data = _parseDraftData(row['payload_json']);
        if (id == null || id.isEmpty || data == null) return null;

        return {
          'id': id,
          ...data,
        };
      } catch (e, stackTrace) {
        logError(
          '获取最新草稿失败',
          error: e,
          stackTrace: stackTrace,
          source: 'DraftService',
        );
        return null;
      }
    });
  }

  /// 获取所有草稿中引用的媒体文件路径
  Future<Set<String>> getAllMediaPathsInDrafts() {
    return _withDbLock(() async {
      final mediaPaths = <String>{};
      try {
        final db = await _ensureDatabaseAndMigrated();
        final rows = await db.query(
          _tableName,
          columns: ['id', 'payload_json'],
        );
        for (final row in rows) {
          final id = row['id']?.toString() ?? '<unknown>';
          try {
            final data = _parseDraftData(row['payload_json']);
            if (data == null) continue;

            if (data.containsKey('deltaContent')) {
              final deltaContent = data['deltaContent'];
              if (deltaContent is String) {
                try {
                  final delta = jsonDecode(deltaContent);
                  _extractMediaFromDelta(delta, mediaPaths);
                } catch (e) {
                  logDebug('[DraftService] delta content parse failed: $e');
                }
              }
            }
          } catch (e) {
            logDebug('扫描草稿媒体失败: $id, $e');
          }
        }
      } catch (e, stackTrace) {
        logError(
          '获取草稿媒体路径失败',
          error: e,
          stackTrace: stackTrace,
          source: 'DraftService',
        );
      }
      return mediaPaths;
    });
  }

  void _extractMediaFromDelta(dynamic delta, Set<String> paths) {
    if (delta is List) {
      for (final op in delta) {
        if (op is Map && op.containsKey('insert')) {
          final insert = op['insert'];
          if (insert is Map) {
            if (insert.containsKey('image')) {
              paths.add(insert['image'].toString());
            }
            if (insert.containsKey('video')) {
              paths.add(insert['video'].toString());
            }
            if (insert.containsKey('custom') && insert['custom'] is Map) {
              final custom = insert['custom'];
              if (custom.containsKey('audio')) {
                paths.add(custom['audio'].toString());
              }
            }
          }
        }
      }
    }
  }
}
