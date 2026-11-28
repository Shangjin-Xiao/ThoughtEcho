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

@immutable
class ChatMessageShardDescriptor {
  const ChatMessageShardDescriptor({
    required this.file,
    required this.sha256,
    this.localPath,
  });

  final String file;
  final String sha256;
  final String? localPath;

  Map<String, Object?> toJson() => <String, Object?>{
        'file': file,
        'sha256': sha256,
      };
}

const int _maxChatMessageShardCount = 512;
final RegExp _chatShardSha256Pattern = RegExp(r'^[0-9a-f]{64}$');

ChatMessageShardDescriptor _parseAndValidateChatMessageShardDescriptor(
  Object? raw,
) {
  if (raw is! Map) {
    throw const FormatException('chat.message_shards 条目格式无效');
  }
  final fileObj = raw['file'];
  final shaObj = raw['sha256'];
  if (fileObj is! String || shaObj is! String) {
    throw const FormatException('chat.message_shards 缺少合法 file 或 sha256');
  }
  final file = fileObj.trim();
  final sha = shaObj.trim().toLowerCase();
  if (!_chatShardSha256Pattern.hasMatch(sha) || file != 'shard_$sha.zip') {
    throw const FormatException('chat.message_shards 文件名或哈希不匹配');
  }
  return ChatMessageShardDescriptor(file: file, sha256: sha);
}

class _ParsedChatTombstone {
  const _ParsedChatTombstone({
    required this.entityType,
    required this.entityId,
    required this.deletedAtRaw,
    required this.deletedAtUtc,
    this.sessionId,
  });

  final String entityType;
  final String entityId;
  final String deletedAtRaw;
  final DateTime deletedAtUtc;
  final String? sessionId;
}

typedef _ChatSyncVersion = ({DateTime utc, bool hasExplicitZone});

final _ChatSyncVersion _epochChatSyncVersion = (
  utc: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
  hasExplicitZone: false,
);

_ChatSyncVersion _parseChatSyncVersion(Object? primary, [Object? fallback]) {
  return LWWUtils.tryParseSyncVersion(primary) ??
      (fallback != null ? LWWUtils.tryParseSyncVersion(fallback) : null) ??
      _epochChatSyncVersion;
}

DateTime? _tryParseChatUtc(Object? raw) {
  if (raw is! String) return null;
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return null;
  final parsed = DateTime.tryParse(trimmed);
  return parsed?.toUtc();
}

String _normalizeChatTimestampToUtcOrKeep(Object? raw) {
  return LWWUtils.normalizeTimestampPreservingOffsetless(raw);
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
  final rawShards = chatSection['message_shards'];

  if (rawSessions != null && rawSessions is! List) {
    throw const FormatException('chat.sessions 格式无效');
  }
  if (rawMessages != null && rawMessages is! List) {
    throw const FormatException('chat.messages 格式无效');
  }
  if (rawTombstones != null && rawTombstones is! List) {
    throw const FormatException('chat.tombstones 格式无效');
  }
  if (rawShards != null) {
    if (rawShards is! List || rawShards.length > _maxChatMessageShardCount) {
      throw const FormatException('chat.message_shards 格式无效');
    }
    for (final item in rawShards) {
      _parseAndValidateChatMessageShardDescriptor(item);
    }
  }
}

List<ChatMessageShardDescriptor> parseChatMessageShardDescriptors(
  Map<String, dynamic>? chatSection,
) {
  if (chatSection == null) return const <ChatMessageShardDescriptor>[];
  final rawShards = chatSection['message_shards'];
  if (rawShards == null) return const <ChatMessageShardDescriptor>[];
  if (rawShards is! List || rawShards.length > _maxChatMessageShardCount) {
    throw const FormatException('chat.message_shards 格式无效');
  }
  return rawShards
      .map(_parseAndValidateChatMessageShardDescriptor)
      .toList(growable: false);
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

  final lastActiveRaw = item['last_active_at'] ?? item['lastActiveAt'];
  final lastActiveUtc = _tryParseChatUtc(lastActiveRaw);
  if (lastActiveRaw != null &&
      lastActiveRaw.toString().trim().isNotEmpty &&
      lastActiveUtc == null) {
    return null;
  }

  final updatedRaw = item['updated_at'] ?? item['updatedAt'];
  final updatedUtc = _tryParseChatUtc(updatedRaw);
  if (updatedRaw != null &&
      updatedRaw.toString().trim().isNotEmpty &&
      updatedUtc == null) {
    return null;
  }

  final createdAtStr = _normalizeChatTimestampToUtcOrKeep(createdAtRaw);
  final lastActiveStr = lastActiveUtc != null
      ? _normalizeChatTimestampToUtcOrKeep(lastActiveRaw)
      : createdAtStr;
  final updatedStr = updatedUtc != null
      ? _normalizeChatTimestampToUtcOrKeep(updatedRaw)
      : lastActiveStr;

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

  final updatedRaw = item['updated_at'] ?? item['updatedAt'];
  final updatedUtc = _tryParseChatUtc(updatedRaw);
  if (updatedRaw != null &&
      updatedRaw.toString().trim().isNotEmpty &&
      updatedUtc == null) {
    return null;
  }

  final createdAtStr = _normalizeChatTimestampToUtcOrKeep(createdAtRaw);
  final updatedStr = updatedUtc != null
      ? _normalizeChatTimestampToUtcOrKeep(updatedRaw)
      : createdAtStr;

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
  if ((type != 'session' && type != 'message' && type != 'session_cutoff') ||
      id.isEmpty) {
    return null;
  }
  final deletedUtc = _tryParseChatUtc(deletedStr);
  if (deletedUtc == null) return null;
  final rawSessionId = item['session_id'];
  if (rawSessionId != null && rawSessionId is! String) {
    return null;
  }
  final trimmedSessionId = (rawSessionId as String?)?.trim();
  final sessionId = (type == 'message' &&
          trimmedSessionId != null &&
          trimmedSessionId.isNotEmpty)
      ? trimmedSessionId
      : null;
  return _ParsedChatTombstone(
    entityType: type,
    entityId: id,
    deletedAtRaw: _normalizeChatTimestampToUtcOrKeep(deletedStr),
    deletedAtUtc: deletedUtc,
    sessionId: sessionId,
  );
}

Map<String, Object?> _exportWhitelistedSession(Map<String, Object?> raw) {
  final row = <String, Object?>{
    for (final col in _chatSessionColumnWhitelist) col: raw[col],
  };
  final rawUpdated = row['updated_at'];
  final created = _normalizeChatTimestampToUtcOrKeep(row['created_at']);
  row['created_at'] = created;
  final lastActive = _normalizeChatTimestampToUtcOrKeep(row['last_active_at']);
  row['last_active_at'] = lastActive.isNotEmpty ? lastActive : created;
  final updated = _normalizeChatTimestampToUtcOrKeep(rawUpdated);
  row['updated_at'] = updated.isNotEmpty
      ? updated
      : (row['last_active_at'] as String? ?? created);
  return row;
}

Map<String, Object?> _exportWhitelistedMessage(Map<String, Object?> raw) {
  final row = <String, Object?>{
    for (final col in _chatMessageColumnWhitelist) col: raw[col],
  };
  final rawUpdated = row['updated_at'];
  final created = _normalizeChatTimestampToUtcOrKeep(row['created_at']);
  row['created_at'] = created;
  final updated = _normalizeChatTimestampToUtcOrKeep(rawUpdated);
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
    bool includeInlineMessages = true,
    List<ChatMessageShardDescriptor>? messageShards,
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
      final tombstones = rawTombstones.map((r) {
        final rawSid = (r['session_id'] as String?)?.trim();
        return <String, Object?>{
          'entity_type': r['entity_type'],
          'entity_id': r['entity_id'],
          'deleted_at': _normalizeChatTimestampToUtcOrKeep(r['deleted_at']),
          if (r['entity_type'] == 'message' &&
              rawSid != null &&
              rawSid.isNotEmpty)
            'session_id': rawSid,
        };
      }).toList(growable: false);

      sink.write(
          '{"format":1,"sessions":${json.encode(sessions)},"messages":[');

      if (includeInlineMessages) {
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
      }

      sink.write('],"tombstones":${json.encode(tombstones)}');
      if (messageShards != null && messageShards.isNotEmpty) {
        final encodedShards = json.encode(
          messageShards.map((s) => s.toJson()).toList(growable: false),
        );
        sink.write(',"message_shards":$encodedShards');
      }
      sink.write('}');
    });
  }

  /// 将全部 `chat_messages` 按字节预算分页导出为多个本地分片 JSON 文件（每片单独封装合法 JSON 对象）。
  Future<List<File>> exportChatMessageShardJsonFiles(
    Directory outputDir, {
    required int maxShardJsonBytes,
    int messagePageSize = 200,
    CancelToken? cancelToken,
  }) async {
    final effectivePageSize = messagePageSize > 0 ? messagePageSize : 200;
    final effectiveMaxBytes =
        maxShardJsonBytes > 4096 ? maxShardJsonBytes : 4096;
    final db = await _obtainSyncDatabase();
    final shardFiles = <File>[];

    await db.transaction((txn) async {
      var offset = 0;
      var shardIndex = 0;
      IOSink? currentSink;
      var currentBytes = 0;
      var currentHasItem = false;

      Future<void> closeCurrentShard() async {
        final sink = currentSink;
        if (sink == null) return;
        sink.write(']}');
        await sink.flush();
        await sink.close();
        currentSink = null;
        currentBytes = 0;
        currentHasItem = false;
      }

      void openNewShard() {
        if (shardFiles.length >= _maxChatMessageShardCount) {
          throw StateError(
            '对话分片数量超过上限 ($_maxChatMessageShardCount)，已停止导出',
          );
        }
        final file = File(
          path.join(outputDir.path, 'chat_shard_raw_$shardIndex.json'),
        );
        shardIndex++;
        shardFiles.add(file);
        final sink = file.openWrite(encoding: utf8);
        const prefix = '{"format":1,"chat_shard":true,"messages":[';
        sink.write(prefix);
        currentSink = sink;
        currentBytes = prefix.length + 2; // 预留末尾 `]}`
        currentHasItem = false;
      }

      try {
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
            final encodedMsg = json.encode(_exportWhitelistedMessage(rawMsg));
            final msgBytes = utf8.encode(encodedMsg).length;
            final separatorBytes = currentHasItem ? 1 : 0;
            if (currentSink != null &&
                currentHasItem &&
                currentBytes + separatorBytes + msgBytes > effectiveMaxBytes) {
              await closeCurrentShard();
            }
            if (currentSink == null) {
              openNewShard();
            }
            if (currentHasItem) {
              currentSink!.write(',');
              currentBytes += 1;
            }
            currentSink!.write(encodedMsg);
            currentBytes += msgBytes;
            currentHasItem = true;
          }

          offset += page.length;
          if (page.length < effectivePageSize) break;
        }
      } finally {
        await closeCurrentShard();
      }
    });

    return shardFiles;
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

  /// 按 LWW + 双向墓碑合并远端 `chat` 段（可选附带已下载校验的分片消息 JSON 路径列表）。
  Future<ChatMergeStats> mergeChatSection(
    Map<String, dynamic> chatSection, {
    List<String>? chatMessageShardPaths,
  }) async {
    _validateChatSectionContainers(chatSection);
    final expectedShards = parseChatMessageShardDescriptors(chatSection);
    final shardPaths = chatMessageShardPaths ?? const <String>[];
    if (expectedShards.isNotEmpty &&
        shardPaths.length != expectedShards.length) {
      throw const FormatException('chat.message_shards 分片数据不完整');
    }
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
        final candUpdated = _parseChatSyncVersion(sanitized['updated_at']);
        final existUpdated = _parseChatSyncVersion(existing['updated_at']);
        final cmpUpdated = LWWUtils.compareSyncVersions(
          candUpdated,
          existUpdated,
        );
        final existCreatedStr = existing['created_at'] as String;
        final candCreatedStr = sanitized['created_at'] as String;
        final mergedCreatedStr = LWWUtils.compareSyncVersions(
                  _parseChatSyncVersion(candCreatedStr),
                  _parseChatSyncVersion(existCreatedStr),
                ) <
                0
            ? candCreatedStr
            : existCreatedStr;
        final existLastActiveStr = existing['last_active_at'] as String;
        final candLastActiveStr = sanitized['last_active_at'] as String;
        final mergedLastActiveStr = LWWUtils.compareSyncVersions(
                  _parseChatSyncVersion(candLastActiveStr),
                  _parseChatSyncVersion(existLastActiveStr),
                ) >
                0
            ? candLastActiveStr
            : existLastActiveStr;
        if (cmpUpdated > 0 ||
            (cmpUpdated == 0 &&
                _compareChatCanonicalFields(
                      sanitized,
                      existing,
                      _chatSessionTieBreakKeys,
                    ) >
                    0)) {
          sanitized['created_at'] = mergedCreatedStr;
          sanitized['last_active_at'] = mergedLastActiveStr;
          remoteSessionsById[id] = sanitized;
        } else {
          existing['created_at'] = mergedCreatedStr;
          existing['last_active_at'] = mergedLastActiveStr;
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
        final candUpdated = _parseChatSyncVersion(sanitized['updated_at']);
        final existUpdated = _parseChatSyncVersion(existing['updated_at']);
        final cmpUpdated = LWWUtils.compareSyncVersions(
          candUpdated,
          existUpdated,
        );
        if (cmpUpdated > 0 ||
            (cmpUpdated == 0 &&
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
    final remoteSessionCutoffs = <String, _ParsedChatTombstone>{};
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
        final Map<String, _ParsedChatTombstone> target;
        if (parsed.entityType == 'session') {
          target = remoteSessionTombstones;
        } else if (parsed.entityType == 'session_cutoff') {
          target = remoteSessionCutoffs;
        } else {
          target = remoteMessageTombstones;
        }
        final existing = target[parsed.entityId];
        if (existing == null ||
            parsed.deletedAtUtc.isAfter(existing.deletedAtUtc)) {
          final mergedSessionId = parsed.sessionId ?? existing?.sessionId;
          target[parsed.entityId] = mergedSessionId != parsed.sessionId
              ? _ParsedChatTombstone(
                  entityType: parsed.entityType,
                  entityId: parsed.entityId,
                  deletedAtRaw: parsed.deletedAtRaw,
                  deletedAtUtc: parsed.deletedAtUtc,
                  sessionId: mergedSessionId,
                )
              : parsed;
        } else if (existing.sessionId == null && parsed.sessionId != null) {
          target[parsed.entityId] = _ParsedChatTombstone(
            entityType: existing.entityType,
            entityId: existing.entityId,
            deletedAtRaw: existing.deletedAtRaw,
            deletedAtUtc: existing.deletedAtUtc,
            sessionId: parsed.sessionId,
          );
        }
      }
    }

    // 若存在消息分片文件，先按片逐个流式扫描轻量版本摘要（同一时刻内存中只驻留单片），
    // 用于跨分片同 ID 去重与会话复活时间戳预判。
    final winningRemoteMsgSourceById = <String,
        ({String sessionId, _ChatSyncVersion updatedVer, int shardIndex})>{};
    if (shardPaths.isNotEmpty) {
      for (final entry in remoteMessagesById.entries) {
        final row = entry.value;
        winningRemoteMsgSourceById[entry.key] = (
          sessionId: row['session_id'] as String,
          updatedVer: _parseChatSyncVersion(
            row['updated_at'],
            row['created_at'],
          ),
          shardIndex: -1,
        );
      }
      for (var shardIdx = 0; shardIdx < shardPaths.length; shardIdx++) {
        final decodedShard = json.decode(
          await File(shardPaths[shardIdx]).readAsString(),
        );
        if (decodedShard is! Map) {
          throw const FormatException('对话分片内容不是有效 JSON 对象');
        }
        final rawShardMsgs = decodedShard['messages'];
        if (rawShardMsgs is! List) {
          throw const FormatException('对话分片缺少 messages 列表');
        }
        for (final item in rawShardMsgs) {
          final sanitized = _sanitizeMessageRow(item);
          if (sanitized == null) continue;
          final id = sanitized['id'] as String;
          final candVer = _parseChatSyncVersion(
            sanitized['updated_at'],
            sanitized['created_at'],
          );
          final prev = winningRemoteMsgSourceById[id];
          if (prev == null ||
              LWWUtils.compareSyncVersions(candVer, prev.updatedVer) >= 0) {
            if (prev != null && prev.shardIndex == -1) {
              remoteMessagesById.remove(id);
              messagesSkipped++;
            } else if (prev != null) {
              messagesSkipped++;
            }
            winningRemoteMsgSourceById[id] = (
              sessionId: sanitized['session_id'] as String,
              updatedVer: candVer,
              shardIndex: shardIdx,
            );
          } else {
            messagesSkipped++;
          }
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
      final localSessionCutoffs = <String, _ParsedChatTombstone>{};
      final localMessageTombstones = <String, _ParsedChatTombstone>{};
      for (final row in localTombstoneRows) {
        final parsed = _sanitizeChatTombstone(row);
        if (parsed == null) continue;
        if (parsed.entityType == 'session') {
          localSessionTombstones[parsed.entityId] = parsed;
        } else if (parsed.entityType == 'session_cutoff') {
          localSessionCutoffs[parsed.entityId] = parsed;
        } else {
          localMessageTombstones[parsed.entityId] = parsed;
        }
      }

      _ParsedChatTombstone? pickLatestTomb(
        _ParsedChatTombstone? a,
        _ParsedChatTombstone? b,
      ) {
        if (a != null && b != null) {
          final winner = b.deletedAtUtc.isAfter(a.deletedAtUtc) ? b : a;
          final mergedSid = winner.sessionId ?? a.sessionId ?? b.sessionId;
          if (mergedSid != winner.sessionId) {
            return _ParsedChatTombstone(
              entityType: winner.entityType,
              entityId: winner.entityId,
              deletedAtRaw: winner.deletedAtRaw,
              deletedAtUtc: winner.deletedAtUtc,
              sessionId: mergedSid,
            );
          }
          return winner;
        }
        return b ?? a;
      }

      _ParsedChatTombstone? effectiveSessionTombstoneFor(String sId) =>
          pickLatestTomb(
            localSessionTombstones[sId],
            remoteSessionTombstones[sId],
          );

      _ParsedChatTombstone? effectiveSessionCutoffFor(String sId) =>
          pickLatestTomb(
            pickLatestTomb(localSessionCutoffs[sId], remoteSessionCutoffs[sId]),
            effectiveSessionTombstoneFor(sId),
          );

      _ParsedChatTombstone? effectiveMessageTombstoneFor(String msgId) =>
          pickLatestTomb(
            localMessageTombstones[msgId],
            remoteMessageTombstones[msgId],
          );

      // 1b. 对同时存在会话元数据行与会话墓碑/历史删除截止线的候选会话，预先计算其名下仍能通过
      //     消息墓碑与会话截止线双重判定的最新存活消息 updated_at，并缓存本机该会话内的既有消息，
      //     以便在会话因更新回复存活时，同步清除本机与远端所有 <= 会话删除时间的漏网旧消息。
      final allSessionIds = <String>{
        ...localSessions.keys,
        ...remoteSessionsById.keys,
        ...remoteSessionTombstones.keys,
        ...remoteSessionCutoffs.keys,
      };
      final tombstonedCandidateSessionIds = <String>[
        for (final sId in allSessionIds)
          if ((localSessions.containsKey(sId) ||
                  remoteSessionsById.containsKey(sId)) &&
              (localSessionTombstones.containsKey(sId) ||
                  remoteSessionTombstones.containsKey(sId) ||
                  localSessionCutoffs.containsKey(sId) ||
                  remoteSessionCutoffs.containsKey(sId)))
            sId,
      ];

      final maxSurvivingMsgUpdatedBySession = <String, _ChatSyncVersion>{};
      final localMsgsInTombstonedSessions =
          <String, ({String sessionId, _ChatSyncVersion updatedVer})>{};
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
            final msgUpdated = _parseChatSyncVersion(
              r['updated_at'],
              r['created_at'],
            );
            localMsgsInTombstonedSessions[mId] = (
              sessionId: sId,
              updatedVer: msgUpdated,
            );
            final effMsgTomb = effectiveMessageTombstoneFor(mId);
            final effSessCutoff = effectiveSessionCutoffFor(sId);
            if ((effMsgTomb == null ||
                    LWWUtils.syncVersionBeatsDeletion(
                      msgUpdated,
                      effMsgTomb.deletedAtUtc,
                    )) &&
                (effSessCutoff == null ||
                    LWWUtils.syncVersionBeatsDeletion(
                      msgUpdated,
                      effSessCutoff.deletedAtUtc,
                    ))) {
              final prev = maxSurvivingMsgUpdatedBySession[sId];
              if (prev == null ||
                  LWWUtils.compareSyncVersions(msgUpdated, prev) > 0) {
                maxSurvivingMsgUpdatedBySession[sId] = msgUpdated;
              }
            }
          }
        }

        if (winningRemoteMsgSourceById.isNotEmpty) {
          for (final entry in winningRemoteMsgSourceById.entries) {
            final mId = entry.key;
            final sId = entry.value.sessionId;
            if (!candidateSessionSet.contains(sId) ||
                !remoteSessionsById.containsKey(sId)) {
              continue;
            }
            final msgUpdated = entry.value.updatedVer;
            final effMsgTomb = effectiveMessageTombstoneFor(mId);
            final effSessCutoff = effectiveSessionCutoffFor(sId);
            if ((effMsgTomb == null ||
                    LWWUtils.syncVersionBeatsDeletion(
                      msgUpdated,
                      effMsgTomb.deletedAtUtc,
                    )) &&
                (effSessCutoff == null ||
                    LWWUtils.syncVersionBeatsDeletion(
                      msgUpdated,
                      effSessCutoff.deletedAtUtc,
                    ))) {
              final prev = maxSurvivingMsgUpdatedBySession[sId];
              if (prev == null ||
                  LWWUtils.compareSyncVersions(msgUpdated, prev) > 0) {
                maxSurvivingMsgUpdatedBySession[sId] = msgUpdated;
              }
            }
          }
        } else {
          for (final remoteMsg in remoteMessagesById.values) {
            final mId = remoteMsg['id'] as String;
            final sId = remoteMsg['session_id'] as String;
            if (!candidateSessionSet.contains(sId) ||
                !remoteSessionsById.containsKey(sId)) {
              continue;
            }
            final msgUpdated = _parseChatSyncVersion(
              remoteMsg['updated_at'],
              remoteMsg['created_at'],
            );
            final effMsgTomb = effectiveMessageTombstoneFor(mId);
            final effSessCutoff = effectiveSessionCutoffFor(sId);
            if ((effMsgTomb == null ||
                    LWWUtils.syncVersionBeatsDeletion(
                      msgUpdated,
                      effMsgTomb.deletedAtUtc,
                    )) &&
                (effSessCutoff == null ||
                    LWWUtils.syncVersionBeatsDeletion(
                      msgUpdated,
                      effSessCutoff.deletedAtUtc,
                    ))) {
              final prev = maxSurvivingMsgUpdatedBySession[sId];
              if (prev == null ||
                  LWWUtils.compareSyncVersions(msgUpdated, prev) > 0) {
                maxSurvivingMsgUpdatedBySession[sId] = msgUpdated;
              }
            }
          }
        }
      }

      // 2. 先合并会话墓碑与会话数据
      final survivingSessionIds = <String>{...localSessions.keys};
      final effectiveSessionCutoffs = <String, _ParsedChatTombstone>{};

      for (final sessionId in allSessionIds) {
        final localRow = localSessions[sessionId];
        final remoteRow = remoteSessionsById[sessionId];
        final localTomb = localSessionTombstones[sessionId];
        final localCutoff = localSessionCutoffs[sessionId];
        final effectiveTomb = effectiveSessionTombstoneFor(sessionId);
        final effectiveCutoff = effectiveSessionCutoffFor(sessionId);

        final localUpdated = localRow != null
            ? _parseChatSyncVersion(
                localRow['updated_at'],
                localRow['last_active_at'],
              )
            : null;
        final remoteUpdated = remoteRow != null
            ? _parseChatSyncVersion(
                remoteRow['updated_at'],
                remoteRow['last_active_at'],
              )
            : null;

        _ChatSyncVersion? maxLiveUpdated;
        if (localUpdated != null && remoteUpdated != null) {
          maxLiveUpdated =
              LWWUtils.compareSyncVersions(remoteUpdated, localUpdated) > 0
                  ? remoteUpdated
                  : localUpdated;
        } else {
          maxLiveUpdated = remoteUpdated ?? localUpdated;
        }

        // 仅当会话本身在本机或远端存在元数据行（非纯孤儿消息）时，才允许其名下更新的存活消息阻止会话墓碑。
        final maxSurvivingMsgUpdated = (localRow != null || remoteRow != null)
            ? maxSurvivingMsgUpdatedBySession[sessionId]
            : null;
        _ChatSyncVersion? maxLiveActivityUpdated = maxLiveUpdated;
        if (maxSurvivingMsgUpdated != null &&
            (maxLiveActivityUpdated == null ||
                LWWUtils.compareSyncVersions(
                      maxSurvivingMsgUpdated,
                      maxLiveActivityUpdated,
                    ) >
                    0)) {
          maxLiveActivityUpdated = maxSurvivingMsgUpdated;
        }

        // 墓碑胜出条件：显式会话删除墓碑 deleted_at >= 最新活跃版本时间（无偏移历史旧版本绝不跨时区压倒墓碑）
        if (effectiveTomb != null &&
            (maxLiveActivityUpdated == null ||
                !LWWUtils.syncVersionBeatsDeletion(
                  maxLiveActivityUpdated,
                  effectiveTomb.deletedAtUtc,
                ))) {
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
          if (localCutoff != null &&
              !localCutoff.deletedAtUtc.isAfter(effectiveTomb.deletedAtUtc)) {
            await txn.delete(
              'chat_tombstones',
              where: 'entity_type = ? AND entity_id = ?',
              whereArgs: ['session_cutoff', sessionId],
            );
            tombstoneMutated = true;
          }
          continue;
        }

        if (localRow == null && remoteRow == null) {
          if (effectiveCutoff != null &&
              (localCutoff == null ||
                  effectiveCutoff.deletedAtUtc
                      .isAfter(localCutoff.deletedAtUtc))) {
            await txn.insert(
              'chat_tombstones',
              {
                'entity_type': 'session_cutoff',
                'entity_id': sessionId,
                'deleted_at': effectiveCutoff.deletedAtRaw,
              },
              conflictAlgorithm: ConflictAlgorithm.replace,
            );
            tombstoneMutated = true;
          }
          continue;
        }

        // 数据行（或更新的后续消息）胜出：移除整会话删除墓碑以免后续误杀会话，
        // 同时将会话删除时间持久化为 `session_cutoff` 历史消息截止线，确保本端、对端
        // 以及后续同步的三方设备均不会把 <= deleted_at 的漏网旧消息复活。
        if (localTomb != null) {
          await txn.delete(
            'chat_tombstones',
            where: 'entity_type = ? AND entity_id = ?',
            whereArgs: ['session', sessionId],
          );
          tombstoneMutated = true;
        }
        if (effectiveCutoff != null) {
          effectiveSessionCutoffs[sessionId] = effectiveCutoff;
          if (localCutoff == null ||
              effectiveCutoff.deletedAtUtc.isAfter(localCutoff.deletedAtUtc)) {
            await txn.insert(
              'chat_tombstones',
              {
                'entity_type': 'session_cutoff',
                'entity_id': sessionId,
                'deleted_at': effectiveCutoff.deletedAtRaw,
              },
              conflictAlgorithm: ConflictAlgorithm.replace,
            );
            tombstoneMutated = true;
          }
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
          final mergedCreatedAt = LWWUtils.compareSyncVersions(
                    _parseChatSyncVersion(remoteCreatedStr),
                    _parseChatSyncVersion(localCreatedStr),
                  ) <
                  0
              ? remoteCreatedStr
              : localCreatedStr;

          final localLastActiveStr = localRow['last_active_at'] as String;
          final remoteLastActiveStr = remoteRow['last_active_at'] as String;
          final mergedLastActiveAt = LWWUtils.compareSyncVersions(
                    _parseChatSyncVersion(remoteLastActiveStr),
                    _parseChatSyncVersion(localLastActiveStr),
                  ) >
                  0
              ? remoteLastActiveStr
              : localLastActiveStr;

          final cmpMeta = LWWUtils.compareSyncVersions(
            remoteUpdated!,
            localUpdated!,
          );
          final remoteWinsMetadata = cmpMeta > 0 ||
              (cmpMeta == 0 &&
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

      // 3. 合并消息墓碑与消息数据（包含复活会话内的本机既有消息与可选分片文件）
      bool isKilledByMsgOrSessionCutoff(
        _ChatSyncVersion msgUpdated,
        _ParsedChatTombstone? msgTomb,
        _ParsedChatTombstone? sessionCutoff,
      ) {
        if (msgTomb != null &&
            !LWWUtils.syncVersionBeatsDeletion(
              msgUpdated,
              msgTomb.deletedAtUtc,
            )) {
          return true;
        }
        if (sessionCutoff != null &&
            !LWWUtils.syncVersionBeatsDeletion(
              msgUpdated,
              sessionCutoff.deletedAtUtc,
            )) {
          return true;
        }
        return false;
      }

      final sessionsWithAddedOrUpdatedMessages = <String>{};
      final sessionsWithDeletedMessages = <String>{};
      final activeDeletionTimeBySession = <String, DateTime>{};
      final resurrectedMessageIds = <String>{};
      DateTime? maxUnattributedMsgTombUtc;

      void recordSessionDeletionTime(String sessionId, DateTime deletedAtUtc) {
        final prev = activeDeletionTimeBySession[sessionId];
        if (prev == null || deletedAtUtc.isAfter(prev)) {
          activeDeletionTimeBySession[sessionId] = deletedAtUtc;
        }
      }

      Future<void> mergeMessageBatchInTxn(
        Map<String, Map<String, Object?>> batchRemoteMessagesById, {
        required bool includeTombstonesAndResurrectedLocals,
      }) async {
        final candidateMsgIds = <String>{
          ...batchRemoteMessagesById.keys,
          if (includeTombstonesAndResurrectedLocals) ...<String>{
            ...remoteMessageTombstones.keys,
            ...localMsgsInTombstonedSessions.keys,
          },
        }.toList(growable: false);
        if (candidateMsgIds.isEmpty) return;

        final localMsgUpdatedById = <String, _ChatSyncVersion>{};
        final localMsgSessionById = <String, String>{};
        if (includeTombstonesAndResurrectedLocals) {
          for (final entry in localMsgsInTombstonedSessions.entries) {
            if (survivingSessionIds.contains(entry.value.sessionId)) {
              localMsgUpdatedById[entry.key] = entry.value.updatedVer;
              localMsgSessionById[entry.key] = entry.value.sessionId;
            }
          }
        }
        final unqueriedMsgIds = <String>[
          for (final id in candidateMsgIds)
            if (!localMsgUpdatedById.containsKey(id)) id,
        ];
        for (var i = 0; i < unqueriedMsgIds.length; i += chunkSize) {
          final end = (i + chunkSize < unqueriedMsgIds.length)
              ? i + chunkSize
              : unqueriedMsgIds.length;
          final chunk = unqueriedMsgIds.sublist(i, end);
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
            localMsgUpdatedById[id] = _parseChatSyncVersion(
              r['updated_at'],
              r['created_at'],
            );
          }
        }

        // 仅对存活且 updated_at 完全相等的同 ID 消息分小批流式拉取完整行做确定性决胜，
        // 每批比较后立即释放本地消息正文，仅保留远端决胜赢家的 ID 集合，防止重复同步时内存累积。
        final exactTieMsgIds = <String>[];
        for (final msgId in candidateMsgIds) {
          final localUpd = localMsgUpdatedById[msgId];
          final remoteRow = batchRemoteMessagesById[msgId];
          if (localUpd == null || remoteRow == null) continue;
          final remoteSessionId = remoteRow['session_id'] as String?;
          if (!survivingSessionIds.contains(remoteSessionId)) continue;
          final remoteUpd = _parseChatSyncVersion(
            remoteRow['updated_at'],
            remoteRow['created_at'],
          );
          if (LWWUtils.compareSyncVersions(remoteUpd, localUpd) != 0) continue;
          final effTomb = effectiveMessageTombstoneFor(msgId);
          final localSessionId = localMsgSessionById[msgId];
          if (isKilledByMsgOrSessionCutoff(
                localUpd,
                effTomb,
                localSessionId != null
                    ? effectiveSessionCutoffs[localSessionId]
                    : null,
              ) ||
              isKilledByMsgOrSessionCutoff(
                remoteUpd,
                effTomb,
                remoteSessionId != null
                    ? effectiveSessionCutoffs[remoteSessionId]
                    : null,
              )) {
            continue;
          }
          exactTieMsgIds.add(msgId);
        }
        const tieBreakChunkSize = 200;
        final remoteWinsOnTieMsgIds = <String>{};
        for (var i = 0; i < exactTieMsgIds.length; i += tieBreakChunkSize) {
          final end = (i + tieBreakChunkSize < exactTieMsgIds.length)
              ? i + tieBreakChunkSize
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
            if (id.isEmpty) continue;
            final remoteRow = batchRemoteMessagesById[id];
            if (remoteRow != null &&
                _compareChatCanonicalFields(
                      remoteRow,
                      _exportWhitelistedMessage(r),
                      _chatMessageTieBreakKeys,
                    ) >
                    0) {
              remoteWinsOnTieMsgIds.add(id);
            }
          }
        }

        for (final msgId in candidateMsgIds) {
          final localUpdated = localMsgUpdatedById[msgId];
          final localSessionId = localMsgSessionById[msgId];
          final remoteRow = batchRemoteMessagesById[msgId];
          final localTomb = localMessageTombstones[msgId];

          final remoteSessionId = remoteRow?['session_id'] as String?;
          final validRemoteRow = (remoteRow != null &&
                  survivingSessionIds.contains(remoteSessionId))
              ? remoteRow
              : null;
          final missingParentForRemote =
              remoteRow != null && validRemoteRow == null;

          final effectiveTomb = effectiveMessageTombstoneFor(msgId);
          final localSessCutoff = localSessionId != null
              ? effectiveSessionCutoffs[localSessionId]
              : null;
          final remoteSessCutoff = remoteSessionId != null
              ? effectiveSessionCutoffs[remoteSessionId]
              : null;

          final remoteUpdated = validRemoteRow != null
              ? _parseChatSyncVersion(
                  validRemoteRow['updated_at'],
                  validRemoteRow['created_at'],
                )
              : null;

          _ChatSyncVersion? maxLiveUpdated;
          if (localUpdated != null && remoteUpdated != null) {
            maxLiveUpdated =
                LWWUtils.compareSyncVersions(remoteUpdated, localUpdated) > 0
                    ? remoteUpdated
                    : localUpdated;
          } else {
            maxLiveUpdated = remoteUpdated ?? localUpdated;
          }

          final localAlive = localUpdated != null &&
              !isKilledByMsgOrSessionCutoff(
                localUpdated,
                effectiveTomb,
                localSessCutoff,
              );
          final remoteAlive = validRemoteRow != null &&
              remoteUpdated != null &&
              !isKilledByMsgOrSessionCutoff(
                remoteUpdated,
                effectiveTomb,
                remoteSessCutoff,
              );

          if (!localAlive && !remoteAlive) {
            if (localUpdated != null) {
              await txn.delete(
                'chat_messages',
                where: 'id = ?',
                whereArgs: [msgId],
              );
              messagesDeleted++;
              if (localSessionId != null &&
                  survivingSessionIds.contains(localSessionId)) {
                sessionsWithDeletedMessages.add(localSessionId);
              }
            }
            if (remoteRow != null) {
              messagesSkipped++;
              if (remoteSessionId != null &&
                  survivingSessionIds.contains(remoteSessionId)) {
                sessionsWithDeletedMessages.add(remoteSessionId);
              }
            }
            if (effectiveTomb != null &&
                (maxLiveUpdated == null ||
                    !LWWUtils.syncVersionBeatsDeletion(
                      maxLiveUpdated,
                      effectiveTomb.deletedAtUtc,
                    ))) {
              final resolvedSessionId =
                  effectiveTomb.sessionId ?? localSessionId ?? remoteSessionId;
              if (resolvedSessionId != null &&
                  survivingSessionIds.contains(resolvedSessionId)) {
                sessionsWithDeletedMessages.add(resolvedSessionId);
                recordSessionDeletionTime(
                  resolvedSessionId,
                  effectiveTomb.deletedAtUtc,
                );
              }
              if (localTomb == null ||
                  effectiveTomb.deletedAtUtc.isAfter(localTomb.deletedAtUtc) ||
                  (localTomb.sessionId == null && resolvedSessionId != null)) {
                await txn.insert(
                  'chat_tombstones',
                  {
                    'entity_type': 'message',
                    'entity_id': msgId,
                    'deleted_at': effectiveTomb.deletedAtRaw,
                    if (resolvedSessionId != null &&
                        resolvedSessionId.isNotEmpty)
                      'session_id': resolvedSessionId,
                  },
                  conflictAlgorithm: ConflictAlgorithm.replace,
                );
                tombstoneMutated = true;
              }
            } else if (localTomb != null) {
              await txn.delete(
                'chat_tombstones',
                where: 'entity_type = ? AND entity_id = ?',
                whereArgs: ['message', msgId],
              );
              resurrectedMessageIds.add(msgId);
              tombstoneMutated = true;
            }
            continue;
          }

          resurrectedMessageIds.add(msgId);
          if (localTomb != null) {
            await txn.delete(
              'chat_tombstones',
              where: 'entity_type = ? AND entity_id = ?',
              whereArgs: ['message', msgId],
            );
            tombstoneMutated = true;
          }

          if (missingParentForRemote && localAlive) {
            messagesSkipped++;
            continue;
          }

          if (!localAlive && remoteAlive) {
            if (localUpdated == null) {
              await txn.insert(
                'chat_messages',
                validRemoteRow,
                conflictAlgorithm: ConflictAlgorithm.replace,
              );
              messagesAdded++;
            } else {
              await txn.update(
                'chat_messages',
                validRemoteRow,
                where: 'id = ?',
                whereArgs: <Object?>[msgId],
              );
              messagesUpdated++;
            }
            if (remoteSessionId != null) {
              sessionsWithAddedOrUpdatedMessages.add(remoteSessionId);
            }
          } else if (localAlive && !remoteAlive) {
            if (remoteRow != null) {
              messagesSkipped++;
            }
          } else if (localAlive && remoteAlive) {
            final cmpMsg = LWWUtils.compareSyncVersions(
              remoteUpdated,
              localUpdated,
            );
            final remoteWinsOnTie =
                cmpMsg == 0 && remoteWinsOnTieMsgIds.contains(msgId);
            if (cmpMsg > 0 || remoteWinsOnTie) {
              await txn.update(
                'chat_messages',
                validRemoteRow,
                where: 'id = ?',
                whereArgs: <Object?>[msgId],
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
      }

      await mergeMessageBatchInTxn(
        remoteMessagesById,
        includeTombstonesAndResurrectedLocals: true,
      );

      for (var shardIdx = 0; shardIdx < shardPaths.length; shardIdx++) {
        final decodedShard = json.decode(
          await File(shardPaths[shardIdx]).readAsString(),
        ) as Map;
        final rawShardMsgs = decodedShard['messages'] as List;
        final shardBatchById = <String, Map<String, Object?>>{};
        for (final item in rawShardMsgs) {
          final sanitized = _sanitizeMessageRow(item);
          if (sanitized == null) {
            messagesSkipped++;
            continue;
          }
          final id = sanitized['id'] as String;
          final winner = winningRemoteMsgSourceById[id];
          if (winner == null || winner.shardIndex != shardIdx) {
            continue;
          }
          final existing = shardBatchById[id];
          if (existing == null) {
            shardBatchById[id] = sanitized;
            continue;
          }
          final candUpdated = _parseChatSyncVersion(sanitized['updated_at']);
          final existUpdated = _parseChatSyncVersion(existing['updated_at']);
          final cmpUpdated = LWWUtils.compareSyncVersions(
            candUpdated,
            existUpdated,
          );
          if (cmpUpdated > 0 ||
              (cmpUpdated == 0 &&
                  _compareChatCanonicalFields(
                        sanitized,
                        existing,
                        _chatMessageTieBreakKeys,
                      ) >
                      0)) {
            shardBatchById[id] = sanitized;
          }
        }
        await mergeMessageBatchInTxn(
          shardBatchById,
          includeTombstonesAndResurrectedLocals: false,
        );
      }

      // 3b. 将所有生效中的会话截止线与既有消息墓碑纳入校准范围：
      //     防止对端或云端旧快照携带删除前残留的高水位 `last_active_at` 在多轮同步中反复回灌。
      for (final entry in effectiveSessionCutoffs.entries) {
        if (survivingSessionIds.contains(entry.key)) {
          sessionsWithDeletedMessages.add(entry.key);
          recordSessionDeletionTime(entry.key, entry.value.deletedAtUtc);
        }
      }
      final allTombMsgIds = <String>{
        ...localMessageTombstones.keys,
        ...remoteMessageTombstones.keys,
      };
      for (final mId in allTombMsgIds) {
        if (resurrectedMessageIds.contains(mId)) continue;
        final effTomb = effectiveMessageTombstoneFor(mId);
        if (effTomb == null) continue;
        final tSid = effTomb.sessionId;
        if (tSid != null && tSid.isNotEmpty) {
          if (survivingSessionIds.contains(tSid)) {
            sessionsWithDeletedMessages.add(tSid);
            recordSessionDeletionTime(tSid, effTomb.deletedAtUtc);
          }
        } else {
          if (maxUnattributedMsgTombUtc == null ||
              effTomb.deletedAtUtc.isAfter(maxUnattributedMsgTombUtc)) {
            maxUnattributedMsgTombUtc = effTomb.deletedAtUtc;
          }
        }
      }
      if (maxUnattributedMsgTombUtc != null && survivingSessionIds.isNotEmpty) {
        // 兼容旧版未携带 `session_id` 的历史消息墓碑：对 `last_active_at <= maxUnattributedMsgTombUtc`
        // 的存活会话补充校验，防止无归属旧墓碑场景下残留过高活跃时间。
        final survivingList = survivingSessionIds.toList(growable: false);
        for (var i = 0; i < survivingList.length; i += chunkSize) {
          final end = (i + chunkSize < survivingList.length)
              ? i + chunkSize
              : survivingList.length;
          final chunk = survivingList.sublist(i, end);
          final placeholders = List.filled(chunk.length, '?').join(',');
          final rows = await txn.query(
            'chat_sessions',
            columns: const <String>['id', 'created_at', 'last_active_at'],
            where: 'id IN ($placeholders)',
            whereArgs: chunk,
          );
          for (final r in rows) {
            final sId = r['id']?.toString() ?? '';
            if (sId.isEmpty) continue;
            final lastActiveVer = _parseChatSyncVersion(
              r['last_active_at'],
              r['created_at'],
            );
            if (!LWWUtils.syncVersionBeatsDeletion(
              lastActiveVer,
              maxUnattributedMsgTombUtc,
            )) {
              sessionsWithDeletedMessages.add(sId);
            }
          }
        }
      }

      // 4. 对经历消息增删改或携带消息删除墓碑的存活会话重新校准 last_active_at（不触碰会话 updated_at）。
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
            columns: const <String>[
              'id',
              'created_at',
              'last_active_at',
              'updated_at',
            ],
            where: 'id IN ($placeholders)',
            whereArgs: chunk,
          );
          final msgTimeRows = await txn.query(
            'chat_messages',
            columns: const <String>['session_id', 'created_at', 'updated_at'],
            where: 'session_id IN ($placeholders)',
            whereArgs: chunk,
          );
          final maxMsgVerBySession =
              <String, ({_ChatSyncVersion ver, String iso})>{};
          for (final r in msgTimeRows) {
            final sId = r['session_id']?.toString() ?? '';
            if (sId.isEmpty) continue;
            final createdNorm = _normalizeChatTimestampToUtcOrKeep(
              r['created_at'],
            );
            final updatedNorm = _normalizeChatTimestampToUtcOrKeep(
              r['updated_at'],
            );
            final createdVer = LWWUtils.tryParseSyncVersion(createdNorm);
            final updatedVer = LWWUtils.tryParseSyncVersion(updatedNorm);
            ({_ChatSyncVersion ver, String iso})? rowMax;
            if (createdVer != null && updatedVer != null) {
              rowMax = LWWUtils.compareSyncVersions(updatedVer, createdVer) >= 0
                  ? (ver: updatedVer, iso: updatedNorm)
                  : (ver: createdVer, iso: createdNorm);
            } else if (updatedVer != null) {
              rowMax = (ver: updatedVer, iso: updatedNorm);
            } else if (createdVer != null) {
              rowMax = (ver: createdVer, iso: createdNorm);
            }
            if (rowMax != null) {
              final prev = maxMsgVerBySession[sId];
              if (prev == null ||
                  LWWUtils.compareSyncVersions(rowMax.ver, prev.ver) > 0) {
                maxMsgVerBySession[sId] = rowMax;
              }
            }
          }

          final batch = txn.batch();
          var hasCalibrationUpdates = false;
          for (final sRow in sessionRows) {
            final sId = sRow['id']?.toString() ?? '';
            if (sId.isEmpty) continue;
            final createdStr = _normalizeChatTimestampToUtcOrKeep(
              sRow['created_at'],
            );
            final updatedStr = _normalizeChatTimestampToUtcOrKeep(
              sRow['updated_at'],
            );
            final currentLastActiveRaw =
                sRow['last_active_at']?.toString() ?? '';
            final currentLastActiveNorm = _normalizeChatTimestampToUtcOrKeep(
              currentLastActiveRaw,
            );
            final createdVer = _parseChatSyncVersion(createdStr);
            final updatedVer = _parseChatSyncVersion(updatedStr, createdStr);
            final currentLastActiveVer = _parseChatSyncVersion(
              currentLastActiveNorm,
              createdStr,
            );
            final maxMsg = maxMsgVerBySession[sId];

            final String targetIso;
            if (sessionsWithDeletedMessages.contains(sId)) {
              // 若该会话受消息删除或截止线影响，回退至剩余消息最新时间或会话创建时间；
              // 若用户在消息删除之后显式重命名过会话（updated_at > 删除时间），保留该更新水位。
              var floorVer = createdVer;
              var floorIso = createdStr;
              final delUtc =
                  activeDeletionTimeBySession[sId] ?? maxUnattributedMsgTombUtc;
              if (updatedStr.isNotEmpty &&
                  delUtc != null &&
                  LWWUtils.syncVersionBeatsDeletion(updatedVer, delUtc) &&
                  LWWUtils.compareSyncVersions(updatedVer, floorVer) > 0 &&
                  LWWUtils.compareSyncVersions(
                        currentLastActiveVer,
                        updatedVer,
                      ) >=
                      0) {
                floorVer = updatedVer;
                floorIso = updatedStr;
              }
              targetIso = (maxMsg != null &&
                      LWWUtils.compareSyncVersions(maxMsg.ver, floorVer) > 0)
                  ? maxMsg.iso
                  : floorIso;
            } else {
              // 仅新增或更新消息时，确保会话活跃时间不早于最新消息时间。
              targetIso = (maxMsg != null &&
                      LWWUtils.compareSyncVersions(
                            maxMsg.ver,
                            currentLastActiveVer,
                          ) >
                          0)
                  ? maxMsg.iso
                  : (currentLastActiveNorm.isNotEmpty
                      ? currentLastActiveNorm
                      : createdStr);
            }

            if (targetIso.isNotEmpty && targetIso != currentLastActiveRaw) {
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
      await _refreshOffsetlessTimestampFlag(txn);
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
    if (parseChatMessageShardDescriptors(chatSection).isNotEmpty) {
      throw const FormatException('分片对话载荷不支持在缺少分片文件时执行全量覆盖恢复');
    }
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
            final candUpd = _parseChatSyncVersion(sanitized['updated_at']);
            final existUpd = _parseChatSyncVersion(existing['updated_at']);
            final cmpUpd = LWWUtils.compareSyncVersions(candUpd, existUpd);
            if (cmpUpd > 0 ||
                (cmpUpd == 0 &&
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
            final candUpd = _parseChatSyncVersion(sanitized['updated_at']);
            final existUpd = _parseChatSyncVersion(existing['updated_at']);
            final cmpUpd = LWWUtils.compareSyncVersions(candUpd, existUpd);
            if (cmpUpd > 0 ||
                (cmpUpd == 0 &&
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
              if (t.entityType == 'message' &&
                  t.sessionId != null &&
                  t.sessionId!.isNotEmpty)
                'session_id': t.sessionId,
            },
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
        await batch.commit(noResult: true);
      }
      await _refreshOffsetlessTimestampFlag(txn);
    });

    _notifySyncListeners();
  }
}
