import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../models/chat_message.dart';
import '../models/chat_session.dart';
import '../utils/app_logger.dart';

class ChatSessionService extends ChangeNotifier {
  Database? _database;

  void setDatabase(Database? db) {
    _database = db;
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
      if (_database != null && !kIsWeb) {
        await _database!.insert('chat_sessions', session.toMap());
      }
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
    if (_database == null || kIsWeb) return null;
    try {
      final rows = await _database!.query(
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
    if (_database == null || kIsWeb) return [];
    try {
      final rows = await _database!.query(
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
    if (_database == null || kIsWeb) return [];
    try {
      final rows = await _database!.query(
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
    if (_database == null || kIsWeb) return [];
    try {
      final rows = await _database!.query(
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
      if (_database != null && !kIsWeb) {
        await _database!.delete(
          'chat_sessions',
          where: 'id = ?',
          whereArgs: [sessionId],
        );
      }
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
      if (_database != null && !kIsWeb) {
        await _database!.update(
          'chat_sessions',
          {
            'title': title,
            'last_active_at': DateTime.now().toIso8601String(),
          },
          where: 'id = ?',
          whereArgs: [sessionId],
        );
      }
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
      if (_database != null && !kIsWeb) {
        final rows = await _database!.query(
          'chat_sessions',
          where: 'id = ?',
          whereArgs: [sessionId],
        );
        if (rows.isNotEmpty) {
          final current = (rows.first['is_pinned'] as int? ?? 0) == 1;
          await _database!.update(
            'chat_sessions',
            {'is_pinned': current ? 0 : 1},
            where: 'id = ?',
            whereArgs: [sessionId],
          );
        }
      }
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
      if (_database != null && !kIsWeb) {
        await _database!.insert('chat_messages', message.toMap(sessionId));
        await _database!.update(
          'chat_sessions',
          {'last_active_at': DateTime.now().toIso8601String()},
          where: 'id = ?',
          whereArgs: [sessionId],
        );
      }
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
    if (_database == null || kIsWeb) return [];
    try {
      final rows = await _database!.query(
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
    if (_database == null || kIsWeb) return 0;
    try {
      final result = await _database!.rawQuery(
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
      if (_database != null && !kIsWeb) {
        await _database!.delete(
          'chat_messages',
          where: 'id = ?',
          whereArgs: [messageId],
        );
      }
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
      if (_database != null && !kIsWeb) {
        await _database!.delete(
          'chat_messages',
          where: 'session_id = ?',
          whereArgs: [sessionId],
        );
      }
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
      if (_database != null && !kIsWeb) {
        await _database!.delete(
          'chat_sessions',
          where: 'note_id = ?',
          whereArgs: [noteId],
        );
      }
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
