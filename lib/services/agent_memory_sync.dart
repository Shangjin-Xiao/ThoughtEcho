part of 'agent_memory_service.dart';

/// 判定某轮 Dreaming 记录的 `(basisWatermark, basisNoteCount)` 在合并后的本地主库上是否“看全了”。
typedef AgentMemoryBasisChecker = Future<bool> Function(
  String? basisWatermark,
  int? basisNoteCount,
);

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

DateTime? _tryParseMemoryUtc(Object? raw) {
  if (raw is! String) return null;
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return null;
  return DateTime.tryParse(trimmed)?.toUtc();
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

DateTime _parseMemoryRowVersionUtc(Object? primary, Object? fallback) {
  return _tryParseMemoryUtc(primary) ??
      _tryParseMemoryUtc(fallback) ??
      DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
}

String? _sanitizeEncodedNoteIds(Object? raw,
    {required bool rejectInvalidType}) {
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
  final observedStr = (observedRaw as String).trim();

  final updatedRaw = item['updated_at'];
  final updatedUtc = _tryParseMemoryUtc(updatedRaw);
  if (updatedRaw != null &&
      updatedRaw.toString().trim().isNotEmpty &&
      updatedUtc == null) {
    return null;
  }
  final updatedStr = (updatedUtc ?? observedUtc).toIso8601String();

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

  final replacesId = optionalCleanStr(item['replaces_id'], allowAny: false);
  if (replacesId == '\u0000') return null;

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
  final createdStr = (createdRaw as String).trim();

  final updatedRaw = item['updated_at'];
  final updatedUtc = _tryParseMemoryUtc(updatedRaw);
  if (updatedRaw != null &&
      updatedRaw.toString().trim().isNotEmpty &&
      updatedUtc == null) {
    return null;
  }
  final updatedStr = (updatedUtc ?? createdUtc).toIso8601String();

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
      if (_tryParseMemoryUtc(trimmedRecalled) == null) return null;
      lastRecalledAt = trimmedRecalled;
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
  if (_tryParseMemoryUtc(observedRaw) == null) return null;
  final observedStr = (observedRaw as String).trim();

  final expiresRaw = item['expires_at'];
  if (_tryParseMemoryUtc(expiresRaw) == null) return null;
  final expiresStr = (expiresRaw as String).trim();

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
    deletedAtRaw: deletedUtc.toIso8601String(),
    deletedAtUtc: deletedUtc,
  );
}

Map<String, Object?> _exportWhitelistedProfile(Map<String, Object?> raw) {
  final row = <String, Object?>{
    for (final col in _memoryProfileColumnWhitelist) col: raw[col],
  };
  final updated = row['updated_at']?.toString() ?? '';
  if (updated.isEmpty) {
    row['updated_at'] = row['observed_at'] ?? '';
  }
  return row;
}

Map<String, Object?> _exportWhitelistedFact(Map<String, Object?> raw) {
  final row = <String, Object?>{
    for (final col in _memoryFactColumnWhitelist) col: raw[col],
  };
  final updated = row['updated_at']?.toString() ?? '';
  if (updated.isEmpty) {
    row['updated_at'] = row['created_at'] ?? '';
  }
  return row;
}

Map<String, Object?> _exportWhitelistedSlice(Map<String, Object?> raw) {
  return <String, Object?>{
    for (final col in _memorySliceColumnWhitelist) col: raw[col],
  };
}

String? _pickLatestTimestampStr(Object? leftRaw, Object? rightRaw) {
  final leftStr =
      leftRaw is String && leftRaw.trim().isNotEmpty ? leftRaw.trim() : null;
  final rightStr =
      rightRaw is String && rightRaw.trim().isNotEmpty ? rightRaw.trim() : null;
  if (leftStr == null) return rightStr;
  if (rightStr == null) return leftStr;
  final leftUtc = LWWUtils.parseTimestamp(leftStr);
  final rightUtc = LWWUtils.parseTimestamp(rightStr);
  return rightUtc.isAfter(leftUtc) ? rightStr : leftStr;
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

  final leftTime = _parseMemoryRowVersionUtc(
    left['updated_at'],
    left['observed_at'],
  );
  final rightTime = _parseMemoryRowVersionUtc(
    right['updated_at'],
    right['observed_at'],
  );
  final timeCmp = rightTime.compareTo(leftTime);
  if (timeCmp != 0) {
    return timeCmp;
  }

  final leftId = (left['id'] as String?) ?? '';
  final rightId = (right['id'] as String?) ?? '';
  return leftId.compareTo(rightId);
}

Future<({int supersededCount, bool bothUncoveredDreamingConflict})>
    _convergeActiveProfilesInTxn(
  DatabaseExecutor txn, {
  required String nowUtcIso,
  bool Function(String? watermark, int? noteCount)? isBasisCovered,
}) async {
  final activeRows = await txn.query(
    AgentMemoryService.profileTable,
    where: 'status = ?',
    whereArgs: <Object?>[AgentMemoryStatus.active.storageValue],
  );
  if (activeRows.length <= 1) {
    return (supersededCount: 0, bothUncoveredDreamingConflict: false);
  }

  final sorted = List<Map<String, Object?>>.of(activeRows)
    ..sort(
      (a, b) => _compareProfileRowsByWinnerRule(
        a,
        b,
        isBasisCovered: isBasisCovered,
      ),
    );

  final rowById = <String, Map<String, Object?>>{
    for (final row in sorted)
      if (row['id'] is String) row['id'] as String: row,
  };
  final supersededToWinner = <String, Map<String, Object?>>{};

  // 1. 分叉收敛：多个 active 条目的 replaces_id 非空且相同时按赢家规则选唯一赢家。
  final seenReplacesId = <String, Map<String, Object?>>{};
  for (final row in sorted) {
    final id = row['id'] as String?;
    if (id == null || id.isEmpty) continue;
    final replacesId = (row['replaces_id'] as String?)?.trim() ?? '';
    if (replacesId.isEmpty) continue;
    final existingWinner = seenReplacesId[replacesId];
    if (existingWinner != null) {
      supersededToWinner[id] = existingWinner;
    } else {
      seenReplacesId[replacesId] = row;
    }
  }

  // 2. 单活跃类别收敛（taste / voice / style）。
  final singletonKinds = <String>{
    AgentMemoryKind.taste.storageValue,
    AgentMemoryKind.voice.storageValue,
    AgentMemoryKind.style.storageValue,
  };
  final seenSingletonKind = <String, Map<String, Object?>>{};
  for (final row in sorted) {
    final id = row['id'] as String?;
    if (id == null || id.isEmpty || supersededToWinner.containsKey(id)) {
      continue;
    }
    final rawKind = (row['kind'] as String? ?? '').trim();
    if (!singletonKinds.contains(rawKind)) continue;
    final existingWinner = seenSingletonKind[rawKind];
    if (existingWinner != null) {
      supersededToWinner[id] = existingWinner;
    } else {
      seenSingletonKind[rawKind] = row;
    }
  }

  // 3. 身份别名（已确认优先于存疑、同别名唯一）与同 kind + directive 去重。
  final confirmedAliasToWinner = <String, Map<String, Object?>>{};
  for (final row in sorted) {
    final id = row['id'] as String?;
    if (id == null || id.isEmpty || supersededToWinner.containsKey(id)) {
      continue;
    }
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
    final id = row['id'] as String?;
    if (id == null || id.isEmpty || supersededToWinner.containsKey(id)) {
      continue;
    }
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
      supersededToWinner[id] = winner;
    }
  }

  var bothUncoveredDreamingConflict = false;
  for (final entry in supersededToWinner.entries) {
    final loserId = entry.key;
    final winnerRow = entry.value;
    final winnerId = winnerRow['id'] as String;
    final loserRow = rowById[loserId];

    if (isBasisCovered != null &&
        loserRow != null &&
        _isDreamingMemorySource(winnerRow['source']) &&
        _isDreamingMemorySource(loserRow['source'])) {
      final winnerCovered = isBasisCovered(
        winnerRow['basis_watermark'] as String?,
        _parseMemoryOptionalInt(winnerRow['basis_note_count']),
      );
      final loserCovered = isBasisCovered(
        loserRow['basis_watermark'] as String?,
        _parseMemoryOptionalInt(loserRow['basis_note_count']),
      );
      if (!winnerCovered && !loserCovered) {
        bothUncoveredDreamingConflict = true;
      }
    }

    await txn.update(
      AgentMemoryService.profileTable,
      <String, Object?>{
        'status': AgentMemoryStatus.superseded.storageValue,
        'superseded_by': winnerId,
        'updated_at': nowUtcIso,
      },
      where: 'id = ?',
      whereArgs: <Object?>[loserId],
    );

    final sharedReplacesId = (loserRow?['replaces_id'] as String?)?.trim();
    if (sharedReplacesId != null &&
        sharedReplacesId.isNotEmpty &&
        sharedReplacesId == (winnerRow['replaces_id'] as String?)?.trim()) {
      await txn.update(
        AgentMemoryService.profileTable,
        <String, Object?>{
          'superseded_by': winnerId,
          'updated_at': nowUtcIso,
        },
        where: 'id = ? AND status = ?',
        whereArgs: <Object?>[
          sharedReplacesId,
          AgentMemoryStatus.superseded.storageValue,
        ],
      );
    }
  }

  return (
    supersededCount: supersededToWinner.length,
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
        final aCreated = LWWUtils.parseTimestamp(a['created_at'] as String?);
        final bCreated = LWWUtils.parseTimestamp(b['created_at'] as String?);
        final cmp = aCreated.compareTo(bCreated);
        if (cmp != 0) return cmp;
        final aId = (a['id'] as String?) ?? '';
        final bId = (b['id'] as String?) ?? '';
        return aId.compareTo(bId);
      });

      final survivor = group.first;
      final survivorId = survivor['id'] as String;
      var maxRecall = _parseMemoryOptionalInt(survivor['recall_count']) ?? 0;
      String? maxLastRecalled = survivor['last_recalled_at'] as String?;

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
  /// 流式写出 `agent_memory` 同步载荷（不含外层键名 `"agent_memory":`）。
  ///
  /// 调用方应先检查 [isEnabled]；若记忆开关关闭，本方法不写出任何内容。
  Future<void> exportMemorySectionStreaming(
    IOSink sink, {
    CancelToken? cancelToken,
  }) async {
    if (!isEnabled) {
      return;
    }
    final payload = await _buildExportMemoryPayload(cancelToken: cancelToken);
    sink.write(jsonEncode(payload));
  }

  @visibleForTesting
  Future<Map<String, dynamic>?> exportMemorySectionForTesting() async {
    if (!isEnabled) {
      return null;
    }
    return _buildExportMemoryPayload();
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

      final clearedAtRaw = metaMap[AgentMemoryService.metaClearedAtKey];
      final clearedAt =
          (clearedAtRaw != null && _tryParseMemoryUtc(clearedAtRaw) != null)
              ? _tryParseMemoryUtc(clearedAtRaw)!.toIso8601String()
              : null;

      final settingsLastRunUtc = _settingsService.lastDreamingAt?.toUtc();
      Map<String, Object?> dreamingPayload;
      if (settingsLastRunUtc != null) {
        final metaLastRunUtc = _tryParseMemoryUtc(
          metaMap[AgentMemoryService.metaDreamingLastRunAtKey],
        );
        final matchesMeta = metaLastRunUtc != null &&
            metaLastRunUtc.difference(settingsLastRunUtc).inSeconds.abs() <= 1;
        dreamingPayload = <String, Object?>{
          'last_run_at': settingsLastRunUtc.toIso8601String(),
          'basis_watermark': matchesMeta
              ? metaMap[AgentMemoryService.metaDreamingBasisWatermarkKey]
              : null,
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
                'deleted_at': r['deleted_at'],
              },
            )
            .toList(growable: false),
        'cleared_at': clearedAt,
        'dreaming': dreamingPayload,
      };
    });
  }

  /// 将远端 `agent_memory` 段按 LWW + 墓碑 + `cleared_at` 屏障 + 四步收敛合入本地。
  Future<MemoryMergeStats> mergeMemorySection(
    Object? rawSection, {
    AgentMemoryBasisChecker? isBasisCovered,
  }) async {
    if (rawSection == null) {
      return const MemoryMergeStats();
    }
    if (rawSection is! Map) {
      throw const FormatException('Invalid agent_memory section format');
    }
    if (!isEnabled) {
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
    var skippedCount = 0;

    DateTime? remoteClearedAtUtc;
    final rawClearedAt = rawSection['cleared_at'];
    if (rawClearedAt != null) {
      remoteClearedAtUtc = _tryParseMemoryUtc(rawClearedAt);
      if (remoteClearedAtUtc == null) {
        skippedCount++;
      }
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
    } else if (rawDreaming != null) {
      skippedCount++;
    }

    final remoteProfiles = <Map<String, Object?>>[];
    final rawProfiles = rawSection['profile'];
    if (rawProfiles is List) {
      for (final item in rawProfiles) {
        final sanitized = _sanitizeMemoryProfileRow(item);
        if (sanitized == null) {
          skippedCount++;
        } else {
          remoteProfiles.add(sanitized);
        }
      }
    } else if (rawProfiles != null) {
      skippedCount++;
    }

    final remoteFacts = <Map<String, Object?>>[];
    final rawFacts = rawSection['facts'];
    if (rawFacts is List) {
      for (final item in rawFacts) {
        final sanitized = _sanitizeMemoryFactRow(item);
        if (sanitized == null) {
          skippedCount++;
        } else {
          remoteFacts.add(sanitized);
        }
      }
    } else if (rawFacts != null) {
      skippedCount++;
    }

    final remoteSlices = <Map<String, Object?>>[];
    final rawSlices = rawSection['recent_slices'];
    if (rawSlices is List) {
      for (final item in rawSlices) {
        final sanitized = _sanitizeMemorySliceRow(item);
        if (sanitized == null) {
          skippedCount++;
        } else {
          remoteSlices.add(sanitized);
        }
      }
    } else if (rawSlices != null) {
      skippedCount++;
    }

    final remoteTombstones = <_ParsedMemoryTombstone>[];
    final rawTombstones = rawSection['tombstones'];
    if (rawTombstones is List) {
      for (final item in rawTombstones) {
        final sanitized = _sanitizeMemoryTombstone(item);
        if (sanitized == null) {
          skippedCount++;
        } else {
          remoteTombstones.add(sanitized);
        }
      }
    } else if (rawTombstones != null) {
      skippedCount++;
    }

    final db = await _db;

    // 在开启记忆库写事务前，针对主库已完成合并的快照预评估所有 Dreaming 依据对，
    // 避免在 agent_memory.db 事务内跨库异步等待，同时确保收敛比较函数纯同步确定。
    final basisPairs = <(String, int)>{};
    void collectBasis(Object? wmRaw, Object? cntRaw) {
      if (wmRaw is! String) return;
      final wm = wmRaw.trim();
      final cnt = _parseMemoryOptionalInt(cntRaw);
      if (wm.isEmpty || cnt == null || cnt < 0) return;
      if (_tryParseMemoryUtc(wm) == null) return;
      basisPairs.add((wm, cnt));
    }

    if (isBasisCovered != null) {
      final existingActive = await db.query(
        AgentMemoryService.profileTable,
        columns: const <String>[
          'source',
          'basis_watermark',
          'basis_note_count'
        ],
        where: 'status = ?',
        whereArgs: <Object?>[AgentMemoryStatus.active.storageValue],
      );
      for (final row in existingActive) {
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
    if (isBasisCovered != null) {
      for (final pair in basisPairs) {
        coverageCache[pair] = await isBasisCovered(pair.$1, pair.$2);
      }
    }

    bool syncCheckCovered(String? wm, int? cnt) {
      if (wm == null || cnt == null || cnt < 0) return false;
      final trimmed = wm.trim();
      if (trimmed.isEmpty) return false;
      return coverageCache[(trimmed, cnt)] ?? false;
    }

    var changed = false;
    var bothUncoveredDreamingConflict = false;
    DateTime? effectiveClearedAtUtc;
    final nowUtcIso = DateTime.now().toUtc().toIso8601String();

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
          effectiveClearedAtUtc = remoteClearedAtUtc.isAfter(localClearedAtUtc)
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
              'value': remoteCleared.toIso8601String(),
            },
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
          changed = true;

          final localProfRows =
              await txn.query(AgentMemoryService.profileTable);
          for (final row in localProfRows) {
            final rowUtc = _parseMemoryRowVersionUtc(
              row['updated_at'],
              row['observed_at'],
            );
            if (!rowUtc.isAfter(remoteCleared)) {
              await txn.delete(
                AgentMemoryService.profileTable,
                where: 'id = ?',
                whereArgs: <Object?>[row['id']],
              );
              profilesDeleted++;
            }
          }

          final localFactRows = await txn.query(AgentMemoryService.factsTable);
          for (final row in localFactRows) {
            final rowUtc = _parseMemoryRowVersionUtc(
              row['updated_at'],
              row['created_at'],
            );
            if (!rowUtc.isAfter(remoteCleared)) {
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
            final rowUtc = _parseMemoryRowVersionUtc(row['observed_at'], null);
            if (!rowUtc.isAfter(remoteCleared)) {
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
            final delUtc = _parseMemoryRowVersionUtc(row['deleted_at'], null);
            if (!delUtc.isAfter(remoteCleared)) {
              await txn.delete(
                AgentMemoryService.tombstonesTable,
                where: 'entity_type = ? AND entity_id = ?',
                whereArgs: <Object?>[row['entity_type'], row['entity_id']],
              );
            }
          }
        }

        bool isBlockedByClearedAt(DateTime tsUtc) =>
            effectiveClearedAtUtc != null &&
            !tsUtc.isAfter(effectiveClearedAtUtc!);

        // 2. 加载当前本地快照
        final localProfilesById = <String, Map<String, Object?>>{
          for (final r in await txn.query(AgentMemoryService.profileTable))
            if (r['id'] is String) r['id'] as String: r,
        };
        final localFactsById = <String, Map<String, Object?>>{
          for (final r in await txn.query(AgentMemoryService.factsTable))
            if (r['id'] is String) r['id'] as String: r,
        };
        final localSlicesById = <String, Map<String, Object?>>{
          for (final r in await txn.query(AgentMemoryService.recentSliceTable))
            if (r['id'] is String) r['id'] as String: r,
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
              'deleted_at': effective.toIso8601String(),
            },
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
          localTombstones[key] = effective;
          changed = true;
        }

        // 3. 应用远端墓碑
        for (final tomb in remoteTombstones) {
          if (isBlockedByClearedAt(tomb.deletedAtUtc)) {
            skippedCount++;
            continue;
          }
          final key = '${tomb.entityType}:${tomb.entityId}';
          if (tomb.entityType == 'profile') {
            final localRow = localProfilesById[tomb.entityId];
            if (localRow != null) {
              final localUtc = _parseMemoryRowVersionUtc(
                localRow['updated_at'],
                localRow['observed_at'],
              );
              if (!tomb.deletedAtUtc.isBefore(localUtc)) {
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
              final localUtc = _parseMemoryRowVersionUtc(
                localRow['updated_at'],
                localRow['created_at'],
              );
              if (!tomb.deletedAtUtc.isBefore(localUtc)) {
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
              final localUtc =
                  _parseMemoryRowVersionUtc(localRow['observed_at'], null);
              if (!tomb.deletedAtUtc.isBefore(localUtc)) {
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

        // 4. 合并 profile 行
        for (final remoteRow in remoteProfiles) {
          final id = remoteRow['id'] as String;
          final remoteUtc = _parseMemoryRowVersionUtc(
            remoteRow['updated_at'],
            remoteRow['observed_at'],
          );
          if (isBlockedByClearedAt(remoteUtc)) {
            skippedCount++;
            continue;
          }
          final tombKey = 'profile:$id';
          final localTombUtc = localTombstones[tombKey];
          if (localTombUtc != null) {
            if (!remoteUtc.isAfter(localTombUtc)) {
              skippedCount++;
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
            final localUtc = _parseMemoryRowVersionUtc(
              localRow['updated_at'],
              localRow['observed_at'],
            );
            if (remoteUtc.isAfter(localUtc)) {
              await txn.insert(
                AgentMemoryService.profileTable,
                remoteRow,
                conflictAlgorithm: ConflictAlgorithm.replace,
              );
              localProfilesById[id] = remoteRow;
              profilesUpdated++;
              changed = true;
            }
          }
        }

        // 5. 合并 facts 行（同一 id 始终合并保留最大 recall_count 与最晚 last_recalled_at）
        for (final remoteRow in remoteFacts) {
          final id = remoteRow['id'] as String;
          final remoteUtc = _parseMemoryRowVersionUtc(
            remoteRow['updated_at'],
            remoteRow['created_at'],
          );
          if (isBlockedByClearedAt(remoteUtc)) {
            skippedCount++;
            continue;
          }
          final tombKey = 'fact:$id';
          final localTombUtc = localTombstones[tombKey];
          if (localTombUtc != null) {
            if (!remoteUtc.isAfter(localTombUtc)) {
              skippedCount++;
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
            final localUtc = _parseMemoryRowVersionUtc(
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

            if (remoteUtc.isAfter(localUtc)) {
              final mergedRow = <String, Object?>{
                ...remoteRow,
                'recall_count': mergedRecall,
                'last_recalled_at': mergedLastRecalled,
              };
              await txn.insert(
                AgentMemoryService.factsTable,
                mergedRow,
                conflictAlgorithm: ConflictAlgorithm.replace,
              );
              localFactsById[id] = mergedRow;
              factsUpdated++;
              changed = true;
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
          final remoteUtc =
              _parseMemoryRowVersionUtc(remoteRow['observed_at'], null);
          if (isBlockedByClearedAt(remoteUtc)) {
            skippedCount++;
            continue;
          }
          final tombKey = 'slice:$id';
          final localTombUtc = localTombstones[tombKey];
          if (localTombUtc != null) {
            if (!remoteUtc.isAfter(localTombUtc)) {
              skippedCount++;
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
            final localUtc =
                _parseMemoryRowVersionUtc(localRow['observed_at'], null);
            if (remoteUtc.isAfter(localUtc)) {
              await txn.insert(
                AgentMemoryService.recentSliceTable,
                remoteRow,
                conflictAlgorithm: ConflictAlgorithm.replace,
              );
              localSlicesById[id] = remoteRow;
              slicesUpdated++;
              changed = true;
            }
          }
        }

        // 7. 同一事务内执行四步确定性收敛
        final profileConv = await _convergeActiveProfilesInTxn(
          txn,
          nowUtcIso: nowUtcIso,
          isBasisCovered: isBasisCovered != null ? syncCheckCovered : null,
        );
        if (profileConv.supersededCount > 0) {
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

    // 8. 同步 Dreaming 时间戳（严格处理双漏看重做与看全沿用）
    if (bothUncoveredDreamingConflict) {
      await _settingsService.setLastDreamingAt(null);
      await _clearDreamingMeta();
    } else if (remoteDreamingLastRunUtc != null &&
        (effectiveClearedAtUtc == null ||
            remoteDreamingLastRunUtc.isAfter(effectiveClearedAtUtc!)) &&
        isBasisCovered != null &&
        syncCheckCovered(remoteDreamingWatermark, remoteDreamingNoteCount)) {
      final localLastDreamingUtc = _settingsService.lastDreamingAt?.toUtc();
      if (localLastDreamingUtc == null ||
          remoteDreamingLastRunUtc.isAfter(localLastDreamingUtc)) {
        await _settingsService.setLastDreamingAt(remoteDreamingLastRunUtc);
        await recordDreamingRun(
          runAt: remoteDreamingLastRunUtc,
          basisWatermark: remoteDreamingWatermark,
          basisNoteCount: remoteDreamingNoteCount,
        );
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
      skippedCount: skippedCount,
    );
  }

  /// 覆盖恢复 `agent_memory` 段。
  ///
  /// 包中无 `agent_memory` 段或本机记忆开关关闭时保持本地原数据不动。
  Future<void> restoreMemorySection(Object? rawSection) async {
    if (rawSection == null || !isEnabled) {
      return;
    }
    if (rawSection is! Map) {
      throw const FormatException('Invalid agent_memory backup section');
    }

    final profiles = <Map<String, Object?>>[];
    final rawProfiles = rawSection['profile'];
    if (rawProfiles is List) {
      for (final item in rawProfiles) {
        final sanitized = _sanitizeMemoryProfileRow(item);
        if (sanitized != null) {
          profiles.add(sanitized);
        }
      }
    }

    final facts = <Map<String, Object?>>[];
    final rawFacts = rawSection['facts'];
    if (rawFacts is List) {
      for (final item in rawFacts) {
        final sanitized = _sanitizeMemoryFactRow(item);
        if (sanitized != null) {
          facts.add(sanitized);
        }
      }
    }

    final slices = <Map<String, Object?>>[];
    final rawSlices = rawSection['recent_slices'];
    if (rawSlices is List) {
      for (final item in rawSlices) {
        final sanitized = _sanitizeMemorySliceRow(item);
        if (sanitized != null) {
          slices.add(sanitized);
        }
      }
    }

    final tombstones = <_ParsedMemoryTombstone>[];
    final rawTombstones = rawSection['tombstones'];
    if (rawTombstones is List) {
      for (final item in rawTombstones) {
        final sanitized = _sanitizeMemoryTombstone(item);
        if (sanitized != null) {
          tombstones.add(sanitized);
        }
      }
    }

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
              'value': clearedAtUtc.toIso8601String(),
            },
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }

        if (dreamingLastRunUtc != null) {
          await txn.insert(
            AgentMemoryService.metaTable,
            <String, Object?>{
              'key': AgentMemoryService.metaDreamingLastRunAtKey,
              'value': dreamingLastRunUtc.toIso8601String(),
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
  }
}
