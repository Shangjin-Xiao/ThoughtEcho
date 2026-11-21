part of 'agent_memory_service.dart';

/// 判定某轮 Dreaming 记录的 `(basisWatermark, basisNoteCount)` 在合并后的本地主库上是否“看全了”。
typedef AgentMemoryBasisChecker = Future<bool> Function(
  String? basisWatermark,
  int? basisNoteCount,
);

/// 批量判定多组 Dreaming `(basisWatermark, basisNoteCount)` 在合并后的本地主库上是否“看全了”。
typedef AgentMemoryBatchBasisChecker = Future<Map<(String, int), bool>>
    Function(Set<(String, int)> basisPairs);

const List<String> _memoryProfileColumnWhitelist = <String>[
  'id',
  'kind',
  'directive',
  'observed_at',
  'updated_at',
  'status',
  'superseded_by',
  'replaces_id',
  'source',
  'source_note_ids',
  'basis_watermark',
  'basis_note_count',
];

const List<String> _memoryFactColumnWhitelist = <String>[
  'id',
  'category',
  'content',
  'importance',
  'trigger_phrases',
  'created_at',
  'updated_at',
  'last_recalled_at',
  'recall_count',
  'source_ref',
];

const List<String> _memorySliceColumnWhitelist = <String>[
  'id',
  'content',
  'observed_at',
  'expires_at',
  'source_note_ids',
];

const List<String> _memoryProfileTieBreakKeys = <String>[
  'kind',
  'directive',
  'observed_at',
  'replaces_id',
  'source',
  'source_note_ids',
  'basis_watermark',
  'basis_note_count',
];

const List<String> _memoryFactTieBreakKeys = <String>[
  'category',
  'content',
  'importance',
  'trigger_phrases',
  'created_at',
  'source_ref',
];

const List<String> _memorySliceTieBreakKeys = <String>[
  'expires_at',
  'content',
  'source_note_ids',
];

final Set<String> _validMemoryKinds =
    AgentMemoryKind.values.map((k) => k.storageValue).toSet();

@immutable
class MemoryMergeStats {
  const MemoryMergeStats({
    this.profilesAdded = 0,
    this.profilesUpdated = 0,
    this.profilesDeleted = 0,
    this.factsAdded = 0,
    this.factsUpdated = 0,
    this.factsDeleted = 0,
    this.slicesAdded = 0,
    this.slicesUpdated = 0,
    this.slicesDeleted = 0,
    this.skippedCount = 0,
    this.skippedBecauseDisabled = false,
  });

  final int profilesAdded;
  final int profilesUpdated;
  final int profilesDeleted;
  final int factsAdded;
  final int factsUpdated;
  final int factsDeleted;
  final int slicesAdded;
  final int slicesUpdated;
  final int slicesDeleted;
  final int skippedCount;
  final bool skippedBecauseDisabled;

  int get totalAdded => profilesAdded + factsAdded + slicesAdded;
  int get totalUpdated => profilesUpdated + factsUpdated + slicesUpdated;
  int get totalDeleted => profilesDeleted + factsDeleted + slicesDeleted;

  bool get hasChanges => totalAdded > 0 || totalUpdated > 0 || totalDeleted > 0;
}

class _ParsedMemoryTombstone {
  const _ParsedMemoryTombstone({
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

typedef _MemorySyncVersion = ({DateTime utc, bool hasExplicitZone});

final _MemorySyncVersion _epochMemorySyncVersion = (
  utc: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
  hasExplicitZone: false,
);

_MemorySyncVersion _parseMemoryRowSyncVersion(
  Object? primary,
  Object? fallback,
) {
  return LWWUtils.tryParseSyncVersion(primary) ??
      (fallback != null ? LWWUtils.tryParseSyncVersion(fallback) : null) ??
      _epochMemorySyncVersion;
}

DateTime? _tryParseMemoryUtc(Object? raw) {
  if (raw is! String) return null;
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return null;
  return DateTime.tryParse(trimmed)?.toUtc();
}

DateTime _parseMemoryRowVersionUtc(Object? primary, Object? fallback) {
  return _tryParseMemoryUtc(primary) ??
      (fallback != null ? _tryParseMemoryUtc(fallback) : null) ??
      DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
}

String _normalizeMemoryTimestampToUtcOrKeep(Object? raw) {
  return LWWUtils.normalizeTimestampPreservingOffsetless(raw);
}

bool _isValidMemoryFormatVersion(Object? rawFormat) {
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

void _validateMemorySectionContainers(Map<dynamic, dynamic> rawSection) {
  final rawFormat = rawSection['format'];
  if (rawFormat != null && !_isValidMemoryFormatVersion(rawFormat)) {
    throw const FormatException('Invalid agent_memory.format');
  }
  final rawProfiles = rawSection['profile'];
  if (rawProfiles != null && rawProfiles is! List) {
    throw const FormatException('Invalid agent_memory.profile container');
  }
  final rawFacts = rawSection['facts'];
  if (rawFacts != null && rawFacts is! List) {
    throw const FormatException('Invalid agent_memory.facts container');
  }
  final rawSlices = rawSection['recent_slices'];
  if (rawSlices != null && rawSlices is! List) {
    throw const FormatException('Invalid agent_memory.recent_slices container');
  }
  final rawTombstones = rawSection['tombstones'];
  if (rawTombstones != null && rawTombstones is! List) {
    throw const FormatException('Invalid agent_memory.tombstones container');
  }
  final rawDreaming = rawSection['dreaming'];
  if (rawDreaming != null && rawDreaming is! Map) {
    throw const FormatException('Invalid agent_memory.dreaming container');
  }
  final rawClearedAt = rawSection['cleared_at'];
  if (rawClearedAt != null) {
    if (rawClearedAt is! String) {
      throw const FormatException('Invalid agent_memory.cleared_at');
    }
    final trimmedCleared = rawClearedAt.trim();
    if (trimmedCleared.isNotEmpty &&
        _tryParseMemoryUtc(trimmedCleared) == null) {
      throw const FormatException('Invalid agent_memory.cleared_at');
    }
  }
}

int _compareMemoryCanonicalFields(
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

int _compareMemorySliceOnSameObservedAt(
  Map<String, Object?> left,
  Map<String, Object?> right,
) {
  final leftExp = _tryParseMemoryUtc(left['expires_at']);
  final rightExp = _tryParseMemoryUtc(right['expires_at']);
  if (leftExp != null && rightExp != null) {
    final expCmp = leftExp.compareTo(rightExp);
    if (expCmp != 0) return expCmp;
  }
  return _compareMemoryCanonicalFields(left, right, _memorySliceTieBreakKeys);
}

int? _parseMemoryOptionalInt(Object? raw) {
  if (raw == null) return null;
  if (raw is int) return raw;
  if (raw is num) return raw.toInt();
  if (raw is String && raw.trim().isNotEmpty) {
    return int.tryParse(raw.trim());
  }
  return null;
}

bool _isDreamingMemorySource(Object? rawSource) {
  if (rawSource is! String) return false;
  return rawSource.trim().startsWith('dreaming');
}

String? _sanitizeEncodedNoteIds(
  Object? raw, {
  required bool rejectInvalidType,
}) {
  if (raw == null) return null;
  if (raw is List) {
    final clean = raw
        .whereType<String>()
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList(growable: false);
    return clean.isEmpty ? null : jsonEncode(clean);
  }
  if (raw is String) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;
    try {
      final decoded = jsonDecode(trimmed);
      if (decoded is! List) return rejectInvalidType ? '' : null;
      final clean = decoded
          .whereType<String>()
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList(growable: false);
      return clean.isEmpty ? null : jsonEncode(clean);
    } catch (_) {
      return rejectInvalidType ? '' : null;
    }
  }
  return rejectInvalidType ? '' : null;
}

Map<String, Object?>? _sanitizeMemoryProfileRow(Object? item) {
  if (item is! Map) return null;
  final idObj = item['id'];
  if (idObj is! String || idObj.trim().isEmpty) return null;
  final id = idObj.trim();

  final kindObj = item['kind'];
  if (kindObj is! String) return null;
  final kind = kindObj.trim();
  if (!_validMemoryKinds.contains(kind)) return null;

  final directiveObj = item['directive'];
  if (directiveObj is! String) return null;
  final directive = AgentMemoryService.normalizeMemoryText(
    directiveObj,
    AgentMemoryService.directiveMaxChars,
  );
  if (directive.isEmpty) return null;

  final observedRaw = item['observed_at'];
  final observedUtc = _tryParseMemoryUtc(observedRaw);
  if (observedUtc == null) return null;

  final updatedRaw = item['updated_at'];
  final updatedUtc = _tryParseMemoryUtc(updatedRaw);
  if (updatedRaw != null &&
      updatedRaw.toString().trim().isNotEmpty &&
      updatedUtc == null) {
    return null;
  }
  final observedStr = _normalizeMemoryTimestampToUtcOrKeep(observedRaw);
  final updatedStr = (updatedRaw is String &&
          updatedRaw.trim().isNotEmpty &&
          updatedUtc != null)
      ? _normalizeMemoryTimestampToUtcOrKeep(updatedRaw)
      : observedStr;

  final statusObj = item['status'];
  var status = AgentMemoryStatus.active.storageValue;
  if (statusObj != null) {
    if (statusObj is! String) return null;
    final trimmed = statusObj.trim();
    if (trimmed == AgentMemoryStatus.active.storageValue ||
        trimmed == AgentMemoryStatus.superseded.storageValue) {
      status = trimmed;
    } else {
      return null;
    }
  }

  String? optionalCleanStr(Object? v, {required bool allowAny}) {
    if (v == null) return null;
    if (v is! String) return allowAny ? null : '\u0000';
    final t = v.trim();
    return t.isEmpty ? null : t;
  }

  final supersededBy = optionalCleanStr(item['superseded_by'], allowAny: false);
  if (supersededBy == '\u0000') return null;

  var replacesId = optionalCleanStr(item['replaces_id'], allowAny: false);
  if (replacesId == '\u0000') return null;
  if (replacesId == id) {
    replacesId = null;
  }

  final source = optionalCleanStr(item['source'], allowAny: false);
  if (source == '\u0000') return null;

  final encodedNoteIds =
      _sanitizeEncodedNoteIds(item['source_note_ids'], rejectInvalidType: true);
  if (encodedNoteIds == '') return null;

  final rawBasisWm = item['basis_watermark'];
  String? basisWatermark;
  if (rawBasisWm != null) {
    if (rawBasisWm is! String) return null;
    final trimmedWm = rawBasisWm.trim();
    if (trimmedWm.isNotEmpty) {
      final parsedWm = _tryParseMemoryUtc(trimmedWm);
      if (parsedWm == null) return null;
      basisWatermark = parsedWm.toIso8601String();
    }
  }

  final rawBasisCount = item['basis_note_count'];
  int? basisNoteCount;
  if (rawBasisCount != null) {
    final parsedCount = _parseMemoryOptionalInt(rawBasisCount);
    if (parsedCount == null || parsedCount < 0) return null;
    basisNoteCount = parsedCount;
  }

  return <String, Object?>{
    'id': id,
    'kind': kind,
    'directive': directive,
    'observed_at': observedStr,
    'updated_at': updatedStr,
    'status': status,
    'superseded_by': supersededBy,
    'replaces_id': replacesId,
    'source': source,
    'source_note_ids': encodedNoteIds,
    'basis_watermark': basisWatermark,
    'basis_note_count': basisNoteCount,
  };
}

Map<String, Object?>? _sanitizeMemoryFactRow(Object? item) {
  if (item is! Map) return null;
  final idObj = item['id'];
  if (idObj is! String || idObj.trim().isEmpty) return null;
  final id = idObj.trim();

  final contentObj = item['content'];
  if (contentObj is! String) return null;
  final content = AgentMemoryService.normalizeMemoryText(
    contentObj,
    AgentMemoryService.factMaxChars,
  );
  if (content.isEmpty) return null;

  final createdRaw = item['created_at'];
  final createdUtc = _tryParseMemoryUtc(createdRaw);
  if (createdUtc == null) return null;

  final updatedRaw = item['updated_at'];
  final updatedUtc = _tryParseMemoryUtc(updatedRaw);
  if (updatedRaw != null &&
      updatedRaw.toString().trim().isNotEmpty &&
      updatedUtc == null) {
    return null;
  }
  final createdStr = _normalizeMemoryTimestampToUtcOrKeep(createdRaw);
  final updatedStr = (updatedRaw is String &&
          updatedRaw.trim().isNotEmpty &&
          updatedUtc != null)
      ? _normalizeMemoryTimestampToUtcOrKeep(updatedRaw)
      : createdStr;

  final categoryObj = item['category'];
  if (categoryObj != null && categoryObj is! String) return null;
  final categoryTrimmed = (categoryObj as String?)?.trim() ?? '';
  final category = categoryTrimmed.isEmpty ? null : categoryTrimmed;

  final rawImportance = item['importance'];
  int importance = 5;
  if (rawImportance != null) {
    final parsedImp = _parseMemoryOptionalInt(rawImportance);
    if (parsedImp == null) return null;
    importance = parsedImp.clamp(
      AgentMemoryFact.minImportance,
      AgentMemoryFact.maxImportance,
    );
  }

  final rawPhrases = item['trigger_phrases'];
  String? triggerPhrases;
  if (rawPhrases != null) {
    List<String> parts;
    if (rawPhrases is String) {
      parts = rawPhrases.split('\n');
    } else if (rawPhrases is List) {
      if (rawPhrases.any((e) => e != null && e is! String)) return null;
      parts = rawPhrases.whereType<String>().toList();
    } else {
      return null;
    }
    final normalized = parts
        .map((p) => p
            .replaceAll(AgentMemoryService._whitespaceCollapseRegex, ' ')
            .trim())
        .where((p) => p.isNotEmpty)
        .take(8)
        .toList(growable: false);
    triggerPhrases = normalized.isEmpty ? null : normalized.join('\n');
  }

  final recalledRaw = item['last_recalled_at'];
  String? lastRecalledAt;
  if (recalledRaw != null) {
    if (recalledRaw is! String) return null;
    final trimmedRecalled = recalledRaw.trim();
    if (trimmedRecalled.isNotEmpty) {
      final parsedRecalled = _tryParseMemoryUtc(trimmedRecalled);
      if (parsedRecalled == null) return null;
      lastRecalledAt = _normalizeMemoryTimestampToUtcOrKeep(trimmedRecalled);
    }
  }

  final rawRecallCount = item['recall_count'];
  int recallCount = 0;
  if (rawRecallCount != null) {
    final parsedCount = _parseMemoryOptionalInt(rawRecallCount);
    if (parsedCount == null || parsedCount < 0) return null;
    recallCount = parsedCount;
  }

  final sourceRefObj = item['source_ref'];
  if (sourceRefObj != null && sourceRefObj is! String) return null;
  final sourceRefTrimmed = (sourceRefObj as String?)?.trim() ?? '';
  final sourceRef = sourceRefTrimmed.isEmpty ? null : sourceRefTrimmed;

  return <String, Object?>{
    'id': id,
    'category': category,
    'content': content,
    'importance': importance,
    'trigger_phrases': triggerPhrases,
    'created_at': createdStr,
    'updated_at': updatedStr,
    'last_recalled_at': lastRecalledAt,
    'recall_count': recallCount,
    'source_ref': sourceRef,
  };
}

Map<String, Object?>? _sanitizeMemorySliceRow(Object? item) {
  if (item is! Map) return null;
  final idObj = item['id'];
  if (idObj is! String || idObj.trim().isEmpty) return null;
  final id = idObj.trim();

  final contentObj = item['content'];
  if (contentObj is! String) return null;
  final content = AgentMemoryService.normalizeMemoryText(
    contentObj,
    AgentMemoryRecentSlice.maxChars,
  );
  if (content.isEmpty) return null;

  final observedRaw = item['observed_at'];
  final observedUtc = _tryParseMemoryUtc(observedRaw);
  if (observedUtc == null) return null;
  final observedStr = _normalizeMemoryTimestampToUtcOrKeep(observedRaw);

  final expiresRaw = item['expires_at'];
  final expiresUtc = _tryParseMemoryUtc(expiresRaw);
  if (expiresUtc == null) return null;
  final expiresStr = _normalizeMemoryTimestampToUtcOrKeep(expiresRaw);

  final encodedNoteIds =
      _sanitizeEncodedNoteIds(item['source_note_ids'], rejectInvalidType: true);
  if (encodedNoteIds == '') return null;

  return <String, Object?>{
    'id': id,
    'content': content,
    'observed_at': observedStr,
    'expires_at': expiresStr,
    'source_note_ids': encodedNoteIds,
  };
}

_ParsedMemoryTombstone? _sanitizeMemoryTombstone(Object? item) {
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
  if ((type != 'profile' && type != 'fact' && type != 'slice') || id.isEmpty) {
    return null;
  }
  final deletedUtc = _tryParseMemoryUtc(deletedStr);
  if (deletedUtc == null) return null;
  return _ParsedMemoryTombstone(
    entityType: type,
    entityId: id,
    deletedAtRaw: _normalizeMemoryTimestampToUtcOrKeep(deletedStr),
    deletedAtUtc: deletedUtc,
  );
}

Map<String, Object?> _exportWhitelistedProfile(Map<String, Object?> raw) {
  final row = <String, Object?>{
    for (final col in _memoryProfileColumnWhitelist) col: raw[col],
  };
  final observed = _normalizeMemoryTimestampToUtcOrKeep(row['observed_at']);
  row['observed_at'] = observed;
  final updated = _normalizeMemoryTimestampToUtcOrKeep(row['updated_at']);
  row['updated_at'] = updated.isNotEmpty ? updated : observed;
  return row;
}

Map<String, Object?> _exportWhitelistedFact(Map<String, Object?> raw) {
  final row = <String, Object?>{
    for (final col in _memoryFactColumnWhitelist) col: raw[col],
  };
  final created = _normalizeMemoryTimestampToUtcOrKeep(row['created_at']);
  row['created_at'] = created;
  final updated = _normalizeMemoryTimestampToUtcOrKeep(row['updated_at']);
  row['updated_at'] = updated.isNotEmpty ? updated : created;
  final recalledRaw = row['last_recalled_at'];
  if (recalledRaw is String && recalledRaw.trim().isNotEmpty) {
    row['last_recalled_at'] = _normalizeMemoryTimestampToUtcOrKeep(recalledRaw);
  }
  return row;
}

Map<String, Object?> _exportWhitelistedSlice(Map<String, Object?> raw) {
  final row = <String, Object?>{
    for (final col in _memorySliceColumnWhitelist) col: raw[col],
  };
  row['observed_at'] = _normalizeMemoryTimestampToUtcOrKeep(row['observed_at']);
  row['expires_at'] = _normalizeMemoryTimestampToUtcOrKeep(row['expires_at']);
  return row;
}

String? _pickLatestTimestampStr(Object? leftRaw, Object? rightRaw) {
  final leftVer = LWWUtils.tryParseSyncVersion(leftRaw);
  final rightVer = LWWUtils.tryParseSyncVersion(rightRaw);
  if (leftVer == null && rightVer == null) return null;
  if (leftVer == null) return _normalizeMemoryTimestampToUtcOrKeep(rightRaw);
  if (rightVer == null) return _normalizeMemoryTimestampToUtcOrKeep(leftRaw);
  return LWWUtils.compareSyncVersions(rightVer, leftVer) > 0
      ? _normalizeMemoryTimestampToUtcOrKeep(rightRaw)
      : _normalizeMemoryTimestampToUtcOrKeep(leftRaw);
}

int _compareProfileRowsByWinnerRule(
  Map<String, Object?> left,
  Map<String, Object?> right, {
  bool Function(String? watermark, int? noteCount)? isBasisCovered,
}) {
  final leftDream = _isDreamingMemorySource(left['source']);
  final rightDream = _isDreamingMemorySource(right['source']);
  if (leftDream != rightDream) {
    // 非 dreaming*（用户/对话主动写入）优先于 dreaming*。
    return leftDream ? 1 : -1;
  }

  if (leftDream && rightDream && isBasisCovered != null) {
    final leftCovered = isBasisCovered(
      left['basis_watermark'] as String?,
      _parseMemoryOptionalInt(left['basis_note_count']),
    );
    final rightCovered = isBasisCovered(
      right['basis_watermark'] as String?,
      _parseMemoryOptionalInt(right['basis_note_count']),
    );
    if (leftCovered != rightCovered) {
      return leftCovered ? -1 : 1;
    }
  }

  final leftTime = _parseMemoryRowSyncVersion(
    left['updated_at'],
    left['observed_at'],
  );
  final rightTime = _parseMemoryRowSyncVersion(
    right['updated_at'],
    right['observed_at'],
  );
  final timeCmp = LWWUtils.compareSyncVersions(rightTime, leftTime);
  if (timeCmp != 0) {
    return timeCmp;
  }

  final leftId = (left['id'] as String?) ?? '';
  final rightId = (right['id'] as String?) ?? '';
  return leftId.compareTo(rightId);
}

final Set<String> _singletonMemoryKinds = <String>{
  AgentMemoryKind.taste.storageValue,
  AgentMemoryKind.voice.storageValue,
  AgentMemoryKind.style.storageValue,
};

/// 判定在 `Y.replaces_id == X.id` 的显式替换边中，前驱 `X` 是否反而应当胜出并淘汰 `Y`：
/// 1. 非 `dreaming*` 显式/人工画像绝不被后台 `dreaming*` 取代；
/// 2. 同为 `dreaming*` 且挂载了依据判定器时，看全全部笔记依据的前驱 `X` 优先于漏看离线笔记的 `Y`；
/// 3. 其余情况下，仅当 `X` 在 `Y` 创建后又发生了原位编辑（`X` 版本时间严格晚于 `Y`）时 `X` 胜出。
bool _predecessorWinsReplacementEdge(
  Map<String, Object?> xRow,
  Map<String, Object?> yRow, {
  bool Function(String? watermark, int? noteCount)? isBasisCovered,
}) {
  final xDream = _isDreamingMemorySource(xRow['source']);
  final yDream = _isDreamingMemorySource(yRow['source']);
  if (!xDream && yDream) {
    return true;
  }
  if (xDream && yDream && isBasisCovered != null) {
    final xCovered = isBasisCovered(
      xRow['basis_watermark'] as String?,
      _parseMemoryOptionalInt(xRow['basis_note_count']),
    );
    final yCovered = isBasisCovered(
      yRow['basis_watermark'] as String?,
      _parseMemoryOptionalInt(yRow['basis_note_count']),
    );
    if (xCovered != yCovered) {
      return xCovered;
    }
  }
  final xTime = _parseMemoryRowSyncVersion(
    xRow['updated_at'],
    xRow['observed_at'],
  );
  final yTime = _parseMemoryRowSyncVersion(
    yRow['updated_at'],
    yRow['observed_at'],
  );
  return LWWUtils.compareSyncVersions(xTime, yTime) > 0;
}

/// 判定一条处于 `superseded` 状态的条目在沿 `superseded_by` 链到达某条 `active` 终点条目时，
/// 二者是否仍然处于同一个有效竞争槽位（从而允许纳入同步重算）。
///
/// 若某条重复画像 `P1` 曾因“同 `kind + directive` 去重”指向 `P2`，随后用户通过
/// `editProfileDirective(P2)` 将 `P2` 原位改成新指令，此时 `P2` 胜过旧 `P1` 且二者既无 `replaces_id`
/// 血缘、又非单例类别、正文也不再重复——`P1` 必须保持 `superseded` 退休状态，绝不能借重算复活；
/// 反之，若同步并发期间用户恰恰编辑了刚被去重退休的 `P1`（使 `P1` 按赢家规则严格胜过 `P2`），
/// 则必须将 `P1` 纳入重算以恢复人工纠正并淘汰旧终点 `P2`。
bool _doSupersededChainAndActiveTerminalStillCompete(
  List<Map<String, Object?>> chainToActiveTerminal, {
  bool Function(String? watermark, int? noteCount)? isBasisCovered,
}) {
  if (chainToActiveTerminal.length < 2) {
    return true;
  }
  final startRow = chainToActiveTerminal.first;
  final terminalRow = chainToActiveTerminal.last;
  final startId = (startRow['id'] as String?)?.trim() ?? '';
  final terminalId = (terminalRow['id'] as String?)?.trim() ?? '';

  // (a) 链上任意相邻跳或首尾之间存在显式 replaces_id 替换关系
  for (var i = 0; i < chainToActiveTerminal.length - 1; i++) {
    final prev = chainToActiveTerminal[i];
    final next = chainToActiveTerminal[i + 1];
    final prevId = (prev['id'] as String?)?.trim() ?? '';
    final nextId = (next['id'] as String?)?.trim() ?? '';
    final prevRep = (prev['replaces_id'] as String?)?.trim() ?? '';
    final nextRep = (next['replaces_id'] as String?)?.trim() ?? '';
    if ((nextRep.isNotEmpty && nextRep == prevId) ||
        (prevRep.isNotEmpty && prevRep == nextId)) {
      return true;
    }
  }
  final startRep = (startRow['replaces_id'] as String?)?.trim() ?? '';
  final terminalRep = (terminalRow['replaces_id'] as String?)?.trim() ?? '';
  if ((terminalRep.isNotEmpty && terminalRep == startId) ||
      (startRep.isNotEmpty && startRep == terminalId)) {
    return true;
  }

  // (b) 共享非空 replaces_id 分叉祖先
  if (startRep.isNotEmpty && startRep == terminalRep) {
    return true;
  }

  // (c) 同属单活跃类别（taste / voice / style）
  final startKind = (startRow['kind'] as String?)?.trim() ?? '';
  final terminalKind = (terminalRow['kind'] as String?)?.trim() ?? '';
  if (_singletonMemoryKinds.contains(startKind) && startKind == terminalKind) {
    return true;
  }

  // (d) 仍为同 kind + directive 重复项，或同为 identity 且别名集合重叠
  final startDirective = (startRow['directive'] as String?)?.trim() ?? '';
  final terminalDirective = (terminalRow['directive'] as String?)?.trim() ?? '';
  if (startKind == terminalKind &&
      startDirective.isNotEmpty &&
      startDirective == terminalDirective) {
    return true;
  }
  if (startKind == AgentMemoryKind.identity.storageValue &&
      terminalKind == AgentMemoryKind.identity.storageValue) {
    final startAliases = AgentMemoryService.extractAliasesFromDirective(
      startDirective,
      includeUnconfirmed: true,
    ).map((a) => a.toLowerCase()).toSet();
    if (startAliases.isNotEmpty) {
      final terminalAliases = AgentMemoryService.extractAliasesFromDirective(
        terminalDirective,
        includeUnconfirmed: true,
      ).map((a) => a.toLowerCase());
      if (terminalAliases.any(startAliases.contains)) {
        return true;
      }
    }
  }

  // (e) 起点条目在被去重退休后又发生了更新的人工修正或具备严格更高的赢家优先级，
  //     必须允许纳入收敛重算以反超取代旧活跃终点；若编辑发生在赢家终点上（terminal 胜过 start），
  //     此处比较 >= 0，旧起点维持退休不复活。
  if (_compareProfileRowsByWinnerRule(
        startRow,
        terminalRow,
        isBasisCovered: isBasisCovered,
      ) <
      0) {
    return true;
  }

  return false;
}

/// 基于全量有效候选集执行确定性画像收敛重算。
///
/// 关键不变量：
/// 1. 收敛仅修改 `status` 与 `superseded_by` 派生状态，绝不改写任何条目的 `updated_at`；
/// 2. 凡 `status == 'active'`，或 `status == 'superseded'` 且沿 `superseded_by` 链仍指向当前
///    `profileTable` 中处于同一有效竞争槽位的条目（含互指环）均纳入重算；若后继已被 `forgetProfile`
///    墓碑删除、已超期物理清理、或原位编辑后已脱离原去重槽位，绝不纳入重算、绝不复活；
/// 3. 显式 `replaces_id` 链、同 `replaces_id` 分叉、单例类别与身份别名/重复指令统一确定性选出唯一赢家，
///    若最终赢家此前处于 `superseded` 则原位恢复为 `active`。
Future<
    ({
      int supersededCount,
      bool didMutate,
      bool bothUncoveredDreamingConflict,
    })> _convergeProfilesInTxn(
  DatabaseExecutor txn, {
  bool Function(String? watermark, int? noteCount)? isBasisCovered,
  bool includeSupersededCandidates = true,
}) async {
  final allRows = await txn.query(AgentMemoryService.profileTable);
  if (allRows.isEmpty) {
    return (
      supersededCount: 0,
      didMutate: false,
      bothUncoveredDreamingConflict: false,
    );
  }

  final allRowsById = <String, Map<String, Object?>>{
    for (final row in allRows)
      if (row['id'] is String && (row['id'] as String).isNotEmpty)
        row['id'] as String: Map<String, Object?>.of(row),
  };

  var preRetiredCount = 0;
  var preMutated = false;

  // 若某条后继 Y（声明了 replaces_id = X）自身的后继链终点已被墓碑删除（如 X -> Y -> Z 且 Z 被 forgetProfile），
  // 即便发送端早已压缩裁剪掉旧 X、而接收端本地 X 仍标为 active，只要 Z 的墓碑不早于 X 且 X 未胜过 Y，
  // 必须先将 X 退休指向 Y，防止多跳替换后删除最新条目时旧祖先在另一端残留 active。
  if (includeSupersededCandidates) {
    final profileTombRows = await txn.query(
      AgentMemoryService.tombstonesTable,
      columns: const <String>['entity_id', 'deleted_at'],
      where: 'entity_type = ?',
      whereArgs: const <Object?>['profile'],
    );
    final profileTombstones = <String, DateTime>{};
    for (final r in profileTombRows) {
      final id = r['entity_id'] as String?;
      final delUtc = _tryParseMemoryUtc(r['deleted_at']);
      if (id != null && id.isNotEmpty && delUtc != null) {
        profileTombstones[id] = delUtc;
      }
    }

    if (profileTombstones.isNotEmpty) {
      DateTime? resolveChainTombstoneUtc(Map<String, Object?> row) {
        final status = (row['status'] as String?)?.trim();
        var currId = (row['superseded_by'] as String?)?.trim() ?? '';
        if (status != AgentMemoryStatus.superseded.storageValue ||
            currId.isEmpty) {
          return null;
        }
        final startId = (row['id'] as String?)?.trim() ?? '';
        final visited = <String>{if (startId.isNotEmpty) startId};
        while (currId.isNotEmpty && visited.add(currId)) {
          final nextRow = allRowsById[currId];
          final tombUtc = profileTombstones[currId];
          if (tombUtc != null) {
            final aliveAfterTomb = nextRow != null &&
                LWWUtils.syncVersionBeatsDeletion(
                  _parseMemoryRowSyncVersion(
                    nextRow['updated_at'],
                    nextRow['observed_at'],
                  ),
                  tombUtc,
                );
            if (!aliveAfterTomb) {
              return tombUtc;
            }
          }
          if (nextRow == null) {
            return null;
          }
          final nextStatus = (nextRow['status'] as String?)?.trim();
          if (nextStatus != AgentMemoryStatus.superseded.storageValue) {
            return null;
          }
          currId = (nextRow['superseded_by'] as String?)?.trim() ?? '';
        }
        return null;
      }

      var progressed = true;
      while (progressed) {
        progressed = false;
        for (final yRow in allRowsById.values) {
          final yId = yRow['id'] as String;
          final xId = (yRow['replaces_id'] as String?)?.trim() ?? '';
          if (xId.isEmpty || xId == yId) continue;
          final xRow = allRowsById[xId];
          if (xRow == null) continue;
          final xStatus = (xRow['status'] as String?)?.trim() ??
              AgentMemoryStatus.active.storageValue;
          if (xStatus != AgentMemoryStatus.active.storageValue) continue;
          final tombUtc = resolveChainTombstoneUtc(yRow);
          if (tombUtc == null) continue;
          final xVer = _parseMemoryRowSyncVersion(
            xRow['updated_at'],
            xRow['observed_at'],
          );
          if (LWWUtils.syncVersionBeatsDeletion(xVer, tombUtc)) continue;
          if (_predecessorWinsReplacementEdge(
            xRow,
            yRow,
            isBasisCovered: isBasisCovered,
          )) {
            continue;
          }
          await txn.update(
            AgentMemoryService.profileTable,
            <String, Object?>{
              'status': AgentMemoryStatus.superseded.storageValue,
              'superseded_by': yId,
            },
            where: 'id = ?',
            whereArgs: <Object?>[xId],
          );
          xRow['status'] = AgentMemoryStatus.superseded.storageValue;
          xRow['superseded_by'] = yId;
          preRetiredCount++;
          preMutated = true;
          progressed = true;
        }
      }
    }
  }

  bool isEligibleCandidate(String startId) {
    if (!includeSupersededCandidates) {
      final row = allRowsById[startId];
      if (row == null) {
        return false;
      }
      final status = (row['status'] as String?)?.trim() ??
          AgentMemoryStatus.active.storageValue;
      if (status == AgentMemoryStatus.active.storageValue) {
        return true;
      }
      // 本地压缩绝不复活同步淘汰的 dreaming* 历史行，也不复活被用户新指令替换的旧行；
      // 仅当非 dreaming* 人工/显式画像被后台 dreaming* 条目置为 superseded 且链尾仍是同类别活跃
      // dreaming* 条目时，将其纳入重算以自愈恢复人工修正。
      if (status != AgentMemoryStatus.superseded.storageValue ||
          _isDreamingMemorySource(row['source'])) {
        return false;
      }
      final startKind = (row['kind'] as String?)?.trim() ?? '';
      var currId = (row['superseded_by'] as String?)?.trim() ?? '';
      final visited = <String>{startId};
      while (currId.isNotEmpty && visited.add(currId)) {
        final nextRow = allRowsById[currId];
        if (nextRow == null) {
          return false;
        }
        if (((nextRow['kind'] as String?)?.trim() ?? '') != startKind ||
            !_isDreamingMemorySource(nextRow['source'])) {
          return false;
        }
        final nextStatus = (nextRow['status'] as String?)?.trim() ??
            AgentMemoryStatus.active.storageValue;
        if (nextStatus == AgentMemoryStatus.active.storageValue) {
          return true;
        }
        if (nextStatus != AgentMemoryStatus.superseded.storageValue) {
          return false;
        }
        currId = (nextRow['superseded_by'] as String?)?.trim() ?? '';
      }
      return false;
    }
    var currId = startId;
    final visited = <String>{};
    final chain = <Map<String, Object?>>[];
    for (;;) {
      final row = allRowsById[currId];
      if (row == null) {
        return false;
      }
      chain.add(row);
      final status = (row['status'] as String?)?.trim() ??
          AgentMemoryStatus.active.storageValue;
      if (status == AgentMemoryStatus.active.storageValue) {
        return _doSupersededChainAndActiveTerminalStillCompete(
          chain,
          isBasisCovered: isBasisCovered,
        );
      }
      if (status != AgentMemoryStatus.superseded.storageValue) {
        return false;
      }
      final nextId = (row['superseded_by'] as String?)?.trim() ?? '';
      if (nextId.isEmpty) {
        return false;
      }
      if (!visited.add(currId)) {
        // 环中所有节点均存在于 profileTable（例如多端离线互相淘汰），必须纳入重算以打破死锁。
        return true;
      }
      currId = nextId;
    }
  }

  final eligibleRows = <Map<String, Object?>>[
    for (final entry in allRowsById.entries)
      if (isEligibleCandidate(entry.key)) entry.value,
  ];
  if (eligibleRows.isEmpty) {
    return (
      supersededCount: preRetiredCount,
      didMutate: preMutated,
      bothUncoveredDreamingConflict: false,
    );
  }

  final sorted = List<Map<String, Object?>>.of(eligibleRows)
    ..sort(
      (a, b) => _compareProfileRowsByWinnerRule(
        a,
        b,
        isBasisCovered: isBasisCovered,
      ),
    );

  final eligibleById = <String, Map<String, Object?>>{
    for (final row in sorted) row['id'] as String: row,
  };
  final supersededToWinner = <String, Map<String, Object?>>{};

  Map<String, Object?> resolveRootWinner(Map<String, Object?> startRow) {
    var curr = startRow;
    final visited = <String>{};
    for (;;) {
      final currId = curr['id'] as String;
      if (!visited.add(currId)) {
        return curr;
      }
      final nextWinner = supersededToWinner[currId];
      if (nextWinner == null) {
        return curr;
      }
      curr = nextWinner;
    }
  }

  void recordSupersede(String loserId, Map<String, Object?> proposedWinner) {
    final rootWinner = resolveRootWinner(proposedWinner);
    final rootWinnerId = rootWinner['id'] as String;
    if (rootWinnerId == loserId) {
      // 防御损坏的 replaces_id 环：按确定性赢家规则打破环。
      final loserRow = eligibleById[loserId];
      if (loserRow == null) return;
      final cmp = _compareProfileRowsByWinnerRule(
        loserRow,
        proposedWinner,
        isBasisCovered: isBasisCovered,
      );
      if (cmp < 0) {
        final propId = proposedWinner['id'] as String;
        supersededToWinner.remove(loserId);
        supersededToWinner[propId] = loserRow;
      }
      return;
    }

    final existingWinner = supersededToWinner[loserId];
    if (existingWinner == null) {
      supersededToWinner[loserId] = rootWinner;
      return;
    }
    final existingRoot = resolveRootWinner(existingWinner);
    if (_compareProfileRowsByWinnerRule(
          rootWinner,
          existingRoot,
          isBasisCovered: isBasisCovered,
        ) <
        0) {
      supersededToWinner[loserId] = rootWinner;
    }
  }

  // 0. 显式 replaces_id 关系收敛：
  //    若 Y 声明 replaces_id == X.id 且 X、Y 均在候选集：
  //    当 X 为非 dreaming* 而 Y 为后台 Dreaming、或同为 Dreaming 且 X 看全依据而 Y 漏看离线笔记、
  //    或 X 在 Y 创建后又发生原位编辑（X 版本时间严格晚于 Y）时，X 胜出并将 Y 淘汰指向 X；否则 Y 取代 X。
  for (final yRow in sorted) {
    final yId = yRow['id'] as String;
    final xId = (yRow['replaces_id'] as String?)?.trim() ?? '';
    if (xId.isEmpty || xId == yId) continue;
    final xRow = eligibleById[xId];
    if (xRow == null) continue;

    if (_predecessorWinsReplacementEdge(
      xRow,
      yRow,
      isBasisCovered: isBasisCovered,
    )) {
      recordSupersede(yId, xRow);
    } else {
      recordSupersede(xId, yRow);
    }
  }

  // 0b. 去重退休条目后续被人工编辑反超收敛：
  //     若候选条目 X 当前处于 `superseded` 且沿 `superseded_by` 链指向候选终点 T（即便 X 未写 `replaces_id`），
  //     当 X 按赢家规则严格胜过 T（例如同步并发期间用户编辑了 X）时，由 X 反超淘汰 T 并恢复 active。
  for (final xRow in sorted) {
    final xId = xRow['id'] as String;
    final xStatus = (xRow['status'] as String?)?.trim() ?? '';
    var currId = (xRow['superseded_by'] as String?)?.trim() ?? '';
    if (xStatus != AgentMemoryStatus.superseded.storageValue ||
        currId.isEmpty) {
      continue;
    }
    final visited = <String>{xId};
    Map<String, Object?>? terminalRow;
    while (currId.isNotEmpty && visited.add(currId)) {
      final nextRow = allRowsById[currId];
      if (nextRow == null) break;
      final nextStatus = (nextRow['status'] as String?)?.trim() ??
          AgentMemoryStatus.active.storageValue;
      if (nextStatus == AgentMemoryStatus.active.storageValue) {
        terminalRow = eligibleById[currId];
        break;
      }
      if (nextStatus != AgentMemoryStatus.superseded.storageValue) break;
      currId = (nextRow['superseded_by'] as String?)?.trim() ?? '';
    }
    if (terminalRow == null) continue;
    final tId = terminalRow['id'] as String;
    if (tId == xId) continue;
    if (_compareProfileRowsByWinnerRule(
          xRow,
          terminalRow,
          isBasisCovered: isBasisCovered,
        ) <
        0) {
      recordSupersede(tId, xRow);
    }
  }

  // 1. 分叉收敛：多个候选条目的 replaces_id 非空且相同时按赢家规则选唯一赢家。
  final seenReplacesId = <String, Map<String, Object?>>{};
  for (final row in sorted) {
    final id = row['id'] as String;
    if (supersededToWinner.containsKey(id)) continue;
    final replacesId = (row['replaces_id'] as String?)?.trim() ?? '';
    if (replacesId.isEmpty) continue;
    final existingWinner = seenReplacesId[replacesId];
    if (existingWinner != null) {
      recordSupersede(id, existingWinner);
    } else {
      seenReplacesId[replacesId] = row;
    }
  }

  // 2. 单活跃类别收敛（taste / voice / style）。
  final seenSingletonKind = <String, Map<String, Object?>>{};
  for (final row in sorted) {
    final id = row['id'] as String;
    if (supersededToWinner.containsKey(id)) continue;
    final rawKind = (row['kind'] as String? ?? '').trim();
    if (!_singletonMemoryKinds.contains(rawKind)) continue;
    final existingWinner = seenSingletonKind[rawKind];
    if (existingWinner != null) {
      recordSupersede(id, existingWinner);
    } else {
      seenSingletonKind[rawKind] = row;
    }
  }

  // 3. 身份别名（已确认优先于存疑、同别名唯一）与同 kind + directive 去重。
  final confirmedAliasToWinner = <String, Map<String, Object?>>{};
  for (final row in sorted) {
    final id = row['id'] as String;
    if (supersededToWinner.containsKey(id)) continue;
    final rawKind = (row['kind'] as String? ?? '').trim();
    final directive = (row['directive'] as String? ?? '').trim();
    if (rawKind == AgentMemoryKind.identity.storageValue &&
        directive.isNotEmpty) {
      for (final alias
          in AgentMemoryService.extractAliasesFromDirective(directive)) {
        confirmedAliasToWinner.putIfAbsent(alias.toLowerCase(), () => row);
      }
    }
  }

  final seenIdentityAliases = <String, Map<String, Object?>>{};
  final seenUnconfirmedAliases = <String, Map<String, Object?>>{};
  final seenKindDirectives = <String, Map<String, Object?>>{};

  for (final row in sorted) {
    final id = row['id'] as String;
    if (supersededToWinner.containsKey(id)) continue;
    final rawKind = (row['kind'] as String? ?? '').trim();
    final directive = (row['directive'] as String? ?? '').trim();
    if (directive.isEmpty) continue;

    Map<String, Object?>? winner;

    if (rawKind == AgentMemoryKind.identity.storageValue) {
      final confirmedAliases =
          AgentMemoryService.extractAliasesFromDirective(directive);
      if (confirmedAliases.isNotEmpty) {
        for (final alias in confirmedAliases) {
          final lower = alias.toLowerCase();
          if (seenIdentityAliases.containsKey(lower)) {
            winner = seenIdentityAliases[lower];
            break;
          }
        }
        if (winner == null) {
          for (final alias in confirmedAliases) {
            seenIdentityAliases[alias.toLowerCase()] = row;
          }
        }
      } else {
        final unconfirmedAliases =
            AgentMemoryService.extractAliasesFromDirective(
          directive,
          includeUnconfirmed: true,
        );
        if (unconfirmedAliases.isNotEmpty) {
          for (final alias in unconfirmedAliases) {
            final lower = alias.toLowerCase();
            if (confirmedAliasToWinner.containsKey(lower)) {
              winner = confirmedAliasToWinner[lower];
              break;
            }
            if (seenUnconfirmedAliases.containsKey(lower)) {
              winner = seenUnconfirmedAliases[lower];
              break;
            }
          }
          if (winner == null) {
            for (final alias in unconfirmedAliases) {
              seenUnconfirmedAliases[alias.toLowerCase()] = row;
            }
          }
        }
      }
    }

    if (winner == null) {
      final kindDirectiveKey = '$rawKind:$directive';
      if (seenKindDirectives.containsKey(kindDirectiveKey)) {
        winner = seenKindDirectives[kindDirectiveKey];
      } else {
        seenKindDirectives[kindDirectiveKey] = row;
      }
    }

    if (winner != null) {
      recordSupersede(id, winner);
    }
  }

  var newlySupersededCount = preRetiredCount;
  var didMutate = preMutated;
  var bothUncoveredDreamingConflict = false;

  for (final row in sorted) {
    final id = row['id'] as String;
    final prevStatus = (row['status'] as String?)?.trim() ??
        AgentMemoryStatus.active.storageValue;
    final rawPrevSupBy = (row['superseded_by'] as String?)?.trim();
    final prevSupersededBy =
        (rawPrevSupBy != null && rawPrevSupBy.isNotEmpty) ? rawPrevSupBy : null;

    final immediateWinner = supersededToWinner[id];
    if (immediateWinner != null) {
      final finalWinner = resolveRootWinner(immediateWinner);
      final finalWinnerId = finalWinner['id'] as String;
      final winnerPrevStatus = (finalWinner['status'] as String?)?.trim() ??
          AgentMemoryStatus.active.storageValue;
      final winnerRawPrevSupBy =
          (finalWinner['superseded_by'] as String?)?.trim();
      final winnerNeedsRestore =
          winnerPrevStatus != AgentMemoryStatus.active.storageValue ||
              (winnerRawPrevSupBy != null && winnerRawPrevSupBy.isNotEmpty);
      final loserNeedsUpdate =
          prevStatus != AgentMemoryStatus.superseded.storageValue ||
              prevSupersededBy != finalWinnerId;

      if ((loserNeedsUpdate || winnerNeedsRestore) &&
          isBasisCovered != null &&
          _isDreamingMemorySource(finalWinner['source']) &&
          _isDreamingMemorySource(row['source'])) {
        final winnerCovered = isBasisCovered(
          finalWinner['basis_watermark'] as String?,
          _parseMemoryOptionalInt(finalWinner['basis_note_count']),
        );
        final loserCovered = isBasisCovered(
          row['basis_watermark'] as String?,
          _parseMemoryOptionalInt(row['basis_note_count']),
        );
        if (!winnerCovered && !loserCovered) {
          bothUncoveredDreamingConflict = true;
        }
      }

      if (loserNeedsUpdate) {
        await txn.update(
          AgentMemoryService.profileTable,
          <String, Object?>{
            'status': AgentMemoryStatus.superseded.storageValue,
            'superseded_by': finalWinnerId,
          },
          where: 'id = ?',
          whereArgs: <Object?>[id],
        );
        didMutate = true;
        if (prevStatus == AgentMemoryStatus.active.storageValue) {
          newlySupersededCount++;
        }
      }

      final sharedReplacesId = (row['replaces_id'] as String?)?.trim();
      if (sharedReplacesId != null &&
          sharedReplacesId.isNotEmpty &&
          sharedReplacesId == (finalWinner['replaces_id'] as String?)?.trim() &&
          !eligibleById.containsKey(sharedReplacesId)) {
        final ancestor = allRowsById[sharedReplacesId];
        if (ancestor != null &&
            ancestor['status'] == AgentMemoryStatus.superseded.storageValue &&
            ancestor['superseded_by'] != finalWinnerId) {
          await txn.update(
            AgentMemoryService.profileTable,
            <String, Object?>{'superseded_by': finalWinnerId},
            where: 'id = ? AND status = ?',
            whereArgs: <Object?>[
              sharedReplacesId,
              AgentMemoryStatus.superseded.storageValue,
            ],
          );
          didMutate = true;
        }
      }
    } else {
      final needsRestore =
          prevStatus != AgentMemoryStatus.active.storageValue ||
              prevSupersededBy != null;
      if (needsRestore) {
        await txn.update(
          AgentMemoryService.profileTable,
          <String, Object?>{
            'status': AgentMemoryStatus.active.storageValue,
            'superseded_by': null,
          },
          where: 'id = ?',
          whereArgs: <Object?>[id],
        );
        didMutate = true;
      }
    }
  }

  return (
    supersededCount: newlySupersededCount,
    didMutate: didMutate,
    bothUncoveredDreamingConflict: bothUncoveredDreamingConflict,
  );
}

Future<int> _dedupAndTrimFactsInTxn(DatabaseExecutor txn) async {
  final rows = await txn.query(AgentMemoryService.factsTable);
  var removedCount = 0;

  if (rows.length > 1) {
    final byNormalizedContent = <String, List<Map<String, Object?>>>{};
    for (final row in rows) {
      final rawContent = (row['content'] as String?) ?? '';
      final normalized = AgentMemoryService.normalizeMemoryText(
        rawContent,
        AgentMemoryService.factMaxChars,
      );
      if (normalized.isEmpty) continue;
      byNormalizedContent
          .putIfAbsent(normalized, () => <Map<String, Object?>>[])
          .add(row);
    }

    final idsToDelete = <String>[];
    for (final group in byNormalizedContent.values) {
      if (group.length <= 1) continue;
      group.sort((a, b) {
        final aCreated = _parseMemoryRowSyncVersion(a['created_at'], null);
        final bCreated = _parseMemoryRowSyncVersion(b['created_at'], null);
        final cmp = LWWUtils.compareSyncVersions(aCreated, bCreated);
        if (cmp != 0) return cmp;
        final aId = (a['id'] as String?) ?? '';
        final bId = (b['id'] as String?) ?? '';
        return aId.compareTo(bId);
      });

      final survivor = group.first;
      final survivorId = survivor['id'] as String;
      var maxRecall = _parseMemoryOptionalInt(survivor['recall_count']) ?? 0;
      String? maxLastRecalled = _pickLatestTimestampStr(
        survivor['last_recalled_at'],
        null,
      );

      for (var i = 1; i < group.length; i++) {
        final dup = group[i];
        final dupId = dup['id'] as String?;
        if (dupId != null && dupId.isNotEmpty) {
          idsToDelete.add(dupId);
        }
        final dupRecall = _parseMemoryOptionalInt(dup['recall_count']) ?? 0;
        if (dupRecall > maxRecall) {
          maxRecall = dupRecall;
        }
        maxLastRecalled = _pickLatestTimestampStr(
          maxLastRecalled,
          dup['last_recalled_at'],
        );
      }

      final survivorRecall =
          _parseMemoryOptionalInt(survivor['recall_count']) ?? 0;
      final survivorLastRecalled = survivor['last_recalled_at'] as String?;
      if (maxRecall != survivorRecall ||
          maxLastRecalled != survivorLastRecalled) {
        await txn.update(
          AgentMemoryService.factsTable,
          <String, Object?>{
            'recall_count': maxRecall,
            'last_recalled_at': maxLastRecalled,
          },
          where: 'id = ?',
          whereArgs: <Object?>[survivorId],
        );
      }
    }

    if (idsToDelete.isNotEmpty) {
      final placeholders =
          List<String>.filled(idsToDelete.length, '?').join(', ');
      removedCount = await txn.rawDelete(
        'DELETE FROM ${AgentMemoryService.factsTable} WHERE id IN ($placeholders)',
        idsToDelete,
      );
    }
  }

  await AgentMemoryService._evictOverflowFactsInTxn(txn);
  return removedCount;
}

extension AgentMemorySyncExtension on AgentMemoryService {
  /// 在策略代际锁保护下序列化当前 `agent_memory` JSON 字符串；
  /// 若记忆已关闭或在构建期间被关闭/失效，返回 `null`，绝不泄露已关闭记忆。
  Future<String?> encodeMemorySectionIfEnabled({
    CancelToken? cancelToken,
  }) async {
    final payload = await _buildGuardedExportMemoryPayload(
      cancelToken: cancelToken,
    );
    if (payload == null) {
      return null;
    }
    return jsonEncode(payload);
  }

  /// 流式写出 `agent_memory` 同步载荷（不含外层键名 `"agent_memory":`）。
  ///
  /// 与策略代际锁协同：若记忆开关关闭或在序列化期间被关闭，本方法不写出任何内容。
  Future<void> exportMemorySectionStreaming(
    IOSink sink, {
    CancelToken? cancelToken,
  }) async {
    final encoded = await encodeMemorySectionIfEnabled(
      cancelToken: cancelToken,
    );
    if (encoded == null) {
      return;
    }
    sink.write(encoded);
  }

  @visibleForTesting
  Future<Map<String, dynamic>?> exportMemorySectionForTesting() {
    return _buildGuardedExportMemoryPayload();
  }

  Future<Map<String, dynamic>?> _buildGuardedExportMemoryPayload({
    CancelToken? cancelToken,
  }) async {
    if (!isEnabled) {
      return null;
    }
    final startGeneration = captureGeneration;
    return _settingsService.withAgentMemoryPolicy<Map<String, dynamic>?>(
      () async {
        if (!isCaptureCurrent(startGeneration)) {
          return null;
        }
        final payload = await _buildExportMemoryPayload(
          cancelToken: cancelToken,
        );
        if (!isCaptureCurrent(startGeneration)) {
          return null;
        }
        return payload;
      },
    );
  }

  Future<Map<String, dynamic>> _buildExportMemoryPayload({
    CancelToken? cancelToken,
  }) async {
    final db = await _db;
    return db.transaction<Map<String, dynamic>>((txn) async {
      cancelToken?.throwIfCancelled();
      final rawProfiles = await txn.query(
        AgentMemoryService.profileTable,
        orderBy: 'observed_at ASC, id ASC',
      );
      final rawFacts = await txn.query(
        AgentMemoryService.factsTable,
        orderBy: 'created_at ASC, id ASC',
      );
      final rawSlices = await txn.query(
        AgentMemoryService.recentSliceTable,
        orderBy: 'observed_at ASC, id ASC',
      );
      final rawTombstones = await txn.query(
        AgentMemoryService.tombstonesTable,
        orderBy: 'entity_type ASC, entity_id ASC',
      );
      final rawMeta = await txn.query(AgentMemoryService.metaTable);

      final metaMap = <String, String>{
        for (final row in rawMeta)
          if (row['key'] is String && row['value'] is String)
            row['key'] as String: row['value'] as String,
      };

      final clearedRaw = metaMap[AgentMemoryService.metaClearedAtKey];
      final clearedAtUtc = _tryParseMemoryUtc(clearedRaw);
      final clearedAt = clearedAtUtc != null
          ? _normalizeMemoryTimestampToUtcOrKeep(clearedRaw)
          : null;

      final settingsLastRunUtc = _settingsService.lastDreamingAt?.toUtc();
      final isDreamingAfterClear = settingsLastRunUtc != null &&
          (clearedAtUtc == null || settingsLastRunUtc.isAfter(clearedAtUtc));
      Map<String, Object?> dreamingPayload;
      if (isDreamingAfterClear) {
        final metaLastRunUtc = _tryParseMemoryUtc(
          metaMap[AgentMemoryService.metaDreamingLastRunAtKey],
        );
        final matchesMeta = metaLastRunUtc != null &&
            metaLastRunUtc.difference(settingsLastRunUtc).inSeconds.abs() <= 1;
        final rawWatermark = matchesMeta
            ? metaMap[AgentMemoryService.metaDreamingBasisWatermarkKey]
            : null;
        final normalizedWatermark =
            _tryParseMemoryUtc(rawWatermark)?.toIso8601String() ??
                ((rawWatermark != null && rawWatermark.trim().isNotEmpty)
                    ? rawWatermark.trim()
                    : null);
        dreamingPayload = <String, Object?>{
          'last_run_at': LWWUtils.formatFixedUtcIso(settingsLastRunUtc),
          'basis_watermark': normalizedWatermark,
          'basis_note_count': matchesMeta
              ? _parseMemoryOptionalInt(
                  metaMap[AgentMemoryService.metaDreamingBasisNoteCountKey],
                )
              : null,
        };
      } else {
        dreamingPayload = <String, Object?>{
          'last_run_at': null,
          'basis_watermark': null,
          'basis_note_count': null,
        };
      }

      return <String, dynamic>{
        'format': 1,
        'profile':
            rawProfiles.map(_exportWhitelistedProfile).toList(growable: false),
        'facts': rawFacts.map(_exportWhitelistedFact).toList(growable: false),
        'recent_slices':
            rawSlices.map(_exportWhitelistedSlice).toList(growable: false),
        'tombstones': rawTombstones
            .map(
              (r) => <String, Object?>{
                'entity_type': r['entity_type'],
                'entity_id': r['entity_id'],
                'deleted_at': _normalizeMemoryTimestampToUtcOrKeep(
                  r['deleted_at'],
                ),
              },
            )
            .toList(growable: false),
        'cleared_at': clearedAt,
        'dreaming': dreamingPayload,
      };
    });
  }

  /// 将远端 `agent_memory` 段按 LWW + 墓碑 + `cleared_at` 屏障 + 确定性收敛合入本地。
  Future<MemoryMergeStats> mergeMemorySection(
    Object? rawSection, {
    AgentMemoryBasisChecker? isBasisCovered,
    AgentMemoryBatchBasisChecker? checkBasisBatch,
  }) async {
    if (rawSection == null) {
      return const MemoryMergeStats();
    }
    if (rawSection is! Map) {
      throw const FormatException('Invalid agent_memory section format');
    }
    _validateMemorySectionContainers(rawSection);

    if (!isEnabled) {
      return const MemoryMergeStats(skippedBecauseDisabled: true);
    }
    final startGeneration = captureGeneration;

    var skippedCount = 0;

    DateTime? remoteClearedAtUtc;
    final rawClearedAt = rawSection['cleared_at'];
    if (rawClearedAt is String && rawClearedAt.trim().isNotEmpty) {
      remoteClearedAtUtc = _tryParseMemoryUtc(rawClearedAt);
    }

    DateTime? remoteDreamingLastRunUtc;
    String? remoteDreamingWatermark;
    int? remoteDreamingNoteCount;
    final rawDreaming = rawSection['dreaming'];
    if (rawDreaming is Map) {
      remoteDreamingLastRunUtc = _tryParseMemoryUtc(rawDreaming['last_run_at']);
      final wmUtc = _tryParseMemoryUtc(rawDreaming['basis_watermark']);
      remoteDreamingWatermark = wmUtc?.toIso8601String();
      final cnt = _parseMemoryOptionalInt(rawDreaming['basis_note_count']);
      if (cnt != null && cnt >= 0) {
        remoteDreamingNoteCount = cnt;
      }
    }

    final remoteProfilesById = <String, Map<String, Object?>>{};
    final rawProfiles = rawSection['profile'];
    if (rawProfiles is List) {
      for (final item in rawProfiles) {
        final sanitized = _sanitizeMemoryProfileRow(item);
        if (sanitized == null) {
          skippedCount++;
          continue;
        }
        final id = sanitized['id'] as String;
        final existing = remoteProfilesById[id];
        if (existing == null) {
          remoteProfilesById[id] = sanitized;
          continue;
        }
        final candVer = _parseMemoryRowSyncVersion(
          sanitized['updated_at'],
          sanitized['observed_at'],
        );
        final existVer = _parseMemoryRowSyncVersion(
          existing['updated_at'],
          existing['observed_at'],
        );
        final cmp = LWWUtils.compareSyncVersions(candVer, existVer);
        if (cmp > 0 ||
            (cmp == 0 &&
                _compareMemoryCanonicalFields(
                      sanitized,
                      existing,
                      _memoryProfileTieBreakKeys,
                    ) >
                    0)) {
          remoteProfilesById[id] = sanitized;
        } else {
          skippedCount++;
        }
      }
    }
    final remoteProfiles = remoteProfilesById.values.toList(growable: false);

    final remoteFactsById = <String, Map<String, Object?>>{};
    final rawFacts = rawSection['facts'];
    if (rawFacts is List) {
      for (final item in rawFacts) {
        final sanitized = _sanitizeMemoryFactRow(item);
        if (sanitized == null) {
          skippedCount++;
          continue;
        }
        final id = sanitized['id'] as String;
        final existing = remoteFactsById[id];
        if (existing == null) {
          remoteFactsById[id] = sanitized;
          continue;
        }
        final candVer = _parseMemoryRowSyncVersion(
          sanitized['updated_at'],
          sanitized['created_at'],
        );
        final existVer = _parseMemoryRowSyncVersion(
          existing['updated_at'],
          existing['created_at'],
        );
        final mergedRecall = math.max(
          _parseMemoryOptionalInt(existing['recall_count']) ?? 0,
          _parseMemoryOptionalInt(sanitized['recall_count']) ?? 0,
        );
        final mergedLastRecalled = _pickLatestTimestampStr(
          existing['last_recalled_at'],
          sanitized['last_recalled_at'],
        );
        final cmp = LWWUtils.compareSyncVersions(candVer, existVer);
        if (cmp > 0 ||
            (cmp == 0 &&
                _compareMemoryCanonicalFields(
                      sanitized,
                      existing,
                      _memoryFactTieBreakKeys,
                    ) >
                    0)) {
          sanitized['recall_count'] = mergedRecall;
          sanitized['last_recalled_at'] = mergedLastRecalled;
          remoteFactsById[id] = sanitized;
        } else {
          existing['recall_count'] = mergedRecall;
          existing['last_recalled_at'] = mergedLastRecalled;
          skippedCount++;
        }
      }
    }
    final remoteFacts = remoteFactsById.values.toList(growable: false);

    final remoteSlicesById = <String, Map<String, Object?>>{};
    final rawSlices = rawSection['recent_slices'];
    if (rawSlices is List) {
      for (final item in rawSlices) {
        final sanitized = _sanitizeMemorySliceRow(item);
        if (sanitized == null) {
          skippedCount++;
          continue;
        }
        final id = sanitized['id'] as String;
        final existing = remoteSlicesById[id];
        if (existing == null) {
          remoteSlicesById[id] = sanitized;
          continue;
        }
        final candVer = _parseMemoryRowSyncVersion(
          sanitized['observed_at'],
          null,
        );
        final existVer = _parseMemoryRowSyncVersion(
          existing['observed_at'],
          null,
        );
        final cmp = LWWUtils.compareSyncVersions(candVer, existVer);
        if (cmp > 0 ||
            (cmp == 0 &&
                _compareMemorySliceOnSameObservedAt(sanitized, existing) > 0)) {
          remoteSlicesById[id] = sanitized;
        } else {
          skippedCount++;
        }
      }
    }
    final remoteSlices = remoteSlicesById.values.toList(growable: false);

    final remoteTombstonesByKey = <String, _ParsedMemoryTombstone>{};
    final rawTombstones = rawSection['tombstones'];
    if (rawTombstones is List) {
      for (final item in rawTombstones) {
        final sanitized = _sanitizeMemoryTombstone(item);
        if (sanitized == null) {
          skippedCount++;
          continue;
        }
        final key = '${sanitized.entityType}:${sanitized.entityId}';
        final existing = remoteTombstonesByKey[key];
        if (existing == null ||
            sanitized.deletedAtUtc.isAfter(existing.deletedAtUtc)) {
          remoteTombstonesByKey[key] = sanitized;
        }
      }
    }
    final remoteTombstones =
        remoteTombstonesByKey.values.toList(growable: false);

    final db = await _db;
    if (!isCaptureCurrent(startGeneration)) {
      return const MemoryMergeStats(skippedBecauseDisabled: true);
    }

    // 在开启记忆库写事务前，针对主库已完成合并的快照批量预评估所有 Dreaming 依据对，
    // 避免在 agent_memory.db 事务内跨库异步等待，同时确保收敛比较函数纯同步确定。
    final effectiveCheckBasisBatch =
        checkBasisBatch ?? (isBasisCovered == null ? _basisChecker : null);
    final hasBasisChecker =
        effectiveCheckBasisBatch != null || isBasisCovered != null;
    final basisPairs = <(String, int)>{};
    void collectBasis(Object? wmRaw, Object? cntRaw) {
      if (wmRaw is! String) return;
      final wm = wmRaw.trim();
      final cnt = _parseMemoryOptionalInt(cntRaw);
      if (wm.isEmpty || cnt == null || cnt < 0) return;
      if (_tryParseMemoryUtc(wm) == null) return;
      basisPairs.add((wm, cnt));
    }

    if (hasBasisChecker) {
      final existingProfiles = await db.query(
        AgentMemoryService.profileTable,
        columns: const <String>[
          'source',
          'basis_watermark',
          'basis_note_count',
        ],
      );
      for (final row in existingProfiles) {
        if (_isDreamingMemorySource(row['source'])) {
          collectBasis(row['basis_watermark'], row['basis_note_count']);
        }
      }
      for (final row in remoteProfiles) {
        if (_isDreamingMemorySource(row['source'])) {
          collectBasis(row['basis_watermark'], row['basis_note_count']);
        }
      }
      if (remoteDreamingLastRunUtc != null) {
        collectBasis(remoteDreamingWatermark, remoteDreamingNoteCount);
      }
    }

    final coverageCache = <(String, int), bool>{};
    if (basisPairs.isNotEmpty) {
      if (effectiveCheckBasisBatch != null) {
        coverageCache.addAll(await effectiveCheckBasisBatch(basisPairs));
      } else if (isBasisCovered != null) {
        for (final pair in basisPairs) {
          if (!isCaptureCurrent(startGeneration)) {
            return const MemoryMergeStats(skippedBecauseDisabled: true);
          }
          coverageCache[pair] = await isBasisCovered(pair.$1, pair.$2);
        }
      }
    }

    if (!isCaptureCurrent(startGeneration)) {
      return const MemoryMergeStats(skippedBecauseDisabled: true);
    }

    bool syncCheckCovered(String? wm, int? cnt) {
      if (wm == null || cnt == null || cnt < 0) return false;
      final trimmed = wm.trim();
      if (trimmed.isEmpty) return false;
      return coverageCache[(trimmed, cnt)] ?? false;
    }

    return _settingsService.withAgentMemoryPolicy<MemoryMergeStats>(() async {
      if (!isCaptureCurrent(startGeneration)) {
        return const MemoryMergeStats(skippedBecauseDisabled: true);
      }

      var profilesAdded = 0;
      var profilesUpdated = 0;
      var profilesDeleted = 0;
      var factsAdded = 0;
      var factsUpdated = 0;
      var factsDeleted = 0;
      var slicesAdded = 0;
      var slicesUpdated = 0;
      var slicesDeleted = 0;
      var localSkippedCount = skippedCount;

      var changed = false;
      var bothUncoveredDreamingConflict = false;
      DateTime? effectiveClearedAtUtc;

      try {
        await db.transaction((txn) async {
          // 1. cleared_at 屏障计算与本地清理
          final metaRows = await txn.query(
            AgentMemoryService.metaTable,
            where: 'key = ?',
            whereArgs: <Object?>[AgentMemoryService.metaClearedAtKey],
            limit: 1,
          );
          final localClearedAtUtc = metaRows.isEmpty
              ? null
              : _tryParseMemoryUtc(metaRows.first['value']);

          if (localClearedAtUtc != null && remoteClearedAtUtc != null) {
            effectiveClearedAtUtc =
                remoteClearedAtUtc.isAfter(localClearedAtUtc)
                    ? remoteClearedAtUtc
                    : localClearedAtUtc;
          } else {
            effectiveClearedAtUtc = remoteClearedAtUtc ?? localClearedAtUtc;
          }

          final remoteCleared = remoteClearedAtUtc;
          if (remoteCleared != null &&
              (localClearedAtUtc == null ||
                  remoteCleared.isAfter(localClearedAtUtc))) {
            await txn.insert(
              AgentMemoryService.metaTable,
              <String, Object?>{
                'key': AgentMemoryService.metaClearedAtKey,
                'value': LWWUtils.formatFixedUtcIso(remoteCleared),
              },
              conflictAlgorithm: ConflictAlgorithm.replace,
            );
            changed = true;

            final localProfRows =
                await txn.query(AgentMemoryService.profileTable);
            for (final row in localProfRows) {
              final rowVer = _parseMemoryRowSyncVersion(
                row['updated_at'],
                row['observed_at'],
              );
              if (!LWWUtils.syncVersionBeatsDeletion(rowVer, remoteCleared)) {
                await txn.delete(
                  AgentMemoryService.profileTable,
                  where: 'id = ?',
                  whereArgs: <Object?>[row['id']],
                );
                profilesDeleted++;
              }
            }

            final localFactRows =
                await txn.query(AgentMemoryService.factsTable);
            for (final row in localFactRows) {
              final rowVer = _parseMemoryRowSyncVersion(
                row['updated_at'],
                row['created_at'],
              );
              if (!LWWUtils.syncVersionBeatsDeletion(rowVer, remoteCleared)) {
                await txn.delete(
                  AgentMemoryService.factsTable,
                  where: 'id = ?',
                  whereArgs: <Object?>[row['id']],
                );
                factsDeleted++;
              }
            }

            final localSliceRows =
                await txn.query(AgentMemoryService.recentSliceTable);
            for (final row in localSliceRows) {
              final rowVer =
                  _parseMemoryRowSyncVersion(row['observed_at'], null);
              if (!LWWUtils.syncVersionBeatsDeletion(rowVer, remoteCleared)) {
                await txn.delete(
                  AgentMemoryService.recentSliceTable,
                  where: 'id = ?',
                  whereArgs: <Object?>[row['id']],
                );
                slicesDeleted++;
              }
            }

            final localTombRows =
                await txn.query(AgentMemoryService.tombstonesTable);
            for (final row in localTombRows) {
              final delVer =
                  _parseMemoryRowSyncVersion(row['deleted_at'], null);
              if (!LWWUtils.syncVersionBeatsDeletion(delVer, remoteCleared)) {
                await txn.delete(
                  AgentMemoryService.tombstonesTable,
                  where: 'entity_type = ? AND entity_id = ?',
                  whereArgs: <Object?>[row['entity_type'], row['entity_id']],
                );
              }
            }
          }

          bool isTombstoneBlockedByClearedAt(DateTime tsUtc) =>
              effectiveClearedAtUtc != null &&
              !tsUtc.isAfter(effectiveClearedAtUtc!);

          bool isVersionBlockedByClearedAt(_MemorySyncVersion ver) =>
              effectiveClearedAtUtc != null &&
              !LWWUtils.syncVersionBeatsDeletion(ver, effectiveClearedAtUtc!);

          // 2. 加载当前本地快照
          final localProfilesById = <String, Map<String, Object?>>{
            for (final r in await txn.query(AgentMemoryService.profileTable))
              if (r['id'] is String)
                r['id'] as String: _exportWhitelistedProfile(r),
          };
          final localFactsById = <String, Map<String, Object?>>{
            for (final r in await txn.query(AgentMemoryService.factsTable))
              if (r['id'] is String)
                r['id'] as String: _exportWhitelistedFact(r),
          };
          final localSlicesById = <String, Map<String, Object?>>{
            for (final r
                in await txn.query(AgentMemoryService.recentSliceTable))
              if (r['id'] is String)
                r['id'] as String: _exportWhitelistedSlice(r),
          };
          final localTombstones = <String, DateTime>{};
          for (final r in await txn.query(AgentMemoryService.tombstonesTable)) {
            final type = r['entity_type'] as String?;
            final id = r['entity_id'] as String?;
            final delUtc = _tryParseMemoryUtc(r['deleted_at']);
            if (type != null && id != null && delUtc != null) {
              localTombstones['$type:$id'] = delUtc;
            }
          }

          Future<void> upsertTombstone(
            String type,
            String id,
            DateTime deletedUtc,
          ) async {
            final key = '$type:$id';
            final existing = localTombstones[key];
            final effective = (existing != null && existing.isAfter(deletedUtc))
                ? existing
                : deletedUtc;
            await txn.insert(
              AgentMemoryService.tombstonesTable,
              <String, Object?>{
                'entity_type': type,
                'entity_id': id,
                'deleted_at': LWWUtils.formatFixedUtcIso(effective),
              },
              conflictAlgorithm: ConflictAlgorithm.replace,
            );
            localTombstones[key] = effective;
            changed = true;
          }

          // 3. 应用远端墓碑
          for (final tomb in remoteTombstones) {
            if (isTombstoneBlockedByClearedAt(tomb.deletedAtUtc)) {
              localSkippedCount++;
              continue;
            }
            final key = '${tomb.entityType}:${tomb.entityId}';
            if (tomb.entityType == 'profile') {
              final localRow = localProfilesById[tomb.entityId];
              if (localRow != null) {
                final localVer = _parseMemoryRowSyncVersion(
                  localRow['updated_at'],
                  localRow['observed_at'],
                );
                if (!LWWUtils.syncVersionBeatsDeletion(
                  localVer,
                  tomb.deletedAtUtc,
                )) {
                  await txn.delete(
                    AgentMemoryService.profileTable,
                    where: 'id = ?',
                    whereArgs: <Object?>[tomb.entityId],
                  );
                  localProfilesById.remove(tomb.entityId);
                  profilesDeleted++;
                  await upsertTombstone(
                    tomb.entityType,
                    tomb.entityId,
                    tomb.deletedAtUtc,
                  );
                } else if (localTombstones.containsKey(key)) {
                  await txn.delete(
                    AgentMemoryService.tombstonesTable,
                    where: 'entity_type = ? AND entity_id = ?',
                    whereArgs: <Object?>[tomb.entityType, tomb.entityId],
                  );
                  localTombstones.remove(key);
                  changed = true;
                }
              } else {
                final existingTomb = localTombstones[key];
                if (existingTomb == null ||
                    tomb.deletedAtUtc.isAfter(existingTomb)) {
                  await upsertTombstone(
                    tomb.entityType,
                    tomb.entityId,
                    tomb.deletedAtUtc,
                  );
                }
              }
            } else if (tomb.entityType == 'fact') {
              final localRow = localFactsById[tomb.entityId];
              if (localRow != null) {
                final localVer = _parseMemoryRowSyncVersion(
                  localRow['updated_at'],
                  localRow['created_at'],
                );
                if (!LWWUtils.syncVersionBeatsDeletion(
                  localVer,
                  tomb.deletedAtUtc,
                )) {
                  await txn.delete(
                    AgentMemoryService.factsTable,
                    where: 'id = ?',
                    whereArgs: <Object?>[tomb.entityId],
                  );
                  localFactsById.remove(tomb.entityId);
                  factsDeleted++;
                  await upsertTombstone(
                    tomb.entityType,
                    tomb.entityId,
                    tomb.deletedAtUtc,
                  );
                } else if (localTombstones.containsKey(key)) {
                  await txn.delete(
                    AgentMemoryService.tombstonesTable,
                    where: 'entity_type = ? AND entity_id = ?',
                    whereArgs: <Object?>[tomb.entityType, tomb.entityId],
                  );
                  localTombstones.remove(key);
                  changed = true;
                }
              } else {
                final existingTomb = localTombstones[key];
                if (existingTomb == null ||
                    tomb.deletedAtUtc.isAfter(existingTomb)) {
                  await upsertTombstone(
                    tomb.entityType,
                    tomb.entityId,
                    tomb.deletedAtUtc,
                  );
                }
              }
            } else if (tomb.entityType == 'slice') {
              final localRow = localSlicesById[tomb.entityId];
              if (localRow != null) {
                final localVer =
                    _parseMemoryRowSyncVersion(localRow['observed_at'], null);
                if (!LWWUtils.syncVersionBeatsDeletion(
                  localVer,
                  tomb.deletedAtUtc,
                )) {
                  await txn.delete(
                    AgentMemoryService.recentSliceTable,
                    where: 'id = ?',
                    whereArgs: <Object?>[tomb.entityId],
                  );
                  localSlicesById.remove(tomb.entityId);
                  slicesDeleted++;
                  await upsertTombstone(
                    tomb.entityType,
                    tomb.entityId,
                    tomb.deletedAtUtc,
                  );
                } else if (localTombstones.containsKey(key)) {
                  await txn.delete(
                    AgentMemoryService.tombstonesTable,
                    where: 'entity_type = ? AND entity_id = ?',
                    whereArgs: <Object?>[tomb.entityType, tomb.entityId],
                  );
                  localTombstones.remove(key);
                  changed = true;
                }
              } else {
                final existingTomb = localTombstones[key];
                if (existingTomb == null ||
                    tomb.deletedAtUtc.isAfter(existingTomb)) {
                  await upsertTombstone(
                    tomb.entityType,
                    tomb.entityId,
                    tomb.deletedAtUtc,
                  );
                }
              }
            }
          }

          DateTime? findTombstonedProfileChainTime(
            Map<String, Object?> startRow,
          ) {
            final startStatus = (startRow['status'] as String?)?.trim();
            var currId = (startRow['superseded_by'] as String?)?.trim() ?? '';
            if (startStatus != AgentMemoryStatus.superseded.storageValue ||
                currId.isEmpty) {
              return null;
            }
            final startId = (startRow['id'] as String?)?.trim() ?? '';
            final visited = <String>{if (startId.isNotEmpty) startId};
            while (currId.isNotEmpty && visited.add(currId)) {
              final tombUtc = localTombstones['profile:$currId'];
              final rNext = remoteProfilesById[currId];
              final lNext = localProfilesById[currId];
              if (tombUtc != null) {
                final rAliveAfterTomb = rNext != null &&
                    LWWUtils.syncVersionBeatsDeletion(
                      _parseMemoryRowSyncVersion(
                        rNext['updated_at'],
                        rNext['observed_at'],
                      ),
                      tombUtc,
                    );
                final lAliveAfterTomb = lNext != null &&
                    LWWUtils.syncVersionBeatsDeletion(
                      _parseMemoryRowSyncVersion(
                        lNext['updated_at'],
                        lNext['observed_at'],
                      ),
                      tombUtc,
                    );
                if (!rAliveAfterTomb && !lAliveAfterTomb) {
                  return tombUtc;
                }
              }
              Map<String, Object?>? nextRow;
              if (rNext != null && lNext != null) {
                final rVer = _parseMemoryRowSyncVersion(
                  rNext['updated_at'],
                  rNext['observed_at'],
                );
                final lVer = _parseMemoryRowSyncVersion(
                  lNext['updated_at'],
                  lNext['observed_at'],
                );
                final cmpNext = LWWUtils.compareSyncVersions(rVer, lVer);
                if (cmpNext > 0) {
                  nextRow = rNext;
                } else if (cmpNext < 0) {
                  nextRow = lNext;
                } else {
                  final rSup = (rNext['status'] as String?)?.trim() ==
                          AgentMemoryStatus.superseded.storageValue &&
                      ((rNext['superseded_by'] as String?)?.trim().isNotEmpty ??
                          false);
                  nextRow = rSup ? rNext : lNext;
                }
              } else {
                nextRow = rNext ?? lNext;
              }
              if (nextRow == null) {
                return null;
              }
              final nextStatus = (nextRow['status'] as String?)?.trim();
              if (nextStatus != AgentMemoryStatus.superseded.storageValue) {
                return null;
              }
              currId = (nextRow['superseded_by'] as String?)?.trim() ?? '';
            }
            return null;
          }

          bool hasTombstonedProfileSuccessor(
            Map<String, Object?> row,
            _MemorySyncVersion rowVersion,
          ) {
            final tombUtc = findTombstonedProfileChainTime(row);
            return tombUtc != null &&
                !LWWUtils.syncVersionBeatsDeletion(rowVersion, tombUtc);
          }

          bool hasKnownLiveProfileSuccessor(Map<String, Object?> row) {
            final status = (row['status'] as String?)?.trim();
            final supBy = (row['superseded_by'] as String?)?.trim() ?? '';
            if (status != AgentMemoryStatus.superseded.storageValue ||
                supBy.isEmpty) {
              return false;
            }
            return remoteProfilesById.containsKey(supBy) ||
                localProfilesById.containsKey(supBy);
          }

          String? resolveOlderSupersededTerminalToRetire({
            required String selfId,
            required Map<String, Object?> winnerRow,
            required Map<String, Object?> olderRow,
          }) {
            final winnerStatus = (winnerRow['status'] as String?)?.trim() ??
                AgentMemoryStatus.active.storageValue;
            final winnerReplaces =
                (winnerRow['replaces_id'] as String?)?.trim() ?? '';
            final olderStatus = (olderRow['status'] as String?)?.trim() ?? '';
            var currId = (olderRow['superseded_by'] as String?)?.trim() ?? '';
            if (winnerStatus != AgentMemoryStatus.active.storageValue ||
                winnerReplaces.isNotEmpty ||
                olderStatus != AgentMemoryStatus.superseded.storageValue ||
                currId.isEmpty) {
              return null;
            }
            final visited = <String>{selfId};
            while (currId.isNotEmpty && visited.add(currId)) {
              final rCand = remoteProfilesById[currId];
              final lCand = localProfilesById[currId];
              Map<String, Object?>? cand;
              if (rCand != null && lCand != null) {
                final cmpCand = LWWUtils.compareSyncVersions(
                  _parseMemoryRowSyncVersion(
                    rCand['updated_at'],
                    rCand['observed_at'],
                  ),
                  _parseMemoryRowSyncVersion(
                    lCand['updated_at'],
                    lCand['observed_at'],
                  ),
                );
                cand = cmpCand > 0 ? rCand : lCand;
              } else {
                cand = rCand ?? lCand;
              }
              if (cand == null) return null;
              final candStatus = (cand['status'] as String?)?.trim() ??
                  AgentMemoryStatus.active.storageValue;
              if (candStatus == AgentMemoryStatus.active.storageValue) {
                final tId = (cand['id'] as String?)?.trim() ?? '';
                if (tId.isEmpty || tId == selfId) return null;
                final beatsTerminal = _compareProfileRowsByWinnerRule(
                      winnerRow,
                      cand,
                      isBasisCovered: hasBasisChecker ? syncCheckCovered : null,
                    ) <
                    0;
                return beatsTerminal ? tId : null;
              }
              if (candStatus != AgentMemoryStatus.superseded.storageValue) {
                return null;
              }
              currId = (cand['superseded_by'] as String?)?.trim() ?? '';
            }
            return null;
          }

          // 4. 合并 profile 行
          for (final remoteRow in remoteProfiles) {
            final id = remoteRow['id'] as String;
            final remoteVer = _parseMemoryRowSyncVersion(
              remoteRow['updated_at'],
              remoteRow['observed_at'],
            );
            if (isVersionBlockedByClearedAt(remoteVer)) {
              localSkippedCount++;
              continue;
            }
            final tombKey = 'profile:$id';
            final localTombUtc = localTombstones[tombKey];
            if (localTombUtc != null) {
              if (!LWWUtils.syncVersionBeatsDeletion(remoteVer, localTombUtc)) {
                localSkippedCount++;
                continue;
              }
              await txn.delete(
                AgentMemoryService.tombstonesTable,
                where: 'entity_type = ? AND entity_id = ?',
                whereArgs: <Object?>['profile', id],
              );
              localTombstones.remove(tombKey);
              changed = true;
            }

            final localRow = localProfilesById[id];
            if (localRow == null) {
              await txn.insert(
                AgentMemoryService.profileTable,
                remoteRow,
                conflictAlgorithm: ConflictAlgorithm.replace,
              );
              localProfilesById[id] = remoteRow;
              profilesAdded++;
              changed = true;
            } else {
              final localVer = _parseMemoryRowSyncVersion(
                localRow['updated_at'],
                localRow['observed_at'],
              );
              final cmpProf = LWWUtils.compareSyncVersions(remoteVer, localVer);
              if (cmpProf > 0) {
                final retiredSuccId = resolveOlderSupersededTerminalToRetire(
                  selfId: id,
                  winnerRow: remoteRow,
                  olderRow: localRow,
                );
                final effectiveRemoteRow = retiredSuccId != null
                    ? <String, Object?>{
                        ...remoteRow,
                        'replaces_id': retiredSuccId,
                      }
                    : remoteRow;
                await txn.update(
                  AgentMemoryService.profileTable,
                  effectiveRemoteRow,
                  where: 'id = ?',
                  whereArgs: <Object?>[id],
                );
                localProfilesById[id] = effectiveRemoteRow;
                profilesUpdated++;
                changed = true;
              } else if (cmpProf < 0) {
                final retiredSuccId = resolveOlderSupersededTerminalToRetire(
                  selfId: id,
                  winnerRow: localRow,
                  olderRow: remoteRow,
                );
                if (retiredSuccId != null) {
                  final updatedLocalRow = <String, Object?>{
                    ...localRow,
                    'replaces_id': retiredSuccId,
                  };
                  await txn.update(
                    AgentMemoryService.profileTable,
                    <String, Object?>{'replaces_id': retiredSuccId},
                    where: 'id = ?',
                    whereArgs: <Object?>[id],
                  );
                  localProfilesById[id] = updatedLocalRow;
                  profilesUpdated++;
                  changed = true;
                }
              } else {
                final remoteTombSucc =
                    hasTombstonedProfileSuccessor(remoteRow, remoteVer);
                final localTombSucc =
                    hasTombstonedProfileSuccessor(localRow, localVer);
                final remoteLiveSucc = hasKnownLiveProfileSuccessor(remoteRow);
                final localLiveSucc = hasKnownLiveProfileSuccessor(localRow);
                final contentTieCmp = _compareMemoryCanonicalFields(
                  remoteRow,
                  localRow,
                  _memoryProfileTieBreakKeys,
                );

                final mergedRow = Map<String, Object?>.of(
                  contentTieCmp > 0 ? remoteRow : localRow,
                );
                if (remoteTombSucc || localTombSucc) {
                  mergedRow['status'] =
                      AgentMemoryStatus.superseded.storageValue;
                  if (remoteTombSucc && localTombSucc) {
                    final rSup =
                        (remoteRow['superseded_by'] as String?)?.trim() ?? '';
                    final lSup =
                        (localRow['superseded_by'] as String?)?.trim() ?? '';
                    mergedRow['superseded_by'] =
                        rSup.compareTo(lSup) >= 0 ? rSup : lSup;
                  } else {
                    final tombSource = remoteTombSucc ? remoteRow : localRow;
                    mergedRow['superseded_by'] = tombSource['superseded_by'];
                  }
                } else if (remoteLiveSucc || localLiveSucc) {
                  mergedRow['status'] =
                      AgentMemoryStatus.superseded.storageValue;
                  if (remoteLiveSucc && localLiveSucc) {
                    final rSup =
                        (remoteRow['superseded_by'] as String?)?.trim() ?? '';
                    final lSup =
                        (localRow['superseded_by'] as String?)?.trim() ?? '';
                    mergedRow['superseded_by'] =
                        rSup.compareTo(lSup) >= 0 ? rSup : lSup;
                  } else {
                    final succSource = remoteLiveSucc ? remoteRow : localRow;
                    mergedRow['superseded_by'] = succSource['superseded_by'];
                  }
                } else {
                  mergedRow['status'] = localRow['status'];
                  mergedRow['superseded_by'] = localRow['superseded_by'];
                }

                final hasDiff = _memoryProfileColumnWhitelist.any(
                  (col) => localRow[col] != mergedRow[col],
                );
                if (hasDiff) {
                  await txn.update(
                    AgentMemoryService.profileTable,
                    mergedRow,
                    where: 'id = ?',
                    whereArgs: <Object?>[id],
                  );
                  localProfilesById[id] = mergedRow;
                  profilesUpdated++;
                  changed = true;
                }
              }
            }
          }

          // 5. 合并 facts 行（同一 id 始终合并保留最大 recall_count 与最晚 last_recalled_at）
          for (final remoteRow in remoteFacts) {
            final id = remoteRow['id'] as String;
            final remoteVer = _parseMemoryRowSyncVersion(
              remoteRow['updated_at'],
              remoteRow['created_at'],
            );
            if (isVersionBlockedByClearedAt(remoteVer)) {
              localSkippedCount++;
              continue;
            }
            final tombKey = 'fact:$id';
            final localTombUtc = localTombstones[tombKey];
            if (localTombUtc != null) {
              if (!LWWUtils.syncVersionBeatsDeletion(remoteVer, localTombUtc)) {
                localSkippedCount++;
                continue;
              }
              await txn.delete(
                AgentMemoryService.tombstonesTable,
                where: 'entity_type = ? AND entity_id = ?',
                whereArgs: <Object?>['fact', id],
              );
              localTombstones.remove(tombKey);
              changed = true;
            }

            final localRow = localFactsById[id];
            if (localRow == null) {
              await txn.insert(
                AgentMemoryService.factsTable,
                remoteRow,
                conflictAlgorithm: ConflictAlgorithm.replace,
              );
              localFactsById[id] = remoteRow;
              factsAdded++;
              changed = true;
            } else {
              final localVer = _parseMemoryRowSyncVersion(
                localRow['updated_at'],
                localRow['created_at'],
              );
              final localRecall =
                  _parseMemoryOptionalInt(localRow['recall_count']) ?? 0;
              final remoteRecall =
                  _parseMemoryOptionalInt(remoteRow['recall_count']) ?? 0;
              final mergedRecall = math.max(localRecall, remoteRecall);
              final mergedLastRecalled = _pickLatestTimestampStr(
                localRow['last_recalled_at'],
                remoteRow['last_recalled_at'],
              );

              final cmpFact = LWWUtils.compareSyncVersions(remoteVer, localVer);
              final remoteWinsContent = cmpFact > 0 ||
                  (cmpFact == 0 &&
                      _compareMemoryCanonicalFields(
                            remoteRow,
                            localRow,
                            _memoryFactTieBreakKeys,
                          ) >
                          0);

              if (remoteWinsContent) {
                final mergedRow = <String, Object?>{
                  ...remoteRow,
                  'recall_count': mergedRecall,
                  'last_recalled_at': mergedLastRecalled,
                };
                final hasDiff = _memoryFactColumnWhitelist.any(
                  (col) => localRow[col] != mergedRow[col],
                );
                if (hasDiff) {
                  await txn.update(
                    AgentMemoryService.factsTable,
                    mergedRow,
                    where: 'id = ?',
                    whereArgs: <Object?>[id],
                  );
                  localFactsById[id] = mergedRow;
                  factsUpdated++;
                  changed = true;
                }
              } else if (mergedRecall != localRecall ||
                  mergedLastRecalled != localRow['last_recalled_at']) {
                await txn.update(
                  AgentMemoryService.factsTable,
                  <String, Object?>{
                    'recall_count': mergedRecall,
                    'last_recalled_at': mergedLastRecalled,
                  },
                  where: 'id = ?',
                  whereArgs: <Object?>[id],
                );
                localFactsById[id] = <String, Object?>{
                  ...localRow,
                  'recall_count': mergedRecall,
                  'last_recalled_at': mergedLastRecalled,
                };
                factsUpdated++;
                changed = true;
              }
            }
          }

          // 6. 合并 recent_slices 行
          for (final remoteRow in remoteSlices) {
            final id = remoteRow['id'] as String;
            final remoteVer =
                _parseMemoryRowSyncVersion(remoteRow['observed_at'], null);
            if (isVersionBlockedByClearedAt(remoteVer)) {
              localSkippedCount++;
              continue;
            }
            final tombKey = 'slice:$id';
            final localTombUtc = localTombstones[tombKey];
            if (localTombUtc != null) {
              if (!LWWUtils.syncVersionBeatsDeletion(remoteVer, localTombUtc)) {
                localSkippedCount++;
                continue;
              }
              await txn.delete(
                AgentMemoryService.tombstonesTable,
                where: 'entity_type = ? AND entity_id = ?',
                whereArgs: <Object?>['slice', id],
              );
              localTombstones.remove(tombKey);
              changed = true;
            }

            final localRow = localSlicesById[id];
            if (localRow == null) {
              await txn.insert(
                AgentMemoryService.recentSliceTable,
                remoteRow,
                conflictAlgorithm: ConflictAlgorithm.replace,
              );
              localSlicesById[id] = remoteRow;
              slicesAdded++;
              changed = true;
            } else {
              final localVer =
                  _parseMemoryRowSyncVersion(localRow['observed_at'], null);
              final cmpSlice = LWWUtils.compareSyncVersions(
                remoteVer,
                localVer,
              );
              final remoteWins = cmpSlice > 0 ||
                  (cmpSlice == 0 &&
                      _compareMemorySliceOnSameObservedAt(remoteRow, localRow) >
                          0);
              if (remoteWins) {
                final hasDiff = _memorySliceColumnWhitelist.any(
                  (col) => localRow[col] != remoteRow[col],
                );
                if (hasDiff) {
                  await txn.update(
                    AgentMemoryService.recentSliceTable,
                    remoteRow,
                    where: 'id = ?',
                    whereArgs: <Object?>[id],
                  );
                  localSlicesById[id] = remoteRow;
                  slicesUpdated++;
                  changed = true;
                }
              }
            }
          }

          // 7. 同一事务内执行全量候选集确定性收敛（不改写 updated_at）
          final profileConv = await _convergeProfilesInTxn(
            txn,
            includeSupersededCandidates: true,
            isBasisCovered: hasBasisChecker ? syncCheckCovered : null,
          );
          if (profileConv.didMutate) {
            changed = true;
          }
          bothUncoveredDreamingConflict =
              profileConv.bothUncoveredDreamingConflict;

          final factsDeduped = await _dedupAndTrimFactsInTxn(txn);
          if (factsDeduped > 0) {
            changed = true;
          }
        });
      } catch (error, stackTrace) {
        _reportDatabaseError('mergeMemorySection', error, stackTrace);
        rethrow;
      }

      // 8. 同步 Dreaming 时间戳（严格处理 cleared_at 重置、双漏看重做与看全沿用）
      if (bothUncoveredDreamingConflict) {
        await _settingsService.setLastDreamingAt(null);
        await _clearDreamingMeta();
      } else {
        if (effectiveClearedAtUtc != null) {
          final currentLastDreamingUtc =
              _settingsService.lastDreamingAt?.toUtc();
          if (currentLastDreamingUtc != null &&
              !currentLastDreamingUtc.isAfter(effectiveClearedAtUtc!)) {
            await _settingsService.setLastDreamingAt(null);
            await _clearDreamingMeta();
          }
        }

        final candidateRemoteRunUtc = remoteDreamingLastRunUtc;
        final clearedUtcSnapshot = effectiveClearedAtUtc;
        if (candidateRemoteRunUtc != null &&
            (clearedUtcSnapshot == null ||
                candidateRemoteRunUtc.isAfter(clearedUtcSnapshot)) &&
            hasBasisChecker &&
            syncCheckCovered(
              remoteDreamingWatermark,
              remoteDreamingNoteCount,
            )) {
          final localLastDreamingUtc = _settingsService.lastDreamingAt?.toUtc();
          if (localLastDreamingUtc == null ||
              candidateRemoteRunUtc.isAfter(localLastDreamingUtc)) {
            await _settingsService.setLastDreamingAt(candidateRemoteRunUtc);
            await recordDreamingRun(
              runAt: candidateRemoteRunUtc,
              basisWatermark: remoteDreamingWatermark,
              basisNoteCount: remoteDreamingNoteCount,
            );
          }
        }
      }

      if (changed) {
        _activeProfileCache = null;
        await activeIdentityAliases();
        _settingsService.refreshIdentityAliases();
        _notifySyncListeners();
      }

      return MemoryMergeStats(
        profilesAdded: profilesAdded,
        profilesUpdated: profilesUpdated,
        profilesDeleted: profilesDeleted,
        factsAdded: factsAdded,
        factsUpdated: factsUpdated,
        factsDeleted: factsDeleted,
        slicesAdded: slicesAdded,
        slicesUpdated: slicesUpdated,
        slicesDeleted: slicesDeleted,
        skippedCount: localSkippedCount,
      );
    });
  }

  /// 覆盖恢复 `agent_memory` 段。
  ///
  /// 顶层或内部容器结构损坏时立即抛出 [FormatException] 且不触碰本地现有数据；
  /// 包中无 `agent_memory` 段或本机记忆开关关闭时保持本地原数据不动。
  Future<void> restoreMemorySection(Object? rawSection) async {
    if (rawSection == null) {
      return;
    }
    if (rawSection is! Map) {
      throw const FormatException('Invalid agent_memory backup section');
    }
    _validateMemorySectionContainers(rawSection);

    if (!isEnabled) {
      return;
    }
    final startGeneration = captureGeneration;

    final profilesById = <String, Map<String, Object?>>{};
    final rawProfiles = rawSection['profile'];
    if (rawProfiles is List) {
      for (final item in rawProfiles) {
        final sanitized = _sanitizeMemoryProfileRow(item);
        if (sanitized == null) continue;
        final id = sanitized['id'] as String;
        final existing = profilesById[id];
        if (existing == null) {
          profilesById[id] = sanitized;
        } else {
          final candVer = _parseMemoryRowSyncVersion(
            sanitized['updated_at'],
            sanitized['observed_at'],
          );
          final existVer = _parseMemoryRowSyncVersion(
            existing['updated_at'],
            existing['observed_at'],
          );
          final cmp = LWWUtils.compareSyncVersions(candVer, existVer);
          if (cmp > 0 ||
              (cmp == 0 &&
                  _compareMemoryCanonicalFields(
                        sanitized,
                        existing,
                        _memoryProfileTieBreakKeys,
                      ) >
                      0)) {
            profilesById[id] = sanitized;
          }
        }
      }
    }
    final profiles = profilesById.values.toList(growable: false);

    final factsById = <String, Map<String, Object?>>{};
    final rawFacts = rawSection['facts'];
    if (rawFacts is List) {
      for (final item in rawFacts) {
        final sanitized = _sanitizeMemoryFactRow(item);
        if (sanitized == null) continue;
        final id = sanitized['id'] as String;
        final existing = factsById[id];
        if (existing == null) {
          factsById[id] = sanitized;
        } else {
          final candVer = _parseMemoryRowSyncVersion(
            sanitized['updated_at'],
            sanitized['created_at'],
          );
          final existVer = _parseMemoryRowSyncVersion(
            existing['updated_at'],
            existing['created_at'],
          );
          final cmp = LWWUtils.compareSyncVersions(candVer, existVer);
          if (cmp > 0 ||
              (cmp == 0 &&
                  _compareMemoryCanonicalFields(
                        sanitized,
                        existing,
                        _memoryFactTieBreakKeys,
                      ) >
                      0)) {
            factsById[id] = sanitized;
          }
        }
      }
    }
    final facts = factsById.values.toList(growable: false);

    final slicesById = <String, Map<String, Object?>>{};
    final rawSlices = rawSection['recent_slices'];
    if (rawSlices is List) {
      for (final item in rawSlices) {
        final sanitized = _sanitizeMemorySliceRow(item);
        if (sanitized == null) continue;
        final id = sanitized['id'] as String;
        final existing = slicesById[id];
        if (existing == null) {
          slicesById[id] = sanitized;
        } else {
          final candVer = _parseMemoryRowSyncVersion(
            sanitized['observed_at'],
            null,
          );
          final existVer = _parseMemoryRowSyncVersion(
            existing['observed_at'],
            null,
          );
          final cmp = LWWUtils.compareSyncVersions(candVer, existVer);
          if (cmp > 0 ||
              (cmp == 0 &&
                  _compareMemorySliceOnSameObservedAt(sanitized, existing) >
                      0)) {
            slicesById[id] = sanitized;
          }
        }
      }
    }
    final slices = slicesById.values.toList(growable: false);

    final tombstonesByKey = <String, _ParsedMemoryTombstone>{};
    final rawTombstones = rawSection['tombstones'];
    if (rawTombstones is List) {
      for (final item in rawTombstones) {
        final sanitized = _sanitizeMemoryTombstone(item);
        if (sanitized == null) continue;
        final key = '${sanitized.entityType}:${sanitized.entityId}';
        final existing = tombstonesByKey[key];
        if (existing == null ||
            sanitized.deletedAtUtc.isAfter(existing.deletedAtUtc)) {
          tombstonesByKey[key] = sanitized;
        }
      }
    }
    final tombstones = tombstonesByKey.values.toList(growable: false);

    final clearedAtUtc = _tryParseMemoryUtc(rawSection['cleared_at']);

    DateTime? dreamingLastRunUtc;
    String? dreamingWatermark;
    int? dreamingNoteCount;
    final hasDreamingKey = rawSection.containsKey('dreaming');
    final rawDreaming = rawSection['dreaming'];
    if (rawDreaming is Map) {
      dreamingLastRunUtc = _tryParseMemoryUtc(rawDreaming['last_run_at']);
      dreamingWatermark =
          _tryParseMemoryUtc(rawDreaming['basis_watermark'])?.toIso8601String();
      final cnt = _parseMemoryOptionalInt(rawDreaming['basis_note_count']);
      if (cnt != null && cnt >= 0) {
        dreamingNoteCount = cnt;
      }
    }

    final db = await _db;
    await _settingsService.withAgentMemoryPolicy<void>(() async {
      if (!isCaptureCurrent(startGeneration)) {
        return;
      }

      try {
        await db.transaction((txn) async {
          await txn.delete(AgentMemoryService.profileTable);
          await txn.delete(AgentMemoryService.factsTable);
          await txn.delete(AgentMemoryService.recentSliceTable);
          await txn.delete(AgentMemoryService.tombstonesTable);
          await txn.delete(AgentMemoryService.metaTable);

          for (final row in profiles) {
            await txn.insert(
              AgentMemoryService.profileTable,
              row,
              conflictAlgorithm: ConflictAlgorithm.replace,
            );
          }
          for (final row in facts) {
            await txn.insert(
              AgentMemoryService.factsTable,
              row,
              conflictAlgorithm: ConflictAlgorithm.replace,
            );
          }
          for (final row in slices) {
            await txn.insert(
              AgentMemoryService.recentSliceTable,
              row,
              conflictAlgorithm: ConflictAlgorithm.replace,
            );
          }
          for (final tomb in tombstones) {
            await txn.insert(
              AgentMemoryService.tombstonesTable,
              <String, Object?>{
                'entity_type': tomb.entityType,
                'entity_id': tomb.entityId,
                'deleted_at': tomb.deletedAtRaw,
              },
              conflictAlgorithm: ConflictAlgorithm.replace,
            );
          }

          if (clearedAtUtc != null) {
            await txn.insert(
              AgentMemoryService.metaTable,
              <String, Object?>{
                'key': AgentMemoryService.metaClearedAtKey,
                'value': LWWUtils.formatFixedUtcIso(clearedAtUtc),
              },
              conflictAlgorithm: ConflictAlgorithm.replace,
            );
          }

          if (dreamingLastRunUtc != null) {
            await txn.insert(
              AgentMemoryService.metaTable,
              <String, Object?>{
                'key': AgentMemoryService.metaDreamingLastRunAtKey,
                'value': LWWUtils.formatFixedUtcIso(dreamingLastRunUtc),
              },
              conflictAlgorithm: ConflictAlgorithm.replace,
            );
            if (dreamingWatermark != null) {
              await txn.insert(
                AgentMemoryService.metaTable,
                <String, Object?>{
                  'key': AgentMemoryService.metaDreamingBasisWatermarkKey,
                  'value': dreamingWatermark,
                },
                conflictAlgorithm: ConflictAlgorithm.replace,
              );
            }
            if (dreamingNoteCount != null) {
              await txn.insert(
                AgentMemoryService.metaTable,
                <String, Object?>{
                  'key': AgentMemoryService.metaDreamingBasisNoteCountKey,
                  'value': dreamingNoteCount.toString(),
                },
                conflictAlgorithm: ConflictAlgorithm.replace,
              );
            }
          }
        });
      } catch (error, stackTrace) {
        _reportDatabaseError('restoreMemorySection', error, stackTrace);
        rethrow;
      }

      if (hasDreamingKey) {
        await _settingsService.setLastDreamingAt(dreamingLastRunUtc);
      }

      _activeProfileCache = null;
      await activeIdentityAliases();
      _settingsService.refreshIdentityAliases();
      _notifySyncListeners();
    });
  }
}
