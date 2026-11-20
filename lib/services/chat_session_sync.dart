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

String _normalizeChatTimestampToUtcOrKeep(Object? raw) {
  if (raw is! String) return '';
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return '';
  final parsed = DateTime.tryParse(trimmed);
  return parsed != null ? parsed.toUtc().toIso8601String() : trimmed;
}

bool _isValidPositiveFormatVersion(Object? rawFormat) {
  if (rawFormat is int) {
    return rawFormat > 0;
  }
  if (rawFormat is num) {
    return rawFormat.isFinite &&
        rawFormat > 0 &&
        rawFormat == rawFormat.truncateToDouble();
  }
  return false;
}

void _validateChatSectionContainers(Map<String, dynamic> chatSection) {
  final rawFormat = chatSection['format'];
  if (rawFormat != null && !_isValidPositiveFormatVersion(rawFormat)) {
    throw const FormatException('chat.format 格式无效');
  }
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
}

int _compareChatCanonicalFields(
  Map<String, Object?> left,
  Map<String, Object?> right,
  List<String> keys,
) {
  for (final key in keys) {
    final leftVal = left[key];
    final rightVal = right[key];
    if (leftVal == null && rightVal == null) continue;
    if (leftVal == null) return -1;
    if (rightVal == null) return 1;
    final cmp = leftVal.toString().compareTo(rightVal.toString());
    if (cmp != 0) return cmp;
  }
  return 0;
}

const List<String> _chatSessionTieBreakKeys = <String>[
  'title',
  'is_pinned',
  'session_type',
  'note_id',
];

const List<String> _chatMessageTieBreakKeys = <String>[
  'session_id',
  'role',
  'content',
  'created_at',
  'included_in_context',
  'meta_json',
  'content_format',
  'delta_json',
];

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
  final createdAtStr = createdAtUtc.toIso8601String();

  final lastActiveRaw = item['last_active_at'] ?? item['lastActiveAt'];
  final lastActiveUtc = _tryParseChatUtc(lastActiveRaw);
  if (lastActiveRaw != null &&
      lastActiveRaw.toString().trim().isNotEmpty &&
      lastActiveUtc == null) {
    return null;
  }
  final lastActiveStr =
      lastActiveUtc != null ? lastActiveUtc.toIso8601String() : createdAtStr;

  final updatedRaw = item['updated_at'] ?? item['updatedAt'];
  final updatedUtc = _tryParseChatUtc(updatedRaw);
  if (updatedRaw != null &&
      updatedRaw.toString().trim().isNotEmpty &&
      updatedUtc == null) {
    return null;
  }
  final updatedStr =
      updatedUtc != null ? updatedUtc.toIso8601String() : lastActiveStr;

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
  final createdAtStr = createdAtUtc.toIso8601String();

  final updatedRaw = item['updated_at'] ?? item['updatedAt'];
  final updatedUtc = _tryParseChatUtc(updatedRaw);
  if (updatedRaw != null &&
      updatedRaw.toString().trim().isNotEmpty &&
      updatedUtc == null) {
    return null;
  }
  final updatedStr =
      updatedUtc != null ? updatedUtc.toIso8601String() : createdAtStr;

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
    deletedAtRaw: deletedUtc.toIso8601String(),
    deletedAtUtc: deletedUtc,
  );
}

Map<String, Object?> _exportWhitelistedSession(Map<String, Object?> raw) {
  final row = <String, Object?>{
    for (final col in _chatSessionColumnWhitelist) col: raw[col],
  };
  final created = _normalizeChatTimestampToUtcOrKeep(row['created_at']);
  row['created_at'] = created;
  final lastActive = _normalizeChatTimestampToUtcOrKeep(row['last_active_at']);
  row['last_active_at'] = lastActive.isNotEmpty ? lastActive : created;
  final updated = _normalizeChatTimestampToUtcOrKeep(row['updated_at']);
  row['updated_at'] = updated.isNotEmpty
      ? updated
      : (row['last_active_at'] as String? ?? created);
  return row;
}

Map<String, Object?> _exportWhitelistedMessage(Map<String, Object?> raw) {
  final row = <String, Object?>{
    for (final col in _chatMessageColumnWhitelist) col: raw[col],
  };
  final created = _normalizeChatTimestampToUtcOrKeep(row['created_at']);
  row['created_at'] = created;
  final updated = _normalizeChatTimestampToUtcOrKeep(row['updated_at']);
  row['updated_at'] = updated.isNotEmpty ? updated : created;
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
              'deleted_at': _normalizeChatTimestampToUtcOrKeep(r['deleted_at']),
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
    _validateChatSectionContainers(chatSection);
    final rawSessions = chatSection['sessions'];
    final rawMessages = chatSection['messages'];
    final rawTombstones = chatSection['tombstones'];

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
        if (existing == null) {
          remoteSessionsById[id] = sanitized;
          continue;
        }
        final candUpdated =
            LWWUtils.parseTimestamp(sanitized['updated_at'] as String);
        final existUpdated =
            LWWUtils.parseTimestamp(existing['updated_at'] as String);
        if (candUpdated.isAfter(existUpdated) ||
            (candUpdated.isAtSameMomentAs(existUpdated) &&
                _compareChatCanonicalFields(
                      sanitized,
                      existing,
                      _chatSessionTieBreakKeys,
                    ) >
                    0)) {
          final existCreatedStr = existing['created_at'] as String;
          final candCreatedStr = sanitized['created_at'] as String;
          final mergedCreatedStr = LWWUtils.parseTimestamp(candCreatedStr)
                  .isBefore(LWWUtils.parseTimestamp(existCreatedStr))
              ? candCreatedStr
              : existCreatedStr;
          final existLastActiveStr = existing['last_active_at'] as String;
          final candLastActiveStr = sanitized['last_active_at'] as String;
          final mergedLastActiveStr = LWWUtils.parseTimestamp(candLastActiveStr)
                  .isAfter(LWWUtils.parseTimestamp(existLastActiveStr))
              ? candLastActiveStr
              : existLastActiveStr;
          sanitized['created_at'] = mergedCreatedStr;
          sanitized['last_active_at'] = mergedLastActiveStr;
          remoteSessionsById[id] = sanitized;
        } else {
          final existCreatedStr = existing['created_at'] as String;
          final candCreatedStr = sanitized['created_at'] as String;
          if (LWWUtils.parseTimestamp(candCreatedStr)
              .isBefore(LWWUtils.parseTimestamp(existCreatedStr))) {
            existing['created_at'] = candCreatedStr;
          }
          final existLastActiveStr = existing['last_active_at'] as String;
          final candLastActiveStr = sanitized['last_active_at'] as String;
          if (LWWUtils.parseTimestamp(candLastActiveStr)
              .isAfter(LWWUtils.parseTimestamp(existLastActiveStr))) {
            existing['last_active_at'] = candLastActiveStr;
          }
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
        if (existing == null) {
          remoteMessagesById[id] = sanitized;
          continue;
        }
        final candUpdated =
            LWWUtils.parseTimestamp(sanitized['updated_at'] as String);
        final existUpdated =
            LWWUtils.parseTimestamp(existing['updated_at'] as String);
        if (candUpdated.isAfter(existUpdated) ||
            (candUpdated.isAtSameMomentAs(existUpdated) &&
                _compareChatCanonicalFields(
                      sanitized,
                      existing,
                      _chatMessageTieBreakKeys,
                    ) >
                    0)) {
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
      const chunkSize = 500;

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

      _ParsedChatTombstone? effectiveMessageTombstoneFor(String msgId) {
        final localTomb = localMessageTombstones[msgId];
        final remoteTomb = remoteMessageTombstones[msgId];
        if (localTomb != null && remoteTomb != null) {
          return remoteTomb.deletedAtUtc.isAfter(localTomb.deletedAtUtc)
              ? remoteTomb
              : localTomb;
        }
        return remoteTomb ?? localTomb;
      }

      // 1b. 对同时存在会话元数据行与会话墓碑的候选会话，预先计算其名下仍能通过消息墓碑判定的
      //     最新存活消息 updated_at：由于 addMessage 不推进 chat_sessions.updated_at，
      //     若离线设备在会话墓碑之后新增/修订了存活消息，必须保护该会话不被会话墓碑误杀。
      final allSessionIds = <String>{
        ...localSessions.keys,
        ...remoteSessionsById.keys,
        ...remoteSessionTombstones.keys,
      };
      final tombstonedCandidateSessionIds = <String>[
        for (final sId in allSessionIds)
          if ((localSessions.containsKey(sId) ||
                  remoteSessionsById.containsKey(sId)) &&
              (localSessionTombstones.containsKey(sId) ||
                  remoteSessionTombstones.containsKey(sId)))
            sId,
      ];

      final maxSurvivingMsgUpdatedBySession = <String, DateTime>{};
      if (tombstonedCandidateSessionIds.isNotEmpty) {
        final candidateSessionSet = tombstonedCandidateSessionIds.toSet();
        for (var i = 0;
            i < tombstonedCandidateSessionIds.length;
            i += chunkSize) {
          final end = (i + chunkSize < tombstonedCandidateSessionIds.length)
              ? i + chunkSize
              : tombstonedCandidateSessionIds.length;
          final chunk = tombstonedCandidateSessionIds.sublist(i, end);
          final placeholders = List.filled(chunk.length, '?').join(',');
          final localMsgRows = await txn.query(
            'chat_messages',
            columns: const <String>[
              'id',
              'session_id',
              'created_at',
              'updated_at',
            ],
            where: 'session_id IN ($placeholders)',
            whereArgs: chunk,
          );
          for (final r in localMsgRows) {
            final mId = r['id']?.toString() ?? '';
            final sId = r['session_id']?.toString() ?? '';
            if (mId.isEmpty || sId.isEmpty || !localSessions.containsKey(sId)) {
              continue;
            }
            final updatedRaw = r['updated_at']?.toString() ?? '';
            final effectiveStr = updatedRaw.isNotEmpty
                ? updatedRaw
                : (r['created_at']?.toString() ?? '');
            final msgUpdated = LWWUtils.parseTimestamp(effectiveStr);
            final effMsgTomb = effectiveMessageTombstoneFor(mId);
            if (effMsgTomb == null ||
                msgUpdated.isAfter(effMsgTomb.deletedAtUtc)) {
              final prev = maxSurvivingMsgUpdatedBySession[sId];
              if (prev == null || msgUpdated.isAfter(prev)) {
                maxSurvivingMsgUpdatedBySession[sId] = msgUpdated;
              }
            }
          }
        }

        for (final remoteMsg in remoteMessagesById.values) {
          final mId = remoteMsg['id'] as String;
          final sId = remoteMsg['session_id'] as String;
          if (!candidateSessionSet.contains(sId) ||
              !remoteSessionsById.containsKey(sId)) {
            continue;
          }
          final msgUpdated =
              LWWUtils.parseTimestamp(remoteMsg['updated_at'] as String?);
          final effMsgTomb = effectiveMessageTombstoneFor(mId);
          if (effMsgTomb == null ||
              msgUpdated.isAfter(effMsgTomb.deletedAtUtc)) {
            final prev = maxSurvivingMsgUpdatedBySession[sId];
            if (prev == null || msgUpdated.isAfter(prev)) {
              maxSurvivingMsgUpdatedBySession[sId] = msgUpdated;
            }
          }
        }
      }

      // 2. 先合并会话墓碑与会话数据
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

        // 仅当会话本身在本机或远端存在元数据行（非纯孤儿消息）时，才允许其名下更新的存活消息阻止会话墓碑。
        final maxSurvivingMsgUpdated = (localRow != null || remoteRow != null)
            ? maxSurvivingMsgUpdatedBySession[sessionId]
            : null;
        DateTime? maxLiveActivityUpdated = maxLiveUpdated;
        if (maxSurvivingMsgUpdated != null &&
            (maxLiveActivityUpdated == null ||
                maxSurvivingMsgUpdated.isAfter(maxLiveActivityUpdated))) {
          maxLiveActivityUpdated = maxSurvivingMsgUpdated;
        }

        // 墓碑胜出条件：墓碑 deleted_at >= 最新活跃版本时间（或无数据行）
        if (effectiveTomb != null &&
            (maxLiveActivityUpdated == null ||
                !maxLiveActivityUpdated.isAfter(effectiveTomb.deletedAtUtc))) {
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

          final remoteWinsMetadata = remoteUpdated!.isAfter(localUpdated!) ||
              (remoteUpdated.isAtSameMomentAs(localUpdated) &&
                  _compareChatCanonicalFields(
                        remoteRow,
                        localRow,
                        _chatSessionTieBreakKeys,
                      ) >
                      0);

          if (remoteWinsMetadata) {
            final updatedRow = <String, Object?>{
              'title': remoteRow['title'],
              'is_pinned': remoteRow['is_pinned'],
              'session_type': remoteRow['session_type'],
              'note_id': remoteRow['note_id'],
              'updated_at': remoteRow['updated_at'],
              'created_at': mergedCreatedAt,
              'last_active_at': mergedLastActiveAt,
            };
            final hasAnyDiff = updatedRow.entries.any(
              (entry) => localRow[entry.key] != entry.value,
            );
            if (hasAnyDiff) {
              await txn.update(
                'chat_sessions',
                updatedRow,
                where: 'id = ?',
                whereArgs: [sessionId],
              );
              sessionsUpdated++;
            } else {
              sessionsSkipped++;
            }
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
      final localMsgSessionById = <String, String>{};
      for (var i = 0; i < candidateMsgIds.length; i += chunkSize) {
        final end = (i + chunkSize < candidateMsgIds.length)
            ? i + chunkSize
            : candidateMsgIds.length;
        final chunk = candidateMsgIds.sublist(i, end);
        final placeholders = List.filled(chunk.length, '?').join(',');
        final rows = await txn.query(
          'chat_messages',
          columns: const <String>[
            'id',
            'session_id',
            'created_at',
            'updated_at',
          ],
          where: 'id IN ($placeholders)',
          whereArgs: chunk,
        );
        for (final r in rows) {
          final id = r['id']?.toString() ?? '';
          if (id.isEmpty) continue;
          final sId = r['session_id']?.toString() ?? '';
          if (sId.isNotEmpty) {
            localMsgSessionById[id] = sId;
          }
          final updatedRaw = r['updated_at']?.toString() ?? '';
          final effectiveStr = updatedRaw.isNotEmpty
              ? updatedRaw
              : (r['created_at']?.toString() ?? '');
          localMsgUpdatedById[id] = LWWUtils.parseTimestamp(effectiveStr);
        }
      }

      // 仅对 updated_at 完全相等的极少数同 ID 消息批量拉取完整行用于确定性决胜。
      final exactTieMsgIds = <String>[];
      for (final msgId in candidateMsgIds) {
        final localUpd = localMsgUpdatedById[msgId];
        final remoteRow = remoteMessagesById[msgId];
        if (localUpd == null || remoteRow == null) continue;
        final remoteSessionId = remoteRow['session_id'] as String?;
        if (!survivingSessionIds.contains(remoteSessionId)) continue;
        final remoteUpd =
            LWWUtils.parseTimestamp(remoteRow['updated_at'] as String?);
        if (remoteUpd.isAtSameMomentAs(localUpd)) {
          exactTieMsgIds.add(msgId);
        }
      }
      final localTiedMsgsById = <String, Map<String, Object?>>{};
      for (var i = 0; i < exactTieMsgIds.length; i += chunkSize) {
        final end = (i + chunkSize < exactTieMsgIds.length)
            ? i + chunkSize
            : exactTieMsgIds.length;
        final chunk = exactTieMsgIds.sublist(i, end);
        final placeholders = List.filled(chunk.length, '?').join(',');
        final rows = await txn.query(
          'chat_messages',
          where: 'id IN ($placeholders)',
          whereArgs: chunk,
        );
        for (final r in rows) {
          final id = r['id']?.toString() ?? '';
          if (id.isNotEmpty) {
            localTiedMsgsById[id] = _exportWhitelistedMessage(r);
          }
        }
      }

      final sessionsWithAddedOrUpdatedMessages = <String>{};
      final sessionsWithDeletedMessages = <String>{};

      for (final msgId in candidateMsgIds) {
        final localUpdated = localMsgUpdatedById[msgId];
        final remoteRow = remoteMessagesById[msgId];
        final localTomb = localMessageTombstones[msgId];

        final remoteSessionId = remoteRow?['session_id'] as String?;
        final validRemoteRow =
            (remoteRow != null && survivingSessionIds.contains(remoteSessionId))
                ? remoteRow
                : null;
        final missingParentForRemote =
            remoteRow != null && validRemoteRow == null;

        final effectiveTomb = effectiveMessageTombstoneFor(msgId);

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
            final localSessionId = localMsgSessionById[msgId];
            if (localSessionId != null &&
                survivingSessionIds.contains(localSessionId)) {
              sessionsWithDeletedMessages.add(localSessionId);
            }
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
          if (remoteSessionId != null) {
            sessionsWithAddedOrUpdatedMessages.add(remoteSessionId);
          }
        } else if (localUpdated != null && validRemoteRow != null) {
          final localTiedRow = localTiedMsgsById[msgId];
          final remoteWinsOnTie = remoteUpdated!.isAtSameMomentAs(
                localUpdated,
              ) &&
              localTiedRow != null &&
              _compareChatCanonicalFields(
                    validRemoteRow,
                    localTiedRow,
                    _chatMessageTieBreakKeys,
                  ) >
                  0;
          if (remoteUpdated.isAfter(localUpdated) || remoteWinsOnTie) {
            await txn.insert(
              'chat_messages',
              validRemoteRow,
              conflictAlgorithm: ConflictAlgorithm.replace,
            );
            messagesUpdated++;
            if (remoteSessionId != null) {
              sessionsWithAddedOrUpdatedMessages.add(remoteSessionId);
            }
          } else {
            messagesSkipped++;
          }
        }
      }

      // 4. 对经历消息增删改的存活会话重新校准 last_active_at（不触碰会话 updated_at）。
      final sessionsToCalibrate = survivingSessionIds.intersection(<String>{
        ...sessionsWithAddedOrUpdatedMessages,
        ...sessionsWithDeletedMessages,
      }).toList(growable: false);
      if (sessionsToCalibrate.isNotEmpty) {
        for (var i = 0; i < sessionsToCalibrate.length; i += chunkSize) {
          final end = (i + chunkSize < sessionsToCalibrate.length)
              ? i + chunkSize
              : sessionsToCalibrate.length;
          final chunk = sessionsToCalibrate.sublist(i, end);
          final placeholders = List.filled(chunk.length, '?').join(',');

          final sessionRows = await txn.query(
            'chat_sessions',
            columns: const <String>['id', 'created_at', 'last_active_at'],
            where: 'id IN ($placeholders)',
            whereArgs: chunk,
          );
          final maxMsgRows = await txn.rawQuery(
            'SELECT session_id, MAX(created_at) AS max_created, '
            'MAX(updated_at) AS max_updated '
            'FROM chat_messages '
            'WHERE session_id IN ($placeholders) '
            'GROUP BY session_id',
            chunk,
          );
          final maxMsgUtcBySession = <String, DateTime>{};
          for (final r in maxMsgRows) {
            final sId = r['session_id']?.toString() ?? '';
            if (sId.isEmpty) continue;
            final maxCreated = _tryParseChatUtc(r['max_created']);
            final maxUpdated = _tryParseChatUtc(r['max_updated']);
            DateTime? maxUtc;
            if (maxCreated != null && maxUpdated != null) {
              maxUtc = maxUpdated.isAfter(maxCreated) ? maxUpdated : maxCreated;
            } else {
              maxUtc = maxUpdated ?? maxCreated;
            }
            if (maxUtc != null) {
              maxMsgUtcBySession[sId] = maxUtc;
            }
          }

          final batch = txn.batch();
          var hasCalibrationUpdates = false;
          for (final sRow in sessionRows) {
            final sId = sRow['id']?.toString() ?? '';
            if (sId.isEmpty) continue;
            final createdStr = sRow['created_at']?.toString() ?? '';
            final currentLastActiveStr =
                sRow['last_active_at']?.toString() ?? '';
            final createdUtc = LWWUtils.parseTimestamp(createdStr);
            final currentLastActiveUtc =
                LWWUtils.parseTimestamp(currentLastActiveStr);
            final maxMsgUtc = maxMsgUtcBySession[sId];

            final DateTime targetUtc;
            if (sessionsWithDeletedMessages.contains(sId)) {
              // 若删除了本地消息（如删除了最新一条消息），则回退至剩余消息最新时间或会话创建时间。
              targetUtc = (maxMsgUtc != null && maxMsgUtc.isAfter(createdUtc))
                  ? maxMsgUtc
                  : createdUtc;
            } else {
              // 仅新增或更新消息时，确保会话活跃时间不早于最新消息时间。
              targetUtc =
                  (maxMsgUtc != null && maxMsgUtc.isAfter(currentLastActiveUtc))
                      ? maxMsgUtc
                      : currentLastActiveUtc;
            }

            final targetIso = targetUtc.toIso8601String();
            if (targetIso != currentLastActiveStr) {
              batch.update(
                'chat_sessions',
                <String, Object?>{'last_active_at': targetIso},
                where: 'id = ?',
                whereArgs: <Object?>[sId],
              );
              hasCalibrationUpdates = true;
            }
          }
          if (hasCalibrationUpdates) {
            await batch.commit(noResult: true);
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

    _validateChatSectionContainers(chatSection);
    final rawSessions = chatSection['sessions'];
    final rawMessages = chatSection['messages'];
    final rawTombstones = chatSection['tombstones'];

    final sessionsToInsert = <String, Map<String, Object?>>{};
    if (rawSessions is List) {
      for (final item in rawSessions) {
        final sanitized = _sanitizeSessionRow(item);
        if (sanitized != null) {
          final id = sanitized['id'] as String;
          final existing = sessionsToInsert[id];
          if (existing == null) {
            sessionsToInsert[id] = sanitized;
          } else {
            final candUpd =
                LWWUtils.parseTimestamp(sanitized['updated_at'] as String);
            final existUpd =
                LWWUtils.parseTimestamp(existing['updated_at'] as String);
            if (candUpd.isAfter(existUpd) ||
                (candUpd.isAtSameMomentAs(existUpd) &&
                    _compareChatCanonicalFields(
                          sanitized,
                          existing,
                          _chatSessionTieBreakKeys,
                        ) >
                        0)) {
              sessionsToInsert[id] = sanitized;
            }
          }
        }
      }
    }

    final messagesToInsertById = <String, Map<String, Object?>>{};
    if (rawMessages is List) {
      for (final item in rawMessages) {
        final sanitized = _sanitizeMessageRow(item);
        if (sanitized != null &&
            sessionsToInsert.containsKey(sanitized['session_id'] as String)) {
          final id = sanitized['id'] as String;
          final existing = messagesToInsertById[id];
          if (existing == null) {
            messagesToInsertById[id] = sanitized;
          } else {
            final candUpd =
                LWWUtils.parseTimestamp(sanitized['updated_at'] as String);
            final existUpd =
                LWWUtils.parseTimestamp(existing['updated_at'] as String);
            if (candUpd.isAfter(existUpd) ||
                (candUpd.isAtSameMomentAs(existUpd) &&
                    _compareChatCanonicalFields(
                          sanitized,
                          existing,
                          _chatMessageTieBreakKeys,
                        ) >
                        0)) {
              messagesToInsertById[id] = sanitized;
            }
          }
        }
      }
    }
    final messagesToInsert =
        messagesToInsertById.values.toList(growable: false);

    final tombstonesByKey = <String, _ParsedChatTombstone>{};
    if (rawTombstones is List) {
      for (final item in rawTombstones) {
        final parsed = _sanitizeChatTombstone(item);
        if (parsed != null) {
          final key = '${parsed.entityType}:${parsed.entityId}';
          final existing = tombstonesByKey[key];
          if (existing == null ||
              parsed.deletedAtUtc.isAfter(existing.deletedAtUtc)) {
            tombstonesByKey[key] = parsed;
          }
        }
      }
    }
    final tombstonesToInsert = tombstonesByKey.values.toList(growable: false);

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
