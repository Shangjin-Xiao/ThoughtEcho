import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/models/note_proposal_artifact.dart';

void main() {
  test('note proposal artifact is immutable and survives JSON round-trip', () {
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
    );
    sourceOps.first['insert'] = 'mutated';

    final decoded = jsonDecode(jsonEncode(artifact.toJson()));
    final restored = AgentArtifact.fromJson(
      Map<String, Object?>.from(decoded as Map),
    )! as NoteProposalArtifact;

    expect(artifact.documentOps!.first['insert'], 'Draft\n');
    expect(restored.toJson(), artifact.toJson());
    expect(
      () => restored.metadata['author'] = 'Grace',
      throwsUnsupportedError,
    );
    expect(
      () => (restored.metadata['author'] as Map)['value'] = 'Grace',
      throwsUnsupportedError,
    );
  });
}
