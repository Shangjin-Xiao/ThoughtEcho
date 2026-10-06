import 'dart:async';

import 'package:flutter/material.dart';
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

      state.replaceController(oldController);
      expect(notifyCount, 0);

      final newController = quill.QuillController.basic();
      state.replaceController(newController);

      expect(notifyCount, 1);
      expect(state.controller, equals(newController));
      expect(oldController.document.documentChangeObserver.isClosed, isTrue);
      expect(
        () => oldController.replaceText(0, 0, 'z', null),
        throwsAssertionError,
      );

      newController.replaceText(0, 0, 'a', null);
      expect(draftChangeCount, greaterThan(0));

      expect(state.restoredFromDraft, isTrue);
      state.markDraftSaved();
      expect(state.restoredFromDraft, isFalse);
      expect(state.isDirty, isFalse);

      state.dispose();
    });

    test('dirty state tracking and document versioning on edit', () async {
      final state = NoteEditorState(
        initialPlainText: 'test',
        initialDeltaContent: null,
        draftStorageKey: 'key_dirty',
        restoredFromDraft: false,
      );

      expect(state.isDirty, isFalse);
      final initialVersion = state.documentVersion;

      state.controller.replaceText(0, 0, 'new content ', null);
      await Future<void>.delayed(Duration.zero);

      expect(state.isDirty, isTrue);
      expect(state.documentVersion, greaterThan(initialVersion));

      state.markDraftSaved();
      expect(state.isDirty, isFalse);

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

    test(
        'sessionGeneration increments on cancelDraftSave, incrementSessionGeneration, and dispose',
        () {
      final state = NoteEditorState(
        initialPlainText: '',
        initialDeltaContent: null,
        draftStorageKey: 'key',
        restoredFromDraft: false,
      );

      expect(state.sessionGeneration, 0);

      state.cancelDraftSave();
      expect(state.sessionGeneration, 1);

      state.incrementSessionGeneration();
      expect(state.sessionGeneration, 2);

      expect(state.isDisposed, isFalse);
      state.dispose();
      expect(state.isDisposed, isTrue);
      expect(state.sessionGeneration, 3);
    });

    test('in-flight draft saves tracking and waitForActiveDraftSaves',
        () async {
      final state = NoteEditorState(
        initialPlainText: '',
        initialDeltaContent: null,
        draftStorageKey: 'key',
        restoredFromDraft: false,
      );

      expect(state.hasActiveDraftSaves, isFalse);

      final completer1 = Completer<void>();
      final completer2 = Completer<void>();

      state.registerInFlightDraftSave(completer1.future);
      state.registerInFlightDraftSave(completer2.future);

      expect(state.hasActiveDraftSaves, isTrue);

      var waited = false;
      final waitFuture = state.waitForActiveDraftSaves().then((_) {
        waited = true;
      });

      expect(waited, isFalse);

      completer1.complete();
      state.unregisterInFlightDraftSave(completer1.future);
      await Future<void>.delayed(Duration.zero);
      expect(waited, isFalse);

      completer2.complete();
      state.unregisterInFlightDraftSave(completer2.future);
      await waitFuture;

      expect(waited, isTrue);
      expect(state.hasActiveDraftSaves, isFalse);

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

    test(
        'replaceController preserves isDirty if state was dirty prior to replacement',
        () {
      final state = NoteEditorState(
        initialPlainText: 'initial',
        initialDeltaContent: null,
        draftStorageKey: 'key_replace_dirty',
        restoredFromDraft: false,
      );

      expect(state.isDirty, isFalse);

      // Simulate user editing before replacement controller is set
      state.markDirty();
      expect(state.isDirty, isTrue);

      final newController = quill.QuillController.basic();
      state.replaceController(newController);

      // Should preserve dirty state
      expect(state.isDirty, isTrue);

      state.dispose();
    });

    test(
        'disposed NoteEditorState ignores markDirty, markClean, markDraftSaved and replaceController calls, and disposes incoming controller',
        () {
      final state = NoteEditorState(
        initialPlainText: 'initial',
        initialDeltaContent: null,
        draftStorageKey: 'key_dispose_safe',
        restoredFromDraft: false,
      );

      var notified = false;
      state.addListener(() => notified = true);

      state.dispose();

      expect(state.isDisposed, isTrue);

      // Subsequent mutator calls on disposed state should not throw or notify
      expect(() => state.markDirty(), returnsNormally);
      expect(() => state.markClean(), returnsNormally);
      expect(() => state.markDraftSaved(), returnsNormally);
      expect(() => state.setDraftLoaded(true), returnsNormally);
      expect(() => state.setFullQuoteLoading(true), returnsNormally);
      expect(() => state.setFullInitialQuote(Quote(content: 'c', date: 'd')),
          returnsNormally);
      expect(() => state.setRichTextLoadFailed(true), returnsNormally);
      expect(() => state.cancelDraftSave(), returnsNormally);
      expect(() => state.incrementSessionGeneration(), returnsNormally);

      expect(notified, isFalse);

      // replaceController on disposed state should dispose incoming controller and not throw
      final incomingController = quill.QuillController.basic();
      expect(
          () => state.replaceController(incomingController), returnsNormally);
      expect(
          incomingController.document.documentChangeObserver.isClosed, isTrue);
    });

    test(
        'replaceController respects markCleanIfUnchanged only if state was clean prior to replacement',
        () {
      final state = NoteEditorState(
        initialPlainText: 'initial',
        initialDeltaContent: null,
        draftStorageKey: 'key_mark_clean_test',
        restoredFromDraft: false,
      );

      expect(state.isDirty, isFalse);

      final controller1 = quill.QuillController.basic();
      state.replaceController(controller1, markCleanIfUnchanged: true);
      expect(state.isDirty, isFalse);

      // Make dirty
      state.markDirty();
      expect(state.isDirty, isTrue);

      // Replace controller with markCleanIfUnchanged: true while dirty
      final controller2 = quill.QuillController.basic();
      state.replaceController(controller2, markCleanIfUnchanged: true);

      // Must remain dirty!
      expect(state.isDirty, isTrue);

      state.dispose();
    });

    test('undo back to saved baseline reverts isDirty to false', () async {
      final doc = quill.Document()..insert(0, 'hello');
      final state = NoteEditorState(
        initialPlainText: 'hello',
        initialDeltaContent: null,
        draftStorageKey: 'test_undo_key',
        restoredFromDraft: false,
      );
      state.replaceController(
        quill.QuillController(
          document: doc,
          selection: const TextSelection.collapsed(offset: 5),
        ),
        markCleanIfUnchanged: true,
      );

      expect(state.isDirty, isFalse);

      // User types text
      state.controller.replaceText(5, 0, ' world', null);
      await Future<void>.delayed(Duration.zero);
      expect(state.isDirty, isTrue);

      // User undoes text back to initial state
      state.controller.replaceText(5, 6, '', null);
      await Future<void>.delayed(Duration.zero);
      expect(state.isDirty, isFalse);

      state.dispose();
    });

    test('window input append preserves rich text formatting and inserts', () {
      final state = NoteEditorState(
        initialPlainText: 'initial text',
        initialDeltaContent: null,
        draftStorageKey: 'test_merge_key',
        restoredFromDraft: false,
      );

      // Simulate user typing formatted rich text during loading window
      state.controller.replaceText(0, 0, 'Window ', null);
      state.controller.formatText(0, 6, quill.Attribute.bold);

      // Loaded document from async DB
      final loadedDoc = quill.Document()..insert(0, 'Loaded content\n');

      final mergedDoc = appendWindowInput(
        loadedDoc: loadedDoc,
        baselineWindowDelta: state.baselineWindowDelta,
        currentWindowDelta: state.controller.document.toDelta(),
        isDirty: state.isDirty,
      );

      expect(mergedDoc.toPlainText().contains('Loaded content'), isTrue);
      expect(mergedDoc.toPlainText().contains('Window '), isTrue);
      expect(
        mergedDoc
            .toDelta()
            .toJson()
            .any((op) => op['attributes']?['bold'] == true),
        isTrue,
      );

      state.dispose();
    });

    test(
        'chunked loading placeholder preserves window typing before and during replacement',
        () {
      final state = NoteEditorState(
        initialPlainText: '',
        initialDeltaContent: null,
        draftStorageKey: 'test_chunked_key',
        restoredFromDraft: false,
      );

      // User types before placeholder arrives
      state.controller.replaceText(0, 0, 'Pre-placeholder text. ', null);

      // Placeholder is created
      const loadingMessage = 'Loading large document...';
      final placeholderDocument = quill.Document()..insert(0, loadingMessage);

      // Merge pre-placeholder text into placeholder doc using production function
      final mergedPlaceholder = appendWindowInput(
        loadedDoc: placeholderDocument,
        baselineWindowDelta: state.baselineWindowDelta,
        currentWindowDelta: state.controller.document.toDelta(),
        isDirty: state.isDirty,
      );

      state.replaceController(
        quill.QuillController(
          document: mergedPlaceholder,
          selection: const TextSelection.collapsed(offset: 0),
        ),
        newBaselineWindowDelta: placeholderDocument.toDelta(),
      );

      // User types while placeholder is shown
      state.controller.replaceText(
        state.controller.document.length - 1,
        0,
        'Typed during placeholder!',
        null,
      );

      // Large document finishes loading
      final largeLoadedDoc = quill.Document()
        ..insert(0, 'Full large document content.\n');

      final finalMergedDoc = appendWindowInput(
        loadedDoc: largeLoadedDoc,
        baselineWindowDelta: state.baselineWindowDelta,
        currentWindowDelta: state.controller.document.toDelta(),
        isDirty: state.isDirty,
        ignorePlaceholder: loadingMessage,
      );

      expect(
        finalMergedDoc.toPlainText().contains('Full large document content.'),
        isTrue,
      );
      expect(
        finalMergedDoc.toPlainText().contains('Pre-placeholder text.'),
        isTrue,
      );
      expect(
        finalMergedDoc.toPlainText().contains('Typed during placeholder!'),
        isTrue,
      );
      expect(finalMergedDoc.toPlainText().contains(loadingMessage), isFalse);

      state.dispose();
    });

    test(
        'async document load with window input reverts to clean state when window input is undone',
        () async {
      final state = NoteEditorState(
        initialPlainText: '',
        initialDeltaContent: null,
        draftStorageKey: 'test_async_undo_key',
        restoredFromDraft: false,
      );

      // User types during async loading window
      state.controller.replaceText(0, 0, 'window input', null);
      await Future<void>.delayed(Duration.zero);
      expect(state.isDirty, isTrue);

      // Async DB load completes with loadedDoc
      final loadedDoc = quill.Document()..insert(0, 'Loaded DB Content\n');
      final loadedDelta = loadedDoc.toDelta();

      final mergedDoc = appendWindowInput(
        loadedDoc: loadedDoc,
        baselineWindowDelta: state.baselineWindowDelta,
        currentWindowDelta: state.controller.document.toDelta(),
        isDirty: state.isDirty,
      );

      // replaceController with mergedDoc and pass loadedDelta as clean baseline
      state.replaceController(
        quill.QuillController(
          document: mergedDoc,
          selection: const TextSelection.collapsed(offset: 0),
        ),
        savedDocumentDelta: loadedDelta,
        markCleanIfUnchanged: true,
      );

      // State is dirty because window input 'window input' was appended
      expect(state.isDirty, isTrue);
      expect(
        state.controller.document.toPlainText().contains('window input'),
        isTrue,
      );

      // User undos 'window input' back to 'Loaded DB Content\n'
      final windowInputPos =
          state.controller.document.toPlainText().indexOf('window input');
      state.controller
          .replaceText(windowInputPos, 'window input'.length, '', null);
      await Future<void>.delayed(Duration.zero);

      // Document now matches loadedDelta, so isDirty reverts to false!
      expect(state.isDirty, isFalse);

      state.dispose();
    });

    test(
        'fast-path length comparison optimizes dirty state checking without delta deserialization',
        () async {
      final doc = quill.Document()..insert(0, 'Original Baseline Content\n');
      final state = NoteEditorState(
        initialPlainText: 'Original Baseline Content',
        initialDeltaContent: null,
        draftStorageKey: 'test_fastpath_key',
        restoredFromDraft: false,
      );
      state.replaceController(
        quill.QuillController(
          document: doc,
          selection: const TextSelection.collapsed(offset: 0),
        ),
        markCleanIfUnchanged: true,
      );

      expect(state.isDirty, isFalse);

      // Typing different length text triggers dirty state
      state.controller.replaceText(0, 0, 'Extra ', null);
      await Future<void>.delayed(Duration.zero);
      expect(state.isDirty, isTrue);

      // Undoing extra text returns to baseline length & content
      state.controller.replaceText(0, 6, '', null);
      await Future<void>.delayed(Duration.zero);
      expect(state.isDirty, isFalse);

      state.dispose();
    });

    test('typing during media file replacement preserves newly typed text',
        () async {
      final doc = quill.Document()..insert(0, 'Text before media\n');
      const tempImagePath = '/tmp/media/temp_123.jpg';
      const permImagePath = '/perm/media/perm_123.jpg';
      doc.insert(doc.length - 1, quill.BlockEmbed.image(tempImagePath));

      final state = NoteEditorState(
        initialPlainText: 'Text before media',
        initialDeltaContent: null,
        draftStorageKey: 'test_media_key',
        restoredFromDraft: false,
      );
      state.replaceController(quill.QuillController(
        document: doc,
        selection: const TextSelection.collapsed(offset: 0),
      ));

      final processedFiles = <String, String>{tempImagePath: permImagePath};

      // User types while media files are being moved asynchronously
      state.controller.replaceText(0, 0, 'Typed during media move! ', null);

      // Media process completes and takes latest delta
      final latestDeltaData = state.controller.document.toDelta().toJson();
      for (final op in latestDeltaData) {
        if (op.containsKey('insert') && op['insert'] is Map) {
          final insertMap = op['insert'] as Map;
          if (insertMap['image'] == tempImagePath) {
            insertMap['image'] = processedFiles[tempImagePath];
          }
        }
      }

      final updatedDoc = quill.Document.fromJson(latestDeltaData);
      state.replaceController(quill.QuillController(
        document: updatedDoc,
        selection: const TextSelection.collapsed(offset: 0),
      ));

      expect(
        state.controller.document
            .toPlainText()
            .contains('Typed during media move!'),
        isTrue,
      );
      expect(
        state.controller.document.toPlainText().contains('Text before media'),
        isTrue,
      );
      final hasPermImage = state.controller.document.toDelta().toJson().any(
            (op) =>
                op['insert'] is Map && op['insert']['image'] == permImagePath,
          );
      expect(hasPermImage, isTrue);

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

      state.hydrateAiAnalysisIfUnchanged('Updated Analysis');
      expect(state.currentAiAnalysis, 'Updated Analysis');

      state.currentAiAnalysis = 'User Modified Analysis';

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

      state.location = 'New City';
      expect(state.hasChanges(isExistingNote: true), isTrue);
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
