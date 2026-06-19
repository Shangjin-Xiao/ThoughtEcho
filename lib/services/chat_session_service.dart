import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../models/chat_message.dart';
import '../models/chat_session.dart';
import '../utils/app_logger.dart';

class ChatSessionService extends ChangeNotifier {
  Database? _database;
  final List<Future<void> Function(Database db)> _pendingWrites = [];
  final Completer<void> _databaseReady = Completer<void>();

  ChatSessionService();

  void setDatabase(Database? db) {
    _database = db;
    if (db != null && !_databaseReady.isCompleted) {
      _databaseReady.complete();
    }
    if (db != null) {
      _flushPendingWrites(db);
    }
  }

  void _flushPendingWrites(Database db) {
    if (_pendingWrites.isEmpty) return;
    final writes =
        List<Future<void> Function(Database db)>.from(_pendingWrites);
    _pendingWrites.clear();
    for (final write in writes) {
      Future<void>.microtask(() async {
        try {
          await write(db);
        } catch (e) {
          logError(
            'ChatSessionService 延迟写入执行失败',
            error: e,
            source: 'ChatSessionService',
          );
        } finally {
          notifyListeners();
        }
      });
    }
  }

  /// 获取数据库实例，若数据库尚未就绪则等待
  ///
  /// 平台差异（如 Web 内存库）由 DatabaseService 层处理，此处不做短路。
  Future<Database?> _getDatabase() async {
    if (_database != null) return _database;
    // 无限等待数据库就绪，避免超时后静默丢数据
    await _databaseReady.future;
    return _database;
  }

  /// 获取数据库实例，带超时限制（仅用于只读查询）
  ///
  /// 超时后返回 null，调用方需自行处理降级逻辑（如返回空列表）。
  /// 写操作禁止使用此方法，应使用 [_persistOrQueueWrite]。
  Future<Database?> _getDatabaseForRead({
    Duration timeout = const Duration(seconds: 5),
  }) async {
    if (_database != null) return _database;
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
    final db = await _getDatabase();
    if (db == null) {
      // 数据库尚未就绪，加入队列等待后续执行
      logWarning(
        '$operationName 数据库未就绪，已加入延迟写入队列',
        source: 'ChatSessionService',
      );
      _pendingWrites.add(write);
      return;
    }
    await write(db);
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
      await _persistOrQueueWrite(
        (db) async {
          await db.insert('chat_sessions', session.toMap());
        },
        operationName: 'ChatSessionService.createSession',
      );
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
      return rows.map(ChatSession.fromMap).toList();
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
      return rows.map(ChatSession.fromMap).toList();
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
      // 先清理没有消息的会话（防止之前保存失败残留的脏数据）
      await _cleanupEmptySessions(db);

      final rows = await db.query(
        'chat_sessions',
        orderBy: 'is_pinned DESC, last_active_at DESC',
        limit: limit,
        offset: offset,
      );
      return rows.map(ChatSession.fromMap).toList();
    } catch (e) {
      logError(
        'ChatSessionService.getAllSessions 失败',
        error: e,
        source: 'ChatSessionService',
      );
      return [];
    }
  }

  /// 清理没有消息的会话（修复之前保存失败残留的脏数据）
  Future<void> _cleanupEmptySessions(Database db) async {
    try {
      // 查找没有关联 chat_messages 的 chat_sessions
      final emptySessions = await db.rawQuery('''
        SELECT s.id FROM chat_sessions s
        LEFT JOIN chat_messages m ON s.id = m.session_id
        WHERE m.id IS NULL
      ''');
      for (final row in emptySessions) {
        final id = row['id'] as String;
        await db.delete('chat_sessions', where: 'id = ?', whereArgs: [id]);
      }
      if (emptySessions.isNotEmpty) {
        logDebug('清理了 ${emptySessions.length} 个空会话');
      }
    } catch (e) {
      logDebug('清理空会话失败: $e');
    }
  }

  Future<void> deleteSession(String sessionId) async {
    try {
      await _persistOrQueueWrite(
        (db) async {
          await db.delete(
            'chat_sessions',
            where: 'id = ?',
            whereArgs: [sessionId],
          );
        },
        operationName: 'ChatSessionService.deleteSession',
      );
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
      await _persistOrQueueWrite(
        (db) async {
          await db.update(
            'chat_sessions',
            {
              'title': title,
              'last_active_at': DateTime.now().toIso8601String(),
            },
            where: 'id = ?',
            whereArgs: [sessionId],
          );
        },
        operationName: 'ChatSessionService.updateSessionTitle',
      );
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
      await _persistOrQueueWrite(
        (db) async {
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
        },
        operationName: 'ChatSessionService.togglePin',
      );
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
      await _persistOrQueueWrite(
        (db) async {
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
        },
        operationName: 'ChatSessionService.addMessage',
      );
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
      await _persistOrQueueWrite(
        (db) async {
          await db.delete(
            'chat_messages',
            where: 'id = ?',
            whereArgs: [messageId],
          );
        },
        operationName: 'ChatSessionService.deleteMessage',
      );
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
      await _persistOrQueueWrite(
        (db) async {
          await db.delete(
            'chat_messages',
            where: 'session_id = ?',
            whereArgs: [sessionId],
          );
        },
        operationName: 'ChatSessionService.clearMessages',
      );
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
      await _persistOrQueueWrite(
        (db) async {
          await db.transaction((txn) async {
            // 首先通过 note_id 找到所有相关的会话 ID
            final sessions = await txn.query(
              'chat_sessions',
              columns: ['id'],
              where: 'note_id = ?',
              whereArgs: [noteId],
            );

            if (sessions.isNotEmpty) {
              final sessionIds =
                  sessions.map((s) => s['id'] as String).toList();
              // 删除这些会话的所有消息
              final placeholders =
                  List.filled(sessionIds.length, '?').join(',');
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
        },
        operationName: 'ChatSessionService.deleteSessionsForNote',
      );
    } catch (e) {
      logError(
        'ChatSessionService.deleteSessionsForNote 失败',
        error: e,
        source: 'ChatSessionService',
      );
    }
    notifyListeners();
  }

  /// 按标签查询笔记（支持多标签AND查询）
  Future<List<Map<String, dynamic>>> getNotesByTags(
    List<String> tags, {
    int limit = 20,
  }) async {
    final db = await _getDatabaseForRead();
    if (db == null || tags.isEmpty) return [];
    try {
      final placeholders = List.filled(tags.length, '?').join(',');
      final query = '''
        SELECT DISTINCT q.* FROM quotes q
        JOIN quote_tags qt ON q.id = qt.quote_id
        WHERE qt.tag_id IN ($placeholders)
        GROUP BY q.id
        HAVING COUNT(DISTINCT qt.tag_id) = ${tags.length}
        ORDER BY q.date DESC
        LIMIT ?
      ''';
      final args = [...tags, limit];
      final rows = await db.rawQuery(query, args);
      return rows;
    } catch (e) {
      logError(
        'ChatSessionService.getNotesByTags 失败',
        error: e,
        source: 'ChatSessionService',
      );
      return [];
    }
  }

  /// 获取最新N条笔记
  Future<List<Map<String, dynamic>>> getRecentNotes({
    int limit = 10,
    String? beforeNoteId,
  }) async {
    final db = await _getDatabaseForRead();
    if (db == null) return [];
    try {
      String query = '''
        SELECT * FROM quotes
        ORDER BY date DESC
      ''';
      final args = <dynamic>[];

      if (beforeNoteId != null && beforeNoteId.isNotEmpty) {
        query += ' WHERE id != ?';
        args.add(beforeNoteId);
      }

      query += ' LIMIT ?';
      args.add(limit);

      final rows = await db.rawQuery(query, args);
      return rows;
    } catch (e) {
      logError(
        'ChatSessionService.getRecentNotes 失败',
        error: e,
        source: 'ChatSessionService',
      );
      return [];
    }
  }

  /// 按日期范围查询
  Future<List<Map<String, dynamic>>> getNotesByDateRange(
    DateTime start,
    DateTime end, {
    int limit = 20,
  }) async {
    final db = await _getDatabaseForRead();
    if (db == null) return [];
    try {
      final startStr = start.toIso8601String();
      final endStr = end.toIso8601String();
      final rows = await db.query(
        'quotes',
        where: 'date BETWEEN ? AND ?',
        whereArgs: [startStr, endStr],
        orderBy: 'date DESC',
        limit: limit,
      );
      return rows;
    } catch (e) {
      logError(
        'ChatSessionService.getNotesByDateRange 失败',
        error: e,
        source: 'ChatSessionService',
      );
      return [];
    }
  }

  /// 组合查询：标签 + 日期 + 关键词
  Future<List<Map<String, dynamic>>> queryNotes({
    List<String>? tags,
    DateTime? dateStart,
    DateTime? dateEnd,
    String? keyword,
    int limit = 20,
  }) async {
    final db = await _getDatabaseForRead();
    if (db == null) return [];
    try {
      var query = 'SELECT DISTINCT q.* FROM quotes q';
      final args = <dynamic>[];
      final conditions = <String>[];

      // 标签条件
      if (tags != null && tags.isNotEmpty) {
        query += ' JOIN quote_tags qt ON q.id = qt.quote_id';
        final placeholders = List.filled(tags.length, '?').join(',');
        conditions.add('qt.tag_id IN ($placeholders)');
        args.addAll(tags);
      }

      // 日期范围条件
      if (dateStart != null && dateEnd != null) {
        conditions.add('q.date BETWEEN ? AND ?');
        args.add(dateStart.toIso8601String());
        args.add(dateEnd.toIso8601String());
      }

      // 关键词条件
      if (keyword != null && keyword.trim().isNotEmpty) {
        conditions.add('q.content LIKE ?');
        args.add('%${keyword.trim()}%');
      }

      if (conditions.isNotEmpty) {
        query += ' WHERE ${conditions.join(' AND ')}';
      }

      // 多标签AND查询
      if (tags != null && tags.isNotEmpty) {
        query +=
            ' GROUP BY q.id HAVING COUNT(DISTINCT qt.tag_id) = ${tags.length}';
      }

      query += ' ORDER BY q.date DESC LIMIT ?';
      args.add(limit);

      final rows = await db.rawQuery(query, args);
      return rows;
    } catch (e) {
      logError(
        'ChatSessionService.queryNotes 失败',
        error: e,
        source: 'ChatSessionService',
      );
      return [];
    }
  }

  /// 获取笔记标签
  Future<List<String>> getNoteTagIds(String noteId) async {
    final db = await _getDatabaseForRead();
    if (db == null) return [];
    try {
      final rows = await db.query(
        'quote_tags',
        columns: ['tag_id'],
        where: 'quote_id = ?',
        whereArgs: [noteId],
      );
      return rows.map((row) => row['tag_id'].toString()).toList();
    } catch (e) {
      logError(
        'ChatSessionService.getNoteTagIds 失败',
        error: e,
        source: 'ChatSessionService',
      );
      return [];
    }
  }

  /// 将笔记数据转换为Agent友好的格式
  static Map<String, dynamic> formatNoteForAgent(
    Map<String, dynamic> noteRow, {
    List<String>? tags,
    double? matchScore,
  }) {
    return {
      'id': noteRow['id'] ?? '',
      'title': _extractTitle(noteRow['content'] ?? '', maxLength: 50),
      'content': noteRow['content'] ?? '',
      'tags': tags ?? [],
      'createdAt': noteRow['date'] ?? '',
      'matchScore': matchScore ?? 1.0,
      'summary': noteRow['summary'],
      'sentiment': noteRow['sentiment'],
      'keywords': _parseKeywords(noteRow['keywords']),
    };
  }

  /// 从内容提取标题（前50字）
  static String _extractTitle(String content, {int maxLength = 50}) {
    if (content.isEmpty) return '';
    final lines = content.split('\n');
    final firstLine = lines.first.trim();
    if (firstLine.length <= maxLength) {
      return firstLine;
    }
    return '${firstLine.substring(0, maxLength)}...';
  }

  /// 解析关键词字符串
  static List<String> _parseKeywords(dynamic keywords) {
    if (keywords == null) return [];
    if (keywords is String) {
      return keywords
          .split(',')
          .map((k) => k.trim())
          .where((k) => k.isNotEmpty)
          .toList();
    }
    if (keywords is List) {
      return keywords.map((k) => k.toString().trim()).toList();
    }
    return [];
  }
}
