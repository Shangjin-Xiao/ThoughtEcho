import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/gen_l10n/app_localizations.dart';
import 'package:thoughtecho/services/api_service.dart';
import 'package:thoughtecho/services/database_service.dart';
import 'package:thoughtecho/utils/http_response.dart';

import '../../test_harness.dart';

class _MockDatabaseServiceSuccess extends DatabaseService {
  _MockDatabaseServiceSuccess(this.mockQuote) : super.forTesting();

  final Map<String, dynamic>? mockQuote;
  String? lastOfflineQuoteSource;

  @override
  Future<Map<String, dynamic>?> getLocalDailyQuote({
    String offlineQuoteSource = 'tagOnly',
  }) async {
    lastOfflineQuoteSource = offlineQuoteSource;
    return mockQuote;
  }
}

class _MockDatabaseServiceError extends DatabaseService {
  _MockDatabaseServiceError() : super.forTesting();

  @override
  Future<Map<String, dynamic>?> getLocalDailyQuote({
    String offlineQuoteSource = 'tagOnly',
  }) async {
    throw Exception('Database query error');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await TestHarness.initialize();
  });

  group('ApiService Daily Quote Fallback Tests', () {
    late AppLocalizations l10n;

    setUp(() {
      l10n = lookupAppLocalizations(const Locale('zh'));
    });

    group('_getLocalOnlyQuote flow (useLocalOnly: true)', () {
      test('returns local quote when database has local quote', () async {
        final mockDb = _MockDatabaseServiceSuccess({
          'content': '本地自定义一言笔记',
          'source': '出处笔记',
          'author': '作者',
          'type': 'a',
          'from_who': '作者',
          'from': '出处笔记',
          'provider': 'local',
        });

        final result = await ApiService.getDailyQuote(
          l10n,
          'a',
          useLocalOnly: true,
          offlineQuoteSource: 'tagOnly',
          databaseService: mockDb,
        );

        expect(mockDb.lastOfflineQuoteSource, 'tagOnly');
        expect(result['content'], '本地自定义一言笔记');
        expect(result['provider'], 'local');
      });

      test(
        'returns local-empty payload when database returns null and offlineQuoteSource is tagOnly',
        () async {
          final mockDb = _MockDatabaseServiceSuccess(null);

          final result = await ApiService.getDailyQuote(
            l10n,
            'a',
            useLocalOnly: true,
            offlineQuoteSource: 'tagOnly',
            databaseService: mockDb,
          );

          expect(mockDb.lastOfflineQuoteSource, 'tagOnly');
          expect(result['content'], l10n.noLocalSavedQuotes);
          expect(result['type'], 'local-empty');
          expect(result['provider'], 'local');
          expect(result['source'], '');
          expect(result['author'], '');
        },
      );

      test(
        'returns default quote when database returns null and offlineQuoteSource is allNotes',
        () async {
          final mockDb = _MockDatabaseServiceSuccess(null);

          final result = await ApiService.getDailyQuote(
            l10n,
            'a',
            useLocalOnly: true,
            offlineQuoteSource: 'allNotes',
            databaseService: mockDb,
          );

          expect(mockDb.lastOfflineQuoteSource, 'allNotes');
          final defaultQuotes = [
            l10n.defaultQuote1,
            l10n.defaultQuote2,
            l10n.defaultQuote3,
          ];
          expect(defaultQuotes.contains(result['content']), isTrue);
          expect(result['provider'], 'default');
          expect(result['type'], 'a');
          expect(result['source'], l10n.unknown);
          expect(result['author'], l10n.unknown);
        },
      );

      test(
        'handles database exception gracefully in local-only mode with tagOnly',
        () async {
          final mockDb = _MockDatabaseServiceError();

          final result = await ApiService.getDailyQuote(
            l10n,
            'a',
            useLocalOnly: true,
            offlineQuoteSource: 'tagOnly',
            databaseService: mockDb,
          );

          expect(result['content'], l10n.noLocalSavedQuotes);
          expect(result['type'], 'local-empty');
          expect(result['provider'], 'local');
        },
      );

      test(
        'handles database exception gracefully in local-only mode with allNotes',
        () async {
          final mockDb = _MockDatabaseServiceError();

          final result = await ApiService.getDailyQuote(
            l10n,
            'a',
            useLocalOnly: true,
            offlineQuoteSource: 'allNotes',
            databaseService: mockDb,
          );

          final defaultQuotes = [
            l10n.defaultQuote1,
            l10n.defaultQuote2,
            l10n.defaultQuote3,
          ];
          expect(defaultQuotes.contains(result['content']), isTrue);
          expect(result['provider'], 'default');
        },
      );
    });

    group('Remote fetch failure fallback flow', () {
      test('returns default quote when remote fetch returns null', () async {
        final result = await ApiService.getDailyQuote(
          l10n,
          'a',
          provider: 'hitokoto',
          httpGet: (url, {headers, timeoutSeconds}) async {
            return HttpResponse('invalid', 500);
          },
        );

        final defaultQuotes = [
          l10n.defaultQuote1,
          l10n.defaultQuote2,
          l10n.defaultQuote3,
        ];
        expect(defaultQuotes.contains(result['content']), isTrue);
        expect(result['provider'], 'default');
      });

      test(
        'returns local quote when remote fetch fails and database has local quote',
        () async {
          final mockDb = _MockDatabaseServiceSuccess({
            'content': '回退到本地笔记',
            'source': '本地源',
            'author': '本地作者',
            'type': 'b',
            'from_who': '本地作者',
            'from': '本地源',
            'provider': 'local',
          });

          final result = await ApiService.getDailyQuote(
            l10n,
            'a',
            provider: 'hitokoto',
            databaseService: mockDb,
            httpGet: (url, {headers, timeoutSeconds}) async {
              throw Exception('Network error');
            },
          );

          expect(result['content'], '回退到本地笔记');
          expect(result['provider'], 'local');
        },
      );
    });

    group('Default quote structure', () {
      test('default quote contains all expected fields and keys', () async {
        final result = await ApiService.getDailyQuote(
          l10n,
          'a',
          useLocalOnly: true,
          offlineQuoteSource: 'allNotes',
          databaseService: null,
        );

        expect(result, containsPair('provider', 'default'));
        expect(result, containsPair('type', 'a'));
        expect(result, containsPair('source', l10n.unknown));
        expect(result, containsPair('author', l10n.unknown));
        expect(result, containsPair('from', l10n.unknown));
        expect(result, containsPair('from_who', l10n.unknown));
        expect(result['content'], isNotNull);
        expect((result['content'] as String).isNotEmpty, isTrue);
      });
    });
  });
}
