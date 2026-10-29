import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:thoughtecho/services/database_service.dart';
import 'package:thoughtecho/services/location_service.dart';
import 'package:thoughtecho/services/mmkv_service.dart';
import 'package:thoughtecho/services/smart_push_service.dart';

import '../../test_harness.dart';

void main() {
  setUpAll(TestHarness.initialize);

  group('Local daily quote cache visibility', () {
    late Database db;
    late DatabaseService databaseService;
    late SmartPushService pushService;
    late _MemoryStorage storage;

    setUp(() async {
      db = await databaseFactory.openDatabase(inMemoryDatabasePath);
      await db.execute('''
        CREATE TABLE quotes (
          id TEXT PRIMARY KEY, content TEXT, is_deleted INTEGER DEFAULT 0
        )
      ''');
      await db.execute('CREATE TABLE categories (id TEXT, name TEXT)');
      await db.execute('CREATE TABLE quote_tags (quote_id TEXT, tag_id TEXT)');
      await db
          .insert('quotes', {'id': 'local-note', 'content': 'Sample quote'});
      DatabaseService.setTestDatabase(db);
      databaseService = DatabaseService.forTesting();
      await databaseService.init();
      storage = _MemoryStorage();
      pushService = SmartPushService(
        databaseService: databaseService,
        locationService: LocationService(),
        mmkvService: storage,
      );
    });

    tearDown(() async {
      pushService.dispose();
      databaseService.dispose();
      if (db.isOpen) await db.close();
      DatabaseService.clearTestDatabase();
    });

    for (final pendingHomeDisplay in [false, true]) {
      Future<Map<String, dynamic>?> readQuote() async {
        if (pendingHomeDisplay) {
          // Simulate the persisted notification handoff through its real reader.
          storage.values['smart_push_pending_home_daily_quote'] =
              storage.values['smart_push_last_daily_quote']!;
          return pushService.consumePendingDailyQuoteForHomeDisplay();
        }
        return pushService.getCachedDailyQuoteForToday();
      }

      for (final change in ['hidden', 'deleted', 'unavailable']) {
        test(
          'rejects $change local note (pending home display: $pendingHomeDisplay)',
          () async {
            final quote = await databaseService.getLocalDailyQuote(
              offlineQuoteSource: 'allNotes',
            );
            expect(quote, isNotNull);
            pushService.cacheDailyQuoteForToday(quote!);
            expect(await readQuote(), containsPair('hitokoto', 'Sample quote'));

            switch (change) {
              case 'hidden':
                await db.insert('quote_tags', {
                  'quote_id': 'local-note',
                  'tag_id': DatabaseService.hiddenTagId,
                });
              case 'deleted':
                await db.update('quotes', {'is_deleted': 1});
              case 'unavailable':
                await db.close();
            }

            expect(await readQuote(), isNull);
          },
        );
      }

      test(
        'rejects legacy local cache without a note ID '
        '(pending home display: $pendingHomeDisplay)',
        () async {
          storage.values['smart_push_last_daily_quote'] = jsonEncode({
            'hitokoto': 'Previously cached protected content',
            'type': 'local',
          });
          storage.values['smart_push_last_daily_quote_date'] =
              DateTime.now().toIso8601String().substring(0, 10);
          expect(await readQuote(), isNull);
        },
      );
    }
  });
}

class _MemoryStorage implements MMKVService {
  final values = <String, String>{};

  @override
  String? getString(String key) => values[key];

  @override
  Future<bool> setString(String key, String value) async {
    values[key] = value;
    return true;
  }

  @override
  Future<bool> remove(String key) async {
    values.remove(key);
    return true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
