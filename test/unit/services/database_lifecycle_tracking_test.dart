import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:thoughtecho/models/quote_model.dart';
import 'package:thoughtecho/services/database_service.dart';
import 'package:thoughtecho/utils/aptabase_helper.dart';

import '../../test_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  group('DatabaseService Lifecycle Tracking Tests', () {
    late DatabaseService service;

    setUp(() async {
      await TestHarness.initialize();
      DatabaseService.clearTestDatabase();
      service = DatabaseService();
      service.reinitialize();
      await service.init();
      final db = await service.safeDatabase;
      await db.delete('quotes');
      await db.delete('quote_tombstones');
      await db.delete('categories');
    });

    tearDown(() async {
      DatabaseService.clearTestDatabase();
      service.reinitialize();
    });

    test(
        'addQuote, updateQuote, deleteQuote, favorite operations execute cleanly',
        () async {
      final id = 'test_track_${DateTime.now().microsecondsSinceEpoch}';
      final note = Quote(
        id: id,
        content: 'Lifecycle Test Content',
        date: DateTime.now().toIso8601String(),
      );

      // Save note (add)
      await service.addQuote(note);

      // Save note (update)
      final updatedNote = note.copyWith(content: 'Updated Content');
      final updateResult = await service.updateQuote(updatedNote);
      expect(updateResult, equals(QuoteUpdateResult.updated));

      // Toggle favorite (increment & reset)
      await service.incrementFavoriteCount(id);
      await service.resetFavoriteCount(id);

      // Delete note
      await service.deleteQuote(id);

      // Permanently delete
      await service.permanentlyDeleteQuote(id);
    });

    test('restoreQuote and emptyTrash trigger telemetry events', () async {
      final events = <Map<String, dynamic>>[];
      AptabaseHelper.onTrackEventForTesting = (eventName, props) {
        events.add({'event': eventName, 'props': props});
      };

      try {
        final id = 'test_restore_${DateTime.now().microsecondsSinceEpoch}';
        final note = Quote(
          id: id,
          content: 'Trash & Restore Content',
          date: DateTime.now().toIso8601String(),
        );
        await service.addQuote(note);
        await service.deleteQuote(id);

        await service.restoreQuote(id);
        expect(
          events.any(
            (e) =>
                e['event'] == 'feature_used' &&
                (e['props'] as Map)['action'] == 'restore_note',
          ),
          isTrue,
        );

        await service.deleteQuote(id);
        await service.emptyTrash();
        expect(
          events.any(
            (e) =>
                e['event'] == 'feature_used' &&
                (e['props'] as Map)['action'] == 'empty_trash',
          ),
          isTrue,
        );
      } finally {
        AptabaseHelper.onTrackEventForTesting = null;
      }
    });

    test('addTag and deleteTag trigger telemetry events', () async {
      final events = <Map<String, dynamic>>[];
      AptabaseHelper.onTrackEventForTesting = (eventName, props) {
        events.add({'event': eventName, 'props': props});
      };

      try {
        await service.addTag('TestTag123');
        expect(
          events.any(
            (e) =>
                e['event'] == 'feature_used' &&
                (e['props'] as Map)['action'] == 'create_tag',
          ),
          isTrue,
        );

        final tags = await service.getTags();
        final createdTag = tags.firstWhere((t) => t.name == 'TestTag123');
        await service.deleteTag(createdTag.id);

        expect(
          events.any(
            (e) =>
                e['event'] == 'feature_used' &&
                (e['props'] as Map)['action'] == 'delete_tag',
          ),
          isTrue,
        );
      } finally {
        AptabaseHelper.onTrackEventForTesting = null;
      }
    });
  });
}
