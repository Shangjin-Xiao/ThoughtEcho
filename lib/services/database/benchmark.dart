import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:thought_echo/services/database/database_service.dart';
import 'package:thought_echo/models/quote.dart';
import 'package:uuid/uuid.dart';

Future<void> main() async {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  final dbService = DatabaseService();
  await dbService.init();

  // Create a lot of quotes
  final uuid = Uuid();
  print('Generating test data...');
  final batch = dbService.database!.batch();
  final tagBatch = dbService.database!.batch();
  for (int i = 0; i < 5000; i++) {
    final quoteId = uuid.v4();
    batch.insert('quotes', {
      'id': quoteId,
      'content': 'Test quote $i',
      'date': DateTime.now().toIso8601String(),
    });
    // Add 3 tags to each quote
    for (int j = 0; j < 3; j++) {
      tagBatch.insert('quote_tags', {
        'quote_id': quoteId,
        'tag_id': 'tag_$j',
      });
    }
  }
  await batch.commit(noResult: true);
  await tagBatch.commit(noResult: true);
  print('Data inserted.');

  // Benchmark
  print('Starting benchmark...');
  final stopwatch = Stopwatch()..start();

  // We need to fetch multiple pages to trigger the N+1 loop efficiently
  for (int i = 0; i < 10; i++) {
    await dbService.getUserQuotes(limit: 500, offset: 0);
  }

  stopwatch.stop();
  print('Time taken: ${stopwatch.elapsedMilliseconds} ms');
}
