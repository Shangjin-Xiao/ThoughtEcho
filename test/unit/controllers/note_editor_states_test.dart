import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/controllers/note_editor_states.dart';
import 'package:thoughtecho/models/quote_model.dart';

void main() {
  group('NoteEditorState', () {
    test('draft scheduling is gated by loaded state and coalesces changes',
        () async {
      final state = NoteEditorState(
        initialPlainText: '',
        initialDeltaContent: null,
        draftStorageKey: 'new_note_1',
        restoredFromDraft: false,
      );
      var saves = 0;

      state.scheduleDraftSave(
        const Duration(milliseconds: 5),
        () async => saves++,
      );
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(saves, 0);

      state
        ..setDraftLoaded(true)
        ..scheduleDraftSave(
          const Duration(milliseconds: 20),
          () async => saves++,
        )
        ..scheduleDraftSave(
          const Duration(milliseconds: 5),
          () async => saves++,
        );
      await Future<void>.delayed(const Duration(milliseconds: 15));

      expect(saves, 1);
      state.dispose();
    });
  });

  group('NoteEditorMetadataState', () {
    test('metadata snapshot compares tags as a selection, not by order', () {
      final state = NoteEditorMetadataState(
        initialQuote: Quote(
          content: 'note',
          date: DateTime(2026).toIso8601String(),
          sourceAuthor: 'author',
          tagIds: const ['tag-1', 'tag-2'],
        ),
      );

      state.setSelectedTagIds(const ['tag-2', 'tag-1']);

      expect(state.hasChanges(isExistingNote: true), isFalse);
      state.setAuthor('changed');
      expect(state.hasChanges(isExistingNote: true), isTrue);
      state.dispose();
    });

    test('automatic location on a new note does not make metadata dirty', () {
      final state = NoteEditorMetadataState();

      state.updateLocation(
        location: 'Beijing',
        latitude: 39.9042,
        longitude: 116.4074,
        show: true,
      );

      expect(state.hasChanges(isExistingNote: false), isFalse);
      state.dispose();
    });

    test('page defaults become the clean baseline after initialization', () {
      final state = NoteEditorMetadataState()
        ..setAuthor('default author')
        ..setSelectedTagIds(const ['default-tag'])
        ..captureInitialSnapshot();

      expect(state.hasChanges(isExistingNote: false), isFalse);
      state.dispose();
    });
  });

  group('NoteEditorMediaState', () {
    test('owns imported media and clamped save progress', () {
      final state = NoteEditorMediaState();

      state
        ..recordImportedMedia('/tmp/image.png')
        ..beginSave(status: 'preparing')
        ..updateSaveProgress(1.5, status: 'done');

      expect(state.unsavedImportedMedia, const {'/tmp/image.png'});
      expect(state.isSaving, isTrue);
      expect(state.saveProgress, 1);
      expect(state.saveStatus, 'done');

      state.markSavedSuccessfully();
      expect(state.unsavedImportedMedia, isEmpty);
    });
  });
}
