import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:thoughtecho/models/quote_model.dart';
import 'package:thoughtecho/services/database_service.dart';

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
    });

    test(
        'addQuote, updateQuote, deleteQuote, favorite operations execute cleanly',
        () async {
      final note = Quote(
        id: 'test_track_1',
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
      await service.incrementFavoriteCount('test_track_1');
      await service.resetFavoriteCount('test_track_1');

      // Delete note
      await service.deleteQuote('test_track_1');

      // Permanently delete
      await service.permanentlyDeleteQuote('test_track_1');
    });
  });
}
