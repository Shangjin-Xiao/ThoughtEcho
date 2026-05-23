import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:thoughtecho/services/database_service.dart';
import 'package:uuid/uuid.dart';
import 'package:thoughtecho/models/quote_model.dart';

Future<void> main() async {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  final dbService = DatabaseService();
  await dbService.init();

  // Create test data
  print('Inserting data...');
  final uuid = Uuid();
  final stopwatch = Stopwatch()..start();
  for (int i = 0; i < 50; i++) {
    final quotes = <Quote>[];
    for (int j = 0; j < 100; j++) {
      final quoteId = uuid.v4();
      final q = Quote(
        id: quoteId,
        content: 'Test quote',
        date: DateTime.now().toIso8601String(),
        tagIds: ['tag_1', 'tag_2', 'tag_3'],
      );
      quotes.add(q);
    }
    await dbService.insertQuotesBatch(quotes);
  }
  print('Data inserted. Time taken: ${stopwatch.elapsedMilliseconds} ms');

  stopwatch.reset();

  // Benchmark
  print('Running benchmark for getUserQuotes...');
  for (int i = 0; i < 10; i++) {
     await dbService.getUserQuotes(limit: 500, offset: i * 500);
  }
  print('Benchmark finished. Time taken: ${stopwatch.elapsedMilliseconds} ms');
}
