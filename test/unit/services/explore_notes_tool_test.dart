import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/models/quote_model.dart';
import 'package:thoughtecho/services/agent_tool.dart';
import 'package:thoughtecho/services/agent_tools/explore_notes_tool.dart';
import 'package:thoughtecho/services/database_service.dart';

import '../../test_helpers.dart';

class _TestDatabaseService extends DatabaseService {
  _TestDatabaseService(this._quotes) : super.forTesting();

  final List<Quote> _quotes;

  List<Quote> _filteredAndSorted({String? searchQuery}) {
    var rows = List<Quote>.from(_quotes);
    if (searchQuery != null && searchQuery.isNotEmpty) {
      final q = searchQuery.toLowerCase();
      rows = rows.where((e) => e.content.toLowerCase().contains(q)).toList();
    }
    rows.sort((a, b) => b.date.compareTo(a.date));
    return rows;
  }

  @override
  Future<int> getQuotesCount({
    List<String>? tagIds,
    String? categoryId,
    String? searchQuery,
    List<String>? selectedWeathers,
    List<String>? selectedDayPeriods,
    bool excludeHiddenNotes = true,
    String? dateStart,
    String? dateEnd,
    bool includeDeleted = false,
  }) async {
    return _filteredAndSorted(searchQuery: searchQuery).length;
  }

  @override
  Future<List<Quote>> getUserQuotes({
    List<String>? tagIds,
    String? categoryId,
    int offset = 0,
    int limit = 10,
    String orderBy = 'date DESC',
    String? searchQuery,
    List<String>? selectedWeathers,
    List<String>? selectedDayPeriods,
    bool excludeHiddenNotes = true,
    String? dateStart,
    String? dateEnd,
    bool includeDeleted = false,
  }) async {
    final rows = _filteredAndSorted(searchQuery: searchQuery);
    if (offset >= rows.length) {
      return <Quote>[];
    }
    final end = (offset + limit).clamp(0, rows.length);
    return rows.sublist(offset, end);
  }

  @override
  Future<Quote?> getQuoteById(String id, {bool includeDeleted = false}) async {
    for (final quote in _quotes) {
      if (quote.id == id) {
        return quote;
      }
    }
    return null;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await TestHelpers.setupTestEnvironment();
  });

  group('ExploreNotesTool', () {
    late ExploreNotesTool tool;
    late List<Quote> quotes;

    setUp(() {
      quotes = <Quote>[];
      for (var i = 0; i < 30; i++) {
        quotes.add(
          Quote(
            id: 'note_$i',
            content: 'keyword item $i ${List<String>.filled(180, 'x').join()}',
            date: DateTime(2026, 1, 30 - i, 12, i).toIso8601String(),
            location: 'loc_$i',
            poiName: 'poi_$i',
          ),
        );
      }
      tool = ExploreNotesTool(_TestDatabaseService(quotes));
    });

    test('returns paged payload with pagination info', () async {
      final result = await tool.execute(
        ToolCall(
          id: 'call_1',
          name: 'explore_notes',
          arguments: const {
            'query': 'keyword',
            'limit': 5,
            'offset': 0,
          },
        ),
      );

      expect(result.isError, isFalse);
      final data = jsonDecode(result.content);
      expect(data['notes'], hasLength(5));
      expect(data['pagination']['offset'], 0);
      expect(data['pagination']['next_offset'], 5);
      expect(data['pagination']['has_more'], isTrue);
      expect(data['pagination']['total_count'], 30);
    });

    test('supports empty query for browsing', () async {
      final result = await tool.execute(
        ToolCall(
          id: 'call_2',
          name: 'explore_notes',
          arguments: const {
            'limit': 10,
          },
        ),
      );

      expect(result.isError, isFalse);
      final data = jsonDecode(result.content);
      expect(data['notes'], hasLength(10));
    });
  });
}
