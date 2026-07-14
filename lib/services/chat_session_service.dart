import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../models/chat_message.dart';
import '../models/chat_session.dart';
import '../utils/app_logger.dart';
import 'data_directory_service.dart';

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

  static const int _schemaVersion = 2;
  static const String _legacyMainDbMigrationKey =
      'legacy_main_db_chat_migration_complete';
  static const Duration _emptySessionCleanupInterval = Duration(minutes: 1);

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
    if (db != null && !_databaseReady.isCompleted) {
      _databaseReady.complete();
    }
    if (db != null) {
      _flushPendingWrites(db);
    }
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
        final batch = txn.batch();
        for (final row in legacySessions) {
          batch.insert(
            'chat_sessions',
            row,
            conflictAlgorithm: ConflictAlgorithm.ignore,
          );
        }

        for (final row in legacyMessages) {
          batch.insert(
            'chat_messages',
            row,
            conflictAlgorithm: ConflictAlgorithm.ignore,
          );
        }
        batch.insert(
          'chat_metadata',
          {
            'key': _legacyMainDbMigrationKey,
            'value': 'true',
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
        await batch.commit(noResult: true);
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

    await _addColumnIfMissing(
      db,
      tableName: 'chat_sessions',
      columnName: 'session_type',
      definition: "TEXT NOT NULL DEFAULT 'note'",
    );
    await _addColumnIfMissing(
      db,
      tableName: 'chat_sessions',
      columnName: 'note_id',
      definition: 'TEXT',
    );
    await _addColumnIfMissing(
      db,
      tableName: 'chat_sessions',
      columnName: 'title',
      definition: "TEXT NOT NULL DEFAULT ''",
    );
    await _addColumnIfMissing(
      db,
      tableName: 'chat_sessions',
      columnName: 'last_active_at',
      definition: 'TEXT',
    );
    await db.execute('''
      UPDATE chat_sessions
      SET last_active_at = COALESCE(NULLIF(last_active_at, ''), created_at)
      WHERE last_active_at IS NULL OR last_active_at = ''
    ''');
    await _addColumnIfMissing(
      db,
      tableName: 'chat_sessions',
      columnName: 'is_pinned',
      definition: 'INTEGER NOT NULL DEFAULT 0',
    );
    await _addColumnIfMissing(
      db,
      tableName: 'chat_messages',
      columnName: 'included_in_context',
      definition: 'INTEGER NOT NULL DEFAULT 1',
    );
    await _addColumnIfMissing(
      db,
      tableName: 'chat_messages',
      columnName: 'meta_json',
      definition: 'TEXT',
    );
    await _addColumnIfMissing(
      db,
      tableName: 'chat_messages',
      columnName: 'content_format',
      definition: 'TEXT',
    );
    await _addColumnIfMissing(
      db,
      tableName: 'chat_messages',
      columnName: 'delta_json',
      definition: 'TEXT',
    );

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
  }

  Future<void> _addColumnIfMissing(
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
    final definitionRegex =
        RegExp(r"^[a-zA-Z0-9_ ]+(?:DEFAULT (?:'[a-zA-Z0-9_]*'|[0-9]+))?$");
    if (!definitionRegex.hasMatch(definition.trim())) {
      throw ArgumentError.value(
          definition, 'definition', 'Invalid column definition');
    }

    final columns =
        await db.rawQuery('SELECT * FROM pragma_table_info(?)', [tableName]);
    final hasColumn = columns.any((column) => column['name'] == columnName);
    if (!hasColumn) {
      await db.execute(
        'ALTER TABLE $tableName ADD COLUMN $columnName $definition',
      );
    }
  }

  Future<ChatSession> createSession({
    required String sessionType,
    String? noteId,
    required String title,
  }) async {
    final now = DateTime.now();
    final session = ChatSession(
      id: const Uuid().v4(),
      sessionType: sessionType,
      noteId: noteId,
      title: title,
      createdAt: now,
      lastActiveAt: now,
    );
    try {
      await _persistOrQueueWrite((db) async {
        await db.insert('chat_sessions', session.toMap());
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

  Future<List<ChatSession>> getSessionsForNote(String noteId) async {
    final db = await _getDatabaseForRead();
    if (db == null) return [];
    try {
      final rows = await db.query(
        'chat_sessions',
        where: 'note_id = ?',
        whereArgs: [noteId],
        orderBy: 'last_active_at DESC',
      );
      return _parseSessionsFromRows(rows);
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
      final rows = await db.query(
        'chat_sessions',
        where: 'session_type = ?',
        whereArgs: ['agent'],
        orderBy: 'last_active_at DESC',
      );
      return _parseSessionsFromRows(rows);
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
    final placeholders = List.filled(sessionIds.length, '?').join(',');
    final rows = await db.rawQuery(
      '''
      SELECT s.id,
        (SELECT COUNT(*) FROM chat_messages c WHERE c.session_id = s.id)
          AS message_count,
        (SELECT m.content FROM chat_messages m
          WHERE m.session_id = s.id
          ORDER BY m.created_at DESC LIMIT 1) AS last_content
      FROM chat_sessions s
      WHERE s.id IN ($placeholders)
      ''',
      sessionIds,
    );
    return {
      for (final row in rows)
        row['id'] as String: ChatSessionOverview(
          messageCount: row['message_count'] as int? ?? 0,
          snippet: _truncatePreview(row['last_content'] as String?),
        ),
    };
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
    if (normalizedQuery.isEmpty) return const [];

    final db = await _getDatabaseForRead();
    if (db == null) return const [];

    try {
      final like = '%$normalizedQuery%';
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
          ) AS matched_content
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
        [like, like, like, limit],
      );

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

  /// 清理没有消息的会话（修复之前保存失败残留的脏数据，排除最近5分钟内新创建的）
  Future<bool> _cleanupEmptySessions(Database db) async {
    try {
      // 查找没有关联 chat_messages 的 chat_sessions
      final emptySessions = await db.rawQuery('''
        SELECT s.id, s.created_at FROM chat_sessions s
        LEFT JOIN chat_messages m ON s.id = m.session_id
        WHERE m.id IS NULL
      ''');

      final now = DateTime.now();
      int deletedCount = 0;

      for (final row in emptySessions) {
        final id = row['id'] as String;
        final createdAtStr = row['created_at'] as String?;
        if (createdAtStr != null) {
          final createdAt = DateTime.tryParse(createdAtStr);
          if (createdAt != null) {
            final diffMinutes = now.difference(createdAt).inMinutes;
            if (diffMinutes >= 0 && diffMinutes < 5) {
              // 最近 5 分钟内创建的空会话，可能是刚生成的，跳过清理
              continue;
            }
          }
        }
        await db.delete('chat_sessions', where: 'id = ?', whereArgs: [id]);
        deletedCount++;
      }
      if (deletedCount > 0) {
        logDebug('清理了 $deletedCount 个空会话');
      }
      return true;
    } catch (e) {
      logDebug('清理空会话失败: $e');
      return false;
    }
  }

  Future<void> deleteSession(String sessionId) async {
    try {
      await _persistOrQueueWrite((db) async {
        await db.delete(
          'chat_sessions',
          where: 'id = ?',
          whereArgs: [sessionId],
        );
      }, operationName: 'ChatSessionService.deleteSession');
    } catch (e) {
      logError(
        'ChatSessionService.deleteSession 失败',
        error: e,
        source: 'ChatSessionService',
      );
    }
    notifyListeners();
  }

  Future<void> updateSessionTitle(String sessionId, String title) async {
    try {
      await _persistOrQueueWrite((db) async {
        await db.update(
          'chat_sessions',
          {'title': title, 'last_active_at': DateTime.now().toIso8601String()},
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
      await _persistOrQueueWrite((db) async {
        final rows = await db.query(
          'chat_sessions',
          where: 'id = ?',
          whereArgs: [sessionId],
        );
        if (rows.isNotEmpty) {
          final current = (rows.first['is_pinned'] as int? ?? 0) == 1;
          await db.update(
            'chat_sessions',
            {'is_pinned': current ? 0 : 1},
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

  Future<void> addMessage(String sessionId, ChatMessage message) async {
    try {
      await _persistOrQueueWrite((db) async {
        await db.transaction((txn) async {
          await txn.insert(
            'chat_messages',
            message.toMap(sessionId),
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
          await txn.update(
            'chat_sessions',
            {'last_active_at': DateTime.now().toIso8601String()},
            where: 'id = ?',
            whereArgs: [sessionId],
          );
        });
      }, operationName: 'ChatSessionService.addMessage');
    } catch (e) {
      logError(
        'ChatSessionService.addMessage 失败',
        error: e,
        source: 'ChatSessionService',
      );
    }
    notifyListeners();
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
      return rows.map(ChatMessage.fromMap).toList();
    } catch (e) {
      logError(
        'ChatSessionService.getMessages 失败',
        error: e,
        source: 'ChatSessionService',
      );
      return [];
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
      return result.first['count'] as int? ?? 0;
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
    try {
      await _persistOrQueueWrite((db) async {
        await db.delete(
          'chat_messages',
          where: 'id = ?',
          whereArgs: [messageId],
        );
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
    try {
      await _persistOrQueueWrite((db) async {
        await db.delete(
          'chat_messages',
          where: 'session_id = ?',
          whereArgs: [sessionId],
        );
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
    try {
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
            final sessionIds = sessions.map((s) => s['id'] as String).toList();
            // 删除这些会话的所有消息
            final placeholders = List.filled(sessionIds.length, '?').join(',');
            await txn.delete(
              'chat_messages',
              where: 'session_id IN ($placeholders)',
              whereArgs: sessionIds,
            );
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
