import 'dart:collection';

enum NoteDocumentKind { plain, rich }

enum NoteProposalAction { create, edit }

enum NoteModeTransition { plainToRich }

class NoteProposalChange {
  NoteProposalChange({
    required this.type,
    required this.before,
    required this.after,
  });

  final String type;
  final String before;
  final String after;

  factory NoteProposalChange.fromJson(Map<String, Object?> json) =>
      NoteProposalChange(
        type: json['type']?.toString() ?? '',
        before: json['before']?.toString() ?? '',
        after: json['after']?.toString() ?? '',
      );

  Map<String, Object?> toJson() => {
        'type': type,
        'before': before,
        'after': after,
      };
}

sealed class AgentArtifact {
  const AgentArtifact();

  Map<String, Object?> toJson();

  static AgentArtifact? fromJson(Map<String, Object?> json) {
    return switch (json['type']) {
      NoteProposalArtifact.typeName => NoteProposalArtifact.fromJson(json),
      _ => null,
    };
  }
}

class NoteProposalArtifact extends AgentArtifact {
  NoteProposalArtifact({
    required this.action,
    required this.proposalTitle,
    required this.reason,
    required this.resultKind,
    required this.content,
    required List<Map<String, dynamic>>? documentOps,
    required Map<String, Object?> metadata,
    required List<NoteProposalChange> changes,
    this.noteId,
    this.originalKind,
    this.modeTransition,
    this.baseRevision,
    this.readOnly = false,
  })  : documentOps = documentOps == null
            ? null
            : List<Map<String, dynamic>>.unmodifiable(
                documentOps.map(
                  (op) => _freezeMap(op).cast<String, dynamic>(),
                ),
              ),
        metadata = _freezeMap(metadata),
        changes = List<NoteProposalChange>.unmodifiable(changes);

  static const String typeName = 'note_proposal';
  static const int schemaVersion = 1;

  final NoteProposalAction action;
  final String proposalTitle;
  final String reason;
  final String? noteId;
  final NoteDocumentKind? originalKind;
  final NoteDocumentKind resultKind;
  final NoteModeTransition? modeTransition;
  final String content;
  final List<Map<String, dynamic>>? documentOps;
  final Map<String, Object?> metadata;
  final List<NoteProposalChange> changes;
  final String? baseRevision;
  final bool readOnly;

  factory NoteProposalArtifact.fromJson(Map<String, Object?> json) {
    final rawOps = json['document_ops'];
    final rawChanges = json['changes'];
    final rawMetadata = json['metadata'];
    return NoteProposalArtifact(
      action: NoteProposalAction.values.byName(json['action'].toString()),
      proposalTitle: json['proposal_title']?.toString() ?? '',
      reason: json['reason']?.toString() ?? '',
      noteId: json['note_id']?.toString(),
      originalKind: json['original_kind'] == null
          ? null
          : NoteDocumentKind.values.byName(json['original_kind'].toString()),
      resultKind:
          NoteDocumentKind.values.byName(json['result_kind'].toString()),
      modeTransition: json['mode_transition'] == null
          ? null
          : NoteModeTransition.values.byName(
              json['mode_transition'].toString(),
            ),
      content: json['content']?.toString() ?? '',
      documentOps: rawOps is List
          ? rawOps
              .whereType<Map>()
              .map((op) => Map<String, dynamic>.from(op))
              .toList(growable: false)
          : null,
      metadata: rawMetadata is Map
          ? rawMetadata.map((key, value) => MapEntry(key.toString(), value))
          : const <String, Object?>{},
      changes: rawChanges is List
          ? rawChanges
              .whereType<Map>()
              .map((item) => NoteProposalChange.fromJson(
                    item.map((key, value) => MapEntry(key.toString(), value)),
                  ))
              .toList(growable: false)
          : const <NoteProposalChange>[],
      baseRevision: json['base_revision']?.toString(),
      readOnly: json['read_only'] == true,
    );
  }

  @override
  Map<String, Object?> toJson() => {
        'type': typeName,
        'schema_version': schemaVersion,
        'action': action.name,
        'proposal_title': proposalTitle,
        'reason': reason,
        if (noteId != null) 'note_id': noteId,
        if (originalKind != null) 'original_kind': originalKind!.name,
        'result_kind': resultKind.name,
        if (modeTransition != null) 'mode_transition': modeTransition!.name,
        'content': content,
        if (documentOps != null) 'document_ops': documentOps,
        'metadata': metadata,
        'changes': changes.map((change) => change.toJson()).toList(),
        if (baseRevision != null) 'base_revision': baseRevision,
        if (readOnly) 'read_only': true,
      };
}

Map<String, Object?> _freezeMap(Map map) {
  return UnmodifiableMapView({
    for (final entry in map.entries)
      entry.key.toString(): _freezeValue(entry.value),
  });
}

Object? _freezeValue(Object? value) {
  if (value is Map) return _freezeMap(value);
  if (value is List) {
    return List<Object?>.unmodifiable(value.map(_freezeValue));
  }
  return value;
}
