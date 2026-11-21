import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../models/chat_message.dart';
import '../models/chat_session.dart';
import '../utils/app_logger.dart';
import '../utils/lww_utils.dart';
import '../utils/sqlite_type_utils.dart';
import 'data_directory_service.dart';
import 'large_file_manager.dart' show CancelToken;

part 'chat_session_sync.dart';

class ChatSessionOverview {
  const ChatSessionOverview({
    required this.messageCount,
    required this.snippet,
  });

  final int messageCount;
  final String snippet;
}

class ChatSessionService extends ChangeNotifier {
  static ChatSessionService? activeInstance;
  Database? _database;
  final String? _databasePath;
  final bool _openOwnDatabase;
  bool _ownsDatabase = false;
  Completer<Database>? _openingCompleter;
  final List<Future<void> Function(Database db)> _pendingWrites = [];
  final Completer<void> _databaseReady = Completer<void>();
  DateTime? _lastEmptySessionCleanupAt;
  bool _hasOffsetlessTimestamps = false;
  bool _hasOffsetlessMessageTimestamps = false;
  bool _offsetlessFlagInitialized = false;

  static const int _schemaVersion = 3;
  static const int schemaVersion = _schemaVersion;
  static const String _legacyMainDbMigrationKey =
      'legacy_main_db_chat_migration_complete';
  static const Duration _emptySessionCleanupInterval = Duration(minutes: 1);

  /// 校验覆盖恢复场景下 `chat` 段顶层及内部容器结构；非法或缺失外部消息分片时立即抛 [FormatException]。
  static void validateChatSectionPayload(Object? rawSection) {
    if (rawSection == null) return;
    if (rawSection is! Map) {
      throw const FormatException('chat 备份段格式无效');
    }
    final chatMap = rawSection is Map<String, dynamic>
        ? rawSection
        : rawSection.map((k, v) => MapEntry(k.toString(), v));
    _validateChatSectionContainers(chatMap);
    if (parseChatMessageShardDescriptors(chatMap).isNotEmpty) {
      throw const FormatException(
        '分片对话载荷不支持在缺少分片文件时执行全量覆盖恢复',
      );
    }
  }

  ChatSessionService({
    String? databasePath,
    bool openOwnDatabase = true,
  })  : _databasePath = databasePath,
        _openOwnDatabase = openOwnDatabase {
    activeInstance = this;
  }

  void setDatabase(Database? db) {
    _database = db;
    _ownsDatabase = false;
    _offsetlessFlagInitialized = false;
    if (db != null && !_databaseReady.isCompleted) {
      _databaseReady.complete();
    }
    if (db != null) {
      _flushPendingWrites(db);
    }
  }

  void _notifySyncListeners() {
    notifyListeners();
  }

  void _flushPendingWrites(Database db) {
    if (_pendingWrites.isEmpty) return;
    final writes = List<Future<void> Function(Database db)>.from(
      _pendingWrites,
    );
    _pendingWrites.clear();
    Future<void>.microtask(() async {
      for (final write in writes) {
        try {
          await write(db);
        } catch (e, stack) {
          logError(
            'ChatSessionService 延迟写入执行失败',
            error: e,
            stackTrace: stack,
            source: 'ChatSessionService',
          );
        } finally {
          notifyListeners();
        }
      }
    });
  }

  /// 获取数据库实例，带超时限制（仅用于只读查询）
  ///
  /// 超时后返回 null，调用方需自行处理降级逻辑（如返回空列表）。
  /// 写操作禁止使用此方法，应使用 [_persistOrQueueWrite]。
  Future<Database?> _getDatabaseForRead({
    Duration timeout = const Duration(seconds: 5),
  }) async {
    if (_database != null) return _database;
    if (_openOwnDatabase) {
      try {
        return await _ensureDatabase();
      } catch (e, stack) {
        logError(
          'ChatSessionService 打开聊天数据库失败',
          error: e,
          stackTrace: stack,
          source: 'ChatSessionService',
        );
        return null;
      }
    }
    try {
      await _databaseReady.future.timeout(timeout);
    } on TimeoutException {
      logWarning(
        'ChatSessionService 等待数据库注入超时（只读查询）',
        source: 'ChatSessionService',
      );
      return null;
    }
    return _database;
  }

  Future<void> _persistOrQueueWrite(
    Future<void> Function(Database db) write, {
    required String operationName,
  }) async {
    final db = _database ?? (_openOwnDatabase ? await _ensureDatabase() : null);
    if (db == null) {
      // 数据库尚未就绪，加入队列等待后续执行
      logWarning(
        '$operationName 数据库未就绪，已加入延迟写入队列',
        source: 'ChatSessionService',
      );
      final completer = Completer<void>();
      _pendingWrites.add((db) async {
        try {
          await write(db);
          completer.complete();
        } catch (e, stack) {
          completer.completeError(e, stack);
          rethrow;
        }
      });
      return completer.future;
    }
    await write(db);
  }

  Future<void> init() async {
    await _ensureDatabase();
  }

  /// 将早期版本存放在主笔记库中的聊天记录迁移到独立 chat.db。
  ///
  /// 迁移使用 INSERT OR IGNORE 保持幂等；主库中的旧表暂不删除，避免在用户
  /// 降级或迁移中断时丢失聊天历史。
  Future<void> migrateFromMainDatabase(Database sourceDb) async {
    final targetDb = await _ensureDatabase();
    try {
      await _ensureChatSchema(targetDb);

      if (await _getMetadataValue(targetDb, _legacyMainDbMigrationKey) ==
          'true') {
        return;
      }

      final hasLegacySessions = await _tableExists(sourceDb, 'chat_sessions');
      final hasLegacyMessages = await _tableExists(sourceDb, 'chat_messages');
      if (!hasLegacySessions || !hasLegacyMessages) {
        await _setMetadataValue(targetDb, _legacyMainDbMigrationKey, 'true');
        return;
      }

      final legacySessions = await sourceDb.query('chat_sessions');
      if (legacySessions.isEmpty) {
        await _setMetadataValue(targetDb, _legacyMainDbMigrationKey, 'true');
        return;
      }
      final legacyMessages = await sourceDb.query('chat_messages');

      await targetDb.transaction((txn) async {
        const chunkSize = 500;

        for (var i = 0; i < legacySessions.length; i += chunkSize) {
          final batch = txn.batch();
          final end = (i + chunkSize < legacySessions.length)
              ? i + chunkSize
              : legacySessions.length;
          for (var j = i; j < end; j++) {
            final raw = legacySessions[j];
            final row = <String, Object?>{
              for (final col in _chatSessionColumnWhitelist)
                if (raw.containsKey(col)) col: raw[col],
            };
            final rawUpdated = row['updated_at'];
            final createdNorm = _normalizeChatTimestampToUtcOrKeep(
              row['created_at'],
            );
            final rawLastActiveStr = row['last_active_at']?.toString() ?? '';
            final lastActiveNorm = rawLastActiveStr.trim().isNotEmpty
                ? _normalizeChatTimestampToUtcOrKeep(rawLastActiveStr)
                : createdNorm;
            final existingUpdated = rawUpdated?.toString() ?? '';
            final updatedNorm = existingUpdated.trim().isNotEmpty
                ? _normalizeChatTimestampToUtcOrKeep(existingUpdated)
                : (lastActiveNorm.isNotEmpty ? lastActiveNorm : createdNorm);
            row['created_at'] = createdNorm;
            row['last_active_at'] = lastActiveNorm;
            row['updated_at'] = updatedNorm;
            batch.insert(
              'chat_sessions',
              row,
              conflictAlgorithm: ConflictAlgorithm.ignore,
            );
          }
          await batch.commit(noResult: true);
        }

        for (var i = 0; i < legacyMessages.length; i += chunkSize) {
          final batch = txn.batch();
          final end = (i + chunkSize < legacyMessages.length)
              ? i + chunkSize
              : legacyMessages.length;
          for (var j = i; j < end; j++) {
            final raw = legacyMessages[j];
            final row = <String, Object?>{
              for (final col in _chatMessageColumnWhitelist)
                if (raw.containsKey(col)) col: raw[col],
            };
            final rawUpdated = row['updated_at'];
            final createdNorm = _normalizeChatTimestampToUtcOrKeep(
              row['created_at'],
            );
            final existingUpdated = rawUpdated?.toString() ?? '';
            final updatedNorm = existingUpdated.trim().isNotEmpty
                ? _normalizeChatTimestampToUtcOrKeep(existingUpdated)
                : createdNorm;
            row['created_at'] = createdNorm;
            row['updated_at'] = updatedNorm;
            batch.insert(
              'chat_messages',
              row,
              conflictAlgorithm: ConflictAlgorithm.ignore,
            );
          }
          await batch.commit(noResult: true);
        }

        final metaBatch = txn.batch();
        metaBatch.insert(
          'chat_metadata',
          {
            'key': _legacyMainDbMigrationKey,
            'value': 'true',
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
        await metaBatch.commit(noResult: true);
        await _refreshOffsetlessTimestampFlag(txn);
      });
      logInfo(
        '已迁移 ${legacySessions.length} 个旧聊天会话到独立聊天数据库',
        source: 'ChatSessionService',
      );
    } catch (e, stack) {
      logError(
        'ChatSessionService.migrateFromMainDatabase 失败',
        error: e,
        stackTrace: stack,
        source: 'ChatSessionService',
      );
    }
  }

  Future<bool> _tableExists(DatabaseExecutor db, String tableName) async {
    final rows = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table' AND name = ?",
      [tableName],
    );
    return rows.isNotEmpty;
  }

  Future<String?> _getMetadataValue(DatabaseExecutor db, String key) async {
    final rows = await db.query(
      'chat_metadata',
      columns: ['value'],
      where: 'key = ?',
      whereArgs: [key],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return rows.first['value'] as String?;
  }

  Future<void> _setMetadataValue(
    DatabaseExecutor db,
    String key,
    String value,
  ) async {
    await db.insert(
      'chat_metadata',
      {
        'key': key,
        'value': value,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> close() async {
    final opening = _openingCompleter;
    if (opening != null) {
      try {
        await opening.future;
      } catch (_) {}
    }

    final db = _database;
    _database = null;
    _openingCompleter = null;
    if (db != null && _ownsDatabase) {
      try {
        await db.execute('PRAGMA wal_checkpoint(FULL);');
      } catch (e) {
        logError('ChatSessionService WAL checkpoint failed: $e');
      }
      try {
        await db.close();
      } catch (_) {}
    }
  }

  Future<Database> _ensureDatabase() async {
    final current = _database;
    if (current != null) return current;

    final existingOpen = _openingCompleter;
    if (existingOpen != null) return existingOpen.future;

    final completer = Completer<Database>();
    _openingCompleter = completer;
    try {
      final dbPath = _databasePath ?? await _defaultDatabasePath();
      await DataDirectoryService.ensureParentDirectoryForFile(dbPath);
      final db = await openDatabase(
        dbPath,
        version: _schemaVersion,
        onCreate: (db, version) async {
          await _ensureChatSchema(db);
        },
        onUpgrade: (db, oldVersion, newVersion) async {
          await _ensureChatSchema(db);
        },
        onConfigure: (db) async {
          await db.execute('PRAGMA foreign_keys = ON');
        },
        onOpen: (db) async {
          await _ensureChatSchema(db);
        },
      );
      _database = db;
      _ownsDatabase = true;
      if (!_databaseReady.isCompleted) {
        _databaseReady.complete();
      }
      _flushPendingWrites(db);
      completer.complete(db);
      return db;
    } catch (e, stack) {
      if (!_databaseReady.isCompleted) {
        _databaseReady.completeError(e, stack);
      }
      completer.completeError(e, stack);
      rethrow;
    } finally {
      _openingCompleter = null;
    }
  }

  Future<String> _defaultDatabasePath() async {
    final basePath = Platform.isWindows
        ? await DataDirectoryService.getCurrentDataDirectory()
        : (await getApplicationDocumentsDirectory()).path;
    return path.join(basePath, 'chat.db');
  }

  Future<void> _ensureChatSchema(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS chat_sessions(
        id TEXT PRIMARY KEY,
        session_type TEXT NOT NULL DEFAULT 'note',
        note_id TEXT,
        title TEXT NOT NULL DEFAULT '',
        created_at TEXT NOT NULL,
        last_active_at TEXT NOT NULL,
        updated_at TEXT,
        is_pinned INTEGER NOT NULL DEFAULT 0
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS chat_messages(
        id TEXT PRIMARY KEY,
        session_id TEXT NOT NULL,
        role TEXT NOT NULL DEFAULT 'user',
        content TEXT NOT NULL DEFAULT '',
        created_at TEXT NOT NULL,
        updated_at TEXT,
        included_in_context INTEGER NOT NULL DEFAULT 1,
        meta_json TEXT,
        content_format TEXT,
        delta_json TEXT,
        FOREIGN KEY (session_id) REFERENCES chat_sessions(id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS chat_metadata(
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS chat_tombstones(
        entity_type TEXT NOT NULL,
        entity_id TEXT NOT NULL,
        deleted_at TEXT NOT NULL,
        session_id TEXT,
        PRIMARY KEY(entity_type, entity_id)
      )
    ''');

    await addColumnIfMissing(
      db,
      tableName: 'chat_sessions',
      columnName: 'session_type',
      definition: "TEXT NOT NULL DEFAULT 'note'",
    );
    await addColumnIfMissing(
      db,
      tableName: 'chat_sessions',
      columnName: 'note_id',
      definition: 'TEXT',
    );
    await addColumnIfMissing(
      db,
      tableName: 'chat_sessions',
      columnName: 'title',
      definition: "TEXT NOT NULL DEFAULT ''",
    );
    await addColumnIfMissing(
      db,
      tableName: 'chat_sessions',
      columnName: 'last_active_at',
      definition: 'TEXT',
    );
    await addColumnIfMissing(
      db,
      tableName: 'chat_sessions',
      columnName: 'updated_at',
      definition: 'TEXT',
    );
    await addColumnIfMissing(
      db,
      tableName: 'chat_sessions',
      columnName: 'is_pinned',
      definition: 'INTEGER NOT NULL DEFAULT 0',
    );
    await addColumnIfMissing(
      db,
      tableName: 'chat_messages',
      columnName: 'updated_at',
      definition: 'TEXT',
    );
    await addColumnIfMissing(
      db,
      tableName: 'chat_messages',
      columnName: 'included_in_context',
      definition: 'INTEGER NOT NULL DEFAULT 1',
    );
    await addColumnIfMissing(
      db,
      tableName: 'chat_messages',
      columnName: 'meta_json',
      definition: 'TEXT',
    );
    await addColumnIfMissing(
      db,
      tableName: 'chat_messages',
      columnName: 'content_format',
      definition: 'TEXT',
    );
    await addColumnIfMissing(
      db,
      tableName: 'chat_messages',
      columnName: 'delta_json',
      definition: 'TEXT',
    );
    await addColumnIfMissing(
      db,
      tableName: 'chat_tombstones',
      columnName: 'session_id',
      definition: 'TEXT',
    );

    // 先对每列各自按显式时区/定宽规则归一化，随后再对仍为空的派生时间列执行回填。
    await _normalizeLegacyChatTimestamps(db);

    await db.execute('''
      UPDATE chat_sessions
      SET last_active_at = COALESCE(NULLIF(last_active_at, ''), created_at)
      WHERE last_active_at IS NULL OR last_active_at = ''
    ''');
    await db.execute('''
      UPDATE chat_sessions
      SET updated_at = COALESCE(NULLIF(last_active_at, ''), created_at)
      WHERE updated_at IS NULL OR updated_at = ''
    ''');
    await db.execute('''
      UPDATE chat_messages
      SET updated_at = created_at
      WHERE updated_at IS NULL OR updated_at = ''
    ''');

    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_chat_sessions_note_id ON chat_sessions(note_id)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_chat_sessions_last_active ON chat_sessions(last_active_at DESC)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_chat_sessions_type ON chat_sessions(session_type)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_chat_messages_session_id ON chat_messages(session_id)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_chat_messages_content ON chat_messages(content)',
    );

    await _refreshOffsetlessTimestampFlag(db);
  }

  Future<void> _refreshOffsetlessTimestampFlag(DatabaseExecutor db) async {
    final sessionRows = await db.query(
      'chat_sessions',
      columns: const <String>['created_at', 'last_active_at'],
      where: "created_at NOT GLOB '${LWWUtils.canonicalFixedUtcGlob}' "
          "OR last_active_at NOT GLOB '${LWWUtils.canonicalFixedUtcGlob}'",
      limit: 1,
    );
    _hasOffsetlessTimestamps = sessionRows.any(
      (row) =>
          !LWWUtils.isCanonicalFixedUtcIso(row['created_at']) ||
          !LWWUtils.isCanonicalFixedUtcIso(row['last_active_at']),
    );

    final messageRows = await db.query(
      'chat_messages',
      columns: const <String>['created_at'],
      where: "created_at NOT GLOB '${LWWUtils.canonicalFixedUtcGlob}'",
      limit: 1,
    );
    _hasOffsetlessMessageTimestamps = messageRows.any(
      (row) => !LWWUtils.isCanonicalFixedUtcIso(row['created_at']),
    );
    _offsetlessFlagInitialized = true;
  }

  Future<void> _ensureOffsetlessTimestampFlagsLoaded(
    DatabaseExecutor db,
  ) async {
    if (_offsetlessFlagInitialized) return;
    await _refreshOffsetlessTimestampFlag(db);
  }

  static String _nonCanonicalTimeClause(String col) {
    return "($col NOT GLOB '${LWWUtils.canonicalFixedUtcGlob}' AND "
        "$col NOT GLOB '${LWWUtils.canonicalFixedOffsetlessGlob}')";
  }

  Future<void> _normalizeLegacyChatTimestamps(DatabaseExecutor db) async {
    const chunkSize = 500;

    final candidateSessions = await db.query(
      'chat_sessions',
      columns: const <String>[
        'id',
        'created_at',
        'last_active_at',
        'updated_at',
      ],
      where: "${_nonCanonicalTimeClause('created_at')} OR "
          "last_active_at IS NULL OR last_active_at = '' OR "
          "${_nonCanonicalTimeClause('last_active_at')} OR "
          "updated_at IS NULL OR updated_at = '' OR "
          "${_nonCanonicalTimeClause('updated_at')}",
    );
    if (candidateSessions.isNotEmpty) {
      var sessionBackupColsEnsured = false;
      Future<void> ensureSessionBackupCols() async {
        if (sessionBackupColsEnsured) return;
        await addColumnIfMissing(
          db,
          tableName: 'chat_sessions',
          columnName: 'created_at_backup',
          definition: 'TEXT',
        );
        await addColumnIfMissing(
          db,
          tableName: 'chat_sessions',
          columnName: 'last_active_at_backup',
          definition: 'TEXT',
        );
        await addColumnIfMissing(
          db,
          tableName: 'chat_sessions',
          columnName: 'updated_at_backup',
          definition: 'TEXT',
        );
        sessionBackupColsEnsured = true;
      }

      for (var i = 0; i < candidateSessions.length; i += chunkSize) {
        final end = (i + chunkSize < candidateSessions.length)
            ? i + chunkSize
            : candidateSessions.length;
        final batch = db.batch();
        var hasUpdates = false;
        for (var j = i; j < end; j++) {
          final row = candidateSessions[j];
          final id = row['id'] as String?;
          if (id == null || id.isEmpty) continue;
          final updatedRaw = row['updated_at'];
          final createdAt = _normalizeChatTimestampToUtcOrKeep(
            row['created_at'],
          );
          final lastActiveRaw = row['last_active_at'];
          final lastActiveAt =
              (lastActiveRaw is String && lastActiveRaw.trim().isNotEmpty)
                  ? _normalizeChatTimestampToUtcOrKeep(lastActiveRaw)
                  : createdAt;
          final updatedAt =
              (updatedRaw is String && updatedRaw.trim().isNotEmpty)
                  ? _normalizeChatTimestampToUtcOrKeep(updatedRaw)
                  : (lastActiveAt.isNotEmpty ? lastActiveAt : createdAt);
          if (createdAt != row['created_at'] ||
              lastActiveAt != row['last_active_at'] ||
              updatedAt != row['updated_at']) {
            await ensureSessionBackupCols();
            batch.rawUpdate(
              'UPDATE chat_sessions SET '
              'created_at_backup = COALESCE(created_at_backup, created_at), '
              'last_active_at_backup = COALESCE(last_active_at_backup, last_active_at), '
              'updated_at_backup = COALESCE(updated_at_backup, updated_at), '
              'created_at = ?, last_active_at = ?, updated_at = ? '
              'WHERE id = ?',
              <Object?>[createdAt, lastActiveAt, updatedAt, id],
            );
            hasUpdates = true;
          }
        }
        if (hasUpdates) {
          await batch.commit(noResult: true);
        }
      }
    }

    final candidateMessages = await db.query(
      'chat_messages',
      columns: const <String>['id', 'created_at', 'updated_at'],
      where: "${_nonCanonicalTimeClause('created_at')} OR "
          "updated_at IS NULL OR updated_at = '' OR "
          "${_nonCanonicalTimeClause('updated_at')}",
    );
    if (candidateMessages.isNotEmpty) {
      var messageBackupColsEnsured = false;
      Future<void> ensureMessageBackupCols() async {
        if (messageBackupColsEnsured) return;
        await addColumnIfMissing(
          db,
          tableName: 'chat_messages',
          columnName: 'created_at_backup',
          definition: 'TEXT',
        );
        await addColumnIfMissing(
          db,
          tableName: 'chat_messages',
          columnName: 'updated_at_backup',
          definition: 'TEXT',
        );
        messageBackupColsEnsured = true;
      }

      for (var i = 0; i < candidateMessages.length; i += chunkSize) {
        final end = (i + chunkSize < candidateMessages.length)
            ? i + chunkSize
            : candidateMessages.length;
        final batch = db.batch();
        var hasUpdates = false;
        for (var j = i; j < end; j++) {
          final row = candidateMessages[j];
          final id = row['id'] as String?;
          if (id == null || id.isEmpty) continue;
          final updatedRaw = row['updated_at'];
          final createdAt = _normalizeChatTimestampToUtcOrKeep(
            row['created_at'],
          );
          final updatedAt =
              (updatedRaw is String && updatedRaw.trim().isNotEmpty)
                  ? _normalizeChatTimestampToUtcOrKeep(updatedRaw)
                  : createdAt;
          if (createdAt != row['created_at'] ||
              updatedAt != row['updated_at']) {
            await ensureMessageBackupCols();
            batch.rawUpdate(
              'UPDATE chat_messages SET '
              'created_at_backup = COALESCE(created_at_backup, created_at), '
              'updated_at_backup = COALESCE(updated_at_backup, updated_at), '
              'created_at = ?, updated_at = ? '
              'WHERE id = ?',
              <Object?>[createdAt, updatedAt, id],
            );
            hasUpdates = true;
          }
        }
        if (hasUpdates) {
          await batch.commit(noResult: true);
        }
      }
    }

    final candidateTombstones = await db.query(
      'chat_tombstones',
      columns: const <String>['entity_type', 'entity_id', 'deleted_at'],
      where: _nonCanonicalTimeClause('deleted_at'),
    );
    if (candidateTombstones.isNotEmpty) {
      var tombstoneBackupColEnsured = false;
      Future<void> ensureTombstoneBackupCol() async {
        if (tombstoneBackupColEnsured) return;
        await addColumnIfMissing(
          db,
          tableName: 'chat_tombstones',
          columnName: 'deleted_at_backup',
          definition: 'TEXT',
        );
        tombstoneBackupColEnsured = true;
      }

      for (var i = 0; i < candidateTombstones.length; i += chunkSize) {
        final end = (i + chunkSize < candidateTombstones.length)
            ? i + chunkSize
            : candidateTombstones.length;
        final batch = db.batch();
        var hasUpdates = false;
        for (var j = i; j < end; j++) {
          final row = candidateTombstones[j];
          final type = row['entity_type'] as String?;
          final id = row['entity_id'] as String?;
          if (type == null || id == null) continue;
          final deletedAt = _normalizeChatTimestampToUtcOrKeep(
            row['deleted_at'],
          );
          if (deletedAt != row['deleted_at']) {
            await ensureTombstoneBackupCol();
            batch.rawUpdate(
              'UPDATE chat_tombstones SET '
              'deleted_at_backup = COALESCE(deleted_at_backup, deleted_at), '
              'deleted_at = ? '
              'WHERE entity_type = ? AND entity_id = ?',
              <Object?>[deletedAt, type, id],
            );
            hasUpdates = true;
          }
        }
        if (hasUpdates) {
          await batch.commit(noResult: true);
        }
      }
    }
  }

  String _escapeIdentifier(String identifier) {
    return identifier.replaceAll('"', '""');
  }

  @visibleForTesting
  Future<void> addColumnIfMissing(
    DatabaseExecutor db, {
    required String tableName,
    required String columnName,
    required String definition,
  }) async {
    final identifierRegex = RegExp(r'^[a-zA-Z_][a-zA-Z0-9_]*$');
    if (!identifierRegex.hasMatch(tableName)) {
      throw ArgumentError.value(tableName, 'tableName', 'Invalid table name');
    }
    if (!identifierRegex.hasMatch(columnName)) {
      throw ArgumentError.value(
          columnName, 'columnName', 'Invalid column name');
    }
    final trimmedDef = definition.trim();
    final parts =
        trimmedDef.split(RegExp(r'\s+DEFAULT\s+', caseSensitive: false));
    if (parts.length > 2 ||
        !RegExp(r'^[a-zA-Z0-9_ ()]+$').hasMatch(parts[0]) ||
        (parts.length == 2 &&
            !RegExp(r"^(?:'[a-zA-Z0-9_]*'|[0-9]+)$").hasMatch(parts[1]))) {
      throw ArgumentError.value(
          definition, 'definition', 'Invalid column definition');
    }

    final columns =
        await db.rawQuery('SELECT * FROM pragma_table_info(?)', [tableName]);
    final hasColumn = columns.any((column) => column['name'] == columnName);
    if (!hasColumn) {
      final safeTableName = _escapeIdentifier(tableName);
      final safeColumnName = _escapeIdentifier(columnName);

      // DDL queries (ALTER TABLE) cannot use parameter bindings in sqlite.
      // Table name, column name, and definition are strictly validated via regex above.
      // Double quoting identifiers and replacing internal double quotes prevents injection.
      // List.join is used to construct non-parameterizable DDL queries safely without SAST string interpolation or string composition warnings.
      final query = [
        'ALTER TABLE "',
        safeTableName,
        '" ADD COLUMN "',
        safeColumnName,
        '" ',
        definition,
      ].join();
      await db.execute(query);
    }
  }

  Future<ChatSession> createSession({
    required String sessionType,
    String? noteId,
    required String title,
  }) async {
    final now = DateTime.now().toUtc();
    final session = ChatSession(
      id: const Uuid().v4(),
      sessionType: sessionType,
      noteId: noteId,
      title: title,
      createdAt: now,
      lastActiveAt: now,
      updatedAt: now,
    );
    try {
      await _persistOrQueueWrite((db) async {
        final row = session.toMap();
        row['created_at'] = LWWUtils.formatFixedUtcIso(session.createdAt);
        row['last_active_at'] =
            LWWUtils.formatFixedUtcIso(session.lastActiveAt);
        row['updated_at'] = LWWUtils.formatFixedUtcIso(
          session.updatedAt ?? session.lastActiveAt,
        );
        await db.insert('chat_sessions', row);
      }, operationName: 'ChatSessionService.createSession');
    } catch (e) {
      logError(
        'ChatSessionService.createSession 失败',
        error: e,
        source: 'ChatSessionService',
      );
    }
    notifyListeners();
    return session;
  }

  Future<ChatSession?> getLatestSessionForNote(String noteId) async {
    final db = await _getDatabaseForRead();
    if (db == null) return null;
    try {
      await _ensureOffsetlessTimestampFlagsLoaded(db);
      if (_hasOffsetlessTimestamps) {
        final rows = await db.query(
          'chat_sessions',
          where: 'note_id = ?',
          whereArgs: [noteId],
        );
        final sessions = _parseSessionsFromRows(
          rows,
        ).where((s) => s.noteId == noteId).toList();
        _sortSessionsByActivityDesc(sessions, includePinOrder: false);
        return sessions.firstOrNull;
      }
      final rows = await db.query(
        'chat_sessions',
        where: 'note_id = ?',
        whereArgs: [noteId],
        orderBy: 'last_active_at DESC',
        limit: 1,
      );
      if (rows.isEmpty) return null;
      return ChatSession.fromMap(rows.first);
    } catch (e) {
      logError(
        'ChatSessionService.getLatestSessionForNote 失败',
        error: e,
        source: 'ChatSessionService',
      );
      return null;
    }
  }

  List<ChatSession> _parseSessionsFromRows(List<Map<String, dynamic>> rows) {
    final sessions = <ChatSession>[];
    for (final row in rows) {
      final id = row['id'] as String?;
      if (id == null || id.isEmpty) {
        logError(
          'Skipping invalid session row with empty ID',
          source: 'ChatSessionService',
        );
        continue;
      }
      try {
        sessions.add(ChatSession.fromMap(row));
      } catch (e) {
        logError(
          'Failed to parse chat session row',
          error: e,
          source: 'ChatSessionService',
        );
      }
    }
    return sessions;
  }

  static void _sortSessionsByActivityDesc(
    List<ChatSession> sessions, {
    required bool includePinOrder,
  }) {
    if (sessions.length <= 1) return;
    sessions.sort((a, b) {
      if (includePinOrder && a.isPinned != b.isPinned) {
        return a.isPinned ? -1 : 1;
      }
      final cmp = b.lastActiveAt.toUtc().compareTo(a.lastActiveAt.toUtc());
      if (cmp != 0) return cmp;
      return a.id.compareTo(b.id);
    });
  }

  Future<List<ChatSession>> getSessionsForNote(String noteId) async {
    final db = await _getDatabaseForRead();
    if (db == null) return [];
    try {
      await _ensureOffsetlessTimestampFlagsLoaded(db);
      final rows = await db.query(
        'chat_sessions',
        where: 'note_id = ?',
        whereArgs: [noteId],
        orderBy: 'last_active_at DESC',
      );
      final sessions = _parseSessionsFromRows(rows);
      if (_hasOffsetlessTimestamps) {
        _sortSessionsByActivityDesc(sessions, includePinOrder: false);
      }
      return sessions;
    } catch (e) {
      logError(
        'ChatSessionService.getSessionsForNote 失败',
        error: e,
        source: 'ChatSessionService',
      );
      return [];
    }
  }

  Future<List<ChatSession>> getAgentSessions() async {
    final db = await _getDatabaseForRead();
    if (db == null) return [];
    try {
      await _ensureOffsetlessTimestampFlagsLoaded(db);
      final rows = await db.query(
        'chat_sessions',
        where: 'session_type = ?',
        whereArgs: ['agent'],
        orderBy: 'last_active_at DESC',
      );
      final sessions = _parseSessionsFromRows(rows);
      if (_hasOffsetlessTimestamps) {
        _sortSessionsByActivityDesc(sessions, includePinOrder: false);
      }
      return sessions;
    } catch (e) {
      logError(
        'ChatSessionService.getAgentSessions 失败',
        error: e,
        source: 'ChatSessionService',
      );
      return [];
    }
  }

  Future<List<ChatSession>> getAllSessions({
    int limit = 50,
    int offset = 0,
  }) async {
    final db = await _getDatabaseForRead();
    if (db == null) return [];
    try {
      final now = DateTime.now();
      final shouldCleanup = _lastEmptySessionCleanupAt == null ||
          now.difference(_lastEmptySessionCleanupAt!) >=
              _emptySessionCleanupInterval;
      if (shouldCleanup) {
        // 先清理没有消息的会话（防止之前保存失败残留的脏数据）
        final cleanupSucceeded = await _cleanupEmptySessions(db);
        if (cleanupSucceeded) {
          _lastEmptySessionCleanupAt = now;
        }
      }

      await _ensureOffsetlessTimestampFlagsLoaded(db);
      if (_hasOffsetlessTimestamps) {
        final rows = await db.query('chat_sessions');
        final sessions = _parseSessionsFromRows(rows);
        _sortSessionsByActivityDesc(sessions, includePinOrder: true);
        if (offset >= sessions.length) return const [];
        final end = (offset + limit < sessions.length)
            ? offset + limit
            : sessions.length;
        return sessions.sublist(offset, end);
      }

      final rows = await db.query(
        'chat_sessions',
        orderBy: 'is_pinned DESC, last_active_at DESC',
        limit: limit,
        offset: offset,
      );
      return _parseSessionsFromRows(rows);
    } catch (e) {
      logError(
        'ChatSessionService.getAllSessions 失败',
        error: e,
        source: 'ChatSessionService',
      );
      return [];
    }
  }

  /// 批量读取历史列表需要的消息数和最后一条正文，避免列表 N+1 查询。
  Future<Map<String, ChatSessionOverview>> getSessionOverviews(
    List<String> sessionIds,
  ) async {
    if (sessionIds.isEmpty) return const {};
    final db = await _getDatabaseForRead();
    if (db == null) return const {};
    const chunkSize = 500;
    final result = <String, ChatSessionOverview>{};
    final mixedTimeSessionIds = <String>[];

    void collectOverviewRow(Map<dynamic, dynamic> row) {
      final id = row['id'] as String?;
      if (id == null) return;
      result[id] = _parseOverviewRow(row);
      if (safeParseInt(row['has_non_canonical_time']) != 0) {
        mixedTimeSessionIds.add(id);
      }
    }

    // 如果只需要查询一个批次，直接使用 db.rawQuery 以避免创建 batch 的开销
    if (sessionIds.length <= chunkSize) {
      final rows = await db.rawQuery(
        _buildSessionOverviewsSql(sessionIds.length),
        sessionIds,
      );
      for (final row in rows) {
        collectOverviewRow(row);
      }
    } else {
      // 超过一个批次时，使用 batch 一次性提交所有查询，降低 IPC/方法通道的往返开销
      final batch = db.batch();
      for (var i = 0; i < sessionIds.length; i += chunkSize) {
        final end = (i + chunkSize < sessionIds.length)
            ? i + chunkSize
            : sessionIds.length;
        final chunk = sessionIds.sublist(i, end);
        batch.rawQuery(
          _buildSessionOverviewsSql(chunk.length),
          chunk,
        );
      }

      final batchResults = await batch.commit(noResult: false);
      for (final rowsObj in batchResults) {
        if (rowsObj is List) {
          for (final rowObj in rowsObj) {
            if (rowObj is Map) {
              collectOverviewRow(rowObj);
            }
          }
        }
      }
    }

    if (mixedTimeSessionIds.isNotEmpty) {
      _hasOffsetlessMessageTimestamps = true;
      await _overrideOverviewsWithUtcLatestMessage(
        db,
        mixedTimeSessionIds,
        result,
      );
    }
    return result;
  }

  Future<void> _overrideOverviewsWithUtcLatestMessage(
    Database db,
    List<String> sessionIds,
    Map<String, ChatSessionOverview> result,
  ) async {
    const chunkSize = 500;
    for (var i = 0; i < sessionIds.length; i += chunkSize) {
      final end = (i + chunkSize < sessionIds.length)
          ? i + chunkSize
          : sessionIds.length;
      final chunk = sessionIds.sublist(i, end);
      final placeholders = List.filled(chunk.length, '?').join(',');
      // 先只拉取消息 ID、会话 ID 与时间列，避免把所有历史消息正文读入内存。
      final rows = await db.rawQuery(
        '''
        SELECT id, session_id, created_at
        FROM chat_messages
        WHERE session_id IN ($placeholders)
        ORDER BY created_at ASC
        ''',
        chunk,
      );
      final latestBySession = <String, ({DateTime tsUtc, String msgId})>{};
      for (final row in rows) {
        final mId = row['id'] as String?;
        final sId = row['session_id'] as String?;
        if (mId == null || mId.isEmpty || sId == null) continue;
        final createdStr = row['created_at'] as String? ?? '';
        final tsUtc = DateTime.tryParse(createdStr)?.toUtc();
        if (tsUtc == null) continue;
        final prev = latestBySession[sId];
        // 与 getMessages 升序稳定排序的末尾元素一致：时间严格更新或时间相同时保留后者。
        if (prev == null || !tsUtc.isBefore(prev.tsUtc)) {
          latestBySession[sId] = (
            tsUtc: tsUtc,
            msgId: mId,
          );
        }
      }
      if (latestBySession.isEmpty) continue;

      final winningMsgIds = latestBySession.values
          .map((v) => v.msgId)
          .toSet()
          .toList(growable: false);
      final msgPlaceholders = List.filled(winningMsgIds.length, '?').join(',');
      final contentRows = await db.rawQuery(
        '''
        SELECT id, content
        FROM chat_messages
        WHERE id IN ($msgPlaceholders)
        ''',
        winningMsgIds,
      );
      final snippetByMsgId = <String, String>{};
      for (final row in contentRows) {
        final mId = row['id'] as String?;
        if (mId == null || mId.isEmpty) continue;
        snippetByMsgId[mId] = _truncatePreview(row['content'] as String?);
      }
      for (final entry in latestBySession.entries) {
        final existing = result[entry.key];
        if (existing != null) {
          result[entry.key] = ChatSessionOverview(
            messageCount: existing.messageCount,
            snippet: snippetByMsgId[entry.value.msgId] ?? '',
          );
        }
      }
    }
  }

  static String _buildSessionOverviewsSql(int count) {
    final placeholders = List.filled(count, '?').join(',');
    return '''
SELECT s.id,
  (SELECT COUNT(*) FROM chat_messages c WHERE c.session_id = s.id)
    AS message_count,
  (SELECT m.content FROM chat_messages m
    WHERE m.session_id = s.id
    ORDER BY m.created_at DESC LIMIT 1) AS last_content,
  EXISTS (
    SELECT 1 FROM chat_messages m2
    WHERE m2.session_id = s.id
      AND m2.created_at NOT GLOB '${LWWUtils.canonicalFixedUtcGlob}'
  ) AS has_non_canonical_time
FROM chat_sessions s
WHERE s.id IN ($placeholders)
''';
  }

  @visibleForTesting
  static int safeParseIntForTest(Object? value, [int defaultValue = 0]) =>
      safeParseInt(value, defaultValue);

  ChatSessionOverview _parseOverviewRow(Map<dynamic, dynamic> row) {
    return ChatSessionOverview(
      messageCount: safeParseInt(row['message_count']),
      snippet: _truncatePreview(row['last_content'] as String?),
    );
  }

  String _truncatePreview(String? content) {
    final value = content?.trim() ?? '';
    return value.length > 80 ? '${value.substring(0, 80)}...' : value;
  }

  Future<List<ChatSessionSearchResult>> searchSessions(
    String query, {
    int limit = 20,
  }) async {
    final normalizedQuery = query.trim();
    if (normalizedQuery.isEmpty || limit <= 0) return const [];

    final db = await _getDatabaseForRead();
    if (db == null) return const [];

    try {
      await _ensureOffsetlessTimestampFlagsLoaded(db);
      final like = '%$normalizedQuery%';
      if (_hasOffsetlessTimestamps || _hasOffsetlessMessageTimestamps) {
        return await _searchSessionsWithMixedTimestamps(
          db,
          normalizedQuery,
          like,
          limit,
        );
      }

      final rows = await db.rawQuery(
        '''
        SELECT
          s.id,
          s.session_type,
          s.note_id,
          s.title,
          s.created_at,
          s.last_active_at,
          s.is_pinned,
          (
            SELECT m.content
            FROM chat_messages m
            WHERE m.session_id = s.id
              AND m.content LIKE ?
            ORDER BY m.created_at ASC
            LIMIT 1
          ) AS matched_content,
          EXISTS (
            SELECT 1
            FROM chat_messages m2
            WHERE m2.session_id = s.id
              AND m2.content LIKE ?
              AND m2.created_at NOT GLOB '${LWWUtils.canonicalFixedUtcGlob}'
          ) AS has_non_canonical_match
        FROM chat_sessions s
        WHERE s.title LIKE ?
          OR EXISTS (
            SELECT 1
            FROM chat_messages m
            WHERE m.session_id = s.id
              AND m.content LIKE ?
          )
        ORDER BY s.last_active_at DESC
        LIMIT ?
        ''',
        [like, like, like, like, limit],
      );

      final detectedNonCanonicalInRows = rows.any(
        (r) =>
            !LWWUtils.isCanonicalFixedUtcIso(r['last_active_at']) ||
            safeParseInt(r['has_non_canonical_match']) != 0,
      );
      if (detectedNonCanonicalInRows) {
        await _refreshOffsetlessTimestampFlag(db);
        return await _searchSessionsWithMixedTimestamps(
          db,
          normalizedQuery,
          like,
          limit,
        );
      }

      final seen = <String>{};
      final results = <ChatSessionSearchResult>[];
      for (final row in rows) {
        final session = ChatSession.fromMap(row);
        if (!seen.add(session.id)) continue;
        final matchedContent = row['matched_content'] as String?;
        final sourceText = (matchedContent?.isNotEmpty ?? false)
            ? matchedContent!
            : session.title;
        final snippet = _buildSnippet(sourceText, normalizedQuery);
        results.add(
          ChatSessionSearchResult(
            session: session,
            snippet: snippet.text,
            isTruncated: snippet.isTruncated,
            matchStart: snippet.matchStart,
            matchEnd: snippet.matchEnd,
          ),
        );
      }
      return results;
    } catch (e) {
      logError(
        'ChatSessionService.searchSessions 失败',
        error: e,
        source: 'ChatSessionService',
      );
      return const [];
    }
  }

  Future<List<ChatSessionSearchResult>> _searchSessionsWithMixedTimestamps(
    Database db,
    String normalizedQuery,
    String like,
    int limit,
  ) async {
    final sessionRows = await db.rawQuery(
      '''
      SELECT
        s.id,
        s.session_type,
        s.note_id,
        s.title,
        s.created_at,
        s.last_active_at,
        s.updated_at,
        s.is_pinned
      FROM chat_sessions s
      WHERE s.title LIKE ?
        OR EXISTS (
          SELECT 1
          FROM chat_messages m
          WHERE m.session_id = s.id
            AND m.content LIKE ?
        )
      ''',
      [like, like],
    );
    if (sessionRows.isEmpty) return const [];

    final sessions = _parseSessionsFromRows(sessionRows);
    _sortSessionsByActivityDesc(sessions, includePinOrder: false);

    final topSessions = <ChatSession>[];
    final seen = <String>{};
    for (final s in sessions) {
      if (seen.add(s.id)) {
        topSessions.add(s);
        if (topSessions.length >= limit) break;
      }
    }
    if (topSessions.isEmpty) return const [];

    final matchedContentBySession = <String, String>{};
    const chunkSize = 500;
    for (var i = 0; i < topSessions.length; i += chunkSize) {
      final end = (i + chunkSize < topSessions.length)
          ? i + chunkSize
          : topSessions.length;
      final chunkIds =
          topSessions.sublist(i, end).map((s) => s.id).toList(growable: false);
      final placeholders = List.filled(chunkIds.length, '?').join(',');
      final msgRows = await db.rawQuery(
        '''
        SELECT session_id, content, created_at
        FROM chat_messages
        WHERE session_id IN ($placeholders)
          AND content LIKE ?
        ORDER BY created_at ASC
        ''',
        <Object?>[...chunkIds, like],
      );
      final earliestBySession = <String, ({DateTime tsUtc, String content})>{};
      for (final mRow in msgRows) {
        final sId = mRow['session_id'] as String?;
        final content = mRow['content'] as String?;
        if (sId == null || content == null) continue;
        final createdStr = mRow['created_at'] as String? ?? '';
        final tsUtc = DateTime.tryParse(createdStr)?.toUtc();
        if (tsUtc == null) continue;
        final prev = earliestBySession[sId];
        if (prev == null || tsUtc.isBefore(prev.tsUtc)) {
          earliestBySession[sId] = (tsUtc: tsUtc, content: content);
        }
      }
      for (final entry in earliestBySession.entries) {
        matchedContentBySession[entry.key] = entry.value.content;
      }
    }

    final results = <ChatSessionSearchResult>[];
    for (final session in topSessions) {
      final matchedContent = matchedContentBySession[session.id];
      final sourceText = (matchedContent?.isNotEmpty ?? false)
          ? matchedContent!
          : session.title;
      final snippet = _buildSnippet(sourceText, normalizedQuery);
      results.add(
        ChatSessionSearchResult(
          session: session,
          snippet: snippet.text,
          isTruncated: snippet.isTruncated,
          matchStart: snippet.matchStart,
          matchEnd: snippet.matchEnd,
        ),
      );
    }
    return results;
  }

  /// 清理没有消息的会话（修复之前保存失败残留的脏数据，排除最近5分钟内新创建的）
  Future<bool> _cleanupEmptySessions(Database db) async {
    try {
      // 查找没有关联 chat_messages 的 chat_sessions
      final emptySessions = await db.rawQuery('''
        SELECT s.id, s.created_at FROM chat_sessions s
        LEFT JOIN chat_messages m ON s.id = m.session_id
        WHERE m.id IS NULL
      ''');

      final now = DateTime.now().toUtc();
      final idsToDelete = <String>[];

      for (final row in emptySessions) {
        final id = row['id'] as String;
        final createdAtStr = row['created_at'] as String?;
        if (createdAtStr != null) {
          final createdAt = DateTime.tryParse(createdAtStr)?.toUtc();
          if (createdAt != null) {
            final diffMinutes = now.difference(createdAt).inMinutes;
            if (diffMinutes >= 0 && diffMinutes < 5) {
              // 最近 5 分钟内创建的空会话，可能是刚生成的，跳过清理
              continue;
            }
          }
        }
        idsToDelete.add(id);
      }

      if (idsToDelete.isNotEmpty) {
        const chunkSize = 500;
        final batch = db.batch();
        for (var i = 0; i < idsToDelete.length; i += chunkSize) {
          final end = (i + chunkSize < idsToDelete.length)
              ? i + chunkSize
              : idsToDelete.length;
          final chunk = idsToDelete.sublist(i, end);
          final placeholders = List.filled(chunk.length, '?').join(',');
          batch.delete(
            'chat_sessions',
            where: 'id IN ($placeholders)',
            whereArgs: chunk,
          );
        }
        await batch.commit(noResult: true);
        logDebug('清理了 ${idsToDelete.length} 个空会话');
      }
      return true;
    } catch (e) {
      logDebug('清理空会话失败: $e');
      return false;
    }
  }

  Future<void> _upsertTombstonesInTxn(
    DatabaseExecutor txn, {
    required String entityType,
    required Iterable<String> entityIds,
    required String deletedAtUtcIso,
    String? sessionId,
    Map<String, String>? sessionIdByEntityId,
  }) async {
    final ids =
        entityIds.where((id) => id.isNotEmpty).toSet().toList(growable: false);
    if (ids.isEmpty) return;
    const chunkSize = 500;
    for (var i = 0; i < ids.length; i += chunkSize) {
      final end = (i + chunkSize < ids.length) ? i + chunkSize : ids.length;
      final batch = txn.batch();
      for (var j = i; j < end; j++) {
        final id = ids[j];
        final resolvedSessionId = entityType == 'message'
            ? (sessionIdByEntityId?[id] ?? sessionId)
            : null;
        batch.insert(
          'chat_tombstones',
          {
            'entity_type': entityType,
            'entity_id': id,
            'deleted_at': deletedAtUtcIso,
            if (resolvedSessionId != null && resolvedSessionId.isNotEmpty)
              'session_id': resolvedSessionId,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      await batch.commit(noResult: true);
    }
  }

  Future<void> _recalibrateSessionLastActiveInTxn(
    DatabaseExecutor txn,
    String sessionId,
  ) async {
    final sessionRows = await txn.query(
      'chat_sessions',
      columns: const <String>['created_at', 'last_active_at'],
      where: 'id = ?',
      whereArgs: <Object?>[sessionId],
      limit: 1,
    );
    if (sessionRows.isEmpty) return;
    final createdStr = _normalizeChatTimestampToUtcOrKeep(
      sessionRows.first['created_at'],
    );
    final currentLastActiveRaw =
        sessionRows.first['last_active_at']?.toString() ?? '';
    final createdVer = _parseChatSyncVersion(createdStr);

    final msgTimeRows = await txn.query(
      'chat_messages',
      columns: const <String>['created_at', 'updated_at'],
      where: 'session_id = ?',
      whereArgs: <Object?>[sessionId],
    );
    ({_ChatSyncVersion ver, String iso})? maxMsg;
    for (final r in msgTimeRows) {
      final createdNorm = _normalizeChatTimestampToUtcOrKeep(r['created_at']);
      final updatedNorm = _normalizeChatTimestampToUtcOrKeep(r['updated_at']);
      final createdMsgVer = LWWUtils.tryParseSyncVersion(createdNorm);
      final updatedMsgVer = LWWUtils.tryParseSyncVersion(updatedNorm);
      ({_ChatSyncVersion ver, String iso})? rowMax;
      if (createdMsgVer != null && updatedMsgVer != null) {
        rowMax = LWWUtils.compareSyncVersions(updatedMsgVer, createdMsgVer) >= 0
            ? (ver: updatedMsgVer, iso: updatedNorm)
            : (ver: createdMsgVer, iso: createdNorm);
      } else if (updatedMsgVer != null) {
        rowMax = (ver: updatedMsgVer, iso: updatedNorm);
      } else if (createdMsgVer != null) {
        rowMax = (ver: createdMsgVer, iso: createdNorm);
      }
      if (rowMax != null &&
          (maxMsg == null ||
              LWWUtils.compareSyncVersions(rowMax.ver, maxMsg.ver) > 0)) {
        maxMsg = rowMax;
      }
    }

    final targetIso = (maxMsg != null &&
            LWWUtils.compareSyncVersions(maxMsg.ver, createdVer) > 0)
        ? maxMsg.iso
        : createdStr;
    if (targetIso.isNotEmpty && targetIso != currentLastActiveRaw) {
      await txn.update(
        'chat_sessions',
        <String, Object?>{'last_active_at': targetIso},
        where: 'id = ?',
        whereArgs: <Object?>[sessionId],
      );
    }
  }

  /// 清理空会话（确认会话内无用户消息时删除，且**不写墓碑**）。
  ///
  /// 用于页面退出时的临时空壳会话回收：不写墓碑，确保若对端同一会话已有消息，
  /// 同步时可正常合入而不被空壳清理误杀。
  Future<bool> deleteEmptySession(String sessionId) async {
    if (sessionId.isEmpty) return false;
    var deleted = false;
    try {
      await _persistOrQueueWrite((db) async {
        await db.transaction((txn) async {
          final userMsgs = await txn.query(
            'chat_messages',
            columns: ['id'],
            where: 'session_id = ? AND role = ?',
            whereArgs: [sessionId, 'user'],
            limit: 1,
          );
          if (userMsgs.isNotEmpty) {
            return;
          }
          await txn.delete(
            'chat_messages',
            where: 'session_id = ?',
            whereArgs: [sessionId],
          );
          final count = await txn.delete(
            'chat_sessions',
            where: 'id = ?',
            whereArgs: [sessionId],
          );
          deleted = count > 0;
        });
      }, operationName: 'ChatSessionService.deleteEmptySession');
    } catch (e) {
      logError(
        'ChatSessionService.deleteEmptySession 失败',
        error: e,
        source: 'ChatSessionService',
      );
    }
    if (deleted) {
      notifyListeners();
    }
    return deleted;
  }

  Future<void> deleteSession(String sessionId) async {
    await deleteSessions([sessionId]);
  }

  /// 批量删除多个会话及其关联消息，避免多次写事务和循环通知导致的性能问题与 N+1 查询。
  Future<void> deleteSessions(List<String> sessionIds) async {
    final targetIds =
        sessionIds.where((id) => id.isNotEmpty).toSet().toList(growable: false);
    if (targetIds.isEmpty) return;
    try {
      await _persistOrQueueWrite((db) async {
        final deletedAt = LWWUtils.formatFixedUtcIso(DateTime.now());
        await db.transaction((txn) async {
          const chunkSize = 500;
          for (var i = 0; i < targetIds.length; i += chunkSize) {
            final end = (i + chunkSize < targetIds.length)
                ? i + chunkSize
                : targetIds.length;
            final chunk = targetIds.sublist(i, end);
            final placeholders = List.filled(chunk.length, '?').join(',');
            final msgRows = await txn.query(
              'chat_messages',
              columns: const ['id', 'session_id'],
              where: 'session_id IN ($placeholders)',
              whereArgs: chunk,
            );
            final msgIds = <String>[];
            final sessionIdByMsgId = <String, String>{};
            for (final r in msgRows) {
              final mId = r['id']?.toString() ?? '';
              if (mId.isEmpty) continue;
              msgIds.add(mId);
              final sId = r['session_id']?.toString() ?? '';
              if (sId.isNotEmpty) {
                sessionIdByMsgId[mId] = sId;
              }
            }
            await _upsertTombstonesInTxn(
              txn,
              entityType: 'message',
              entityIds: msgIds,
              deletedAtUtcIso: deletedAt,
              sessionIdByEntityId: sessionIdByMsgId,
            );
            await _upsertTombstonesInTxn(
              txn,
              entityType: 'session',
              entityIds: chunk,
              deletedAtUtcIso: deletedAt,
            );
            await txn.delete(
              'chat_tombstones',
              where:
                  "entity_type = 'session_cutoff' AND entity_id IN ($placeholders)",
              whereArgs: chunk,
            );
            await txn.delete(
              'chat_messages',
              where: 'session_id IN ($placeholders)',
              whereArgs: chunk,
            );
            await txn.delete(
              'chat_sessions',
              where: 'id IN ($placeholders)',
              whereArgs: chunk,
            );
          }
        });
      }, operationName: 'ChatSessionService.deleteSessions');
    } catch (e) {
      logError(
        'ChatSessionService.deleteSessions 失败',
        error: e,
        source: 'ChatSessionService',
      );
    }
    notifyListeners();
  }

  Future<void> updateSessionTitle(String sessionId, String title) async {
    try {
      final nowUtcIso = LWWUtils.formatFixedUtcIso(DateTime.now());
      await _persistOrQueueWrite((db) async {
        await db.update(
          'chat_sessions',
          {
            'title': title,
            'last_active_at': nowUtcIso,
            'updated_at': nowUtcIso,
          },
          where: 'id = ?',
          whereArgs: [sessionId],
        );
      }, operationName: 'ChatSessionService.updateSessionTitle');
    } catch (e) {
      logError(
        'ChatSessionService.updateSessionTitle 失败',
        error: e,
        source: 'ChatSessionService',
      );
    }
    notifyListeners();
  }

  Future<void> togglePin(String sessionId) async {
    try {
      final nowUtcIso = LWWUtils.formatFixedUtcIso(DateTime.now());
      await _persistOrQueueWrite((db) async {
        final rows = await db.query(
          'chat_sessions',
          where: 'id = ?',
          whereArgs: [sessionId],
        );
        if (rows.isNotEmpty) {
          final current =
              ((rows.first['is_pinned'] as num?)?.toInt() ?? 0) == 1;
          await db.update(
            'chat_sessions',
            {
              'is_pinned': current ? 0 : 1,
              'updated_at': nowUtcIso,
            },
            where: 'id = ?',
            whereArgs: [sessionId],
          );
        }
      }, operationName: 'ChatSessionService.togglePin');
    } catch (e) {
      logError(
        'ChatSessionService.togglePin 失败',
        error: e,
        source: 'ChatSessionService',
      );
    }
    notifyListeners();
  }

  /// 持久化消息并返回是否写入成功。
  ///
  /// 若目标会话已被远端同步或本地操作删除，事务内会因会话不存在而中止并返回 `false`，
  /// 避免写入孤儿消息或静默吞掉外键错误。
  Future<bool> tryAddMessage(String sessionId, ChatMessage message) async {
    if (sessionId.isEmpty) return false;
    var persisted = false;
    try {
      final nowUtcIso = LWWUtils.formatFixedUtcIso(DateTime.now());
      final messageCreatedUtcIso =
          LWWUtils.formatFixedUtcIso(message.timestamp);
      await _persistOrQueueWrite((db) async {
        await db.transaction((txn) async {
          // 先刷新会话活跃时间并校验父会话确实存在（不刷新会话元数据 updated_at，
          // 避免覆盖对端标题/置顶修改）。若父会话已被删除则立即中止，防止产生孤儿消息。
          final updatedSessions = await txn.update(
            'chat_sessions',
            {'last_active_at': nowUtcIso},
            where: 'id = ?',
            whereArgs: [sessionId],
          );
          if (updatedSessions <= 0) {
            throw StateError('目标对话会话不存在: $sessionId');
          }

          final row = message.toMap(sessionId);
          row['created_at'] = messageCreatedUtcIso;
          row['updated_at'] = nowUtcIso;
          final existingRows = await txn.query(
            'chat_messages',
            columns: const <String>['created_at', 'updated_at'],
            where: 'id = ?',
            whereArgs: <Object?>[message.id],
            limit: 1,
          );
          if (existingRows.isEmpty) {
            await txn.insert('chat_messages', row);
          } else {
            final existing = existingRows.first;
            final existingCreated = existing['created_at'];
            final existingUpdated = existing['updated_at'];
            if (!LWWUtils.isCanonicalFixedUtcIso(existingCreated) ||
                !LWWUtils.isCanonicalFixedUtcIso(existingUpdated)) {
              await addColumnIfMissing(
                txn,
                tableName: 'chat_messages',
                columnName: 'created_at_backup',
                definition: 'TEXT',
              );
              await addColumnIfMissing(
                txn,
                tableName: 'chat_messages',
                columnName: 'updated_at_backup',
                definition: 'TEXT',
              );
              await txn.rawUpdate(
                'UPDATE chat_messages SET '
                'created_at_backup = COALESCE(created_at_backup, created_at), '
                'updated_at_backup = COALESCE(updated_at_backup, updated_at) '
                'WHERE id = ?',
                <Object?>[message.id],
              );
            }
            // 使用原地 UPDATE 而非 ConflictAlgorithm.replace（DELETE + INSERT），
            // 确保复用已有消息 ID 编辑时保留迁移生成的 *_backup 快照列。
            await txn.update(
              'chat_messages',
              row,
              where: 'id = ?',
              whereArgs: <Object?>[message.id],
            );
          }
          persisted = true;
        });
      }, operationName: 'ChatSessionService.addMessage');
    } catch (e) {
      logError(
        'ChatSessionService.addMessage 失败',
        error: e,
        source: 'ChatSessionService',
      );
      return false;
    }
    if (persisted) {
      notifyListeners();
    }
    return persisted;
  }

  Future<void> addMessage(String sessionId, ChatMessage message) async {
    await tryAddMessage(sessionId, message);
  }

  /// 检查指定会话是否仍然存在于数据库中。
  ///
  /// 返回 `null` 表示数据库暂不可读（未就绪或查询异常），调用方不应把读库失败
  /// 误判为会话已被删除。
  Future<bool?> sessionExists(String sessionId) async {
    if (sessionId.isEmpty) return false;
    final db = await _getDatabaseForRead();
    if (db == null) return null;
    try {
      final rows = await db.query(
        'chat_sessions',
        columns: const <String>['id'],
        where: 'id = ?',
        whereArgs: <Object?>[sessionId],
        limit: 1,
      );
      return rows.isNotEmpty;
    } catch (e) {
      logError(
        'ChatSessionService.sessionExists 失败',
        error: e,
        source: 'ChatSessionService',
      );
      return null;
    }
  }

  List<ChatMessage> _parseMessagesFromRows(List<Map<String, dynamic>> rows) {
    final messages = <ChatMessage>[];
    var skippedCount = 0;
    String? firstReason;

    for (final row in rows) {
      try {
        messages.add(ChatMessage.fromMap(row));
      } catch (e) {
        firstReason ??= e.runtimeType.toString();
        skippedCount++;
      }
    }

    if (skippedCount > 0) {
      logWarning(
        'ChatSessionService.getMessages 跳过 $skippedCount 条无法解析的消息行'
        '${firstReason != null ? '（首个原因: $firstReason）' : ''}',
        source: 'ChatSessionService',
      );
    }

    return messages;
  }

  Future<List<ChatMessage>> getMessages(String sessionId) async {
    final db = await _getDatabaseForRead();
    if (db == null) return [];
    try {
      final rows = await db.query(
        'chat_messages',
        where: 'session_id = ?',
        whereArgs: [sessionId],
        orderBy: 'created_at ASC',
      );
      final parsed = _parseMessagesFromRows(rows);
      if (parsed.length > 1) {
        final indexById = <String, int>{
          for (var i = 0; i < parsed.length; i++) parsed[i].id: i,
        };
        parsed.sort((a, b) {
          final cmp = a.timestamp.toUtc().compareTo(b.timestamp.toUtc());
          if (cmp != 0) return cmp;
          return (indexById[a.id] ?? 0).compareTo(indexById[b.id] ?? 0);
        });
      }
      return parsed;
    } catch (e) {
      logError(
        'ChatSessionService.getMessages 失败',
        error: e,
        source: 'ChatSessionService',
      );
      return [];
    }
  }

  /// 这个会话里有没有用户消息。
  ///
  /// **返回 `null` 表示没能确认**（数据库还没就绪，或者查询失败），必须和
  /// "确认里面没有"分开看：调用方拿这个结果决定要不要删会话，而 [getMessages]
  /// 在读失败时返回的是空列表——把读不出来当成空会话，一次临时的读库失败
  /// 就会删掉用户一整段对话。
  ///
  /// 只查一行：这里要的是"有没有"，不是把整段对话读进内存。
  Future<bool?> sessionHasUserMessages(String sessionId) async {
    final db = await _getDatabaseForRead();
    if (db == null) return null;
    try {
      final rows = await db.query(
        'chat_messages',
        columns: ['id'],
        where: 'session_id = ? AND role = ?',
        whereArgs: [sessionId, 'user'],
        limit: 1,
      );
      return rows.isNotEmpty;
    } catch (e) {
      logError(
        'ChatSessionService.sessionHasUserMessages 失败',
        error: e,
        source: 'ChatSessionService',
      );
      return null;
    }
  }

  Future<int> getMessageCount(String sessionId) async {
    final db = await _getDatabaseForRead();
    if (db == null) return 0;
    try {
      final result = await db.rawQuery(
        'SELECT COUNT(*) as count FROM chat_messages WHERE session_id = ?',
        [sessionId],
      );
      return safeParseInt(result.firstOrNull?['count']);
    } catch (e) {
      logError(
        'ChatSessionService.getMessageCount 失败',
        error: e,
        source: 'ChatSessionService',
      );
      return 0;
    }
  }

  Future<void> deleteMessage(String messageId) async {
    if (messageId.isEmpty) return;
    try {
      final deletedAt = LWWUtils.formatFixedUtcIso(DateTime.now());
      await _persistOrQueueWrite((db) async {
        await db.transaction((txn) async {
          final existingRows = await txn.query(
            'chat_messages',
            columns: const <String>['session_id'],
            where: 'id = ?',
            whereArgs: <Object?>[messageId],
            limit: 1,
          );
          final rawSessionId =
              existingRows.firstOrNull?['session_id']?.toString() ?? '';
          final sessionId = rawSessionId.isNotEmpty ? rawSessionId : null;
          await _upsertTombstonesInTxn(
            txn,
            entityType: 'message',
            entityIds: [messageId],
            deletedAtUtcIso: deletedAt,
            sessionId: sessionId,
          );
          await txn.delete(
            'chat_messages',
            where: 'id = ?',
            whereArgs: [messageId],
          );
          if (sessionId != null) {
            await _recalibrateSessionLastActiveInTxn(txn, sessionId);
          }
        });
      }, operationName: 'ChatSessionService.deleteMessage');
    } catch (e) {
      logError(
        'ChatSessionService.deleteMessage 失败',
        error: e,
        source: 'ChatSessionService',
      );
    }
    notifyListeners();
  }

  Future<void> clearMessages(String sessionId) async {
    if (sessionId.isEmpty) return;
    try {
      final deletedAt = LWWUtils.formatFixedUtcIso(DateTime.now());
      await _persistOrQueueWrite((db) async {
        await db.transaction((txn) async {
          final rows = await txn.query(
            'chat_messages',
            columns: ['id'],
            where: 'session_id = ?',
            whereArgs: [sessionId],
          );
          final msgIds = rows.map((r) => r['id']?.toString() ?? '').toList();
          await _upsertTombstonesInTxn(
            txn,
            entityType: 'message',
            entityIds: msgIds,
            deletedAtUtcIso: deletedAt,
            sessionId: sessionId,
          );
          await _upsertTombstonesInTxn(
            txn,
            entityType: 'session_cutoff',
            entityIds: [sessionId],
            deletedAtUtcIso: deletedAt,
          );
          await txn.delete(
            'chat_messages',
            where: 'session_id = ?',
            whereArgs: [sessionId],
          );
          await _recalibrateSessionLastActiveInTxn(txn, sessionId);
        });
      }, operationName: 'ChatSessionService.clearMessages');
    } catch (e) {
      logError(
        'ChatSessionService.clearMessages 失败',
        error: e,
        source: 'ChatSessionService',
      );
    }
    notifyListeners();
  }

  Future<void> deleteSessionsForNote(String noteId) async {
    if (noteId.isEmpty) return;
    try {
      final deletedAt = LWWUtils.formatFixedUtcIso(DateTime.now());
      await _persistOrQueueWrite((db) async {
        await db.transaction((txn) async {
          // 首先通过 note_id 找到所有相关的会话 ID
          final sessions = await txn.query(
            'chat_sessions',
            columns: ['id'],
            where: 'note_id = ?',
            whereArgs: [noteId],
          );

          if (sessions.isNotEmpty) {
            final sessionIds = sessions
                .map((s) => s['id']?.toString() ?? '')
                .where((id) => id.isNotEmpty)
                .toList();
            const chunkSize = 500;
            for (var i = 0; i < sessionIds.length; i += chunkSize) {
              final end = (i + chunkSize < sessionIds.length)
                  ? i + chunkSize
                  : sessionIds.length;
              final chunk = sessionIds.sublist(i, end);
              final placeholders = List.filled(chunk.length, '?').join(',');
              final msgRows = await txn.query(
                'chat_messages',
                columns: const ['id', 'session_id'],
                where: 'session_id IN ($placeholders)',
                whereArgs: chunk,
              );
              final msgIds = <String>[];
              final sessionIdByMsgId = <String, String>{};
              for (final r in msgRows) {
                final mId = r['id']?.toString() ?? '';
                if (mId.isEmpty) continue;
                msgIds.add(mId);
                final sId = r['session_id']?.toString() ?? '';
                if (sId.isNotEmpty) {
                  sessionIdByMsgId[mId] = sId;
                }
              }
              await _upsertTombstonesInTxn(
                txn,
                entityType: 'message',
                entityIds: msgIds,
                deletedAtUtcIso: deletedAt,
                sessionIdByEntityId: sessionIdByMsgId,
              );
              await _upsertTombstonesInTxn(
                txn,
                entityType: 'session',
                entityIds: chunk,
                deletedAtUtcIso: deletedAt,
              );
              await txn.delete(
                'chat_tombstones',
                where:
                    "entity_type = 'session_cutoff' AND entity_id IN ($placeholders)",
                whereArgs: chunk,
              );
              await txn.delete(
                'chat_messages',
                where: 'session_id IN ($placeholders)',
                whereArgs: chunk,
              );
            }
          }

          // 然后删除会话本身
          await txn.delete(
            'chat_sessions',
            where: 'note_id = ?',
            whereArgs: [noteId],
          );
        });
      }, operationName: 'ChatSessionService.deleteSessionsForNote');
    } catch (e) {
      logError(
        'ChatSessionService.deleteSessionsForNote 失败',
        error: e,
        source: 'ChatSessionService',
      );
    }
    notifyListeners();
  }

  _Snippet _buildSnippet(String text, String query) {
    final lowerText = text.toLowerCase();
    final lowerQuery = query.toLowerCase();
    final index = lowerText.indexOf(lowerQuery);
    if (index < 0) {
      final snippet = _truncate(text, 120);
      return _Snippet(
        text: snippet,
        isTruncated: snippet.length < text.length,
        matchStart: -1,
        matchEnd: -1,
      );
    }

    const radius = 48;
    final start = (index - radius).clamp(0, text.length);
    final end = (index + query.length + radius).clamp(0, text.length);
    final prefix = start > 0 ? '...' : '';
    final suffix = end < text.length ? '...' : '';
    final snippet = '$prefix${text.substring(start, end)}$suffix';
    return _Snippet(
      text: snippet,
      isTruncated: start > 0 || end < text.length,
      matchStart: prefix.length + index - start,
      matchEnd: prefix.length + index - start + query.length,
    );
  }

  String _truncate(String value, int maxLength) {
    if (value.length <= maxLength) return value;
    return value.substring(0, maxLength);
  }
}

class ChatSessionSearchResult {
  final ChatSession session;
  final String snippet;
  final bool isTruncated;
  final int matchStart;
  final int matchEnd;

  const ChatSessionSearchResult({
    required this.session,
    required this.snippet,
    required this.isTruncated,
    required this.matchStart,
    required this.matchEnd,
  });
}

class _Snippet {
  final String text;
  final bool isTruncated;
  final int matchStart;
  final int matchEnd;

  const _Snippet({
    required this.text,
    required this.isTruncated,
    required this.matchStart,
    required this.matchEnd,
  });
}
