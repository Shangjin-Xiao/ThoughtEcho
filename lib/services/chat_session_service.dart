import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../models/chat_message.dart';
import '../models/chat_session.dart';
import '../utils/app_logger.dart';

class ChatSessionService extends ChangeNotifier {
  static const Duration _defaultDatabaseReadyTimeout = Duration(seconds: 5);

  Database? _database;
  bool _isWebPersistenceUnsupported = false;
  final List<Future<void> Function(Database db)> _pendingWrites = [];
  final Completer<void> _databaseReady = Completer<void>();
  final Duration _databaseReadyTimeout;
  bool _hasLoggedDatabaseWaitTimeout = false;

  ChatSessionService({
    Duration databaseReadyTimeout = _defaultDatabaseReadyTimeout,
  }) : _databaseReadyTimeout = databaseReadyTimeout;

  void setDatabase(Database? db) {
    _database = db;
    _isWebPersistenceUnsupported = false;
    if (db != null && !_databaseReady.isCompleted) {
      _databaseReady.complete();
    }
    if (db != null && _pendingWrites.isNotEmpty) {
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
  }

  Future<Database?> _getDatabase() async {
    if (kIsWeb) {
      _isWebPersistenceUnsupported = true;
      return null;
    }
    if (_database != null) return _database;

    try {
      await _databaseReady.future.timeout(_databaseReadyTimeout);
    } on TimeoutException {
      if (!_hasLoggedDatabaseWaitTimeout) {
        _hasLoggedDatabaseWaitTimeout = true;
        logWarning(
          'ChatSessionService 等待数据库注入超时，跳过本次持久化操作',
          source: 'ChatSessionService',
        );
      }
      return null;
    }

    return _database;
  }

  Future<void> _persistOrQueueWrite(
    Future<void> Function(Database db) write, {
    required String operationName,
    required String onUnavailableLog,
  }) async {
    final db = await _getDatabase();
    if (db == null) {
      if (_isWebPersistenceUnsupported) {
        logWarning(
          '$operationName 跳过持久化：Web 平台当前不支持 SQLite 会话存储',
          source: 'ChatSessionService',
        );
      } else {
        logWarning(onUnavailableLog, source: 'ChatSessionService');
        _pendingWrites.add(write);
      }
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
        onUnavailableLog: 'ChatSessionService.createSession 数据库未就绪，已加入延迟写入队列',
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
    final db = await _getDatabase();
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
    final db = await _getDatabase();
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
    final db = await _getDatabase();
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
    final db = await _getDatabase();
    if (db == null) return [];
    try {
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
        onUnavailableLog: 'ChatSessionService.deleteSession 数据库未就绪，已加入延迟写入队列',
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
        onUnavailableLog:
            'ChatSessionService.updateSessionTitle 数据库未就绪，已加入延迟写入队列',
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
        onUnavailableLog: 'ChatSessionService.togglePin 数据库未就绪，已加入延迟写入队列',
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
          await db.insert('chat_messages', message.toMap(sessionId));
          await db.update(
            'chat_sessions',
            {'last_active_at': DateTime.now().toIso8601String()},
            where: 'id = ?',
            whereArgs: [sessionId],
          );
        },
        operationName: 'ChatSessionService.addMessage',
        onUnavailableLog: 'ChatSessionService.addMessage 数据库未就绪，已加入延迟写入队列',
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
    final db = await _getDatabase();
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
    final db = await _getDatabase();
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
        onUnavailableLog: 'ChatSessionService.deleteMessage 数据库未就绪，已加入延迟写入队列',
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
        onUnavailableLog: 'ChatSessionService.clearMessages 数据库未就绪，已加入延迟写入队列',
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
          await db.delete(
            'chat_sessions',
            where: 'note_id = ?',
            whereArgs: [noteId],
          );
        },
        operationName: 'ChatSessionService.deleteSessionsForNote',
        onUnavailableLog:
            'ChatSessionService.deleteSessionsForNote 数据库未就绪，已加入延迟写入队列',
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
}
