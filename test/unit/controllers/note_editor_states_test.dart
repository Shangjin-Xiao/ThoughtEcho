import 'package:flutter_quill/flutter_quill.dart' as quill;
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

    test('provides and disposes scrollController and focusNode', () {
      final state = NoteEditorState(
        initialPlainText: '',
        initialDeltaContent: null,
        draftStorageKey: 'test_key',
        restoredFromDraft: false,
      );

      final scrollController = state.scrollController;
      final focusNode = state.focusNode;

      expect(scrollController, isNotNull);
      expect(focusNode, isNotNull);
      expect(focusNode.hasFocus, isFalse);

      state.dispose();

      expect(() => scrollController.addListener(() {}), throwsFlutterError);
      expect(() => focusNode.addListener(() {}), throwsFlutterError);
    });

    test('replaceController handles identical, migration, and listener cleanup',
        () {
      final state = NoteEditorState(
        initialPlainText: 'hello',
        initialDeltaContent: null,
        draftStorageKey: 'test_key',
        restoredFromDraft: true,
      );

      final oldController = state.controller;
      var notifyCount = 0;
      state.addListener(() => notifyCount++);

      var draftChangeCount = 0;
      state.setDraftChangeListener(() {
        draftChangeCount++;
      });

      // Replacing with identical controller should return early without notifying
      state.replaceController(oldController);
      expect(notifyCount, 0);

      // Replacing with a new controller
      final newController = quill.QuillController.basic();
      state.replaceController(newController);

      expect(notifyCount, 1);
      expect(state.controller, equals(newController));

      // Check draftChangeListener is attached to new controller
      newController.replaceText(0, 0, 'a', null);
      expect(draftChangeCount, greaterThan(0));

      // Mark draft saved
      expect(state.restoredFromDraft, isTrue);
      state.markDraftSaved();
      expect(state.restoredFromDraft, isFalse);

      state.dispose();
    });

    test('cancelDraftSave cancels pending timer', () async {
      final state = NoteEditorState(
        initialPlainText: '',
        initialDeltaContent: null,
        draftStorageKey: 'key',
        restoredFromDraft: false,
      )..setDraftLoaded(true);

      var saved = false;
      state.scheduleDraftSave(
        const Duration(milliseconds: 50),
        () async {
          saved = true;
        },
      );

      state.cancelDraftSave();
      await Future<void>.delayed(const Duration(milliseconds: 70));
      expect(saved, isFalse);

      state.dispose();
    });

    test('setters update flags and notify listeners when changed', () {
      final state = NoteEditorState(
        initialPlainText: '',
        initialDeltaContent: null,
        draftStorageKey: 'key',
        restoredFromDraft: false,
      );

      var notifyCount = 0;
      state.addListener(() => notifyCount++);

      state.isLoadingFullQuote = true;
      expect(state.isLoadingFullQuote, isTrue);
      expect(notifyCount, 1);

      // Same value should not notify
      state.isLoadingFullQuote = true;
      expect(notifyCount, 1);

      state.richTextLoadFailed = true;
      expect(state.richTextLoadFailed, isTrue);
      expect(notifyCount, 2);

      state.richTextLoadFailed = true;
      expect(notifyCount, 2);

      final quote = Quote(content: 'test', date: '2026-01-01');
      state.fullInitialQuote = quote;
      expect(state.fullInitialQuote, equals(quote));

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

    test('unchanged location and weather do not notify listeners', () {
      final state = NoteEditorMetadataState();
      var notifications = 0;
      state.addListener(() => notifications++);

      state
        ..updateLocation(
          location: 'Beijing',
          latitude: 39.9042,
          longitude: 116.4074,
          poiName: 'Dongcheng',
          show: true,
        )
        ..updateWeather(
          weather: 'sunny',
          temperature: '26°C',
          show: true,
        );
      expect(notifications, 2);

      notifications = 0;
      state
        ..updateLocation(
          location: 'Beijing',
          latitude: 39.9042,
          longitude: 116.4074,
          poiName: 'Dongcheng',
          show: true,
        )
        ..updateWeather(
          weather: 'sunny',
          temperature: '26°C',
          show: true,
        );

      expect(notifications, 0);

      state.updateWeather(
        weather: 'cloudy',
        temperature: '26°C',
        show: true,
      );
      expect(notifications, 1);
      state.dispose();
    });

    test('tag manipulation via toggleTag and removeTag works correctly', () {
      final state = NoteEditorMetadataState();
      var notifications = 0;
      state.addListener(() => notifications++);

      state.toggleTag('tag-1', selected: true);
      expect(state.selectedTagIds, equals(['tag-1']));
      expect(notifications, 1);

      // Adding duplicate does not trigger unnecessary state changes
      state.toggleTag('tag-1', selected: true);
      expect(notifications, 1);

      state.toggleTag('tag-2', selected: true);
      expect(state.selectedTagIds, equals(['tag-1', 'tag-2']));
      expect(notifications, 2);

      state.removeTag('tag-1');
      expect(state.selectedTagIds, equals(['tag-2']));
      expect(notifications, 3);

      state.dispose();
    });

    test('setAuthor, setWork, color, and tag search query update state', () {
      final state = NoteEditorMetadataState();
      var notifications = 0;
      state.addListener(() => notifications++);

      state.setAuthor('Author A');
      expect(state.author, 'Author A');
      expect(notifications, 1);

      // Same author -> no notify
      state.setAuthor('Author A');
      expect(notifications, 1);

      state.setWork('Work W');
      expect(state.work, 'Work W');
      expect(notifications, 2);

      state.selectedColorHex = '#FF0000';
      expect(state.selectedColorHex, '#FF0000');
      expect(notifications, 3);

      state.tagSearchQuery = 'query';
      expect(state.tagSearchQuery, 'query');
      expect(notifications, 4);

      state.dispose();
    });

    test('location/weather setters and original location properties', () {
      final state = NoteEditorMetadataState();

      state.location = 'Shanghai';
      state.latitude = 31.2304;
      state.longitude = 121.4737;
      state.poiName = 'Huangpu';
      state.showLocation = true;

      expect(state.location, 'Shanghai');
      expect(state.latitude, 31.2304);
      expect(state.longitude, 121.4737);
      expect(state.poiName, 'Huangpu');
      expect(state.showLocation, isTrue);

      state.weather = 'rainy';
      state.temperature = '20°C';
      state.showWeather = true;

      expect(state.weather, 'rainy');
      expect(state.temperature, '20°C');
      expect(state.showWeather, isTrue);

      state.originalLocation = 'Original City';
      state.originalLatitude = 10.0;
      state.originalLongitude = 20.0;

      expect(state.originalLocation, 'Original City');
      expect(state.originalLatitude, 10.0);
      expect(state.originalLongitude, 20.0);

      state.dispose();
    });

    test(
        'hydrateAiAnalysisIfUnchanged updates analysis only if unchanged from snapshot',
        () {
      final state = NoteEditorMetadataState(
        initialQuote: Quote(
          content: 'text',
          date: '2026-01-01',
          aiAnalysis: 'Initial Analysis',
        ),
      );

      // When analysis is unchanged from snapshot, hydration succeeds
      state.hydrateAiAnalysisIfUnchanged('Updated Analysis');
      expect(state.currentAiAnalysis, 'Updated Analysis');

      // Now user manually modifies AI analysis
      state.currentAiAnalysis = 'User Modified Analysis';

      // Attempt to hydrate again with another value -> should be ignored because current != initial snapshot
      state.hydrateAiAnalysisIfUnchanged('Third Analysis');
      expect(state.currentAiAnalysis, 'User Modified Analysis');

      state.dispose();
    });

    test(
        'hasChanges checks author, work, color, AI analysis and location/weather',
        () {
      final state = NoteEditorMetadataState(
        initialQuote: Quote(
          content: 'text',
          date: '2026-01-01',
          sourceAuthor: 'Author',
          sourceWork: 'Work',
          colorHex: '#123456',
          location: 'City',
          latitude: 1.0,
          longitude: 2.0,
          poiName: 'POI',
          weather: 'Sunny',
          temperature: '25C',
          aiAnalysis: 'AI',
        ),
      );

      expect(state.hasChanges(isExistingNote: true), isFalse);

      state.setWork('New Work');
      expect(state.hasChanges(isExistingNote: true), isTrue);
      state.setWork('Work');
      expect(state.hasChanges(isExistingNote: true), isFalse);

      state.selectedColorHex = '#654321';
      expect(state.hasChanges(isExistingNote: true), isTrue);
      state.selectedColorHex = '#123456';

      state.currentAiAnalysis = 'New AI';
      expect(state.hasChanges(isExistingNote: true), isTrue);
      state.currentAiAnalysis = 'AI';

      // For existing notes, location changes flag hasChanges
      state.location = 'New City';
      expect(state.hasChanges(isExistingNote: true), isTrue);
      // For new notes (isExistingNote: false), location changes don't flag hasChanges
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
      expect(state.didSaveSuccessfully, isTrue);
    });

    test('duplicate imported media does not notify listeners', () {
      final state = NoteEditorMediaState();
      var notifications = 0;
      state.addListener(() => notifications++);

      state.recordImportedMedia('/path/1.png');
      expect(notifications, 1);

      state.recordImportedMedia('/path/1.png');
      expect(notifications, 1);

      expect(state.sessionImportedMedia, equals({'/path/1.png'}));
    });

    test('save lifecycle state updates and resetAfterFailure', () {
      final state = NoteEditorMediaState();
      var notifications = 0;
      state.addListener(() => notifications++);

      state.isSaving = true;
      expect(notifications, 1);

      // Same setting shouldn't notify
      state.isSaving = true;
      expect(notifications, 1);

      state.saveStatus = 'saving...';
      expect(state.saveStatus, 'saving...');
      expect(notifications, 2);

      state.updateSaveProgress(-0.5);
      expect(state.saveProgress, 0.0);

      state.resetSaveAfterFailure();
      expect(state.isSaving, isFalse);
      expect(state.saveProgress, 0.0);

      state.finishSave();
      expect(state.isSaving, isFalse);
      expect(state.saveProgress, 1.0);
    });
  });
}
