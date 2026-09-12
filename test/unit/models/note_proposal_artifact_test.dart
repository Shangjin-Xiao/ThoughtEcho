import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/models/note_proposal_artifact.dart';

void main() {
  group('NoteProposalChange', () {
    test('toJson and fromJson serialize and deserialize correctly', () {
      final change = NoteProposalChange(
        type: 'insert',
        before: 'old text',
        after: 'new text',
      );

      final json = change.toJson();
      expect(json, {
        'type': 'insert',
        'before': 'old text',
        'after': 'new text',
      });

      final restored = NoteProposalChange.fromJson(json);
      expect(restored.type, 'insert');
      expect(restored.before, 'old text');
      expect(restored.after, 'new text');
    });

    test('fromJson falls back to empty strings when fields are null or missing',
        () {
      final json = <String, Object?>{
        'type': null,
      };

      final change = NoteProposalChange.fromJson(json);
      expect(change.type, '');
      expect(change.before, '');
      expect(change.after, '');
    });
  });

  group('AgentArtifact.fromJson', () {
    test(
        'returns NoteProposalArtifact when type matches NoteProposalArtifact.typeName',
        () {
      final json = <String, Object?>{
        'type': NoteProposalArtifact.typeName,
        'action': 'create',
        'result_kind': 'plain',
      };

      final artifact = AgentArtifact.fromJson(json);
      expect(artifact, isA<NoteProposalArtifact>());
      expect(
          (artifact as NoteProposalArtifact).action, NoteProposalAction.create);
    });

    test('returns null when type is unknown or missing', () {
      expect(AgentArtifact.fromJson({'type': 'unknown_type'}), isNull);
      expect(AgentArtifact.fromJson({}), isNull);
    });
  });

  group('NoteProposalArtifact', () {
    test('survives JSON round-trip with all fields populated', () {
      final sourceOps = <Map<String, dynamic>>[
        {'insert': 'Draft\n'}
      ];
      final artifact = NoteProposalArtifact(
        action: NoteProposalAction.edit,
        proposalTitle: 'Polish',
        reason: 'Clearer',
        noteId: 'note-1',
        originalKind: NoteDocumentKind.plain,
        resultKind: NoteDocumentKind.rich,
        modeTransition: NoteModeTransition.plainToRich,
        content: 'Draft',
        documentOps: sourceOps,
        metadata: const {
          'author': {'action': 'set', 'value': 'Ada'}
        },
        changes: [
          NoteProposalChange(type: 'replace', before: 'Old', after: 'Draft'),
        ],
        baseRevision: 'revision',
        readOnly: true,
      );
      sourceOps.first['insert'] = 'mutated';

      final json = artifact.toJson();
      expect(json['read_only'], true);

      final decoded = jsonDecode(jsonEncode(json));
      final restored = AgentArtifact.fromJson(
        Map<String, Object?>.from(decoded as Map),
      )! as NoteProposalArtifact;

      expect(artifact.documentOps!.first['insert'], 'Draft\n');
      expect(restored.toJson(), artifact.toJson());
      expect(restored.action, NoteProposalAction.edit);
      expect(restored.originalKind, NoteDocumentKind.plain);
      expect(restored.resultKind, NoteDocumentKind.rich);
      expect(restored.modeTransition, NoteModeTransition.plainToRich);
      expect(restored.readOnly, true);
    });

    test('handles minimal json and applies fallback defaults', () {
      final json = <String, Object?>{
        'action': 'create',
        'result_kind': 'plain',
      };

      final artifact = NoteProposalArtifact.fromJson(json);

      expect(artifact.action, NoteProposalAction.create);
      expect(artifact.proposalTitle, '');
      expect(artifact.reason, '');
      expect(artifact.noteId, isNull);
      expect(artifact.originalKind, isNull);
      expect(artifact.resultKind, NoteDocumentKind.plain);
      expect(artifact.modeTransition, isNull);
      expect(artifact.content, '');
      expect(artifact.documentOps, isNull);
      expect(artifact.metadata, isEmpty);
      expect(artifact.changes, isEmpty);
      expect(artifact.baseRevision, isNull);
      expect(artifact.readOnly, false);

      final toJsonResult = artifact.toJson();
      expect(toJsonResult.containsKey('note_id'), false);
      expect(toJsonResult.containsKey('original_kind'), false);
      expect(toJsonResult.containsKey('mode_transition'), false);
      expect(toJsonResult.containsKey('document_ops'), false);
      expect(toJsonResult.containsKey('base_revision'), false);
      expect(toJsonResult.containsKey('read_only'), false);
    });

    test('handles non-standard or malformed input types in json', () {
      final json = <String, Object?>{
        'action': 'create',
        'result_kind': 'rich',
        'document_ops': 'not a list',
        'metadata': 'not a map',
        'changes': 'not a list',
      };

      final artifact = NoteProposalArtifact.fromJson(json);

      expect(artifact.documentOps, isNull);
      expect(artifact.metadata, isEmpty);
      expect(artifact.changes, isEmpty);
    });

    test('enforces deep immutability on documentOps, metadata, and changes',
        () {
      final artifact = NoteProposalArtifact(
        action: NoteProposalAction.create,
        proposalTitle: 'Test',
        reason: 'Reason',
        resultKind: NoteDocumentKind.rich,
        content: 'Content',
        documentOps: [
          {
            'insert': 'Text',
            'attributes': {'bold': true}
          }
        ],
        metadata: {
          'tags': ['a', 'b'],
          'settings': {'active': true}
        },
        changes: [NoteProposalChange(type: 'add', before: '', after: 'Text')],
      );

      expect(
        () => artifact.changes.add(
          NoteProposalChange(type: 'sub', before: 'a', after: 'b'),
        ),
        throwsUnsupportedError,
      );

      expect(
        () => artifact.documentOps!.add({'insert': 'New'}),
        throwsUnsupportedError,
      );

      expect(
        () => (artifact.documentOps!.first['attributes']
            as Map<String, dynamic>)['bold'] = false,
        throwsUnsupportedError,
      );

      expect(
        () => artifact.metadata['tags'] = [],
        throwsUnsupportedError,
      );

      expect(
        () => (artifact.metadata['tags'] as List).add('c'),
        throwsUnsupportedError,
      );

      expect(
        () => (artifact.metadata['settings'] as Map)['active'] = false,
        throwsUnsupportedError,
      );
    });
  });
}
