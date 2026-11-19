part of 'chat_session_service.dart';

const List<String> _chatSessionColumnWhitelist = <String>[
  'id',
  'session_type',
  'note_id',
  'title',
  'created_at',
  'last_active_at',
  'updated_at',
  'is_pinned',
];

const List<String> _chatMessageColumnWhitelist = <String>[
  'id',
  'session_id',
  'role',
  'content',
  'created_at',
  'updated_at',
  'included_in_context',
  'meta_json',
  'content_format',
  'delta_json',
];

@immutable
class ChatMergeStats {
  const ChatMergeStats({
    this.sessionsAdded = 0,
    this.sessionsUpdated = 0,
    this.sessionsDeleted = 0,
    this.sessionsSkipped = 0,
    this.messagesAdded = 0,
    this.messagesUpdated = 0,
    this.messagesDeleted = 0,
    this.messagesSkipped = 0,
  });

  final int sessionsAdded;
  final int sessionsUpdated;
  final int sessionsDeleted;
  final int sessionsSkipped;
  final int messagesAdded;
  final int messagesUpdated;
  final int messagesDeleted;
  final int messagesSkipped;

  bool get hasChanges =>
      sessionsAdded > 0 ||
      sessionsUpdated > 0 ||
      sessionsDeleted > 0 ||
      messagesAdded > 0 ||
      messagesUpdated > 0 ||
      messagesDeleted > 0;
}

class _ParsedChatTombstone {
  const _ParsedChatTombstone({
    required this.entityType,
    required this.entityId,
    required this.deletedAtRaw,
    required this.deletedAtUtc,
  });

  final String entityType;
  final String entityId;
  final String deletedAtRaw;
  final DateTime deletedAtUtc;
}

DateTime? _tryParseChatUtc(Object? raw) {
  if (raw is! String) return null;
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return null;
  final parsed = DateTime.tryParse(trimmed);
  return parsed?.toUtc();
}

int? _parseChatSqliteBoolInt(Object? raw, {required int defaultValue}) {
  if (raw == null) return defaultValue;
  if (raw is bool) return raw ? 1 : 0;
  if (raw is int) return raw == 1 ? 1 : 0;
  if (raw is num) return raw.toInt() == 1 ? 1 : 0;
  if (raw is String) {
    final s = raw.trim().toLowerCase();
    if (s == '1' || s == 'true') return 1;
    if (s == '0' || s == 'false') return 0;
  }
  return null;
}

Map<String, Object?>? _sanitizeSessionRow(Object? item) {
  if (item is! Map) return null;
  final idObj = item['id'];
  if (idObj is! String || idObj.trim().isEmpty) return null;
  final id = idObj.trim();

  final createdAtRaw = item['created_at'] ?? item['createdAt'];
  final createdAtUtc = _tryParseChatUtc(createdAtRaw);
  if (createdAtUtc == null) return null;
  final createdAtStr = (createdAtRaw as String).trim();

  final lastActiveRaw = item['last_active_at'] ?? item['lastActiveAt'];
  final lastActiveUtc = _tryParseChatUtc(lastActiveRaw);
  if (lastActiveRaw != null &&
      lastActiveRaw.toString().trim().isNotEmpty &&
      lastActiveUtc == null) {
    return null;
  }
  final lastActiveStr =
      lastActiveUtc != null ? (lastActiveRaw as String).trim() : createdAtStr;

  final updatedRaw = item['updated_at'] ?? item['updatedAt'];
  final updatedUtc = _tryParseChatUtc(updatedRaw);
  if (updatedRaw != null &&
      updatedRaw.toString().trim().isNotEmpty &&
      updatedUtc == null) {
    return null;
  }
  final updatedStr =
      updatedUtc != null ? (updatedRaw as String).trim() : lastActiveStr;

  final sessionTypeObj = item['session_type'] ?? item['sessionType'];
  String sessionType = 'note';
  if (sessionTypeObj != null) {
    if (sessionTypeObj is! String) return null;
    final trimmed = sessionTypeObj.trim();
    if (trimmed.isNotEmpty) sessionType = trimmed;
  }

  final noteIdObj = item['note_id'] ?? item['noteId'];
  String? noteId;
  if (noteIdObj != null) {
    if (noteIdObj is! String) return null;
    final trimmed = noteIdObj.trim();
    noteId = trimmed.isEmpty ? null : trimmed;
  }

  final titleObj = item['title'];
  if (titleObj != null && titleObj is! String) return null;
  final title = (titleObj as String?) ?? '';

  final isPinned = _parseChatSqliteBoolInt(
    item['is_pinned'] ?? item['isPinned'],
    defaultValue: 0,
  );
  if (isPinned == null) return null;

  return <String, Object?>{
    'id': id,
    'session_type': sessionType,
    'note_id': noteId,
    'title': title,
    'created_at': createdAtStr,
    'last_active_at': lastActiveStr,
    'updated_at': updatedStr,
    'is_pinned': isPinned,
  };
}

Map<String, Object?>? _sanitizeMessageRow(Object? item) {
  if (item is! Map) return null;
  final idObj = item['id'];
  if (idObj is! String || idObj.trim().isEmpty) return null;
  final id = idObj.trim();

  final sessionIdObj = item['session_id'] ?? item['sessionId'];
  if (sessionIdObj is! String || sessionIdObj.trim().isEmpty) return null;
  final sessionId = sessionIdObj.trim();

  final createdAtRaw = item['created_at'] ?? item['timestamp'];
  final createdAtUtc = _tryParseChatUtc(createdAtRaw);
  if (createdAtUtc == null) return null;
  final createdAtStr = (createdAtRaw as String).trim();

  final updatedRaw = item['updated_at'] ?? item['updatedAt'];
  final updatedUtc = _tryParseChatUtc(updatedRaw);
  if (updatedRaw != null &&
      updatedRaw.toString().trim().isNotEmpty &&
      updatedUtc == null) {
    return null;
  }
  final updatedStr =
      updatedUtc != null ? (updatedRaw as String).trim() : createdAtStr;

  final roleObj = item['role'];
  if (roleObj != null && (roleObj is! String || roleObj.trim().isEmpty)) {
    return null;
  }
  final role = (roleObj as String?)?.trim() ?? 'user';

  final contentObj = item['content'];
  if (contentObj != null && contentObj is! String) return null;
  final content = (contentObj as String?) ?? '';

  final includedInContext = _parseChatSqliteBoolInt(
    item['included_in_context'] ?? item['includedInContext'],
    defaultValue: 1,
  );
  if (includedInContext == null) return null;

  String? optionalJsonOrText(Object? val) {
    if (val == null) return null;
    if (val is String) return val;
    if (val is Map || val is List) {
      try {
        return json.encode(val);
      } catch (_) {
        return null;
      }
    }
    return null;
  }

  final metaRaw = item['meta_json'] ?? item['metaJson'];
  if (metaRaw != null &&
      metaRaw is! String &&
      metaRaw is! Map &&
      metaRaw is! List) {
    return null;
  }
  final deltaRaw = item['delta_json'] ?? item['deltaJson'];
  if (deltaRaw != null &&
      deltaRaw is! String &&
      deltaRaw is! Map &&
      deltaRaw is! List) {
    return null;
  }
  final formatRaw = item['content_format'] ?? item['contentFormat'];
  if (formatRaw != null && formatRaw is! String) return null;

  return <String, Object?>{
    'id': id,
    'session_id': sessionId,
    'role': role,
    'content': content,
    'created_at': createdAtStr,
    'updated_at': updatedStr,
    'included_in_context': includedInContext,
    'meta_json': optionalJsonOrText(metaRaw),
    'content_format': formatRaw as String?,
    'delta_json': optionalJsonOrText(deltaRaw),
  };
}

_ParsedChatTombstone? _sanitizeChatTombstone(Object? item) {
  if (item is! Map) return null;
  final typeObj = item['entity_type'];
  final idObj = item['entity_id'];
  final deletedRaw = item['deleted_at'];
  if (typeObj is! String || idObj is! String || deletedRaw is! String) {
    return null;
  }
  final type = typeObj.trim();
  final id = idObj.trim();
  final deletedStr = deletedRaw.trim();
  if ((type != 'session' && type != 'message') || id.isEmpty) {
    return null;
  }
  final deletedUtc = _tryParseChatUtc(deletedStr);
  if (deletedUtc == null) return null;
  return _ParsedChatTombstone(
    entityType: type,
    entityId: id,
    deletedAtRaw: deletedStr,
    deletedAtUtc: deletedUtc,
  );
}

Map<String, Object?> _exportWhitelistedSession(Map<String, Object?> raw) {
  final row = <String, Object?>{
    for (final col in _chatSessionColumnWhitelist) col: raw[col],
  };
  final updated = row['updated_at']?.toString() ?? '';
  if (updated.isEmpty) {
    final lastActive = row['last_active_at']?.toString() ?? '';
    row['updated_at'] =
        lastActive.isNotEmpty ? lastActive : (row['created_at'] ?? '');
  }
  return row;
}

Map<String, Object?> _exportWhitelistedMessage(Map<String, Object?> raw) {
  final row = <String, Object?>{
    for (final col in _chatMessageColumnWhitelist) col: raw[col],
  };
  final updated = row['updated_at']?.toString() ?? '';
  if (updated.isEmpty) {
    row['updated_at'] = row['created_at'] ?? '';
  }
  return row;
}

extension ChatSessionSyncExtension on ChatSessionService {
  Future<Database> _obtainSyncDatabase() async {
    final db = _database ??
        (_openOwnDatabase
            ? await _ensureDatabase()
            : await _getDatabaseForRead());
    if (db == null) {
      throw StateError('ChatSessionService 数据库未就绪');
    }
    await _ensureChatSchema(db);
    return db;
  }

  /// 分页流式写出 `chat` 同步载荷（不含外层键名 `"chat":`）。
  Future<void> exportChatSectionStreaming(
    IOSink sink, {
    int messagePageSize = 200,
    CancelToken? cancelToken,
  }) async {
    final effectivePageSize = messagePageSize > 0 ? messagePageSize : 200;
    final db = await _obtainSyncDatabase();

    await db.transaction((txn) async {
      cancelToken?.throwIfCancelled();
      final rawSessions = await txn.query(
        'chat_sessions',
        orderBy: 'created_at ASC, id ASC',
      );
      final sessions =
          rawSessions.map(_exportWhitelistedSession).toList(growable: false);

      final rawTombstones = await txn.query(
        'chat_tombstones',
        orderBy: 'entity_type ASC, entity_id ASC',
      );
      final tombstones = rawTombstones
          .map(
            (r) => <String, Object?>{
              'entity_type': r['entity_type'],
              'entity_id': r['entity_id'],
              'deleted_at': r['deleted_at'],
            },
          )
          .toList(growable: false);

      sink.write(
          '{"format":1,"sessions":${json.encode(sessions)},"messages":[');

      var offset = 0;
      var isFirst = true;
      for (;;) {
        cancelToken?.throwIfCancelled();
        final page = await txn.query(
          'chat_messages',
          orderBy: 'created_at ASC, id ASC',
          limit: effectivePageSize,
          offset: offset,
        );
        if (page.isEmpty) break;

        for (final rawMsg in page) {
          if (!isFirst) {
            sink.write(',');
          } else {
            isFirst = false;
          }
          sink.write(json.encode(_exportWhitelistedMessage(rawMsg)));
        }
        offset += page.length;
        if (page.length < effectivePageSize) break;
      }

      sink.write('],"tombstones":${json.encode(tombstones)}}');
    });
  }

  /// 导出内存态 `chat` 段（供测试与轻量调用使用）。
  @visibleForTesting
  Future<Map<String, dynamic>> exportChatSectionForTesting({
    int messagePageSize = 200,
  }) async {
    final tempDir = await Directory.systemTemp.createTemp('chat_export_test_');
    final file = File(path.join(tempDir.path, 'chat.json'));
    try {
      final sink = file.openWrite();
      try {
        await exportChatSectionStreaming(
          sink,
          messagePageSize: messagePageSize,
        );
        await sink.flush();
      } finally {
        await sink.close();
      }
      return json.decode(await file.readAsString()) as Map<String, dynamic>;
    } finally {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    }
  }

  /// 按 LWW + 双向墓碑合并远端 `chat` 段。
  Future<ChatMergeStats> mergeChatSection(
    Map<String, dynamic> chatSection,
  ) async {
    final rawSessions = chatSection['sessions'];
    final rawMessages = chatSection['messages'];
    final rawTombstones = chatSection['tombstones'];

    if (rawSessions != null && rawSessions is! List) {
      throw const FormatException('chat.sessions 格式无效');
    }
    if (rawMessages != null && rawMessages is! List) {
      throw const FormatException('chat.messages 格式无效');
    }
    if (rawTombstones != null && rawTombstones is! List) {
      throw const FormatException('chat.tombstones 格式无效');
    }

    var sessionsAdded = 0;
    var sessionsUpdated = 0;
    var sessionsDeleted = 0;
    var sessionsSkipped = 0;
    var messagesAdded = 0;
    var messagesUpdated = 0;
    var messagesDeleted = 0;
    var messagesSkipped = 0;
    var tombstoneMutated = false;

    final remoteSessionsById = <String, Map<String, Object?>>{};
    if (rawSessions is List) {
      for (final item in rawSessions) {
        final sanitized = _sanitizeSessionRow(item);
        if (sanitized == null) {
          sessionsSkipped++;
          continue;
        }
        final id = sanitized['id'] as String;
        final existing = remoteSessionsById[id];
        if (existing == null ||
            LWWUtils.parseTimestamp(sanitized['updated_at'] as String).isAfter(
              LWWUtils.parseTimestamp(existing['updated_at'] as String),
            )) {
          remoteSessionsById[id] = sanitized;
        } else {
          sessionsSkipped++;
        }
      }
    }

    final remoteMessagesById = <String, Map<String, Object?>>{};
    if (rawMessages is List) {
      for (final item in rawMessages) {
        final sanitized = _sanitizeMessageRow(item);
        if (sanitized == null) {
          messagesSkipped++;
          continue;
        }
        final id = sanitized['id'] as String;
        final existing = remoteMessagesById[id];
        if (existing == null ||
            LWWUtils.parseTimestamp(sanitized['updated_at'] as String).isAfter(
              LWWUtils.parseTimestamp(existing['updated_at'] as String),
            )) {
          remoteMessagesById[id] = sanitized;
        } else {
          messagesSkipped++;
        }
      }
    }

    final remoteSessionTombstones = <String, _ParsedChatTombstone>{};
    final remoteMessageTombstones = <String, _ParsedChatTombstone>{};
    if (rawTombstones is List) {
      for (final item in rawTombstones) {
        final parsed = _sanitizeChatTombstone(item);
        if (parsed == null) {
          if (item is Map && item['entity_type'] == 'message') {
            messagesSkipped++;
          } else {
            sessionsSkipped++;
          }
          continue;
        }
        final target = parsed.entityType == 'session'
            ? remoteSessionTombstones
            : remoteMessageTombstones;
        final existing = target[parsed.entityId];
        if (existing == null ||
            parsed.deletedAtUtc.isAfter(existing.deletedAtUtc)) {
          target[parsed.entityId] = parsed;
        }
      }
    }

    final db = await _obtainSyncDatabase();
    await db.transaction((txn) async {
      // 1. 加载本地会话与墓碑快照
      final localSessionRows = await txn.query('chat_sessions');
      final localSessions = <String, Map<String, Object?>>{
        for (final row in localSessionRows)
          if ((row['id']?.toString() ?? '').isNotEmpty)
            row['id'].toString(): _exportWhitelistedSession(row),
      };

      final localTombstoneRows = await txn.query('chat_tombstones');
      final localSessionTombstones = <String, _ParsedChatTombstone>{};
      final localMessageTombstones = <String, _ParsedChatTombstone>{};
      for (final row in localTombstoneRows) {
        final parsed = _sanitizeChatTombstone(row);
        if (parsed == null) continue;
        if (parsed.entityType == 'session') {
          localSessionTombstones[parsed.entityId] = parsed;
        } else {
          localMessageTombstones[parsed.entityId] = parsed;
        }
      }

      // 2. 先合并会话墓碑与会话数据
      final allSessionIds = <String>{
        ...localSessions.keys,
        ...remoteSessionsById.keys,
        ...remoteSessionTombstones.keys,
      };
      final survivingSessionIds = <String>{...localSessions.keys};

      for (final sessionId in allSessionIds) {
        final localRow = localSessions[sessionId];
        final remoteRow = remoteSessionsById[sessionId];
        final localTomb = localSessionTombstones[sessionId];
        final remoteTomb = remoteSessionTombstones[sessionId];

        _ParsedChatTombstone? effectiveTomb;
        if (localTomb != null && remoteTomb != null) {
          effectiveTomb =
              remoteTomb.deletedAtUtc.isAfter(localTomb.deletedAtUtc)
                  ? remoteTomb
                  : localTomb;
        } else {
          effectiveTomb = remoteTomb ?? localTomb;
        }

        final localUpdated = localRow != null
            ? LWWUtils.parseTimestamp(localRow['updated_at'] as String?)
            : null;
        final remoteUpdated = remoteRow != null
            ? LWWUtils.parseTimestamp(remoteRow['updated_at'] as String?)
            : null;

        DateTime? maxLiveUpdated;
        if (localUpdated != null && remoteUpdated != null) {
          maxLiveUpdated = remoteUpdated.isAfter(localUpdated)
              ? remoteUpdated
              : localUpdated;
        } else {
          maxLiveUpdated = remoteUpdated ?? localUpdated;
        }

        // 墓碑胜出条件：墓碑 deleted_at >= 最新数据行 updated_at（或无数据行）
        if (effectiveTomb != null &&
            (maxLiveUpdated == null ||
                !maxLiveUpdated.isAfter(effectiveTomb.deletedAtUtc))) {
          if (localRow != null) {
            await txn.delete(
              'chat_messages',
              where: 'session_id = ?',
              whereArgs: [sessionId],
            );
            await txn.delete(
              'chat_sessions',
              where: 'id = ?',
              whereArgs: [sessionId],
            );
            survivingSessionIds.remove(sessionId);
            sessionsDeleted++;
          }
          if (remoteRow != null) {
            sessionsSkipped++;
          }
          if (localTomb == null ||
              effectiveTomb.deletedAtUtc.isAfter(localTomb.deletedAtUtc)) {
            await txn.insert(
              'chat_tombstones',
              {
                'entity_type': 'session',
                'entity_id': sessionId,
                'deleted_at': effectiveTomb.deletedAtRaw,
              },
              conflictAlgorithm: ConflictAlgorithm.replace,
            );
            tombstoneMutated = true;
          }
          continue;
        }

        // 数据行胜出：若存在本地旧墓碑，予以清理（允许复活或保留本地新行）
        if (localTomb != null) {
          await txn.delete(
            'chat_tombstones',
            where: 'entity_type = ? AND entity_id = ?',
            whereArgs: ['session', sessionId],
          );
          tombstoneMutated = true;
        }

        if (localRow == null && remoteRow != null) {
          await txn.insert(
            'chat_sessions',
            remoteRow,
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
          survivingSessionIds.add(sessionId);
          sessionsAdded++;
        } else if (localRow != null && remoteRow != null) {
          final localCreatedStr = localRow['created_at'] as String;
          final remoteCreatedStr = remoteRow['created_at'] as String;
          final mergedCreatedAt = LWWUtils.parseTimestamp(remoteCreatedStr)
                  .isBefore(LWWUtils.parseTimestamp(localCreatedStr))
              ? remoteCreatedStr
              : localCreatedStr;

          final localLastActiveStr = localRow['last_active_at'] as String;
          final remoteLastActiveStr = remoteRow['last_active_at'] as String;
          final mergedLastActiveAt =
              LWWUtils.parseTimestamp(remoteLastActiveStr)
                      .isAfter(LWWUtils.parseTimestamp(localLastActiveStr))
                  ? remoteLastActiveStr
                  : localLastActiveStr;

          if (remoteUpdated!.isAfter(localUpdated!)) {
            final updatedRow = <String, Object?>{
              'title': remoteRow['title'],
              'is_pinned': remoteRow['is_pinned'],
              'session_type': remoteRow['session_type'],
              'note_id': remoteRow['note_id'],
              'updated_at': remoteRow['updated_at'],
              'created_at': mergedCreatedAt,
              'last_active_at': mergedLastActiveAt,
            };
            await txn.update(
              'chat_sessions',
              updatedRow,
              where: 'id = ?',
              whereArgs: [sessionId],
            );
            sessionsUpdated++;
          } else if (mergedCreatedAt != localCreatedStr ||
              mergedLastActiveAt != localLastActiveStr) {
            await txn.update(
              'chat_sessions',
              {
                'created_at': mergedCreatedAt,
                'last_active_at': mergedLastActiveAt,
              },
              where: 'id = ?',
              whereArgs: [sessionId],
            );
            sessionsUpdated++;
          } else {
            sessionsSkipped++;
          }
        }
      }

      // 3. 合并消息墓碑与消息数据（仅查询相关消息元数据，避免将大对话正文全量载入内存）
      final candidateMsgIds = <String>{
        ...remoteMessagesById.keys,
        ...remoteMessageTombstones.keys,
      }.toList(growable: false);

      final localMsgUpdatedById = <String, DateTime>{};
      const chunkSize = 500;
      for (var i = 0; i < candidateMsgIds.length; i += chunkSize) {
        final end = (i + chunkSize < candidateMsgIds.length)
            ? i + chunkSize
            : candidateMsgIds.length;
        final chunk = candidateMsgIds.sublist(i, end);
        final placeholders = List.filled(chunk.length, '?').join(',');
        final rows = await txn.query(
          'chat_messages',
          columns: ['id', 'created_at', 'updated_at'],
          where: 'id IN ($placeholders)',
          whereArgs: chunk,
        );
        for (final r in rows) {
          final id = r['id']?.toString() ?? '';
          if (id.isEmpty) continue;
          final updatedRaw = r['updated_at']?.toString() ?? '';
          final effectiveStr = updatedRaw.isNotEmpty
              ? updatedRaw
              : (r['created_at']?.toString() ?? '');
          localMsgUpdatedById[id] = LWWUtils.parseTimestamp(effectiveStr);
        }
      }

      for (final msgId in candidateMsgIds) {
        final localUpdated = localMsgUpdatedById[msgId];
        final remoteRow = remoteMessagesById[msgId];
        final localTomb = localMessageTombstones[msgId];
        final remoteTomb = remoteMessageTombstones[msgId];

        final remoteSessionId = remoteRow?['session_id'] as String?;
        final validRemoteRow =
            (remoteRow != null && survivingSessionIds.contains(remoteSessionId))
                ? remoteRow
                : null;
        final missingParentForRemote =
            remoteRow != null && validRemoteRow == null;

        _ParsedChatTombstone? effectiveTomb;
        if (localTomb != null && remoteTomb != null) {
          effectiveTomb =
              remoteTomb.deletedAtUtc.isAfter(localTomb.deletedAtUtc)
                  ? remoteTomb
                  : localTomb;
        } else {
          effectiveTomb = remoteTomb ?? localTomb;
        }

        final remoteUpdated = validRemoteRow != null
            ? LWWUtils.parseTimestamp(validRemoteRow['updated_at'] as String?)
            : null;

        DateTime? maxLiveUpdated;
        if (localUpdated != null && remoteUpdated != null) {
          maxLiveUpdated = remoteUpdated.isAfter(localUpdated)
              ? remoteUpdated
              : localUpdated;
        } else {
          maxLiveUpdated = remoteUpdated ?? localUpdated;
        }

        if (effectiveTomb != null &&
            (maxLiveUpdated == null ||
                !maxLiveUpdated.isAfter(effectiveTomb.deletedAtUtc))) {
          if (localUpdated != null) {
            await txn.delete(
              'chat_messages',
              where: 'id = ?',
              whereArgs: [msgId],
            );
            messagesDeleted++;
          }
          if (remoteRow != null) {
            messagesSkipped++;
          }
          if (localTomb == null ||
              effectiveTomb.deletedAtUtc.isAfter(localTomb.deletedAtUtc)) {
            await txn.insert(
              'chat_tombstones',
              {
                'entity_type': 'message',
                'entity_id': msgId,
                'deleted_at': effectiveTomb.deletedAtRaw,
              },
              conflictAlgorithm: ConflictAlgorithm.replace,
            );
            tombstoneMutated = true;
          }
          continue;
        }

        if (localTomb != null && maxLiveUpdated != null) {
          await txn.delete(
            'chat_tombstones',
            where: 'entity_type = ? AND entity_id = ?',
            whereArgs: ['message', msgId],
          );
          tombstoneMutated = true;
        }

        if (missingParentForRemote) {
          messagesSkipped++;
          continue;
        }

        if (localUpdated == null && validRemoteRow != null) {
          await txn.insert(
            'chat_messages',
            validRemoteRow,
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
          messagesAdded++;
        } else if (localUpdated != null && validRemoteRow != null) {
          if (remoteUpdated!.isAfter(localUpdated)) {
            await txn.insert(
              'chat_messages',
              validRemoteRow,
              conflictAlgorithm: ConflictAlgorithm.replace,
            );
            messagesUpdated++;
          } else {
            messagesSkipped++;
          }
        }
      }
    });

    final stats = ChatMergeStats(
      sessionsAdded: sessionsAdded,
      sessionsUpdated: sessionsUpdated,
      sessionsDeleted: sessionsDeleted,
      sessionsSkipped: sessionsSkipped,
      messagesAdded: messagesAdded,
      messagesUpdated: messagesUpdated,
      messagesDeleted: messagesDeleted,
      messagesSkipped: messagesSkipped,
    );

    if (stats.hasChanges || tombstoneMutated) {
      _notifySyncListeners();
    }
    return stats;
  }

  /// 覆盖恢复 `chat` 段：当且仅当传入合法 Map 时整库替换；传入 null 时保持本地不动。
  Future<void> restoreChatSection(Map<String, dynamic>? chatSection) async {
    if (chatSection == null) return;

    final rawSessions = chatSection['sessions'];
    final rawMessages = chatSection['messages'];
    final rawTombstones = chatSection['tombstones'];

    if (rawSessions != null && rawSessions is! List) {
      throw const FormatException('chat.sessions 格式无效');
    }
    if (rawMessages != null && rawMessages is! List) {
      throw const FormatException('chat.messages 格式无效');
    }
    if (rawTombstones != null && rawTombstones is! List) {
      throw const FormatException('chat.tombstones 格式无效');
    }

    final sessionsToInsert = <String, Map<String, Object?>>{};
    if (rawSessions is List) {
      for (final item in rawSessions) {
        final sanitized = _sanitizeSessionRow(item);
        if (sanitized != null) {
          sessionsToInsert[sanitized['id'] as String] = sanitized;
        }
      }
    }

    final messagesToInsert = <Map<String, Object?>>[];
    if (rawMessages is List) {
      for (final item in rawMessages) {
        final sanitized = _sanitizeMessageRow(item);
        if (sanitized != null &&
            sessionsToInsert.containsKey(sanitized['session_id'] as String)) {
          messagesToInsert.add(sanitized);
        }
      }
    }

    final tombstonesToInsert = <_ParsedChatTombstone>[];
    if (rawTombstones is List) {
      for (final item in rawTombstones) {
        final parsed = _sanitizeChatTombstone(item);
        if (parsed != null) {
          tombstonesToInsert.add(parsed);
        }
      }
    }

    final db = await _obtainSyncDatabase();
    await db.transaction((txn) async {
      await txn.delete('chat_messages');
      await txn.delete('chat_sessions');
      await txn.delete('chat_tombstones');

      const chunkSize = 500;
      final sessionList = sessionsToInsert.values.toList(growable: false);
      for (var i = 0; i < sessionList.length; i += chunkSize) {
        final end = (i + chunkSize < sessionList.length)
            ? i + chunkSize
            : sessionList.length;
        final batch = txn.batch();
        for (var j = i; j < end; j++) {
          batch.insert(
            'chat_sessions',
            sessionList[j],
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
        await batch.commit(noResult: true);
      }

      for (var i = 0; i < messagesToInsert.length; i += chunkSize) {
        final end = (i + chunkSize < messagesToInsert.length)
            ? i + chunkSize
            : messagesToInsert.length;
        final batch = txn.batch();
        for (var j = i; j < end; j++) {
          batch.insert(
            'chat_messages',
            messagesToInsert[j],
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
        await batch.commit(noResult: true);
      }

      for (var i = 0; i < tombstonesToInsert.length; i += chunkSize) {
        final end = (i + chunkSize < tombstonesToInsert.length)
            ? i + chunkSize
            : tombstonesToInsert.length;
        final batch = txn.batch();
        for (var j = i; j < end; j++) {
          final t = tombstonesToInsert[j];
          batch.insert(
            'chat_tombstones',
            {
              'entity_type': t.entityType,
              'entity_id': t.entityId,
              'deleted_at': t.deletedAtRaw,
            },
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
        await batch.commit(noResult: true);
      }
    });

    _notifySyncListeners();
  }
}
